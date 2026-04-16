import Cocoa
import Carbon

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

            // 5. Delete selected text, then paste converted text
            //    In GUI apps Cmd+V replaces the selection, but terminal apps
            //    (Terminal, iTerm, Claude Code) paste without replacing because
            //    terminal selection is a visual overlay — the shell input buffer
            //    doesn't track it.
            //    Universal fix: Right Arrow deselects and moves cursor to the end
            //    of the selection (GUI) or is a no-op at end-of-line (terminal),
            //    then N × Backspace removes exactly the original characters.
            self.simulateKeyStroke(keyCode: CGKeyCode(kVK_RightArrow), flags: [])
            for _ in text {
                self.simulateKeyStroke(keyCode: CGKeyCode(kVK_Delete), flags: [])
            }
            pasteboard.clearContents()
            pasteboard.setString(converted, forType: .string)
            self.simulateKeyStroke(keyCode: CGKeyCode(kVK_ANSI_V), flags: .maskCommand)

            // 6. Switch keyboard layout if the user has enabled this
            if UserDefaults.standard.switchLayoutAfterConversion {
                InputSourceSwitcher.switchTo(direction: direction)
            }

            // 7. Restore original clipboard after paste completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.restoreClipboard(savedItems, to: pasteboard)
            }
        }
    }

    // MARK: - Clipboard

    private func restoreClipboard(_ items: [[NSPasteboard.PasteboardType: Data]]?, to pasteboard: NSPasteboard) {
        guard let items, !items.isEmpty else { return }
        let pasteboardItems = items.map { itemDict -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in itemDict {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.clearContents()
        pasteboard.writeObjects(pasteboardItems)
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
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
            Grant access in System Settings \u{2192} Privacy & Security \u{2192} Accessibility, \
            then restart the app.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
