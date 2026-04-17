import Carbon

enum InputSourceSwitcher {

    /// Switch to the other layout in the user's working pair after conversion.
    static func switchTo(direction: ConversionDirection) {
        guard direction != .auto else { return }

        // Use the recent pair to determine what to switch to.
        // After conversion, the user wants the target layout active.
        if let pair = KeyboardLayoutMap.recentLayoutPair() {
            // The "other" layout in the pair is the one we converted TO.
            let target = direction == .layoutAToB ? pair.previous : pair.current
            TISSelectInputSource(target.source)
        } else {
            // Fallback for 2-layout case without history
            let layouts = KeyboardLayoutMap.installedLayouts()
            guard layouts.count >= 2 else { return }
            let target = direction == .layoutAToB ? layouts[1] : layouts[0]
            TISSelectInputSource(target.source)
        }
    }
}
