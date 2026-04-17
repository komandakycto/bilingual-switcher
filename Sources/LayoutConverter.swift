import Foundation

/// Describes the direction of conversion between two keyboard layouts.
enum ConversionDirection {
    /// Convert from the first layout to the second (e.g., English → Russian).
    case layoutAToB
    /// Convert from the second layout to the first (e.g., Russian → English).
    case layoutBToA
    /// Auto-detect direction from text content.
    case auto

    // Backward-compatible aliases
    static let englishToRussian: ConversionDirection = .layoutAToB
    static let russianToEnglish: ConversionDirection = .layoutBToA
}

class LayoutConverter {

    /// Convert text between the user's installed keyboard layouts.
    /// Auto-detects which layout produced the text and converts to the other.
    static func convert(_ text: String, direction: ConversionDirection = .auto) -> (String, ConversionDirection) {
        let layouts = KeyboardLayoutMap.installedLayouts()
        guard layouts.count >= 2 else {
            // Can't convert with fewer than 2 layouts
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

    /// Identify the source layout from text content and determine conversion target.
    /// For 3+ layouts, uses unique character scoring with a tiebreaker that prefers
    /// the currently active layout's counterpart.
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

    private static func detectSourceLayout(_ text: String, layouts: [LayoutInfo]) -> DetectionResult {

        // Score each layout: count characters that are UNIQUE to that layout
        // (i.e., exist in its reverse map but not in others). Unique chars are
        // stronger signals than shared chars (like digits or common punctuation).
        let reverseMaps = layouts.map { (layout: $0, map: KeyboardLayoutMap.buildReverseMap(for: $0)) }

        var scores: [LayoutScore] = []
        for (index, entry) in reverseMaps.enumerated() {
            var uniqueScore = 0
            var totalScore = 0
            for char in text {
                guard entry.map[char] != nil else { continue }
                totalScore += 1
                let isUnique = !reverseMaps.enumerated().contains { otherIndex, other in
                    otherIndex != index && other.map[char] != nil
                }
                if isUnique { uniqueScore += 1 }
            }
            scores.append(LayoutScore(layout: entry.layout, uniqueScore: uniqueScore, totalScore: totalScore))
        }

        scores.sort { ($0.uniqueScore, $0.totalScore) > ($1.uniqueScore, $1.totalScore) }

        let source = scores[0].layout
        let target = scores.count > 1 ? scores[1].layout : scores[0].layout

        let direction: ConversionDirection = source.id == layouts[0].id ? .layoutAToB : .layoutBToA
        return DetectionResult(source: source, target: target, direction: direction)
    }

    /// Convert text from one layout to another via physical key codes.
    private static func convertText(_ text: String, from source: LayoutInfo, to target: LayoutInfo) -> String {
        let sourceReverse = KeyboardLayoutMap.buildReverseMap(for: source)
        let targetForward = KeyboardLayoutMap.buildCharacterMap(for: target)

        return String(text.map { char -> Character in
            // Find which physical key produces this character in the source layout
            guard let keyMapping = sourceReverse[char] else {
                return char // Character not in source layout, pass through
            }
            // Look up what that physical key produces in the target layout
            let targetKey = CharacterMapKey(keyCode: keyMapping.keyCode, shifted: keyMapping.shifted)
            return targetForward[targetKey] ?? char
        })
    }
}
