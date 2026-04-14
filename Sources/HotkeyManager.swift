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
    private var hotkeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let callback: () -> Void

    init(callback: @escaping () -> Void) {
        self.callback = callback
    }

    func register() {
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

    /// Whether the last `register()` call failed (e.g. conflicting shortcut).
    private(set) var registrationFailed = false

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
            // Default: Control + Option
            return val == 0 && object(forKey: Self.hotkeyModifiersKey) == nil
                ? UInt32(controlKey | optionKey)
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
