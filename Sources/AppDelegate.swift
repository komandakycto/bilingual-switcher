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

        setupMenuBar()
        checkAccessibilityOnFirstLaunch()
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        }

        if let button = statusItem.button {
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

    // MARK: - Accessibility

    private func checkAccessibilityOnFirstLaunch() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted {
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = """
                Bilingual Switcher needs Accessibility access to read \
                and replace selected text.

                Please grant access in:
                System Settings \u{2192} Privacy & Security \u{2192} Accessibility

                Then restart the app.
                """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Later")

            if alert.runModal() == .alertFirstButtonReturn {
                guard let url = URL(
                    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                ) else { return }
                NSWorkspace.shared.open(url)
            }
        }
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
                self?.hotkeyManager.unregister()
                self?.hotkeyManager.register()
                self?.setupMenuBar()
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
