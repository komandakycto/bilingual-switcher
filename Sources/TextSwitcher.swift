import Cocoa
import Carbon
import UserNotifications

class TextSwitcher {

    func switchSelectedText() {
        guard AXIsProcessTrusted() else {
            showAccessibilityNotification()
            return
        }

        // 1. Save current clipboard
        let pasteboard = NSPasteboard.general
        let savedChangeCount = pasteboard.changeCount
        let savedItems = pasteboard.pasteboardItems?.map { item -> [NSPasteboard.PasteboardType: Data] in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type] = data
                }
            }
            return dict
        }

        // 2. Copy selected text via Cmd+C
        pasteboard.clearContents()
        simulateKeyStroke(keyCode: CGKeyCode(kVK_ANSI_C), flags: .maskCommand)

        // 3. Wait for clipboard to update, then process
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }

            // Check if clipboard actually changed (i.e., something was selected)
            guard pasteboard.changeCount != savedChangeCount,
                  let text = pasteboard.string(forType: .string),
                  !text.isEmpty
            else {
                // Nothing was selected — restore and bail
                self.restoreClipboard(savedItems, to: pasteboard)
                return
            }

            // 4. Convert
            let (converted, direction) = LayoutConverter.convert(text)

            // 5. Paste converted text
            pasteboard.clearContents()
            pasteboard.setString(converted, forType: .string)
            self.simulateKeyStroke(keyCode: CGKeyCode(kVK_ANSI_V), flags: .maskCommand)

            // 6. Switch keyboard layout if the user has enabled this
            if UserDefaults.standard.switchLayoutAfterConversion {
                InputSourceSwitcher.switchTo(direction: direction)
            }

            // 7. Restore original clipboard after paste completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.restoreClipboard(savedItems, to: pasteboard)
            }
        }
    }

    // MARK: - Clipboard

    private func restoreClipboard(_ items: [[NSPasteboard.PasteboardType: Data]]?, to pasteboard: NSPasteboard) {
        guard let items, !items.isEmpty else { return }
        pasteboard.clearContents()
        for itemDict in items {
            let item = NSPasteboardItem()
            for (type, data) in itemDict {
                item.setData(data, forType: type)
            }
            pasteboard.writeObjects([item])
        }
    }

    // MARK: - Keyboard Simulation

    private func simulateKeyStroke(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return }

        keyDown.flags = flags
        keyUp.flags = flags

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    // MARK: - Notifications

    private func showAccessibilityNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Bilingual Switcher"
        content.body = "Accessibility permission required. Open Preferences to grant access."
        let request = UNNotificationRequest(identifier: "accessibility", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
