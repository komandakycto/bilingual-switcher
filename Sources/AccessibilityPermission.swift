import ApplicationServices
import Cocoa

/// Accessibility (TCC) permission state, and recovery when a stored grant has
/// gone stale.
///
/// macOS records the app's *designated requirement* when the user grants
/// Accessibility, then re-checks it on every `AXIsProcessTrusted()` call.
/// Releases up to 1.2.0 were ad-hoc signed, which pins that requirement to the
/// binary's cdhash — so every update silently invalidated the grant while
/// System Settings kept showing the toggle as ON (issue #12). Builds signed
/// with the project's stable identity produce a cdhash-independent requirement
/// and the grant now survives updates; but anyone upgrading *from* an ad-hoc
/// build still has a cdhash pinned in TCC and has to re-add the entry once.
///
/// That case needs different wording from a plain first run: telling someone
/// who already ticked the box to "grant access and restart" is wrong, because
/// no amount of restarting refreshes a stale requirement. Only removing and
/// re-adding the entry does.
enum AccessibilityPermission {

    /// What the app should tell the user about the Accessibility grant.
    enum State: Equatable {
        /// Trusted right now — nothing to do.
        case granted
        /// Never observed as trusted on this machine: ordinary first run.
        case notGranted
        /// Observed as trusted under an earlier build and untrusted now: the
        /// requirement stored in TCC no longer matches this binary.
        case stale
    }

    /// Last app version seen running with the grant active. Whether this key
    /// exists is what separates "never granted" from "grant went stale".
    static let lastTrustedVersionKey = "lastTrustedBuildVersion"

    /// True only inside the XCTest harness (which links `XCTestCase`; the
    /// shipping app does not). Keeps the headless suite — which exercises the
    /// registration paths in a process that is not accessibility-trusted —
    /// from blocking forever on `runModal()`.
    private static var isRunningUnderXCTest: Bool {
        NSClassFromString("XCTestCase") != nil
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static var bundleVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    /// Pure state decision, split out so it can be unit-tested without TCC.
    static func state(isTrusted: Bool, lastTrustedVersion: String?) -> State {
        if isTrusted { return .granted }
        return lastTrustedVersion == nil ? .notGranted : .stale
    }

    static var currentState: State {
        state(
            isTrusted: isTrusted,
            lastTrustedVersion: UserDefaults.standard.string(forKey: lastTrustedVersionKey)
        )
    }

    /// Remembers that this build ran while trusted. Called at launch and again
    /// when the watcher sees the grant appear, so a later signature change or
    /// revocation reads as `.stale` rather than a first run.
    static func recordTrustIfNeeded() {
        guard isTrusted else { return }
        UserDefaults.standard.set(bundleVersion, forKey: lastTrustedVersionKey)
    }

    // MARK: - Messaging

    static let alertTitle = "Accessibility Permission Required"

    static let notGrantedBody = """
        Bilingual Switcher needs Accessibility access to read and replace the \
        selected text.

        Open System Settings \u{2192} Privacy & Security \u{2192} Accessibility \
        and turn on Bilingual Switcher.
        """

    /// Deliberately explicit that the existing tick-box is the problem. Users
    /// who hit this have already granted the permission and will otherwise
    /// conclude the app is simply broken.
    static let staleBody = """
        Bilingual Switcher already appears in System Settings \u{2192} Privacy & \
        Security \u{2192} Accessibility, but macOS no longer accepts that entry: \
        it was granted to an earlier build with a different code signature.

        Turning the toggle off and on is not enough. Select Bilingual Switcher \
        in the list, remove it with \u{2212}, then add it again with \u{002B} \
        \u{2014} or use Reset Permission below to do that for you.

        This is a one-time step. Future updates will keep the permission.
        """

    static func body(for state: State) -> String {
        state == .stale ? staleBody : notGrantedBody
    }

    // MARK: - Recovery actions

    static func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Drops the stale TCC row so macOS can record a fresh one against this
    /// binary's signature. Returns false when `tccutil` fails, in which case
    /// the caller should fall back to the manual remove-and-re-add route.
    @discardableResult
    static func resetGrant() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task.arguments = ["reset", "Accessibility", bundleID]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
        } catch {
            NSLog("tccutil reset failed to launch: \(error)")
            return false
        }
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            NSLog("tccutil reset exited with status \(task.terminationStatus)")
            return false
        }
        // The row is gone; ask macOS to re-add it with this build's signature.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        return true
    }

    // MARK: - Alert

    /// Guards against stacking modals: `HotkeyManager.register()` runs at
    /// launch and on every preferences save, and `TextSwitcher` checks on every
    /// hotkey press.
    private static var isPresenting = false

    /// Shows the alert matching the current state. No-op while trusted, so
    /// callers may invoke it unconditionally.
    static func presentIfNeeded() {
        let state = currentState
        guard state != .granted, !isPresenting, !isRunningUnderXCTest else { return }
        isPresenting = true
        defer { isPresenting = false }

        let alert = NSAlert()
        alert.messageText = alertTitle
        alert.informativeText = body(for: state)
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        if state == .stale {
            alert.addButton(withTitle: "Reset Permission")
        }
        alert.addButton(withTitle: "Later")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            openSystemSettings()
        case .alertSecondButtonReturn where state == .stale:
            if !resetGrant() { openSystemSettings() }
        default:
            break
        }
    }

    // MARK: - Watching

    private static var watchTimer: Timer?

    /// Polls until the grant appears, then fires `onGranted` once. Removes the
    /// need to tell users to restart the app after ticking the box.
    static func startWatching(onGranted: @escaping () -> Void) {
        watchTimer?.invalidate()
        watchTimer = nil
        guard !isTrusted else {
            recordTrustIfNeeded()
            return
        }
        watchTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            guard isTrusted else { return }
            timer.invalidate()
            watchTimer = nil
            recordTrustIfNeeded()
            onGranted()
        }
    }

    static func stopWatching() {
        watchTimer?.invalidate()
        watchTimer = nil
    }
}
