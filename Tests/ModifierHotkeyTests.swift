import XCTest
import AppKit
import Carbon

final class ModifierHotkeyTests: XCTestCase {

    // MARK: - Hotkey kind routing

    func testKind_SentinelKeyCodeIsModifierOnly() {
        XCTAssertEqual(
            HotkeyManager.kind(keyCode: HotkeyManager.modifierOnlyKeyCode),
            .modifierOnly
        )
    }

    func testKind_RealKeyCodeIsKeyed() {
        XCTAssertEqual(
            HotkeyManager.kind(keyCode: UInt32(kVK_ANSI_S)),
            .keyed
        )
    }

    func testHotkeyIsModifierOnly_DerivesFromKeyCode() {
        let defaults = UserDefaults.standard
        let key = "hotkeyKeyCode"
        let original = defaults.object(forKey: key)
        defer {
            if let original {
                defaults.set(original, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        defaults.hotkeyKeyCode = HotkeyManager.modifierOnlyKeyCode
        XCTAssertTrue(defaults.hotkeyIsModifierOnly)

        defaults.hotkeyKeyCode = UInt32(kVK_ANSI_S)
        XCTAssertFalse(defaults.hotkeyIsModifierOnly)
    }

    // MARK: - Carbon → normalized flags

    func testFlagsFromCarbon_OptionCommand() {
        let flags = HotkeyModifierHelper.flags(fromCarbon: UInt32(optionKey | cmdKey))
        XCTAssertEqual(flags, [.option, .command])
    }

    func testFlagsFromCarbon_ControlShift() {
        let flags = HotkeyModifierHelper.flags(fromCarbon: UInt32(controlKey | shiftKey))
        XCTAssertEqual(flags, [.control, .shift])
    }

    func testFlagsFromCarbon_AllFour() {
        let mask = UInt32(cmdKey | optionKey | controlKey | shiftKey)
        let flags = HotkeyModifierHelper.flags(fromCarbon: mask)
        XCTAssertEqual(flags, [.command, .option, .control, .shift])
    }

    // MARK: - Carbon ↔ NSFlags round trip

    /// Carbon mask → normalized flags → NSEvent → back to Carbon mask must be
    /// lossless for every representative combo. Exercises the new forward
    /// converter alongside the existing `NSEvent.carbonModifiers` reverse.
    func testCarbonRoundTrip_RepresentativeCombos() throws {
        let masks: [UInt32] = [
            UInt32(optionKey | cmdKey),
            UInt32(controlKey | shiftKey),
            UInt32(cmdKey | optionKey | controlKey | shiftKey)
        ]
        for mask in masks {
            let flags = HotkeyModifierHelper.flags(fromCarbon: mask)
            let event = try XCTUnwrap(makeKeyEvent(flags: flags))
            XCTAssertEqual(event.carbonModifiers, mask,
                           "Round trip must preserve the Carbon mask for \(mask)")
        }
    }

    // MARK: - Noise stripping

    func testNormalize_StripsCapsLockAndFunction() {
        let noisy: NSEvent.ModifierFlags = [.option, .command, .capsLock, .function]
        XCTAssertEqual(HotkeyModifierHelper.normalize(noisy), [.option, .command])
    }

    func testNormalize_StripsNumericPad() {
        let noisy: NSEvent.ModifierFlags = [.control, .shift, .numericPad]
        XCTAssertEqual(HotkeyModifierHelper.normalize(noisy), [.control, .shift])
    }

    func testNormalize_KeepsAllFourRelevantFlags() {
        let noisy: NSEvent.ModifierFlags = [.command, .option, .control, .shift, .capsLock]
        XCTAssertEqual(
            HotkeyModifierHelper.normalize(noisy),
            [.command, .option, .control, .shift]
        )
    }

    // MARK: - Combo validation

    func testIsValidCombo_RejectsZeroModifiers() {
        XCTAssertFalse(HotkeyModifierHelper.isValidModifierOnlyCombo(carbonModifiers: 0))
    }

    func testIsValidCombo_RejectsSingleModifier() {
        XCTAssertFalse(
            HotkeyModifierHelper.isValidModifierOnlyCombo(carbonModifiers: UInt32(cmdKey))
        )
        XCTAssertFalse(
            HotkeyModifierHelper.isValidModifierOnlyCombo(carbonModifiers: UInt32(shiftKey))
        )
    }

    func testIsValidCombo_AcceptsTwoModifiers() {
        XCTAssertTrue(
            HotkeyModifierHelper.isValidModifierOnlyCombo(
                carbonModifiers: UInt32(optionKey | cmdKey)
            )
        )
    }

    func testIsValidCombo_AcceptsThreeModifiers() {
        let mask = UInt32(controlKey | optionKey | cmdKey)
        XCTAssertTrue(HotkeyModifierHelper.isValidModifierOnlyCombo(carbonModifiers: mask))
    }

    // MARK: - Helpers

    private func makeKeyEvent(flags: NSEvent.ModifierFlags) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "a",
            charactersIgnoringModifiers: "a",
            isARepeat: false,
            keyCode: 0
        )
    }
}
