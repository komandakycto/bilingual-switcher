import Carbon

enum InputSourceSwitcher {

    /// Switch the active keyboard layout to match the target language.
    /// After converting EN→RU text, switch layout to Russian so the user can keep typing in Russian.
    static func switchTo(direction: ConversionDirection) {
        let targetLanguage: String
        switch direction {
        case .englishToRussian:
            targetLanguage = "ru"
        case .russianToEnglish:
            targetLanguage = "en"
        case .auto:
            return
        }

        let filter = [
            kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource
        ] as CFDictionary

        guard let sources = TISCreateInputSourceList(filter, false)?
            .takeRetainedValue() as? [TISInputSource] else {
            return
        }

        for source in sources {
            guard let languagesRef = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else {
                continue
            }
            let languages = Unmanaged<CFArray>.fromOpaque(languagesRef).takeUnretainedValue() as? [String] ?? []

            if languages.first == targetLanguage {
                TISSelectInputSource(source)
                return
            }
        }
    }
}
