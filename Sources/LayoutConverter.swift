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
    /// For 3+ layouts, uses the two most recently active layouts as the working pair.
    static func convert(_ text: String, direction: ConversionDirection = .auto) -> (String, ConversionDirection) {
        let layouts = KeyboardLayoutMap.installedLayouts()
        guard layouts.count >= 2 else {
            return (text, .auto)
        }

        // For 3+ layouts, narrow down to the user's recent pair.
        let workingLayouts: [LayoutInfo]
        if layouts.count > 2, let pair = KeyboardLayoutMap.recentLayoutPair() {
            workingLayouts = [pair.current, pair.previous]
        } else {
            workingLayouts = layouts
        }

        let resolvedDirection: ConversionDirection
        let sourceLayout: LayoutInfo
        let targetLayout: LayoutInfo

        switch direction {
        case .auto:
            let detected = detectSourceLayout(text, layouts: workingLayouts)
            sourceLayout = detected.source
            targetLayout = detected.target
            resolvedDirection = detected.direction
        case .layoutAToB:
            sourceLayout = workingLayouts[0]
            targetLayout = workingLayouts[1]
            resolvedDirection = .layoutAToB
        case .layoutBToA:
            sourceLayout = workingLayouts[1]
            targetLayout = workingLayouts[0]
            resolvedDirection = .layoutBToA
        }

        let converted = convertText(text, from: sourceLayout, to: targetLayout)
        return (converted, resolvedDirection)
    }

    /// Detect which installed layout most likely produced the given text.
    /// Uses the same working-pair logic as convert() for 3+ layouts.
    static func detectDirection(_ text: String) -> ConversionDirection {
        let layouts = KeyboardLayoutMap.installedLayouts()
        guard layouts.count >= 2 else { return .auto }

        let workingLayouts: [LayoutInfo]
        if layouts.count > 2, let pair = KeyboardLayoutMap.recentLayoutPair() {
            workingLayouts = [pair.current, pair.previous]
        } else {
            workingLayouts = layouts
        }

        let detected = detectSourceLayout(text, layouts: workingLayouts)
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
    /// Expects a working pair (already narrowed to 2 layouts for the 3+ case).
    ///
    /// When scores are tied (common for same-script pairs like EN↔FR where "hello"
    /// scores equally for both), the currently active layout is assumed to be the source.
    /// Rationale: the user is typing in the active layout and wants to convert to the other.
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

        var source = scores[0].layout

        // Tie-break: when scores are equal (same-script pairs), the currently active
        // layout is the one the user is typing in — that's the source they want to
        // convert FROM. Without this, the sort picks an arbitrary winner.
        if scores.count >= 2,
           scores[0].uniqueScore == scores[1].uniqueScore,
           scores[0].totalScore == scores[1].totalScore,
           let current = KeyboardLayoutMap.currentLayout(),
           layouts.contains(where: { $0.id == current.id }) {
            source = current
        }

        let target: LayoutInfo
        if let other = layouts.first(where: { $0.id != source.id }) {
            target = other
        } else {
            target = source
        }

        let direction: ConversionDirection = source.id == layouts[0].id ? .layoutAToB : .layoutBToA
        return DetectionResult(source: source, target: target, direction: direction)
    }
}
