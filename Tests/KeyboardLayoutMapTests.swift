import XCTest

final class KeyboardLayoutMapTests: XCTestCase {

    // MARK: - Layout Enumeration

    func testInstalledLayoutsReturnsNonEmptyList() {
        let layouts = KeyboardLayoutMap.installedLayouts()
        XCTAssertFalse(layouts.isEmpty, "Should find at least one keyboard layout")
    }

    func testInstalledLayoutsContainUSQWERTY() {
        let layouts = KeyboardLayoutMap.installedLayouts()
        let hasUS = layouts.contains { $0.id.contains("US") || $0.id.contains("ABC") || $0.languages.contains("en") }
        XCTAssertTrue(hasUS, "Should find a US/English keyboard layout")
    }

    func testLayoutInfoHasRequiredFields() {
        let layouts = KeyboardLayoutMap.installedLayouts()
        guard let layout = layouts.first else {
            XCTFail("No layouts found")
            return
        }
        XCTAssertFalse(layout.id.isEmpty, "Layout ID should not be empty")
        XCTAssertFalse(layout.name.isEmpty, "Layout name should not be empty")
    }

    // MARK: - Character Map Building

    func testBuildMapForUSLayout() {
        let layouts = KeyboardLayoutMap.installedLayouts()
        guard let us = layouts.first(where: { $0.id.contains("US") || $0.id.contains("ABC") }) else {
            XCTFail("US layout not found, cannot test")
            return
        }

        let map = KeyboardLayoutMap.buildCharacterMap(for: us)
        XCTAssertFalse(map.isEmpty, "Character map should not be empty")

        // Key code 0 on QWERTY = 'a'
        XCTAssertEqual(map[CharacterMapKey(keyCode: 0, shifted: false)], "a",
                       "Key code 0 unshifted should be 'a' on US QWERTY")
        // Key code 1 = 's'
        XCTAssertEqual(map[CharacterMapKey(keyCode: 1, shifted: false)], "s",
                       "Key code 1 unshifted should be 's' on US QWERTY")
        // Key code 13 = 'w'
        XCTAssertEqual(map[CharacterMapKey(keyCode: 13, shifted: false)], "w",
                       "Key code 13 unshifted should be 'w' on US QWERTY")
    }

    func testBuildMapShiftedKeys() {
        let layouts = KeyboardLayoutMap.installedLayouts()
        guard let us = layouts.first(where: { $0.id.contains("US") || $0.id.contains("ABC") }) else {
            XCTFail("US layout not found")
            return
        }

        let map = KeyboardLayoutMap.buildCharacterMap(for: us)

        // Shift + key code 0 = 'A'
        XCTAssertEqual(map[CharacterMapKey(keyCode: 0, shifted: true)], "A",
                       "Shift + key code 0 should be 'A'")
        // Shift + key code 1 = 'S'
        XCTAssertEqual(map[CharacterMapKey(keyCode: 1, shifted: true)], "S",
                       "Shift + key code 1 should be 'S'")
    }

    func testBuildMapPunctuationKeys() {
        let layouts = KeyboardLayoutMap.installedLayouts()
        guard let us = layouts.first(where: { $0.id.contains("US") || $0.id.contains("ABC") }) else {
            XCTFail("US layout not found")
            return
        }

        let map = KeyboardLayoutMap.buildCharacterMap(for: us)

        // Key code 33 = '[', shifted = '{'
        XCTAssertEqual(map[CharacterMapKey(keyCode: 33, shifted: false)], "[")
        XCTAssertEqual(map[CharacterMapKey(keyCode: 33, shifted: true)], "{")
        // Key code 30 = ']', shifted = '}'
        XCTAssertEqual(map[CharacterMapKey(keyCode: 30, shifted: false)], "]")
        XCTAssertEqual(map[CharacterMapKey(keyCode: 30, shifted: true)], "}")
    }

    func testBuildMapForRussianLayout() {
        let layouts = KeyboardLayoutMap.installedLayouts()
        guard let ru = layouts.first(where: { $0.languages.contains("ru") }) else {
            print("⚠️ Russian layout not installed, skipping test")
            return
        }

        let map = KeyboardLayoutMap.buildCharacterMap(for: ru)
        XCTAssertFalse(map.isEmpty, "Russian character map should not be empty")

        // Key code 0 on Russian PC = 'ф'
        XCTAssertEqual(map[CharacterMapKey(keyCode: 0, shifted: false)], "ф",
                       "Key code 0 unshifted should be 'ф' on Russian layout")
        // Key code 1 on Russian = 'ы'
        XCTAssertEqual(map[CharacterMapKey(keyCode: 1, shifted: false)], "ы",
                       "Key code 1 unshifted should be 'ы' on Russian layout")
        // Shift + key code 0 = 'Ф'
        XCTAssertEqual(map[CharacterMapKey(keyCode: 0, shifted: true)], "Ф",
                       "Shift + key code 0 should be 'Ф' on Russian layout")
    }

    // MARK: - Reverse Map (Character → Key Code)

    func testReverseMapForUSLayout() {
        let layouts = KeyboardLayoutMap.installedLayouts()
        guard let us = layouts.first(where: { $0.id.contains("US") || $0.id.contains("ABC") }) else {
            XCTFail("US layout not found")
            return
        }

        let reverseMap = KeyboardLayoutMap.buildReverseMap(for: us)

        let aMapping = reverseMap["a"]
        XCTAssertNotNil(aMapping, "Should find mapping for 'a'")
        XCTAssertEqual(aMapping?.keyCode, 0)
        XCTAssertEqual(aMapping?.shifted, false)

        let capitalA = reverseMap["A"]
        XCTAssertNotNil(capitalA, "Should find mapping for 'A'")
        XCTAssertEqual(capitalA?.keyCode, 0)
        XCTAssertEqual(capitalA?.shifted, true)
    }

    // MARK: - Character Set Cache

    func testCharacterSetMatchesReverseMapKeys() {
        let layouts = KeyboardLayoutMap.installedLayouts()
        guard let us = layouts.first(where: { $0.id.contains("US") || $0.id.contains("ABC") }) else {
            XCTFail("US layout not found")
            return
        }

        let set = KeyboardLayoutMap.characterSet(for: us)
        let reverse = KeyboardLayoutMap.buildReverseMap(for: us)

        XCTAssertEqual(set, Set(reverse.keys),
                       "characterSet must be exactly the reverse-map key set")
    }

    func testCharacterSetIsCachedAcrossCalls() {
        let layouts = KeyboardLayoutMap.installedLayouts()
        guard let layout = layouts.first else {
            XCTFail("No layouts found")
            return
        }
        // First call materializes; second returns the cached instance.
        // We only verify equality (the cache is private), but identity-stable
        // membership is what consumers rely on.
        let first = KeyboardLayoutMap.characterSet(for: layout)
        let second = KeyboardLayoutMap.characterSet(for: layout)
        XCTAssertEqual(first, second)
        XCTAssertFalse(first.isEmpty, "Layout character set must not be empty")
    }

    func testCharacterSetIsInvalidatedByRebuildMaps() {
        let layouts = KeyboardLayoutMap.installedLayouts()
        guard let layout = layouts.first else {
            XCTFail("No layouts found")
            return
        }
        // Warm cache, then invalidate, then make sure we still get correct data
        // (we can't observe the cache miss directly, but post-invalidate calls
        // must keep returning correct content).
        _ = KeyboardLayoutMap.characterSet(for: layout)
        KeyboardLayoutMap.rebuildMaps()

        let setAfterRebuild = KeyboardLayoutMap.characterSet(for: layout)
        XCTAssertFalse(setAfterRebuild.isEmpty,
                       "characterSet must repopulate cleanly after rebuildMaps()")
    }

    func testReverseMapForRussianLayout() {
        let layouts = KeyboardLayoutMap.installedLayouts()
        guard let ru = layouts.first(where: { $0.languages.contains("ru") }) else {
            print("⚠️ Russian layout not installed, skipping test")
            return
        }

        let reverseMap = KeyboardLayoutMap.buildReverseMap(for: ru)

        let mapping = reverseMap["ф"]
        XCTAssertNotNil(mapping, "Should find mapping for 'ф'")
        XCTAssertEqual(mapping?.keyCode, 0, "'ф' should be at key code 0")
        XCTAssertEqual(mapping?.shifted, false)
    }
}
