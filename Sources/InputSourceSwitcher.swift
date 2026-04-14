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

        guard let sources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            return
        }

        for source in sources {
            guard let categoryRef = TISGetInputSourceProperty(source, kTISPropertyInputSourceCategory) else {
                continue
            }
            let category = Unmanaged<CFString>.fromOpaque(categoryRef).takeUnretainedValue() as String
            guard category == (kTISCategoryKeyboardInputSource as String) else {
                continue
            }

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
