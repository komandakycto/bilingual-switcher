import XCTest

final class LayoutConverterTests: XCTestCase {

    /// Skip tests that require both English and Russian layouts.
    private func requireEnRu() throws {
        let layouts = KeyboardLayoutMap.installedLayouts()
        guard layouts.count >= 2,
              layouts.contains(where: { $0.languages.contains("en") }),
              layouts.contains(where: { $0.languages.contains("ru") }) else {
            throw XCTSkip("EN+RU layouts required")
        }
    }

    // MARK: - EN → RU Conversion

    func testEnglishToRussian_ghbdtn() throws {
        try requireEnRu()
        let (result, _) = LayoutConverter.convert("ghbdtn")
        XCTAssertEqual(result, "привет")
    }

    func testEnglishToRussian_ntcn() throws {
        try requireEnRu()
        let (result, _) = LayoutConverter.convert("ntcn")
        XCTAssertEqual(result, "тест")
    }

    func testEnglishToRussian_cjkywt() throws {
        try requireEnRu()
        let (result, _) = LayoutConverter.convert("cjkywt")
        XCTAssertEqual(result, "солнце")
    }

    func testEnglishToRussian_cnhjrf() throws {
        try requireEnRu()
        let (result, _) = LayoutConverter.convert("cnhjrf")
        XCTAssertEqual(result, "строка")
    }

    func testEnglishToRussian_ghjdthrf() throws {
        try requireEnRu()
        let (result, _) = LayoutConverter.convert("ghjdthrf")
        XCTAssertEqual(result, "проверка")
    }

    // MARK: - RU → EN Conversion

    func testRussianToEnglish_привет() throws {
        try requireEnRu()
        let (result, _) = LayoutConverter.convert("привет")
        XCTAssertEqual(result, "ghbdtn")
    }

    func testRussianToEnglish_тест() throws {
        try requireEnRu()
        let (result, _) = LayoutConverter.convert("тест")
        XCTAssertEqual(result, "ntcn")
    }

    func testRussianToEnglish_строка() throws {
        try requireEnRu()
        let (result, _) = LayoutConverter.convert("строка")
        XCTAssertEqual(result, "cnhjrf")
    }

    // MARK: - Auto-Detection

    func testAutoDetection_latinText() throws {
        try requireEnRu()
        let direction = LayoutConverter.detectDirection("hello world")
        XCTAssertNotEqual(direction, .auto, "Direction should be resolved, not .auto")
    }

    func testAutoDetection_cyrillicText() throws {
        try requireEnRu()
        let direction = LayoutConverter.detectDirection("привет мир")
        XCTAssertNotEqual(direction, .auto, "Direction should be resolved, not .auto")
    }

    // MARK: - Mixed / Edge Cases

    func testMixedText_numbersPassThrough() throws {
        try requireEnRu()
        let (result, _) = LayoutConverter.convert("ntcn123")
        XCTAssertEqual(result, "тест123")
    }

    func testMixedText_spacesPassThrough() throws {
        try requireEnRu()
        let (result, _) = LayoutConverter.convert("ghbdtn vbh")
        XCTAssertEqual(result, "привет мир")
    }

    func testEmptyString() {
        let (result, _) = LayoutConverter.convert("")
        XCTAssertEqual(result, "")
    }

    // MARK: - Uppercase

    func testUppercase_englishToRussian() throws {
        try requireEnRu()
        let (result, _) = LayoutConverter.convert("Ghbdtn")
        XCTAssertEqual(result, "Привет")
    }

    func testUppercase_russianToEnglish() throws {
        try requireEnRu()
        let (result, _) = LayoutConverter.convert("Привет")
        XCTAssertEqual(result, "Ghbdtn")
    }

    // MARK: - Roundtrip

    func testRoundtrip_englishToRussianAndBack() throws {
        try requireEnRu()
        let original = "ghbdtn"
        let (russian, _) = LayoutConverter.convert(original)
        let (backToEnglish, _) = LayoutConverter.convert(russian)
        XCTAssertEqual(backToEnglish, original)
    }

    // MARK: - Detection with multiple layouts

    func testDetection_uniqueCharsPreferred() throws {
        try requireEnRu()
        let direction = LayoutConverter.detectDirection("привет")
        XCTAssertEqual(direction, .layoutBToA)
    }

    func testDetection_latinTextDetectsAsLayoutA() throws {
        try requireEnRu()
        let direction = LayoutConverter.detectDirection("hello")
        XCTAssertEqual(direction, .layoutAToB)
    }

    // MARK: - Backward Compatibility

    func testBackwardCompat_lowercaseLetters() throws {
        try requireEnRu()
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

    func testBackwardCompat_uppercaseLetters() throws {
        try requireEnRu()
        let pairs: [(String, String)] = [
            ("Q", "Й"), ("W", "Ц"), ("E", "У"), ("R", "К"), ("T", "Е"),
            ("Y", "Н"), ("U", "Г"), ("I", "Ш"), ("O", "Щ"), ("P", "З"),
            ("A", "Ф"), ("S", "Ы"), ("D", "В"), ("F", "А"), ("G", "П"),
            ("H", "Р"), ("J", "О"), ("K", "Л"), ("L", "Д"),
            ("Z", "Я"), ("X", "Ч"), ("C", "С"), ("V", "М"), ("B", "И"),
            ("N", "Т"), ("M", "Ь"),
        ]
        for (en, ru) in pairs {
            let (result, _) = LayoutConverter.convert("QQ\(en)")
            let expected = "ЙЙ\(ru)"
            XCTAssertEqual(result, expected, "'\(en)' uppercase should convert correctly")
        }
    }

    func testBackwardCompat_punctuation() throws {
        try requireEnRu()
        let pairs: [(String, String)] = [
            ("[", "х"), ("]", "ъ"),
            (";", "ж"), ("'", "э"),
            (",", "б"), (".", "ю"),
        ]
        for (en, ru) in pairs {
            let (result, _) = LayoutConverter.convert("ghbdtn\(en)")
            XCTAssertEqual(result, "привет\(ru)", "'\(en)' should convert to '\(ru)'")
        }
    }

    func testBackwardCompat_shiftedPunctuation() throws {
        try requireEnRu()
        let pairs: [(String, String)] = [
            ("{", "Х"), ("}", "Ъ"),
            (":", "Ж"), ("\"", "Э"),
            ("<", "Б"), (">", "Ю"),
        ]
        for (en, ru) in pairs {
            let (result, _) = LayoutConverter.convert("GHBDTN\(en)")
            XCTAssertEqual(result, "ПРИВЕТ\(ru)", "'\(en)' should convert to '\(ru)'")
        }
    }

    func testBackwardCompat_backtickTilde() throws {
        try requireEnRu()
        let (result1, _) = LayoutConverter.convert("ghbdtn`")
        XCTAssertTrue(result1.hasPrefix("привет"), "Letter portion should convert")
        XCTAssertNotEqual(result1, "ghbdtn`", "Backtick should be converted")

        let (converted, _) = LayoutConverter.convert("ghbdtn`")
        let (roundtrip, _) = LayoutConverter.convert(converted)
        XCTAssertEqual(roundtrip, "ghbdtn`", "Backtick roundtrip should work")
    }

    func testBackwardCompat_shiftedNumberRowConverts() throws {
        try requireEnRu()
        let symbols = ["@", "#", "$", "^", "&"]
        for sym in symbols {
            let (result, _) = LayoutConverter.convert("ghbdtn\(sym)")
            let prefix = String(result.prefix(6))
            XCTAssertEqual(prefix, "привет", "Letter portion should convert with '\(sym)' appended")
        }
    }

    func testBackwardCompat_punctuationRoundtrip() throws {
        try requireEnRu()
        let testStrings = ["ghbdtn/", "ghbdtn|", "GHBDTN?"]
        for original in testStrings {
            let (converted, _) = LayoutConverter.convert(original)
            let (roundtrip, _) = LayoutConverter.convert(converted)
            XCTAssertEqual(roundtrip, original, "Roundtrip for '\(original)'")
        }
    }
}
