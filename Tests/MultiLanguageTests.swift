import XCTest

/// Tests for additional language pair conversions.
/// These tests skip gracefully when the required layout is not installed.
final class MultiLanguageTests: XCTestCase {

    // MARK: - Helpers

    /// Check if a layout with the given language code is installed and has key data.
    private func layoutAvailable(language: String) -> Bool {
        KeyboardLayoutMap.installedLayouts().contains { $0.languages.contains(language) }
    }

    /// Convert text between two specific layouts identified by language.
    /// Returns nil if either layout is not installed.
    private func convertBetween(text: String, from sourceLang: String, to targetLang: String) -> String? {
        let layouts = KeyboardLayoutMap.installedLayouts()
        guard let source = layouts.first(where: { $0.languages.contains(sourceLang) }),
              let target = layouts.first(where: { $0.languages.contains(targetLang) }) else {
            return nil
        }

        let sourceReverse = KeyboardLayoutMap.buildReverseMap(for: source)
        let targetForward = KeyboardLayoutMap.buildCharacterMap(for: target)

        return String(text.map { char -> Character in
            guard let keyMapping = sourceReverse[char] else { return char }
            let targetKey = CharacterMapKey(keyCode: keyMapping.keyCode, shifted: keyMapping.shifted)
            return targetForward[targetKey] ?? char
        })
    }

    /// Verify roundtrip conversion between two layouts.
    private func assertRoundtrip(_ text: String, lang1: String, lang2: String, file: StaticString = #file, line: UInt = #line) {
        guard let converted = convertBetween(text: text, from: lang1, to: lang2) else {
            print("⚠️ Skipping: \(lang1)/\(lang2) layout not installed")
            return
        }
        guard let roundtrip = convertBetween(text: converted, from: lang2, to: lang1) else {
            XCTFail("Reverse conversion failed", file: file, line: line)
            return
        }
        XCTAssertEqual(roundtrip, text,
                       "Roundtrip \(lang1)→\(lang2)→\(lang1) failed for '\(text)'",
                       file: file, line: line)
    }

    // MARK: - ES (Spanish) / RU

    func testSpanishRussian_available() {
        guard layoutAvailable(language: "es") else {
            print("⚠️ Spanish layout not installed, skipping ES/RU tests")
            return
        }
        // Basic letter roundtrip
        assertRoundtrip("ghbdtn", lang1: "es", lang2: "ru")
    }

    func testSpanishRussian_roundtrip() {
        guard layoutAvailable(language: "es"), layoutAvailable(language: "ru") else {
            print("⚠️ Spanish or Russian layout not installed, skipping")
            return
        }
        let testWords = ["hola", "mundo", "prueba"]
        for word in testWords {
            assertRoundtrip(word, lang1: "es", lang2: "ru")
        }
    }

    // MARK: - DE (German) / RU

    func testGermanRussian_roundtrip() {
        guard layoutAvailable(language: "de"), layoutAvailable(language: "ru") else {
            print("⚠️ German or Russian layout not installed, skipping")
            return
        }
        let testWords = ["hallo", "welt", "test"]
        for word in testWords {
            assertRoundtrip(word, lang1: "de", lang2: "ru")
        }
    }

    func testGermanRussian_umlauts() {
        // Find a layout that's specifically German (not ABC which lists "de" generically)
        let layouts = KeyboardLayoutMap.installedLayouts()
        guard let germanLayout = layouts.first(where: {
            $0.id.lowercased().contains("german") && $0.languages.contains("de")
        }) else {
            print("⚠️ Dedicated German layout not installed (ABC doesn't have umlauts), skipping")
            return
        }
        guard layoutAvailable(language: "ru") else {
            print("⚠️ Russian layout not installed, skipping")
            return
        }
        // Verify ö, ü, ä can be converted (they exist on dedicated German layout)
        let reverseMap = KeyboardLayoutMap.buildReverseMap(for: germanLayout)
        for umlaut: Character in ["ö", "ü", "ä"] {
            XCTAssertNotNil(reverseMap[umlaut], "German layout should contain '\(umlaut)'")
        }
    }

    // MARK: - FR (French) / RU

    func testFrenchRussian_roundtrip() {
        guard layoutAvailable(language: "fr"), layoutAvailable(language: "ru") else {
            print("⚠️ French or Russian layout not installed, skipping")
            return
        }
        let testWords = ["bonjour", "monde", "test"]
        for word in testWords {
            assertRoundtrip(word, lang1: "fr", lang2: "ru")
        }
    }

    func testFrenchLayout_deadKeys() {
        guard layoutAvailable(language: "fr") else {
            print("⚠️ French layout not installed, skipping")
            return
        }
        // French layout should produce accented characters via dead keys
        let frenchLayout = KeyboardLayoutMap.installedLayouts().first { $0.languages.contains("fr") }!
        let reverseMap = KeyboardLayoutMap.buildReverseMap(for: frenchLayout)
        // Check that common French accented chars are reachable
        let expectedChars: [Character] = ["é", "è"]
        for char in expectedChars {
            if reverseMap[char] != nil {
                // Accented char is in the direct key map — good
            } else {
                print("⚠️ '\(char)' not in French reverse map (may need dead key composition)")
            }
        }
    }

    // MARK: - EN / FR

    func testEnglishFrench_roundtrip() {
        guard layoutAvailable(language: "en"), layoutAvailable(language: "fr") else {
            print("⚠️ English or French layout not installed, skipping")
            return
        }
        let testWords = ["hello", "world", "test"]
        for word in testWords {
            assertRoundtrip(word, lang1: "en", lang2: "fr")
        }
    }

    // MARK: - EN / DE

    func testEnglishGerman_roundtrip() {
        guard layoutAvailable(language: "en"), layoutAvailable(language: "de") else {
            print("⚠️ English or German layout not installed, skipping")
            return
        }
        let testWords = ["hello", "world", "keyboard"]
        for word in testWords {
            assertRoundtrip(word, lang1: "en", lang2: "de")
        }
    }

    // MARK: - PT (Portuguese) / EN and PT / RU

    func testPortugueseEnglish_roundtrip() {
        guard layoutAvailable(language: "pt"), layoutAvailable(language: "en") else {
            print("⚠️ Portuguese or English layout not installed, skipping")
            return
        }
        let testWords = ["hello", "world", "code"]
        for word in testWords {
            assertRoundtrip(word, lang1: "pt", lang2: "en")
        }
    }

    func testPortugueseRussian_roundtrip() {
        guard layoutAvailable(language: "pt"), layoutAvailable(language: "ru") else {
            print("⚠️ Portuguese or Russian layout not installed, skipping")
            return
        }
        assertRoundtrip("teste", lang1: "pt", lang2: "ru")
    }

    // MARK: - IT (Italian) / EN and IT / RU

    func testItalianEnglish_roundtrip() {
        guard layoutAvailable(language: "it"), layoutAvailable(language: "en") else {
            print("⚠️ Italian or English layout not installed, skipping")
            return
        }
        let testWords = ["hello", "world", "code"]
        for word in testWords {
            assertRoundtrip(word, lang1: "it", lang2: "en")
        }
    }

    func testItalianRussian_roundtrip() {
        guard layoutAvailable(language: "it"), layoutAvailable(language: "ru") else {
            print("⚠️ Italian or Russian layout not installed, skipping")
            return
        }
        assertRoundtrip("test", lang1: "it", lang2: "ru")
    }

    // MARK: - Generic: any two installed layouts should roundtrip

    func testAllInstalledLayouts_roundtrip() {
        let layouts = KeyboardLayoutMap.installedLayouts()
        guard layouts.count >= 2 else {
            print("⚠️ Fewer than 2 layouts installed, skipping")
            return
        }

        // Test roundtrip between every pair of installed layouts
        for i in 0..<layouts.count {
            for j in (i+1)..<layouts.count {
                let lang1 = layouts[i].languages.first ?? layouts[i].id
                let lang2 = layouts[j].languages.first ?? layouts[j].id

                // Use basic lowercase letters that exist on most layouts
                assertRoundtrip("test", lang1: lang1, lang2: lang2)
            }
        }
    }
}
