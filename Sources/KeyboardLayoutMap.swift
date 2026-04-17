import Carbon
import Cocoa

/// Key for character map lookups: physical key code + shift state.
struct CharacterMapKey: Hashable {
    let keyCode: UInt16
    let shifted: Bool
}

/// Info about an installed keyboard layout.
struct LayoutInfo {
    let id: String
    let name: String
    let languages: [String]
    let source: TISInputSource
}

/// Mapping from a character back to the physical key that produces it.
struct KeyMapping {
    let keyCode: UInt16
    let shifted: Bool
}

/// Reads keyboard layout data from macOS via UCKeyTranslate.
/// Builds and caches character maps for all installed layouts.
class KeyboardLayoutMap {

    /// Cached character maps keyed by layout ID.
    private static var characterMapCache: [String: [CharacterMapKey: Character]] = [:]
    /// Cached reverse maps keyed by layout ID.
    private static var reverseMapCache: [String: [Character: KeyMapping]] = [:]
    /// Cached layout list.
    private static var layoutCache: [LayoutInfo]?

    // MARK: - Layout Enumeration

    /// Returns all installed keyboard layouts (excludes input methods like CJK).
    static func installedLayouts() -> [LayoutInfo] {
        if let cached = layoutCache { return cached }

        let filter = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceType as String: kTISTypeKeyboardLayout as String
        ] as CFDictionary

        guard let sourceList = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }

        let layouts = sourceList.compactMap { source -> LayoutInfo? in
            guard let idRef = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
            let id = Unmanaged<CFString>.fromOpaque(idRef).takeUnretainedValue() as String

            let name: String
            if let nameRef = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) {
                name = Unmanaged<CFString>.fromOpaque(nameRef).takeUnretainedValue() as String
            } else {
                name = id
            }

            var languages: [String] = []
            if let langRef = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) {
                languages = Unmanaged<CFArray>.fromOpaque(langRef).takeUnretainedValue() as? [String] ?? []
            }

            // Only include layouts that have UCKeyboardLayout data
            guard TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) != nil else {
                return nil
            }

            return LayoutInfo(id: id, name: name, languages: languages, source: source)
        }

        layoutCache = layouts
        return layouts
    }

    // MARK: - Character Map Building

    /// Builds a map from (keyCode, shifted) → Character for the given layout.
    static func buildCharacterMap(for layout: LayoutInfo) -> [CharacterMapKey: Character] {
        if let cached = characterMapCache[layout.id] { return cached }

        guard let dataRef = TISGetInputSourceProperty(layout.source, kTISPropertyUnicodeKeyLayoutData) else {
            return [:]
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(dataRef).takeUnretainedValue() as Data
        let keyboardType = UInt32(LMGetKbdType())

        var map: [CharacterMapKey: Character] = [:]

        // Iterate all standard key codes (0–127 covers all physical keys)
        for keyCode: UInt16 in 0...127 {
            // Unshifted
            if let char = translateKey(keyCode: keyCode, shift: false, layoutData: layoutData, keyboardType: keyboardType) {
                map[CharacterMapKey(keyCode: keyCode, shifted: false)] = char
            }
            // Shifted
            if let char = translateKey(keyCode: keyCode, shift: true, layoutData: layoutData, keyboardType: keyboardType) {
                map[CharacterMapKey(keyCode: keyCode, shifted: true)] = char
            }
        }

        // Handle dead keys: try combining with common base characters
        let deadKeyBaseChars: [UInt16] = [
            0, 1, 2, 3, 5, 6, 7, 8, 11, 12, 13, 14, 15, 16, 17,
            31, 32, 34, 35, 37, 38, 40, 41, 45, 46
        ] // key codes for a-z subset covering vowels and common consonants

        for keyCode: UInt16 in 0...127 {
            for shift in [false, true] {
                if let composed = translateDeadKey(deadKeyCode: keyCode, shift: shift,
                                                   baseKeyCodes: deadKeyBaseChars,
                                                   layoutData: layoutData,
                                                   keyboardType: keyboardType) {
                    for result in composed {
                        let key = CharacterMapKey(keyCode: keyCode, shifted: shift)
                        if map[key] == nil {
                            map[key] = result.character
                        }
                    }
                }
            }
        }

        characterMapCache[layout.id] = map
        return map
    }

    /// Builds a reverse map: Character → KeyMapping for the given layout.
    static func buildReverseMap(for layout: LayoutInfo) -> [Character: KeyMapping] {
        if let cached = reverseMapCache[layout.id] { return cached }

        let charMap = buildCharacterMap(for: layout)
        var reverse: [Character: KeyMapping] = [:]
        for (key, char) in charMap {
            if let existing = reverse[char] {
                // Prefer main keyboard (key codes 0–50) over numpad/function keys,
                // and prefer unshifted over shifted within the same priority.
                let existingIsMain = existing.keyCode <= 50
                let newIsMain = key.keyCode <= 50
                if newIsMain && !existingIsMain {
                    reverse[char] = KeyMapping(keyCode: key.keyCode, shifted: key.shifted)
                } else if newIsMain == existingIsMain && !key.shifted && existing.shifted {
                    reverse[char] = KeyMapping(keyCode: key.keyCode, shifted: key.shifted)
                }
            } else {
                reverse[char] = KeyMapping(keyCode: key.keyCode, shifted: key.shifted)
            }
        }

        reverseMapCache[layout.id] = reverse
        return reverse
    }

    /// Invalidate all caches (call when layouts change).
    static func rebuildMaps() {
        characterMapCache.removeAll()
        reverseMapCache.removeAll()
        layoutCache = nil
    }

    /// Start listening for keyboard layout changes and rebuild caches when they occur.
    static func startObservingLayoutChanges() {
        DistributedNotificationCenter.default().addObserver(
            forName: .init("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"),
            object: nil,
            queue: .main
        ) { _ in
            rebuildMaps()
        }
    }

    // MARK: - UCKeyTranslate Helpers

    /// Translate a single key code to a character using UCKeyTranslate.
    private static func translateKey(keyCode: UInt16, shift: Bool,
                                     layoutData: Data, keyboardType: UInt32) -> Character? {
        let modifierState: UInt32 = shift ? (UInt32(shiftKey) >> 8) & 0xFF : 0
        var deadKeyState: UInt32 = 0
        let maxLength = 4
        var chars = [UniChar](repeating: 0, count: maxLength)
        var actualLength: Int = 0

        let result = layoutData.withUnsafeBytes { rawBuffer -> OSStatus in
            guard let ptr = rawBuffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return errSecParam
            }
            return UCKeyTranslate(
                ptr,
                keyCode,
                UInt16(kUCKeyActionDown),
                modifierState,
                keyboardType,
                UInt32(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                maxLength,
                &actualLength,
                &chars
            )
        }

        guard result == noErr, actualLength > 0 else { return nil }
        let str = String(utf16CodeUnits: chars, count: actualLength)
        guard let char = str.first, !char.isNewline, char != "\0" else { return nil }
        // Skip control characters
        guard char.unicodeScalars.first.map({ $0.value >= 0x20 }) == true else { return nil }
        return char
    }

    private struct DeadKeyResult {
        let baseKeyCode: UInt16
        let baseShifted: Bool
        let character: Character
    }

    /// Try a key as a dead key, combining with base characters.
    private static func translateDeadKey(deadKeyCode: UInt16, shift: Bool,
                                         baseKeyCodes: [UInt16],
                                         layoutData: Data, keyboardType: UInt32) -> [DeadKeyResult]? {
        let modifierState: UInt32 = shift ? (UInt32(shiftKey) >> 8) & 0xFF : 0
        var deadKeyState: UInt32 = 0
        let maxLength = 4
        var chars = [UniChar](repeating: 0, count: maxLength)
        var actualLength: Int = 0

        // First press: check if this produces a dead key state
        let result1 = layoutData.withUnsafeBytes { rawBuffer -> OSStatus in
            guard let ptr = rawBuffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return errSecParam
            }
            return UCKeyTranslate(
                ptr,
                deadKeyCode,
                UInt16(kUCKeyActionDown),
                modifierState,
                keyboardType,
                0, // allow dead keys
                &deadKeyState,
                maxLength,
                &actualLength,
                &chars
            )
        }

        guard result1 == noErr, deadKeyState != 0 else { return nil }

        // This is a dead key — try combining with base characters
        var results: [DeadKeyResult] = []
        let savedDeadState = deadKeyState

        for baseCode in baseKeyCodes {
            for baseShift in [false, true] {
                deadKeyState = savedDeadState
                let baseMod: UInt32 = baseShift ? (UInt32(shiftKey) >> 8) & 0xFF : 0
                chars = [UniChar](repeating: 0, count: maxLength)
                actualLength = 0

                let result2 = layoutData.withUnsafeBytes { rawBuffer -> OSStatus in
                    guard let ptr = rawBuffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                        return errSecParam
                    }
                    return UCKeyTranslate(
                        ptr,
                        baseCode,
                        UInt16(kUCKeyActionDown),
                        baseMod,
                        keyboardType,
                        0,
                        &deadKeyState,
                        maxLength,
                        &actualLength,
                        &chars
                    )
                }

                if result2 == noErr, actualLength > 0 {
                    let str = String(utf16CodeUnits: chars, count: actualLength)
                    if let char = str.first, char.unicodeScalars.first.map({ $0.value >= 0x20 }) == true {
                        results.append(DeadKeyResult(baseKeyCode: baseCode, baseShifted: baseShift, character: char))
                    }
                }
            }
        }

        return results.isEmpty ? nil : results
    }
}
