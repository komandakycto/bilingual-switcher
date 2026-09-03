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

    // MARK: - Dead-key compositions

    /// Pinned to the U.S./ABC family on purpose: those layouts keep every dead
    /// key on the Option layer (⌥e ⌥u ⌥i ⌥n ⌥`), which is exactly the case the
    /// probe used to miss. Other layouts put accents elsewhere, so asserting
    /// specific characters against whatever happens to be installed would test
    /// the machine rather than the code.
    private func usLayoutWithOptionDeadKeys() throws -> LayoutInfo {
        let layouts = KeyboardLayoutMap.installedLayouts()
        guard let us = layouts.first(where: {
            $0.id == "com.apple.keylayout.ABC" || $0.id == "com.apple.keylayout.US"
        }) else {
            throw XCTSkip("Neither the ABC nor the U.S. layout is installed")
        }
        return us
    }

    private func russianLayout() throws -> LayoutInfo {
        guard let ru = KeyboardLayoutMap.installedLayouts().first(where: { $0.languages.contains("ru") }) else {
            throw XCTSkip("Russian layout not installed")
        }
        return ru
    }

    /// The regression this section exists for: dead keys were probed with the
    /// bare and Shift states only, so on these layouts none were found and not
    /// one accented character reached the maps.
    func testDeadKeyCompositionsIncludeOptionLayerAccents() throws {
        let reverse = KeyboardLayoutMap.buildReverseMap(for: try usLayoutWithOptionDeadKeys())
        for char: Character in ["é", "è", "ü", "ñ", "ô"] {
            XCTAssertNotNil(reverse[char],
                            "'\(char)' is typed on this layout with an Option dead key and must be mapped")
        }
    }

    /// A composition resolves to its base key. The accent has no counterpart in
    /// the other layout, so this is deliberately lossy — and it is what lets an
    /// accented character convert at all instead of passing through untouched.
    func testComposedCharacterMapsToItsBaseKey() throws {
        let reverse = KeyboardLayoutMap.buildReverseMap(for: try usLayoutWithOptionDeadKeys())
        guard let plainE = reverse["e"] else {
            XCTFail("'e' missing from the reverse map")
            return
        }
        XCTAssertEqual(reverse["é"]?.keyCode, plainE.keyCode)
        XCTAssertEqual(reverse["é"]?.shifted, false)
        XCTAssertEqual(reverse["É"]?.keyCode, plainE.keyCode)
        XCTAssertEqual(reverse["É"]?.shifted, true, "The capital comes from the shifted base key")
    }

    /// A base key that does not combine still emits output — the accent plus the
    /// base character (⌥e then n → `´n`), and the bare accent for space. Taking
    /// `first` of those filed the accent itself under an arbitrary key.
    func testStandaloneAccentsAreNotMapped() throws {
        let reverse = KeyboardLayoutMap.buildReverseMap(for: try usLayoutWithOptionDeadKeys())
        for char: Character in ["´", "¨", "˜", "ˆ"] {
            XCTAssertNil(reverse[char],
                         "'\(char)' is a non-combining artefact, not a character this layout produces")
        }
    }

    /// Detection scores text against these sets. While é belonged to no layout's
    /// set, accented text gave the scorer nothing to weigh.
    func testCharacterSetIncludesComposedCharacters() throws {
        let set = KeyboardLayoutMap.characterSet(for: try usLayoutWithOptionDeadKeys())
        XCTAssertTrue(set.contains("é"), "characterSet must expose composed characters to detection")
    }

    func testComposedCharacterConvertsInsteadOfPassingThrough() throws {
        let us = try usLayoutWithOptionDeadKeys()
        let ru = try russianLayout()

        let converted = LayoutConverter.convertText("é", from: us, to: ru)
        XCTAssertNotEqual(converted, "é", "An unmapped character passes through untouched")
        XCTAssertEqual(converted, LayoutConverter.convertText("e", from: us, to: ru),
                       "é resolves to the same key as 'e', so it must convert the same way")
    }

    /// Guard on the newly added entries: they must not disturb anything that
    /// already mapped. Every directly typed character still survives the trip
    /// out to the other layout and back.
    func testDirectCharactersStillRoundTripLosslessly() throws {
        let us = try usLayoutWithOptionDeadKeys()
        let ru = try russianLayout()

        let direct = Set(KeyboardLayoutMap.buildCharacterMap(for: us).values)
        XCTAssertFalse(direct.isEmpty, "Forward map should not be empty")
        for char in direct {
            let there = LayoutConverter.convertText(String(char), from: us, to: ru)
            let back = LayoutConverter.convertText(there, from: ru, to: us)
            XCTAssertEqual(back, String(char), "Round trip lost '\(char)' (via '\(there)')")
        }
    }
}
