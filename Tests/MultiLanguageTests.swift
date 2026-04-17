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
        return LayoutConverter.convertText(text, from: source, to: target)
    }

    /// Verify roundtrip conversion between two layouts.
    private func assertRoundtrip(_ text: String, lang1: String, lang2: String,
                                 file: StaticString = #file, line: UInt = #line) throws {
        guard let converted = convertBetween(text: text, from: lang1, to: lang2) else {
            throw XCTSkip("\(lang1)/\(lang2) layout not installed")
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

    func testSpanishRussian_available() throws {
        guard layoutAvailable(language: "es") else {
            throw XCTSkip("Spanish layout not installed")
        }
        try assertRoundtrip("ghbdtn", lang1: "es", lang2: "ru")
    }

    func testSpanishRussian_roundtrip() throws {
        guard layoutAvailable(language: "es"), layoutAvailable(language: "ru") else {
            throw XCTSkip("Spanish or Russian layout not installed")
        }
        for word in ["hola", "mundo", "prueba"] {
            try assertRoundtrip(word, lang1: "es", lang2: "ru")
        }
    }

    // MARK: - DE (German) / RU

    func testGermanRussian_roundtrip() throws {
        guard layoutAvailable(language: "de"), layoutAvailable(language: "ru") else {
            throw XCTSkip("German or Russian layout not installed")
        }
        for word in ["hallo", "welt", "test"] {
            try assertRoundtrip(word, lang1: "de", lang2: "ru")
        }
    }

    func testGermanRussian_umlauts() throws {
        let layouts = KeyboardLayoutMap.installedLayouts()
        guard let germanLayout = layouts.first(where: {
            $0.id.lowercased().contains("german") && $0.languages.contains("de")
        }) else {
            throw XCTSkip("Dedicated German layout not installed (ABC doesn't have umlauts)")
        }
        guard layoutAvailable(language: "ru") else {
            throw XCTSkip("Russian layout not installed")
        }
        let reverseMap = KeyboardLayoutMap.buildReverseMap(for: germanLayout)
        for umlaut: Character in ["ö", "ü", "ä"] {
            XCTAssertNotNil(reverseMap[umlaut], "German layout should contain '\(umlaut)'")
        }
    }

    // MARK: - FR (French) / RU

    func testFrenchRussian_roundtrip() throws {
        guard layoutAvailable(language: "fr"), layoutAvailable(language: "ru") else {
            throw XCTSkip("French or Russian layout not installed")
        }
        for word in ["bonjour", "monde", "test"] {
            try assertRoundtrip(word, lang1: "fr", lang2: "ru")
        }
    }

    func testFrenchLayout_deadKeys() throws {
        guard layoutAvailable(language: "fr") else {
            throw XCTSkip("French layout not installed")
        }
        let frenchLayout = KeyboardLayoutMap.installedLayouts().first { $0.languages.contains("fr") }!
        let reverseMap = KeyboardLayoutMap.buildReverseMap(for: frenchLayout)
        for char: Character in ["é", "è"] {
            if reverseMap[char] == nil {
                print("⚠️ '\(char)' not in French reverse map (may need dead key composition)")
            }
        }
    }

    // MARK: - EN / FR

    func testEnglishFrench_roundtrip() throws {
        guard layoutAvailable(language: "en"), layoutAvailable(language: "fr") else {
            throw XCTSkip("English or French layout not installed")
        }
        for word in ["hello", "world", "test"] {
            try assertRoundtrip(word, lang1: "en", lang2: "fr")
        }
    }

    // MARK: - EN / DE

    func testEnglishGerman_roundtrip() throws {
        guard layoutAvailable(language: "en"), layoutAvailable(language: "de") else {
            throw XCTSkip("English or German layout not installed")
        }
        for word in ["hello", "world", "keyboard"] {
            try assertRoundtrip(word, lang1: "en", lang2: "de")
        }
    }

    // MARK: - PT (Portuguese) / EN and PT / RU

    func testPortugueseEnglish_roundtrip() throws {
        guard layoutAvailable(language: "pt"), layoutAvailable(language: "en") else {
            throw XCTSkip("Portuguese or English layout not installed")
        }
        for word in ["hello", "world", "code"] {
            try assertRoundtrip(word, lang1: "pt", lang2: "en")
        }
    }

    func testPortugueseRussian_roundtrip() throws {
        guard layoutAvailable(language: "pt"), layoutAvailable(language: "ru") else {
            throw XCTSkip("Portuguese or Russian layout not installed")
        }
        try assertRoundtrip("teste", lang1: "pt", lang2: "ru")
    }

    // MARK: - IT (Italian) / EN and IT / RU

    func testItalianEnglish_roundtrip() throws {
        guard layoutAvailable(language: "it"), layoutAvailable(language: "en") else {
            throw XCTSkip("Italian or English layout not installed")
        }
        for word in ["hello", "world", "code"] {
            try assertRoundtrip(word, lang1: "it", lang2: "en")
        }
    }

    func testItalianRussian_roundtrip() throws {
        guard layoutAvailable(language: "it"), layoutAvailable(language: "ru") else {
            throw XCTSkip("Italian or Russian layout not installed")
        }
        try assertRoundtrip("test", lang1: "it", lang2: "ru")
    }

    // MARK: - Generic: any two installed layouts should roundtrip

    func testAllInstalledLayouts_roundtrip() throws {
        let layouts = KeyboardLayoutMap.installedLayouts()
        guard layouts.count >= 2 else {
            throw XCTSkip("Fewer than 2 layouts installed")
        }

        for outer in 0..<layouts.count {
            for inner in (outer + 1)..<layouts.count {
                let lang1 = layouts[outer].languages.first ?? layouts[outer].id
                let lang2 = layouts[inner].languages.first ?? layouts[inner].id
                try assertRoundtrip("test", lang1: lang1, lang2: lang2)
            }
        }
    }
}
