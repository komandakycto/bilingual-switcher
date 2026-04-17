import Foundation

/// Describes the direction of conversion between two keyboard layouts.
enum ConversionDirection {
    /// Convert from the first layout to the second (e.g., English → Russian).
    case layoutAToB
    /// Convert from the second layout to the first (e.g., Russian → English).
    case layoutBToA
    /// Auto-detect direction from text content.
    case auto
}

class LayoutConverter {

    /// Convert text between the user's installed keyboard layouts.
    /// Auto-detects which layout produced the text and converts to the other.
    static func convert(_ text: String, direction: ConversionDirection = .auto) -> (String, ConversionDirection) {
        let layouts = KeyboardLayoutMap.installedLayouts()
        guard layouts.count >= 2 else {
            return (text, .auto)
        }

        let resolvedDirection: ConversionDirection
        let sourceLayout: LayoutInfo
        let targetLayout: LayoutInfo

        switch direction {
        case .auto:
            let detected = detectSourceLayout(text, layouts: layouts)
            sourceLayout = detected.source
            targetLayout = detected.target
            resolvedDirection = detected.direction
        case .layoutAToB:
            sourceLayout = layouts[0]
            targetLayout = layouts[1]
            resolvedDirection = .layoutAToB
        case .layoutBToA:
            sourceLayout = layouts[1]
            targetLayout = layouts[0]
            resolvedDirection = .layoutBToA
        }

        let converted = convertText(text, from: sourceLayout, to: targetLayout)
        return (converted, resolvedDirection)
    }

    /// Detect which installed layout most likely produced the given text.
    static func detectDirection(_ text: String) -> ConversionDirection {
        let layouts = KeyboardLayoutMap.installedLayouts()
        guard layouts.count >= 2 else { return .auto }
        let detected = detectSourceLayout(text, layouts: layouts)
        return detected.direction
    }

    /// Convert text from one layout to another via physical key codes.
    /// Exposed as internal for testing (avoid duplicating conversion logic in tests).
    static func convertText(_ text: String, from source: LayoutInfo, to target: LayoutInfo) -> String {
        let sourceReverse = KeyboardLayoutMap.buildReverseMap(for: source)
        let targetForward = KeyboardLayoutMap.buildCharacterMap(for: target)

        return String(text.map { char -> Character in
            guard let keyMapping = sourceReverse[char] else {
                return char
            }
            let targetKey = CharacterMapKey(keyCode: keyMapping.keyCode, shifted: keyMapping.shifted)
            return targetForward[targetKey] ?? char
        })
    }

    // MARK: - Detection

    private struct DetectionResult {
        let source: LayoutInfo
        let target: LayoutInfo
        let direction: ConversionDirection
    }

    private struct LayoutScore {
        let layout: LayoutInfo
        let uniqueScore: Int
        let totalScore: Int
    }

    /// Identify the source layout from text content and determine conversion target.
    /// For 3+ layouts, prefers the currently active layout as target when it differs
    /// from the detected source.
    private static func detectSourceLayout(_ text: String, layouts: [LayoutInfo]) -> DetectionResult {
        // Build character sets per layout for O(1) membership checks
        let layoutCharSets: [(layout: LayoutInfo, chars: Set<Character>)] = layouts.map { layout in
            let reverseMap = KeyboardLayoutMap.buildReverseMap(for: layout)
            return (layout, Set(reverseMap.keys))
        }

        // Score each layout: unique chars (only in this layout) + total chars
        var scores: [LayoutScore] = []
        for (index, entry) in layoutCharSets.enumerated() {
            var uniqueScore = 0
            var totalScore = 0
            for char in text {
                guard entry.chars.contains(char) else { continue }
                totalScore += 1
                let isUnique = !layoutCharSets.enumerated().contains { otherIndex, other in
                    otherIndex != index && other.chars.contains(char)
                }
                if isUnique { uniqueScore += 1 }
            }
            scores.append(LayoutScore(layout: entry.layout, uniqueScore: uniqueScore, totalScore: totalScore))
        }

        scores.sort { ($0.uniqueScore, $0.totalScore) > ($1.uniqueScore, $1.totalScore) }

        let source = scores[0].layout

        // Target selection: prefer the currently active layout if it differs from source.
        // This handles 3+ layouts correctly (e.g., EN+RU+FR: if user is typing in RU
        // and text is detected as EN, target should be RU — the active layout).
        let target: LayoutInfo
        if let current = KeyboardLayoutMap.currentLayout(), current.id != source.id {
            target = current
        } else {
            target = scores.count > 1 ? scores[1].layout : source
        }

        let direction: ConversionDirection = source.id == layouts[0].id ? .layoutAToB : .layoutBToA
        return DetectionResult(source: source, target: target, direction: direction)
    }
}
