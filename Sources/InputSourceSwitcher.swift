import Carbon

enum InputSourceSwitcher {

    static func switchTo(_ layout: LayoutInfo) {
        TISSelectInputSource(layout.source)
    }
}
