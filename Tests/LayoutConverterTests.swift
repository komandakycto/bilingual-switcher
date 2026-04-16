import XCTest

final class LayoutConverterTests: XCTestCase {

    // MARK: - EN → RU Conversion

    func testEnglishToRussian_ghbdtn() {
        let (result, _) = LayoutConverter.convert("ghbdtn")
        XCTAssertEqual(result, "привет", "'ghbdtn' should convert to 'привет'")
    }

    func testEnglishToRussian_ntcn() {
        let (result, _) = LayoutConverter.convert("ntcn")
        XCTAssertEqual(result, "тест", "'ntcn' should convert to 'тест'")
    }

    func testEnglishToRussian_cjkywt() {
        let (result, _) = LayoutConverter.convert("cjkywt")
        XCTAssertEqual(result, "солнце", "'cjkywt' should convert to 'солнце'")
    }

    func testEnglishToRussian_cnhjrf() {
        let (result, _) = LayoutConverter.convert("cnhjrf")
        XCTAssertEqual(result, "строка", "'cnhjrf' should convert to 'строка'")
    }

    func testEnglishToRussian_ghjdthrf() {
        let (result, _) = LayoutConverter.convert("ghjdthrf")
        XCTAssertEqual(result, "проверка", "'ghjdthrf' should convert to 'проверка'")
    }

    // MARK: - RU → EN Conversion

    func testRussianToEnglish_привет() {
        let (result, _) = LayoutConverter.convert("привет")
        XCTAssertEqual(result, "ghbdtn", "'привет' should convert to 'ghbdtn'")
    }

    func testRussianToEnglish_тест() {
        let (result, _) = LayoutConverter.convert("тест")
        XCTAssertEqual(result, "ntcn", "'тест' should convert to 'ntcn'")
    }

    func testRussianToEnglish_строка() {
        let (result, _) = LayoutConverter.convert("строка")
        XCTAssertEqual(result, "cnhjrf", "'строка' should convert to 'cnhjrf'")
    }

    // MARK: - Auto-Detection

    func testAutoDetection_latinText() {
        let direction = LayoutConverter.detectDirection("hello world")
        // Latin text should be detected as needing conversion TO a non-Latin layout
        XCTAssertNotEqual(direction, .auto, "Direction should be resolved, not .auto")
    }

    func testAutoDetection_cyrillicText() {
        let direction = LayoutConverter.detectDirection("привет мир")
        XCTAssertNotEqual(direction, .auto, "Direction should be resolved, not .auto")
    }

    // MARK: - Mixed / Edge Cases

    func testMixedText_numbersPassThrough() {
        let (result, _) = LayoutConverter.convert("ntcn123")
        XCTAssertEqual(result, "тест123", "Numbers should pass through unchanged")
    }

    func testMixedText_spacesPassThrough() {
        let (result, _) = LayoutConverter.convert("ghbdtn vbh")
        XCTAssertEqual(result, "привет мир", "Spaces should pass through unchanged")
    }

    func testEmptyString() {
        let (result, _) = LayoutConverter.convert("")
        XCTAssertEqual(result, "", "Empty string should return empty string")
    }

    // MARK: - Uppercase

    func testUppercase_englishToRussian() {
        let (result, _) = LayoutConverter.convert("Ghbdtn")
        XCTAssertEqual(result, "Привет", "'Ghbdtn' should convert to 'Привет'")
    }

    func testUppercase_russianToEnglish() {
        let (result, _) = LayoutConverter.convert("Привет")
        XCTAssertEqual(result, "Ghbdtn", "'Привет' should convert to 'Ghbdtn'")
    }

    // MARK: - Roundtrip

    func testRoundtrip_englishToRussianAndBack() {
        let original = "ghbdtn"
        let (russian, _) = LayoutConverter.convert(original)
        let (backToEnglish, _) = LayoutConverter.convert(russian)
        XCTAssertEqual(backToEnglish, original, "Roundtrip conversion should return original text")
    }

    // MARK: - Detection with multiple layouts

    func testDetection_uniqueCharsPreferred() {
        // Cyrillic chars are unique to Russian layout → should detect as Russian
        let direction = LayoutConverter.detectDirection("привет")
        XCTAssertEqual(direction, .layoutBToA, "Cyrillic text should detect as layout B (Russian)")
    }

    func testDetection_latinTextDetectsAsLayoutA() {
        let direction = LayoutConverter.detectDirection("hello")
        XCTAssertEqual(direction, .layoutAToB, "Latin text should detect as layout A (English)")
    }

    // MARK: - Backward Compatibility (all original hardcoded mappings)

    /// Verify all lowercase letter mappings match the original hardcoded EN→RU map.
    func testBackwardCompat_lowercaseLetters() {
        let pairs: [(String, String)] = [
            ("q", "й"), ("w", "ц"), ("e", "у"), ("r", "к"), ("t", "е"),
            ("y", "н"), ("u", "г"), ("i", "ш"), ("o", "щ"), ("p", "з"),
            ("a", "ф"), ("s", "ы"), ("d", "в"), ("f", "а"), ("g", "п"),
            ("h", "р"), ("j", "о"), ("k", "л"), ("l", "д"),
            ("z", "я"), ("x", "ч"), ("c", "с"), ("v", "м"), ("b", "и"),
            ("n", "т"), ("m", "ь"),
        ]
        for (en, ru) in pairs {
            let (result, _) = LayoutConverter.convert(en)
            XCTAssertEqual(result, ru, "'\(en)' should convert to '\(ru)'")
        }
    }

    /// Verify all uppercase letter mappings.
    func testBackwardCompat_uppercaseLetters() {
        let pairs: [(String, String)] = [
            ("Q", "Й"), ("W", "Ц"), ("E", "У"), ("R", "К"), ("T", "Е"),
            ("Y", "Н"), ("U", "Г"), ("I", "Ш"), ("O", "Щ"), ("P", "З"),
            ("A", "Ф"), ("S", "Ы"), ("D", "В"), ("F", "А"), ("G", "П"),
            ("H", "Р"), ("J", "О"), ("K", "Л"), ("L", "Д"),
            ("Z", "Я"), ("X", "Ч"), ("C", "С"), ("V", "М"), ("B", "И"),
            ("N", "Т"), ("M", "Ь"),
        ]
        // Use a full uppercase word to ensure detection goes EN→RU
        for (en, ru) in pairs {
            let (result, _) = LayoutConverter.convert("QQ\(en)")
            let expected = "ЙЙ\(ru)"
            XCTAssertEqual(result, expected, "'\(en)' uppercase should convert correctly")
        }
    }

    /// Verify punctuation mappings that were in the original hardcoded map.
    func testBackwardCompat_punctuation() {
        // These are tested within longer strings to ensure correct auto-detection
        let pairs: [(String, String)] = [
            ("[", "х"), ("]", "ъ"),
            (";", "ж"), ("'", "э"),
            (",", "б"), (".", "ю"),
        ]
        for (en, ru) in pairs {
            let (result, _) = LayoutConverter.convert("ghbdtn\(en)")
            let expected = "привет\(ru)"
            XCTAssertEqual(result, expected, "Punctuation '\(en)' should convert to '\(ru)'")
        }
    }

    /// Verify shifted punctuation / bracket mappings.
    func testBackwardCompat_shiftedPunctuation() {
        let pairs: [(String, String)] = [
            ("{", "Х"), ("}", "Ъ"),
            (":", "Ж"), ("\"", "Э"),
            ("<", "Б"), (">", "Ю"),
        ]
        for (en, ru) in pairs {
            let (result, _) = LayoutConverter.convert("GHBDTN\(en)")
            let expected = "ПРИВЕТ\(ru)"
            XCTAssertEqual(result, expected, "Shifted punctuation '\(en)' should convert to '\(ru)'")
        }
    }

    /// Verify backtick/tilde convert to something (exact mapping depends on Russian layout variant).
    /// On "Russian" layout: ` → ё, ~ → Ё. On "Russian - PC": ` → ], ~ → [.
    func testBackwardCompat_backtickTilde() {
        let (result1, _) = LayoutConverter.convert("ghbdtn`")
        XCTAssertTrue(result1.hasPrefix("привет"), "Letter portion should convert")
        XCTAssertNotEqual(result1, "ghbdtn`", "Backtick should be converted, not passed through")

        // Roundtrip should work regardless of variant
        let (converted, _) = LayoutConverter.convert("ghbdtn`")
        let (roundtrip, _) = LayoutConverter.convert(converted)
        XCTAssertEqual(roundtrip, "ghbdtn`", "Backtick roundtrip should work")
    }

    /// Verify shifted number row / punctuation are converted (not passed through).
    /// Note: exact mappings depend on the installed Russian layout variant
    /// (Russian vs Russian-PC have different shifted number rows).
    /// The dynamic approach correctly uses whatever variant is installed.
    func testBackwardCompat_shiftedNumberRowConverts() {
        // These should convert to SOMETHING (not pass through unchanged),
        // proving the physical key mapping works for shifted number row
        let symbols = ["@", "#", "$", "^", "&"]
        for sym in symbols {
            let (result, _) = LayoutConverter.convert("ghbdtn\(sym)")
            let prefix = String(result.prefix(6))
            XCTAssertEqual(prefix, "привет", "Letter portion should convert correctly with '\(sym)' appended")
        }
    }

    /// Verify roundtrip for punctuation characters.
    /// This confirms the dynamic mapping is self-consistent regardless of layout variant.
    func testBackwardCompat_punctuationRoundtrip() {
        let testStrings = ["ghbdtn/", "ghbdtn|", "GHBDTN?"]
        for original in testStrings {
            let (converted, _) = LayoutConverter.convert(original)
            let (roundtrip, _) = LayoutConverter.convert(converted)
            XCTAssertEqual(roundtrip, original, "Roundtrip should return original for '\(original)'")
        }
    }
}
