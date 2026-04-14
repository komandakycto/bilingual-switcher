import Cocoa
import Carbon
import ServiceManagement

class PreferencesWindowController: NSWindowController {
    private let onHotkeyChanged: () -> Void
    private var recorderView: ShortcutRecorderView!
    private var launchAtLoginCheckbox: NSButton!
    private var switchLayoutCheckbox: NSButton!
    private var currentKeyCode: UInt32
    private var currentModifiers: UInt32

    init(onHotkeyChanged: @escaping () -> Void) {
        self.onHotkeyChanged = onHotkeyChanged
        self.currentKeyCode = UserDefaults.standard.hotkeyKeyCode
        self.currentModifiers = UserDefaults.standard.hotkeyModifiers

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 310),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Preferences"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        setupHotkeySection(in: contentView)
        setupBehaviorSection(in: contentView)
        setupGeneralSection(in: contentView)
        setupButtons(in: contentView)
    }

    private func setupHotkeySection(in contentView: NSView) {
        let hotkeyLabel = NSTextField(labelWithString: "Hotkey")
        hotkeyLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        hotkeyLabel.frame = NSRect(x: 20, y: 260, width: 200, height: 20)
        contentView.addSubview(hotkeyLabel)

        let recorderLabel = NSTextField(labelWithString: "Shortcut:")
        recorderLabel.frame = NSRect(x: 20, y: 228, width: 80, height: 24)
        recorderLabel.alignment = .right
        contentView.addSubview(recorderLabel)

        recorderView = ShortcutRecorderView(
            frame: NSRect(x: 110, y: 226, width: 260, height: 28),
            keyCode: currentKeyCode,
            modifiers: currentModifiers
        ) { [weak self] keyCode, modifiers in
            self?.currentKeyCode = keyCode
            self?.currentModifiers = modifiers
        }
        contentView.addSubview(recorderView)

        let hint = NSTextField(labelWithString: "Click the field and press your desired key combination")
        hint.frame = NSRect(x: 110, y: 206, width: 300, height: 16)
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        contentView.addSubview(hint)

        addSeparator(in: contentView, y: 190)
    }

    private func setupBehaviorSection(in contentView: NSView) {
        let behaviorLabel = NSTextField(labelWithString: "Behavior")
        behaviorLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        behaviorLabel.frame = NSRect(x: 20, y: 160, width: 200, height: 20)
        contentView.addSubview(behaviorLabel)

        switchLayoutCheckbox = NSButton(
            checkboxWithTitle: "Switch keyboard layout after conversion",
            target: nil,
            action: nil
        )
        switchLayoutCheckbox.frame = NSRect(x: 110, y: 134, width: 310, height: 22)
        switchLayoutCheckbox.state = UserDefaults.standard.switchLayoutAfterConversion ? .on : .off
        contentView.addSubview(switchLayoutCheckbox)

        let switchHint = NSTextField(
            labelWithString: "Automatically activate the target language layout so you can keep typing"
        )
        switchHint.frame = NSRect(x: 126, y: 116, width: 300, height: 16)
        switchHint.font = .systemFont(ofSize: 11)
        switchHint.textColor = .secondaryLabelColor
        contentView.addSubview(switchHint)

        addSeparator(in: contentView, y: 102)
    }

    private func setupGeneralSection(in contentView: NSView) {
        let generalLabel = NSTextField(labelWithString: "General")
        generalLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        generalLabel.frame = NSRect(x: 20, y: 74, width: 200, height: 20)
        contentView.addSubview(generalLabel)

        launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at Login", target: nil, action: nil)
        launchAtLoginCheckbox.frame = NSRect(x: 110, y: 48, width: 200, height: 22)
        launchAtLoginCheckbox.state = LaunchAtLogin.isEnabled ? .on : .off
        contentView.addSubview(launchAtLoginCheckbox)
    }

    private func setupButtons(in contentView: NSView) {
        let saveButton = NSButton(title: "Save", target: self, action: #selector(savePreferences))
        saveButton.frame = NSRect(x: 330, y: 20, width: 90, height: 32)
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        contentView.addSubview(saveButton)

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelPreferences))
        cancelButton.frame = NSRect(x: 230, y: 20, width: 90, height: 32)
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        contentView.addSubview(cancelButton)
    }

    @objc private func savePreferences() {
        UserDefaults.standard.hotkeyKeyCode = currentKeyCode
        UserDefaults.standard.hotkeyModifiers = currentModifiers

        UserDefaults.standard.switchLayoutAfterConversion = switchLayoutCheckbox.state == .on

        let wantsLaunchAtLogin = launchAtLoginCheckbox.state == .on
        LaunchAtLogin.isEnabled = wantsLaunchAtLogin

        onHotkeyChanged()
        window?.close()
    }

    @objc private func cancelPreferences() {
        window?.close()
    }

    private func addSeparator(in contentView: NSView, y: CGFloat) {
        let separator = NSBox()
        separator.boxType = .separator
        separator.frame = NSRect(x: 20, y: y, width: 400, height: 1)
        contentView.addSubview(separator)
    }
}

// MARK: - Shortcut Recorder View

class ShortcutRecorderView: NSView {
    private var keyCode: UInt32
    private var modifiers: UInt32
    private var isRecording = false
    private var displayField: NSTextField!
    private let onChange: (UInt32, UInt32) -> Void

    init(frame: NSRect, keyCode: UInt32, modifiers: UInt32, onChange: @escaping (UInt32, UInt32) -> Void) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.onChange = onChange
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    private func setupView() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        displayField = NSTextField(labelWithString: shortcutString())
        displayField.frame = bounds.insetBy(dx: 8, dy: 4)
        displayField.autoresizingMask = [.width, .height]
        displayField.alignment = .center
        displayField.font = .systemFont(ofSize: 13)
        addSubview(displayField)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
        displayField.stringValue = "Press shortcut..."
        displayField.textColor = .systemOrange
        layer?.borderColor = NSColor.systemOrange.cgColor
        layer?.borderWidth = 2
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        let carbonModifiers = event.carbonModifiers
        guard carbonModifiers != 0 else { return }

        keyCode = UInt32(event.keyCode)
        modifiers = carbonModifiers
        isRecording = false

        displayField.stringValue = shortcutString()
        displayField.textColor = .labelColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1

        onChange(keyCode, modifiers)
    }

    private func shortcutString() -> String {
        HotkeyDisplayHelper.format(keyCode: keyCode, modifiers: modifiers)
    }
}

// MARK: - NSEvent Carbon modifier conversion

extension NSEvent {
    var carbonModifiers: UInt32 {
        var carbon: UInt32 = 0
        if modifierFlags.contains(.control) { carbon |= UInt32(controlKey) }
        if modifierFlags.contains(.option) { carbon |= UInt32(optionKey) }
        if modifierFlags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if modifierFlags.contains(.command) { carbon |= UInt32(cmdKey) }
        return carbon
    }
}

// MARK: - Hotkey display formatting

enum HotkeyDisplayHelper {
    static func format(keyCode: UInt32, modifiers: UInt32) -> String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("\u{2303}") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("\u{2325}") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("\u{21E7}") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("\u{2318}") }
        parts.append(KeyCodeNames.name(for: keyCode))
        return parts.joined()
    }
}

// MARK: - Launch at Login

enum LaunchAtLogin {
    static var isEnabled: Bool {
        get {
            if #available(macOS 13.0, *) {
                return SMAppService.mainApp.status == .enabled
            }
            return UserDefaults.standard.bool(forKey: "launchAtLogin")
        }
        set {
            if #available(macOS 13.0, *) {
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    NSLog("Failed to \(newValue ? "enable" : "disable") launch at login: \(error)")
                }
            }
            UserDefaults.standard.set(newValue, forKey: "launchAtLogin")
        }
    }
}
