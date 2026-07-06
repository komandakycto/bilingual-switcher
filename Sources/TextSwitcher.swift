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

    /// Small settle pause between backspace flood and Unicode injection in
    /// the terminal-fallback path. Terminals drain their input buffer
    /// synchronously, so 50 ms is enough — no renderer IPC queue to worry
    /// about, unlike Electron.
    private static let terminalSettleDelay: TimeInterval = 0.05

    /// Bundle IDs that need the backspace-flood path because their visible
    /// text "selection" is a screen overlay rather than a real selection in
    /// the input buffer — typing does not replace what looks selected.
    /// Anything not in this set uses the selection-replace path, which
    /// works in every app that respects standard "typing replaces
    /// selection" semantics (all Cocoa, Chromium contenteditable, Swing).
    private static let terminalBundles: Set<String> = [
        "com.apple.Terminal",                  // Terminal.app
        "com.googlecode.iterm2",               // iTerm2
        "co.zeit.hyper",                       // Hyper
        "com.github.wez.wezterm",              // WezTerm
        "com.mitchellh.ghostty",               // Ghostty
        "net.kovidgoyal.kitty",                // kitty
        "io.alacritty",                        // Alacritty
        "dev.warp.Warp-Stable",                // Warp
        "dev.warp.Warp-Preview"
    ]

    /// How we deliver the converted text to the focused application.
    enum InjectionStrategy: String {
        /// Default. After Cmd+C the selection is still active in the host
        /// app; we just type the converted text via Unicode injection and
        /// the standard "typing replaces selection" behavior of every
        /// modern text widget (Cocoa, Chromium contenteditable, Java Swing)
        /// does the deletion for us. One injected keystroke per Unicode
        /// chunk — no backspace flood, no race with renderer-queue drain.
        case selectionReplace

        /// Terminal fallback. Shell input buffers don't track visual
        /// selection, so typing appends rather than replaces. We deselect
        /// (Right Arrow) and erase character-by-character (N × Backspace)
        /// before injecting the converted text.
        case backspaceFlood
    }

    /// UserDefaults key for forcing a strategy. Hidden — not exposed in
    /// preferences UI; used for triage via `defaults write`.
    private static let backendOverrideKey = "BILINGUAL_BACKEND"

    /// Decide how to deliver converted text to the focused app. A user
    /// override via UserDefaults wins; otherwise terminal bundle IDs route
    /// to the flood path and everything else to selection-replace.
    static func pickStrategy(bundleID: String?) -> InjectionStrategy {
        if let raw = UserDefaults.standard.string(forKey: backendOverrideKey),
           let forced = InjectionStrategy(rawValue: raw) {
            return forced
        }
        if let id = bundleID, terminalBundles.contains(id) {
            return .backspaceFlood
        }
        return .selectionReplace
    }

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
    /// Off by default — the log contains the user's selected text and the
    /// converted result. Enable per session for triage with:
    ///   defaults write com.komandakycto.bilingual-switcher BILINGUAL_DIAG -bool YES
    private static let diagLogPath = "/tmp/bilingual-switcher.log"
    private static let diagEnabledKey = "BILINGUAL_DIAG"

    static func diag(_ message: String) {
        guard UserDefaults.standard.bool(forKey: diagEnabledKey) else { return }
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
            Self.showAccessibilityNotification()
            return
        }

        Self.diag("--- switchSelectedText start ---")

        // Capture the focused-app bundle ID up front; we'll need it later
        // to pick the settle delay. Doing it before Cmd+C makes it robust
        // against any focus transitions during polling.
        let frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        Self.diag("front app: \(frontBundleID ?? "<unknown>")")

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
                pasteboard: pasteboard,
                frontBundleID: frontBundleID
            )
        }
    }

    private func completeConversion(
        copied: Bool,
        copiedText: String?,
        savedItems: [[NSPasteboard.PasteboardType: Data]],
        pasteboard: NSPasteboard,
        frontBundleID: String?
    ) {
        Self.diag("poll completion copied=\(copied) textLen=\(copiedText?.count ?? -1)")

        guard copied, let text = copiedText, !text.isEmpty else {
            Self.diag("bail — no text from clipboard")
            // Cmd+C put nothing on the clipboard — almost always because no
            // text was selected, or the focused app grabbed the mouse so the
            // terminal never made a selection (full-screen TUIs like Claude
            // Code, vim, htop; in kitty hold Shift while dragging, in iTerm2
            // hold Option). Without feedback this is an invisible no-op that
            // reads as "the hotkey is broken." A beep makes "fired but found
            // nothing to convert" audible so the cause is obvious.
            NSSound.beep()
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

        // Unicode injection never touches the pasteboard, so we can restore
        // the user's clipboard right now — before posting any keystrokes.
        // No race between paste and restore is possible.
        Self.restoreClipboard(savedItems, to: pasteboard)

        // Polling Cmd+C completes in ~30–80 ms — often before the user has
        // physically released the hotkey. With Cmd still held, our
        // synthesized events get hijacked: Cmd+letter becomes a menu
        // shortcut, Cmd+Backspace deletes the whole field. Wait it out.
        let flagsBefore = CGEventSource.flagsState(.hidSystemState)
        Self.diag("flags before modifier wait: 0x\(String(flagsBefore.rawValue, radix: 16))")
        let cleared = Self.waitForModifierRelease()
        let flagsAfter = CGEventSource.flagsState(.hidSystemState)
        Self.diag("flags after wait: 0x\(String(flagsAfter.rawValue, radix: 16)) cleared=\(cleared)")

        let strategy = Self.pickStrategy(bundleID: frontBundleID)
        Self.diag("strategy: \(strategy.rawValue) (bundle=\(frontBundleID ?? "?"))")

        switch strategy {
        case .selectionReplace:
            // The Cmd+C left the user's selection intact. Typing into a
            // live selection replaces it in every text widget that
            // respects standard editing semantics — Cocoa NSText*, Chromium
            // contenteditable (Slack/Discord/VS Code), JTextComponent
            // (JetBrains IDEs). No deletion events needed.
            Self.injectUnicode(converted)

        case .backspaceFlood:
            // Terminals don't see the visual selection at the shell-input
            // level, so typing appends rather than replaces. Deselect and
            // erase character-by-character first.
            Self.simulateKeyStroke(keyCode: CGKeyCode(kVK_RightArrow), flags: [])
            for _ in text {
                Self.simulateKeyStroke(keyCode: CGKeyCode(kVK_Delete), flags: [])
            }
            Thread.sleep(forTimeInterval: Self.terminalSettleDelay)
            Self.injectUnicode(converted)
        }
        Self.diag("injection done")

        if UserDefaults.standard.switchLayoutAfterConversion {
            InputSourceSwitcher.switchTo(direction: direction)
        }
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

    /// Title of the shared accessibility-permission alert. Exposed so a unit
    /// test can assert the wording without running a modal.
    static let accessibilityAlertTitle = "Accessibility Permission Required"

    /// Body of the shared accessibility-permission alert (System Settings →
    /// Privacy & Security → Accessibility).
    static let accessibilityAlertBody = """
        Grant access in System Settings \u{2192} Privacy & Security \u{2192} Accessibility, \
        then restart the app.
        """

    /// Presents the shared accessibility-permission alert. Static so both the
    /// conversion flow here and `HotkeyManager`'s modifier-only registration
    /// surface the *same* message when the Accessibility grant is missing —
    /// the modifier-only global monitor never reaches this flow's own
    /// `AXIsProcessTrusted()` guard, so it must invoke this directly.
    static func showAccessibilityNotification() {
        let alert = NSAlert()
        alert.messageText = accessibilityAlertTitle
        alert.informativeText = accessibilityAlertBody
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
