import Carbon

enum InputSourceSwitcher {

    /// Switch the active keyboard layout to the target layout (the one we just converted TO).
    /// Uses the layout pair from KeyboardLayoutMap to determine which layout to activate.
    static func switchTo(direction: ConversionDirection) {
        let layouts = KeyboardLayoutMap.installedLayouts()
        guard layouts.count >= 2 else { return }

        let targetLayout: LayoutInfo
        switch direction {
        case .layoutAToB:
            targetLayout = layouts[1]
        case .layoutBToA:
            targetLayout = layouts[0]
        case .auto:
            return
        }

        // Activate the target layout's TISInputSource
        TISSelectInputSource(targetLayout.source)
    }
}
