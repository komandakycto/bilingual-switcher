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

    private static let lock = NSLock()

    /// Cached character maps keyed by layout ID.
    private static var characterMapCache: [String: [CharacterMapKey: Character]] = [:]
    /// Cached reverse maps keyed by layout ID.
    private static var reverseMapCache: [String: [Character: KeyMapping]] = [:]
    /// Cached layout list.
    private static var layoutCache: [LayoutInfo]?

    /// The two most recently active layout IDs (newest first).
    /// Tracked via layout-switch notifications so we know the user's working pair.
    private static var recentLayoutIDs: [String] = []

    /// Shift modifier state for UCKeyTranslate: (shiftKey >> 8) & 0xFF.
    private static let shiftModifier: UInt32 = (UInt32(shiftKey) >> 8) & 0xFF

    // MARK: - Layout Enumeration

    /// Returns all installed keyboard layouts (excludes input methods like CJK).
    static func installedLayouts() -> [LayoutInfo] {
        lock.lock()
        defer { lock.unlock() }
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
            let sourceID = Unmanaged<CFString>.fromOpaque(idRef).takeUnretainedValue() as String

            let name: String
            if let nameRef = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) {
                name = Unmanaged<CFString>.fromOpaque(nameRef).takeUnretainedValue() as String
            } else {
                name = sourceID
            }

            var languages: [String] = []
            if let langRef = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) {
                languages = Unmanaged<CFArray>.fromOpaque(langRef).takeUnretainedValue() as? [String] ?? []
            }

            // Only include layouts that have UCKeyboardLayout data
            guard TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) != nil else {
                return nil
            }

            return LayoutInfo(id: sourceID, name: name, languages: languages, source: source)
        }

        layoutCache = layouts
        return layouts
    }

    /// Returns the currently active keyboard layout, or nil if it can't be determined.
    static func currentLayout() -> LayoutInfo? {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        guard let idRef = TISGetInputSourceProperty(current, kTISPropertyInputSourceID) else { return nil }
        let currentID = Unmanaged<CFString>.fromOpaque(idRef).takeUnretainedValue() as String
        return installedLayouts().first { $0.id == currentID }
    }

    /// Returns the two most recently used layouts (newest first).
    /// Falls back to the first two installed layouts if history isn't available yet.
    static func recentLayoutPair() -> (current: LayoutInfo, previous: LayoutInfo)? {
        let layouts = installedLayouts()
        guard layouts.count >= 2 else { return nil }

        lock.lock()
        let recent = recentLayoutIDs
        lock.unlock()

        let current: LayoutInfo
        let previous: LayoutInfo

        if recent.count >= 2,
           let curr = layouts.first(where: { $0.id == recent[0] }),
           let prev = layouts.first(where: { $0.id == recent[1] }) {
            current = curr
            previous = prev
        } else {
            // Not enough history — fall back to current + first different installed layout
            if let curr = currentLayout(), let other = layouts.first(where: { $0.id != curr.id }) {
                current = curr
                previous = other
            } else {
                current = layouts[0]
                previous = layouts[1]
            }
        }

        return (current, previous)
    }

    /// Record a layout switch in the recent history.
    private static func recordLayoutSwitch() {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let idRef = TISGetInputSourceProperty(current, kTISPropertyInputSourceID) else { return }
        let currentID = Unmanaged<CFString>.fromOpaque(idRef).takeUnretainedValue() as String

        // Only keyboard layouts with UCKeyboardLayout data (skip input methods)
        guard TISGetInputSourceProperty(current, kTISPropertyUnicodeKeyLayoutData) != nil else { return }

        lock.lock()
        if recentLayoutIDs.first != currentID {
            recentLayoutIDs.insert(currentID, at: 0)
            if recentLayoutIDs.count > 2 {
                recentLayoutIDs.removeLast(recentLayoutIDs.count - 2)
            }
        }
        lock.unlock()
    }

    // MARK: - Character Map Building

    /// Builds a map from (keyCode, shifted) → Character for the given layout.
    static func buildCharacterMap(for layout: LayoutInfo) -> [CharacterMapKey: Character] {
        lock.lock()
        if let cached = characterMapCache[layout.id] { lock.unlock(); return cached }
        lock.unlock()

        guard let dataRef = TISGetInputSourceProperty(layout.source, kTISPropertyUnicodeKeyLayoutData) else {
            return [:]
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(dataRef).takeUnretainedValue() as Data
        let keyboardType = UInt32(LMGetKbdType())

        var map: [CharacterMapKey: Character] = [:]

        // Iterate all standard key codes (0–127 covers all physical keys)
        for keyCode: UInt16 in 0...127 {
            if let char = translateKey(keyCode: keyCode, shift: false, layoutData: layoutData, keyboardType: keyboardType) {
                map[CharacterMapKey(keyCode: keyCode, shifted: false)] = char
            }
            if let char = translateKey(keyCode: keyCode, shift: true, layoutData: layoutData, keyboardType: keyboardType) {
                map[CharacterMapKey(keyCode: keyCode, shifted: true)] = char
            }
        }

        // Handle dead keys: try combining with all main keyboard keys (0–50)
        for keyCode: UInt16 in 0...127 {
            for shift in [false, true] {
                if let composed = translateDeadKey(deadKeyCode: keyCode, shift: shift,
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

        lock.lock()
        characterMapCache[layout.id] = map
        lock.unlock()
        return map
    }

    /// Builds a reverse map: Character → KeyMapping for the given layout.
    static func buildReverseMap(for layout: LayoutInfo) -> [Character: KeyMapping] {
        lock.lock()
        if let cached = reverseMapCache[layout.id] { lock.unlock(); return cached }
        lock.unlock()

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

        lock.lock()
        reverseMapCache[layout.id] = reverse
        lock.unlock()
        return reverse
    }

    /// Invalidate all caches (call when enabled layouts change).
    static func rebuildMaps() {
        lock.lock()
        characterMapCache.removeAll()
        reverseMapCache.removeAll()
        layoutCache = nil
        lock.unlock()
    }

    /// Start listening for layout events.
    static func startObservingLayoutChanges() {
        let center = DistributedNotificationCenter.default()

        // Invalidate caches when layouts are installed/uninstalled/enabled.
        center.addObserver(
            forName: .init("com.apple.Carbon.TISNotifyEnabledKeyboardInputSourcesChanged"),
            object: nil,
            queue: .main
        ) { _ in
            rebuildMaps()
        }

        // Track layout switches (Cmd+Space etc.) to maintain the recent pair.
        // This does NOT invalidate caches — just records which layouts the user uses.
        center.addObserver(
            forName: .init("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"),
            object: nil,
            queue: .main
        ) { _ in
            recordLayoutSwitch()
        }

        // Seed the history with the current layout on startup.
        recordLayoutSwitch()
    }

    // MARK: - UCKeyTranslate Helpers

    /// Translate a single key code to a character using UCKeyTranslate.
    private static func translateKey(keyCode: UInt16, shift: Bool,
                                     layoutData: Data, keyboardType: UInt32) -> Character? {
        let modifierState: UInt32 = shift ? shiftModifier : 0
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
        guard char.unicodeScalars.first.map({ $0.value >= 0x20 }) == true else { return nil }
        return char
    }

    private struct DeadKeyResult {
        let baseKeyCode: UInt16
        let baseShifted: Bool
        let character: Character
    }

    /// Try a key as a dead key, combining with all main keyboard keys (0–50).
    private static func translateDeadKey(deadKeyCode: UInt16, shift: Bool,
                                         layoutData: Data, keyboardType: UInt32) -> [DeadKeyResult]? {
        let modifierState: UInt32 = shift ? shiftModifier : 0
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

        // This is a dead key — try combining with main keyboard keys
        var results: [DeadKeyResult] = []
        let savedDeadState = deadKeyState

        for baseCode: UInt16 in 0...50 {
            for baseShift in [false, true] {
                deadKeyState = savedDeadState
                let baseMod: UInt32 = baseShift ? shiftModifier : 0
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
