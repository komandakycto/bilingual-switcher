import Cocoa
import Carbon

class TextSwitcher {

    // MARK: - Tunables

    /// Maximum time to wait for the focused app to fill the pasteboard after
    /// Cmd+C. Polling stops as soon as `changeCount` ticks. 500 ms is generous
    /// for slow Electron apps; well under the user-perceived latency budget
    /// for a hotkey gesture.
    private static let copyTimeout: TimeInterval = 0.5

    /// Interval between `changeCount` reads while waiting on Cmd+C. Reads are
    /// cheap, but each requeues `asyncAfter`, which has its own overhead.
    private static let copyPollInterval: TimeInterval = 0.01

    /// `CGEventKeyboardSetUnicodeString` writes into a fixed UniChar buffer in
    /// the event payload. The documented & widely cited size is 20 UTF-16
    /// code units per event; longer strings are silently truncated. See
    /// `<CoreGraphics/CGEvent.h>` and isamert.net "Typing (unicode) characters
    /// programmatically on Linux and macOS".
    static let unicodeChunkLimit = 20

    /// Tiny pause between Unicode chunks. Some apps drop chunks posted
    /// back-to-back at HID rate; Espanso and similar tools default to a
    /// 1–4 ms delay. Conservative middle ground.
    private static let interChunkDelay: useconds_t = 2_000

    /// Maximum time to block waiting for hotkey modifiers to release before
    /// posting keystrokes. Real release latency is typically 50–200 ms;
    /// 500 ms covers users who hold the hotkey longer.
    private static let modifierReleaseTimeout: TimeInterval = 0.5
    private static let modifierReleasePollInterval: TimeInterval = 0.005

    /// Wait between the last backspace and the first Unicode-injection event.
    /// Slack's Chromium renderer drains backspaces ~asynchronously from its
    /// main process IPC queue; even when our HID events have all flowed to
    /// Slack, the renderer is still applying them. If Unicode injection
    /// fires while late backspaces are still being applied, the result is
    /// "typed text appears briefly, then later backspaces eat it". Empirical
    /// drain rate is ~10 ms per character. Min/max bound the latency for
    /// short text and pathological long text respectively.
    private static let postBackspacePerChar: TimeInterval = 0.010
    private static let postBackspaceMin: TimeInterval = 0.10
    private static let postBackspaceMax: TimeInterval = 1.5

    /// Modifiers that hijack our synthesized keystrokes when held:
    /// - Cmd+Backspace = "delete to start of line" in most text fields
    /// - Cmd+letter = menu/keyboard shortcut, eats Unicode injection
    /// - Opt+Backspace = "delete word"
    /// Shift is omitted: it has no shortcut role for our keys and doesn't
    /// affect `keyboardSetUnicodeString` (the unicode string is what types,
    /// not the virtual key).
    private static let hijackingModifiers: CGEventFlags =
        [.maskCommand, .maskAlternate, .maskControl]

    /// One CGEventSource reused for every posted event. Constructing this
    /// object per event was a measurable cost in the old code — for a 50-char
    /// selection we'd build it ~100 times per hotkey press.
    private static let eventSource: CGEventSource? = CGEventSource(stateID: .combinedSessionState)

    /// Path to a plain-text diagnostic log appended on every conversion.
    /// `log show --predicate 'process == "BilingualSwitcher"'` filters out
    /// NSLog messages on recent macOS unless the system is in verbose mode,
    /// so we write directly to a file the user can read with `cat`.
    private static let diagLogPath = "/tmp/bilingual-switcher.log"

    static func diag(_ message: String) {
        let line = "\(Self.diagTimestamp()) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: diagLogPath)
        if FileManager.default.fileExists(atPath: diagLogPath) {
            if let handle = try? FileHandle(forWritingTo: url) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
                return
            }
        }
        try? data.write(to: url)
    }

    private static let diagFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    private static func diagTimestamp() -> String {
        diagFormatter.string(from: Date())
    }

    // MARK: - Main flow

    func switchSelectedText() {
        guard AXIsProcessTrusted() else {
            showAccessibilityNotification()
            return
        }

        Self.diag("--- switchSelectedText start ---")

        let pasteboard = NSPasteboard.general
        let savedItems = Self.snapshot(of: pasteboard)
        pasteboard.clearContents()
        let baselineChangeCount = pasteboard.changeCount

        Self.simulateKeyStroke(keyCode: CGKeyCode(kVK_ANSI_C), flags: .maskCommand)
        Self.diag("posted Cmd+C, baselineChangeCount=\(baselineChangeCount)")

        // Capture self strongly. The clipboard was just cleared; if a
        // `[weak self]` early-returned because self deallocated mid-poll,
        // the user's clipboard would stay cleared. TextSwitcher is owned by
        // AppDelegate for the app's lifetime, so the only extra retention
        // here is ~500 ms during the hotkey operation — no cycle, since
        // this closure is not stored on self.
        Self.pollForClipboardChange(
            initialChangeCount: baselineChangeCount,
            timeout: Self.copyTimeout,
            pollInterval: Self.copyPollInterval,
            pasteboard: pasteboard
        ) { didChange in
            self.completeConversion(
                copied: didChange,
                copiedText: pasteboard.string(forType: .string),
                savedItems: savedItems,
                pasteboard: pasteboard
            )
        }
    }

    private func completeConversion(
        copied: Bool,
        copiedText: String?,
        savedItems: [[NSPasteboard.PasteboardType: Data]],
        pasteboard: NSPasteboard
    ) {
        Self.diag("poll completion copied=\(copied) textLen=\(copiedText?.count ?? -1)")

        guard copied, let text = copiedText, !text.isEmpty else {
            Self.diag("bail — no text from clipboard")
            Self.restoreClipboard(savedItems, to: pasteboard)
            return
        }

        guard KeyboardLayoutMap.installedLayouts().count >= 2 else {
            showSingleLayoutNotification()
            Self.restoreClipboard(savedItems, to: pasteboard)
            return
        }

        let (converted, direction) = LayoutConverter.convert(text)
        let chunkCount = Self.chunkUTF16(converted, maxCodeUnits: Self.unicodeChunkLimit).count
        Self.diag("text=\(text.prefix(120))")
        Self.diag("converted=\(converted.prefix(120)) chunks=\(chunkCount)")

        // The Unicode-injection paste path does NOT touch the pasteboard, so
        // we can restore the user's clipboard right now — before posting any
        // keystrokes. This eliminates the prior race in which a slow host
        // read the clipboard for Cmd+V after our restore timer had already
        // put the original content back.
        Self.restoreClipboard(savedItems, to: pasteboard)

        // Polling Cmd+C completes in ~30–80 ms on Slack — often before the
        // user has physically released the hotkey. With Cmd still held,
        // Backspace becomes Cmd+Backspace (delete entire line in one go)
        // and Unicode events become Cmd+char (eaten as shortcuts in
        // Slack/Chromium). Wait until the user has lifted the modifier
        // keys, with a generous upper bound.
        let flagsBefore = CGEventSource.flagsState(.hidSystemState)
        Self.diag("flags before modifier wait: 0x\(String(flagsBefore.rawValue, radix: 16))")
        let cleared = Self.waitForModifierRelease()
        let flagsAfter = CGEventSource.flagsState(.hidSystemState)
        Self.diag("flags after wait: 0x\(String(flagsAfter.rawValue, radix: 16)) cleared=\(cleared)")

        Self.simulateKeyStroke(keyCode: CGKeyCode(kVK_RightArrow), flags: [])
        for _ in text {
            Self.simulateKeyStroke(keyCode: CGKeyCode(kVK_Delete), flags: [])
        }
        let settle = Self.postBackspaceDelay(forCharCount: text.count)
        Self.diag("posted \(text.count) backspaces, settling for \(Int(settle * 1000)) ms")

        // Give the host time to drain backspaces from its IPC queue before
        // the renderer sees Unicode events. Slack/Electron drop or mis-route
        // unicode chunks if they arrive while backspace processing is
        // still draining.
        Thread.sleep(forTimeInterval: settle)

        Self.injectUnicode(converted)
        Self.diag("injectUnicode done")

        if UserDefaults.standard.switchLayoutAfterConversion {
            InputSourceSwitcher.switchTo(direction: direction)
        }
    }

    /// Settle time between the last backspace and the first Unicode-injection
    /// chunk. Scales with deletion count, clamped to a sane window.
    static func postBackspaceDelay(forCharCount count: Int) -> TimeInterval {
        let raw = postBackspaceMin + postBackspacePerChar * Double(max(0, count))
        return min(max(postBackspaceMin, raw), postBackspaceMax)
    }

    // MARK: - Pasteboard helpers (static + internal — tests drive them directly)

    /// Snapshot every type+data pair on the pasteboard so we can re-create the
    /// items later. Reads happen synchronously on the caller's queue.
    static func snapshot(of pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        return pasteboard.pasteboardItems?.map { item -> [NSPasteboard.PasteboardType: Data] in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type] = data
                }
            }
            return dict
        } ?? []
    }

    /// Re-populate the pasteboard with the previously snapshotted items.
    /// An empty `items` array is a valid saved state — it means the original
    /// pasteboard was empty, and "restoring" must put it back into that
    /// state (clear it), not no-op and leave intermediate Cmd+C content
    /// behind.
    static func restoreClipboard(
        _ items: [[NSPasteboard.PasteboardType: Data]],
        to pasteboard: NSPasteboard
    ) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let pasteboardItems = items.map { dict -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in dict {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(pasteboardItems)
    }

    /// Wait on the main queue (without blocking it) for `pasteboard.changeCount`
    /// to differ from `initialChangeCount`, or for `timeout` to elapse.
    /// `completion` is always called exactly once, on the main queue, with
    /// `true` if the clipboard changed and `false` on timeout.
    static func pollForClipboardChange(
        initialChangeCount: Int,
        timeout: TimeInterval,
        pollInterval: TimeInterval,
        pasteboard: NSPasteboard,
        completion: @escaping (Bool) -> Void
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        func poll() {
            if pasteboard.changeCount != initialChangeCount {
                completion(true)
                return
            }
            if Date() >= deadline {
                completion(false)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + pollInterval, execute: poll)
        }
        poll()
    }

    // MARK: - Modifier-release wait

    /// Block until none of `mask` is currently held on the hardware keyboard,
    /// or `timeout` elapses. Synchronous so we can sequence cleanly with the
    /// subsequent keystroke posts. Reads via `.hidSystemState` because that
    /// reflects only physical keys, regardless of any synthesized events we
    /// or others have injected.
    @discardableResult
    static func waitForModifierRelease(
        mask: CGEventFlags = hijackingModifiers,
        timeout: TimeInterval = modifierReleaseTimeout,
        pollInterval: TimeInterval = modifierReleasePollInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if CGEventSource.flagsState(.hidSystemState).isDisjoint(with: mask) {
                return true
            }
            Thread.sleep(forTimeInterval: pollInterval)
        }
        return false
    }

    // MARK: - Unicode keyboard injection

    /// Post the converted text as a sequence of synthetic Unicode keyboard
    /// events. This is the modern macOS substitute for clipboard-based paste:
    /// no Cmd+V, no clipboard state, no race.
    static func injectUnicode(_ string: String) {
        let chunks = chunkUTF16(string, maxCodeUnits: unicodeChunkLimit)
        for (offset, chunk) in chunks.enumerated() {
            chunk.withUnsafeBufferPointer { buffer in
                postUnicodeEvent(buffer: buffer, keyDown: true)
                postUnicodeEvent(buffer: buffer, keyDown: false)
            }
            if offset < chunks.count - 1 {
                usleep(interChunkDelay)
            }
        }
    }

    private static func postUnicodeEvent(buffer: UnsafeBufferPointer<UniChar>, keyDown: Bool) {
        guard let event = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: keyDown)
        else { return }
        event.flags = []
        event.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
        event.post(tap: .cghidEventTap)
    }

    /// Split `string` into UTF-16 segments of at most `maxCodeUnits` units,
    /// packed scalar by scalar so a non-BMP Unicode scalar (e.g. emoji) — which
    /// occupies a surrogate pair of two UTF-16 code units — is never split
    /// across chunks. Splitting a surrogate pair would send malformed UTF-16
    /// to `CGEventKeyboardSetUnicodeString`, producing replacement characters
    /// or dropped input. Empty input yields `[]`. `maxCodeUnits` must be at
    /// least 2 to accommodate any non-BMP scalar.
    static func chunkUTF16(_ string: String, maxCodeUnits: Int) -> [[UniChar]] {
        precondition(maxCodeUnits > 0, "maxCodeUnits must be positive")
        guard !string.isEmpty else { return [] }

        var chunks: [[UniChar]] = []
        var current: [UniChar] = []
        current.reserveCapacity(maxCodeUnits)

        for scalar in string.unicodeScalars {
            let value = scalar.value
            let needed = value <= 0xFFFF ? 1 : 2
            precondition(needed <= maxCodeUnits,
                         "maxCodeUnits too small to fit a single non-BMP scalar")

            if current.count + needed > maxCodeUnits {
                chunks.append(current)
                current.removeAll(keepingCapacity: true)
            }

            if value <= 0xFFFF {
                current.append(UniChar(value))
            } else {
                // Encode supplementary scalar as UTF-16 surrogate pair.
                // Reference: Unicode Standard §3.9, RFC 2781 §2.1.
                let shifted = value - 0x10000
                current.append(UniChar(0xD800 + (shifted >> 10)))
                current.append(UniChar(0xDC00 + (shifted & 0x3FF)))
            }
        }
        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }

    // MARK: - Keyboard simulation

    static func simulateKeyStroke(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: false)
        else { return }
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    // MARK: - Notifications

    private func showSingleLayoutNotification() {
        let alert = NSAlert()
        alert.messageText = "Two Keyboard Layouts Required"
        alert.informativeText = """
            Add a second keyboard layout in System Settings → Keyboard → \
            Input Sources to enable text conversion.
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

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
