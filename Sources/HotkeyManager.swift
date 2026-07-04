import Carbon
import Cocoa

// Global callback storage — Carbon event handlers require a C function pointer
private var globalHotkeyCallback: (() -> Void)?

private func hotkeyEventHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    globalHotkeyCallback?()
    return noErr
}

class HotkeyManager {
    /// Sentinel key code meaning "modifier-only hotkey": the stored modifier
    /// mask holds the combo and there is no regular key. 0xFFFF is never a real
    /// virtual key code, so it cannot collide with a keyed shortcut.
    static let modifierOnlyKeyCode: UInt32 = 0xFFFF

    /// Distinguishes a regular keyed shortcut from a modifier-only tap.
    enum HotkeyKind {
        case keyed
        case modifierOnly
    }

    /// Classifies a stored key code as keyed or modifier-only.
    static func kind(keyCode: UInt32) -> HotkeyKind {
        keyCode == modifierOnlyKeyCode ? .modifierOnly : .keyed
    }

    /// True only inside the XCTest harness (which links `XCTestCase`; the
    /// shipping app does not). Used to suppress the modal accessibility alert in
    /// `registerModifierOnlyHotkey()` so the headless test suite — which
    /// exercises the modifier-only `register()` path in a process that is not
    /// accessibility-trusted — never blocks on `runModal()`.
    private static var isRunningUnderXCTest: Bool {
        NSClassFromString("XCTestCase") != nil
    }

    private var hotkeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var modifierMonitor: ModifierOnlyHotkeyMonitor?
    private let callback: () -> Void

    init(callback: @escaping () -> Void) {
        self.callback = callback
    }

    /// Registers the stored hotkey, routing to the Carbon keyed path or the
    /// modifier-only global-monitor path based on the stored key code.
    func register() {
        switch HotkeyManager.kind(keyCode: UserDefaults.standard.hotkeyKeyCode) {
        case .keyed:
            registerKeyedHotkey()
        case .modifierOnly:
            registerModifierOnlyHotkey()
        }
    }

    /// Carbon `RegisterEventHotKey` path for a regular key + modifier shortcut.
    /// Uses the global C callback because Carbon event handlers require a C
    /// function pointer.
    private func registerKeyedHotkey() {
        globalHotkeyCallback = callback

        let keyCode = UserDefaults.standard.hotkeyKeyCode
        let modifiers = UserDefaults.standard.hotkeyModifiers

        let hotkeyID = EventHotKeyID(
            signature: OSType(0x42530000), // "BS\0\0"
            id: 1
        )

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            hotkeyEventHandler,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        if status != noErr {
            NSLog("Failed to register hotkey: \(status)")
            registrationFailed = true
        } else {
            registrationFailed = false
        }
    }

    /// Modifier-only path: drives a passive `NSEvent` global monitor from the
    /// stored modifier combo. Unlike Carbon, this path has no conflict detection
    /// against other apps' shortcuts, so `registrationFailed` only trips when the
    /// global monitor itself is nil (rare).
    ///
    /// The real failure mode is a missing/revoked Accessibility grant. A global
    /// NSEvent monitor only receives key/flags events when the app is trusted
    /// for accessibility, yet `addGlobalMonitorForEvents` still returns a
    /// non-nil token when untrusted — so the path *looks* registered but the
    /// callback never runs: a silently dead hotkey. The Carbon keyed path fires
    /// without Accessibility and reaches `TextSwitcher`'s own
    /// `AXIsProcessTrusted()` guard (which shows the alert), but this path never
    /// gets that far. So surface the same accessibility alert here when
    /// untrusted. This runs on every `register()` (launch + each prefs save) but
    /// only while the grant is missing, and stops once it is granted.
    private func registerModifierOnlyHotkey() {
        if !AXIsProcessTrusted() && !HotkeyManager.isRunningUnderXCTest {
            TextSwitcher.showAccessibilityNotification()
        }
        let monitor = ModifierOnlyHotkeyMonitor(
            carbonModifiers: UserDefaults.standard.hotkeyModifiers,
            callback: callback
        )
        modifierMonitor = monitor
        registrationFailed = !monitor.start()
    }

    /// Whether the last `register()` call failed (e.g. conflicting shortcut).
    private(set) var registrationFailed = false

    /// Tears down whichever path is active. Both branches are nil-checked, so it
    /// is safe to call regardless of which path `register()` installed and does
    /// not leak monitors across repeated `unregister()`/`register()` cycles (as
    /// `AppDelegate` performs on every prefs save).
    func unregister() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
            eventHandlerRef = nil
        }
        globalHotkeyCallback = nil

        modifierMonitor?.stop()
        modifierMonitor = nil
    }

    deinit {
        unregister()
    }
}

// MARK: - UserDefaults helpers

extension UserDefaults {
    private static let hotkeyKeyCodeKey = "hotkeyKeyCode"
    private static let hotkeyModifiersKey = "hotkeyModifiers"

    var hotkeyKeyCode: UInt32 {
        get {
            let val = integer(forKey: Self.hotkeyKeyCodeKey)
            // Default: S key (keyCode 1)
            return val == 0 && object(forKey: Self.hotkeyKeyCodeKey) == nil
                ? UInt32(kVK_ANSI_S)
                : UInt32(val)
        }
        set { set(Int(newValue), forKey: Self.hotkeyKeyCodeKey) }
    }

    var hotkeyModifiers: UInt32 {
        get {
            let val = integer(forKey: Self.hotkeyModifiersKey)
            // Default: Option + Command
            return val == 0 && object(forKey: Self.hotkeyModifiersKey) == nil
                ? UInt32(optionKey | cmdKey)
                : UInt32(val)
        }
        set { set(Int(newValue), forKey: Self.hotkeyModifiersKey) }
    }

    private static let switchLayoutKey = "switchLayoutAfterConversion"

    var switchLayoutAfterConversion: Bool {
        get { bool(forKey: Self.switchLayoutKey) }
        set { set(newValue, forKey: Self.switchLayoutKey) }
    }
}

// MARK: - Modifier-only hotkey helpers

/// Converts and validates modifier combinations for the modifier-only hotkey
/// path. Comparisons happen in device-independent `NSEvent.ModifierFlags` space
/// (which collapses left/right variants), restricted to exactly
/// `{command, option, control, shift}` so `capsLock`, `function` (Globe) and
/// numeric-pad noise never prevent a match. The reverse direction
/// (flags → Carbon mask) stays on `NSEvent.carbonModifiers`.
enum HotkeyModifierHelper {
    /// The four modifier flags the app recognizes for hotkeys.
    static let relevantFlags: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    /// Restricts arbitrary flags to exactly the four relevant modifiers,
    /// stripping `capsLock`, `function` and numeric-pad noise.
    static func normalize(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection(relevantFlags)
    }

    /// Builds normalized device-independent flags from a Carbon modifier mask.
    static func flags(fromCarbon carbonModifiers: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonModifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if carbonModifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbonModifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if carbonModifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        return flags
    }

    /// True iff at least two of `{command, option, control, shift}` are set —
    /// lone single modifiers are rejected to keep false triggers low.
    static func isValidModifierOnlyCombo(carbonModifiers: UInt32) -> Bool {
        let carbonBits = [cmdKey, optionKey, controlKey, shiftKey]
        let activeCount = carbonBits.filter { carbonModifiers & UInt32($0) != 0 }.count
        return activeCount >= 2
    }
}

// MARK: - Key code display names

enum KeyCodeNames {
    private static let names: [UInt32: String] = [
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H",
        0x05: "G", 0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V",
        0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R",
        0x10: "Y", 0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3",
        0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=", 0x19: "9",
        0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]",
        0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P",
        0x25: "L", 0x26: "J", 0x27: "'", 0x28: "K", 0x29: ";",
        0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2D: "N", 0x2E: "M",
        0x2F: ".", 0x31: "Space", 0x32: "`",
        0x24: "Return", 0x30: "Tab", 0x33: "Delete",
        0x35: "Escape",
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4",
        0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8",
        0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12"
    ]

    static func name(for keyCode: UInt32) -> String {
        return names[keyCode] ?? "Key\(keyCode)"
    }
}
