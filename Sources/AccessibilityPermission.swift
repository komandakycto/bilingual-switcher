import ApplicationServices
import Cocoa

/// Accessibility (TCC) permission state and recovery.
///
/// macOS stores the app's designated requirement when the grant is given and
/// re-checks it on every `AXIsProcessTrusted()` call. Releases up to 1.2.0 were
/// ad-hoc signed, pinning that requirement to the binary's cdhash, so updating
/// invalidated the grant while System Settings still showed the toggle on
/// (issue #12). Stable-identity builds survive updates, but anyone upgrading
/// from an ad-hoc build must re-add the entry once — and for them "grant access
/// and restart" is wrong advice, hence the separate `stale` state.
enum AccessibilityPermission {

    enum State: Equatable {
        case granted
        case notGranted
        /// Was trusted under an earlier build: the requirement stored in TCC no
        /// longer matches this binary.
        case stale
    }

    /// Whether this key exists separates "never granted" from "went stale".
    static let lastTrustedVersionKey = "lastTrustedBuildVersion"

    /// The shipping app does not link XCTestCase; the headless suite does, and
    /// runs untrusted, so it must never reach `runModal()`.
    private static var isRunningUnderXCTest: Bool {
        NSClassFromString("XCTestCase") != nil
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static var bundleVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    /// Split out from `currentState` so it is testable without TCC.
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

    /// Drops the stale TCC row so macOS can record a fresh one. Returns false
    /// when `tccutil` fails, leaving the caller to fall back to manual steps.
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
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        return true
    }

    // MARK: - Alert

    private static var isPresenting = false

    private static func activate() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// No-op while trusted, so callers may invoke it unconditionally.
    static func presentIfNeeded() {
        let state = currentState
        guard state != .granted, !isPresenting, !isRunningUnderXCTest else { return }
        isPresenting = true
        defer { isPresenting = false }

        // Accessory app: an alert raised from the background opens behind the
        // frontmost windows, and runModal() then blocks the status item too, so
        // the app looks hung. macOS 14 may refuse the activation request, hence
        // the window level as well.
        activate()

        let alert = NSAlert()
        alert.messageText = alertTitle
        alert.informativeText = body(for: state)
        alert.alertStyle = .warning
        alert.window.level = .floating
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

    /// Polls until the grant appears, then fires `onGranted` once, so the user
    /// never has to restart the app after ticking the box.
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
