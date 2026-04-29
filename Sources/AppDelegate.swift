import Cocoa
import Carbon
import Sparkle

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotkeyManager: HotkeyManager!
    private var textSwitcher: TextSwitcher!
    private var preferencesWindow: PreferencesWindowController?
    private var aboutWindow: AboutWindowController?
    private var updaterController: SPUStandardUpdaterController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        textSwitcher = TextSwitcher()
        hotkeyManager = HotkeyManager { [weak self] in
            self?.textSwitcher.switchSelectedText()
        }
        hotkeyManager.register()

        KeyboardLayoutMap.startObservingLayoutChanges()
        setupMenuBar()
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        }

        if let button = statusItem.button {
            button.toolTip = "Bilingual Switcher"
            button.setAccessibilityLabel("Bilingual Switcher")
            if let iconPath = Bundle.main.path(forResource: "MenuBarIcon", ofType: "png"),
               let image = NSImage(contentsOfFile: iconPath) {
                image.isTemplate = true
                image.size = NSSize(width: 18, height: 18)
                button.image = image
            } else if let image = NSImage(
                systemSymbolName: "keyboard.badge.ellipsis",
                accessibilityDescription: "Bilingual Switcher"
            ) {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "BS"
            }
        }

        let menu = NSMenu()

        let switchItem = NSMenuItem(title: "Switch Selected Text", action: #selector(switchText), keyEquivalent: "")
        switchItem.target = self
        menu.addItem(switchItem)

        menu.addItem(NSMenuItem.separator())

        let hotkeyInfo = NSMenuItem(title: hotkeyDescription(), action: nil, keyEquivalent: "")
        hotkeyInfo.isEnabled = false
        menu.addItem(hotkeyInfo)

        menu.addItem(NSMenuItem.separator())

        let checkUpdatesItem = NSMenuItem(
            title: "Check for Updates...",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        checkUpdatesItem.target = updaterController
        menu.addItem(checkUpdatesItem)

        let prefsItem = NSMenuItem(title: "Preferences...", action: #selector(showPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        let aboutItem = NSMenuItem(
            title: "About Bilingual Switcher",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Bilingual Switcher", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func hotkeyDescription() -> String {
        let modifiers = UserDefaults.standard.hotkeyModifiers
        let keyCode = UserDefaults.standard.hotkeyKeyCode
        return "Hotkey: \(HotkeyDisplayHelper.format(keyCode: keyCode, modifiers: modifiers))"
    }

    // MARK: - Helpers

    private func activateApp() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Actions

    @objc private func switchText() {
        textSwitcher.switchSelectedText()
    }

    @objc private func showPreferences() {
        if preferencesWindow == nil {
            preferencesWindow = PreferencesWindowController { [weak self] in
                guard let self else { return }
                self.hotkeyManager.unregister()
                self.hotkeyManager.register()
                self.setupMenuBar()

                if self.hotkeyManager.registrationFailed {
                    let alert = NSAlert()
                    alert.messageText = "Could not register shortcut"
                    alert.informativeText = """
                        This key combination may be in use by another app \
                        or the system. Please choose a different shortcut.
                        """
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
        preferencesWindow?.showWindow(nil)
        activateApp()
    }

    @objc private func showAbout() {
        if aboutWindow == nil {
            aboutWindow = AboutWindowController()
        }
        aboutWindow?.showWindow(nil)
        activateApp()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
