import Foundation

enum ConversionDirection {
    case englishToRussian
    case russianToEnglish
    case auto
}

class LayoutConverter {

    // Complete bidirectional mapping: English QWERTY <-> Russian PC (ЙЦУКЕН)
    // Based on physical key positions on a standard keyboard

    private static let englishToRussianMap: [Character: Character] = [
        // Letter row 1 (QWERTY -> ЙЦУКЕН)
        "q": "й", "w": "ц", "e": "у", "r": "к", "t": "е",
        "y": "н", "u": "г", "i": "ш", "o": "щ", "p": "з",
        "[": "х", "]": "ъ",

        // Letter row 2 (ASDF -> ФЫВА)
        "a": "ф", "s": "ы", "d": "в", "f": "а", "g": "п",
        "h": "р", "j": "о", "k": "л", "l": "д", ";": "ж",
        "'": "э",

        // Letter row 3 (ZXCV -> ЯЧСМ)
        "z": "я", "x": "ч", "c": "с", "v": "м", "b": "и",
        "n": "т", "m": "ь", ",": "б", ".": "ю", "/": ".",

        // Uppercase letters
        "Q": "Й", "W": "Ц", "E": "У", "R": "К", "T": "Е",
        "Y": "Н", "U": "Г", "I": "Ш", "O": "Щ", "P": "З",
        "{": "Х", "}": "Ъ",

        "A": "Ф", "S": "Ы", "D": "В", "F": "А", "G": "П",
        "H": "Р", "J": "О", "K": "Л", "L": "Д", ":": "Ж",
        "\"": "Э",

        "Z": "Я", "X": "Ч", "C": "С", "V": "М", "B": "И",
        "N": "Т", "M": "Ь", "<": "Б", ">": "Ю", "?": ",",

        // Backtick / tilde -> ё / Ё
        "`": "ё", "~": "Ё",

        // Shifted number row (Russian PC layout)
        "@": "\"", "#": "№", "$": ";", "^": ":", "&": "?",

        // Backslash row
        "|": "/"
    ]

    // Build reverse map automatically
    private static let russianToEnglishMap: [Character: Character] = {
        var map: [Character: Character] = [:]
        for (en, ru) in englishToRussianMap {
            map[ru] = en
        }
        return map
    }()

    /// Detect whether text is primarily Latin or Cyrillic
    static func detectDirection(_ text: String) -> ConversionDirection {
        var latinCount = 0
        var cyrillicCount = 0

        for scalar in text.unicodeScalars {
            if (0x0041...0x007A).contains(scalar.value) { // Basic Latin letters
                latinCount += 1
            } else if (0x0400...0x04FF).contains(scalar.value) { // Cyrillic block
                cyrillicCount += 1
            }
        }

        if cyrillicCount > latinCount {
            return .russianToEnglish
        }
        return .englishToRussian
    }

    /// Convert text between layouts. Returns the converted text and the direction that was applied.
    static func convert(_ text: String, direction: ConversionDirection = .auto) -> (String, ConversionDirection) {
        let resolvedDirection: ConversionDirection
        if direction == .auto {
            resolvedDirection = detectDirection(text)
        } else {
            resolvedDirection = direction
        }

        let map: [Character: Character]
        switch resolvedDirection {
        case .englishToRussian:
            map = englishToRussianMap
        case .russianToEnglish:
            map = russianToEnglishMap
        case .auto:
            map = englishToRussianMap
        }

        let converted = String(text.map { char in
            map[char] ?? char
        })
        return (converted, resolvedDirection)
    }
}
