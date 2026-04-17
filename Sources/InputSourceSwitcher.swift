import Carbon

enum InputSourceSwitcher {

    /// Switch to the target layout after conversion.
    /// Determines the target from the currently active layout and conversion direction.
    static func switchTo(direction: ConversionDirection) {
        guard direction != .auto else { return }

        // The target layout is the one we just converted TO.
        // Use the same logic as LayoutConverter: if we converted A→B, activate B.
        let layouts = KeyboardLayoutMap.installedLayouts()
        guard layouts.count >= 2 else { return }

        // Prefer the currently active layout's counterpart, matching LayoutConverter's
        // target selection. If current layout is the source we converted FROM,
        // we want to switch to the target we converted TO.
        if let current = KeyboardLayoutMap.currentLayout() {
            // Find a different layout to switch to
            if let other = layouts.first(where: { $0.id != current.id }) {
                TISSelectInputSource(other.source)
            }
        } else {
            // Fallback: toggle between first two layouts
            let targetLayout = direction == .layoutAToB ? layouts[1] : layouts[0]
            TISSelectInputSource(targetLayout.source)
        }
    }
}
