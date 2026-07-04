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

    // MARK: - ModifierTapDetector state machine

    private let cmd: NSEvent.ModifierFlags = .command
    private let opt: NSEvent.ModifierFlags = .option
    private let cmdOpt: NSEvent.ModifierFlags = [.command, .option]

    /// Drives a detector through a sequence of held-modifier sets, returning the
    /// `handleFlags` result for each step so tests can assert exactly when it
    /// fires.
    private func drive(
        _ detector: inout ModifierTapDetector,
        _ sequence: [NSEvent.ModifierFlags]
    ) -> [Bool] {
        sequence.map { detector.handleFlags($0) }
    }

    func testDetector_CleanTapFiresOnceAtFinalRelease() {
        var detector = ModifierTapDetector(targetSet: cmdOpt)
        let results = drive(&detector, [[], cmd, cmdOpt, cmd, []])
        XCTAssertEqual(results, [false, false, false, false, true])
    }

    func testDetector_CoalescedReleaseFires() {
        var detector = ModifierTapDetector(targetSet: cmdOpt)
        let results = drive(&detector, [[], cmdOpt, []])
        XCTAssertEqual(results, [false, false, true])
    }

    func testDetector_KeyDownBetweenDoesNotFire() {
        var detector = ModifierTapDetector(targetSet: cmdOpt)
        XCTAssertFalse(detector.handleFlags(cmdOpt)) // arm
        detector.handleInterveningInput()            // keyDown contaminates
        XCTAssertFalse(detector.handleFlags([]))     // release: no fire
    }

    func testDetector_MouseDownBetweenDoesNotFire() {
        var detector = ModifierTapDetector(targetSet: cmdOpt)
        XCTAssertFalse(detector.handleFlags(cmdOpt)) // arm
        detector.handleInterveningInput()            // mouse-down (same method)
        XCTAssertFalse(detector.handleFlags([]))     // release: no fire
    }

    func testDetector_ExtraModifierSupersetContaminates() {
        var detector = ModifierTapDetector(targetSet: cmdOpt)
        let superset: NSEvent.ModifierFlags = [.command, .option, .shift]
        let results = drive(&detector, [cmdOpt, superset, cmdOpt, cmd, []])
        XCTAssertEqual(results, [false, false, false, false, false])
    }

    func testDetector_NeverEqualsTargetNeverArms() {
        var detector = ModifierTapDetector(targetSet: cmdOpt)
        let cmdShift: NSEvent.ModifierFlags = [.command, .shift]
        // Passes through {cmd} then {cmd,shift} but never exactly {cmd,opt}.
        let results = drive(&detector, [cmd, cmdShift, cmd, []])
        XCTAssertEqual(results, [false, false, false, false])
    }

    func testDetector_MultiplePartialReleasesFireOnce() {
        var detector = ModifierTapDetector(targetSet: cmdOpt)
        // Arm, dip to a subset and back several times, then fully release.
        let results = drive(&detector, [cmdOpt, cmd, cmdOpt, cmd, cmdOpt, []])
        XCTAssertEqual(results, [false, false, false, false, false, true])
    }

    func testDetector_ReArmRequiresFullRelease() {
        var detector = ModifierTapDetector(targetSet: cmdOpt)
        // Hold cmd, tap opt repeatedly — never an empty set in between: no fire.
        let results = drive(&detector, [cmd, cmdOpt, cmd, cmdOpt, cmd])
        XCTAssertFalse(results.contains(true), "Re-tapping without full release must not fire")
        // Only the transition to empty (a real full release) fires — exactly once.
        XCTAssertTrue(detector.handleFlags([]), "Full release fires")
        XCTAssertFalse(detector.handleFlags([]), "Second empty does not re-fire")
    }

    func testDetector_HoldOneReTapOtherDoesNotMultiFire() {
        var detector = ModifierTapDetector(targetSet: cmdOpt)
        // Complete one clean tap, then keep holding cmd and re-tap opt.
        XCTAssertEqual(drive(&detector, [[], cmd, cmdOpt, cmd, []]).last, true)
        // With cmd held again, re-tapping opt must not produce further fires
        // until another full release to empty.
        let results = drive(&detector, [cmd, cmdOpt, cmd, cmdOpt, cmd])
        XCTAssertFalse(results.contains(true))
    }

    func testDetector_EmptyTargetNeverFires() {
        var detector = ModifierTapDetector(targetSet: [])
        // Any sequence, including repeated empties, must never fire.
        let results = drive(&detector, [[], cmd, cmdOpt, [], opt, []])
        XCTAssertFalse(results.contains(true))
    }

    func testDetector_CapsLockNoiseStillReachesTarget() {
        var detector = ModifierTapDetector(targetSet: cmdOpt)
        // Caller normalizes: a Caps-Lock-on user's raw flags still map to target.
        let noisy: NSEvent.ModifierFlags = [.command, .option, .capsLock]
        let normalized = HotkeyModifierHelper.normalize(noisy)
        XCTAssertEqual(normalized, cmdOpt)
        XCTAssertFalse(detector.handleFlags(normalized)) // arm
        XCTAssertTrue(detector.handleFlags([]))          // fire
    }

    func testDetector_InterveningInputBeforeArmingDoesNotFire() {
        var detector = ModifierTapDetector(targetSet: cmdOpt)
        // Hold a partial subset, press a key (intervening while building toward
        // the combo), then complete the combo and release cleanly.
        XCTAssertFalse(detector.handleFlags(cmd))    // subset — not yet armed
        detector.handleInterveningInput()            // key/click while ⌘ held
        XCTAssertFalse(detector.handleFlags(cmdOpt)) // arm — must keep contamination
        XCTAssertFalse(detector.handleFlags([]),
                       "A key pressed before the combo completed must block the fire")
    }

    func testDetector_InterveningInputWhileNothingHeldDoesNotPoisonNextTap() {
        var detector = ModifierTapDetector(targetSet: cmdOpt)
        // A stray key-down with no modifiers held (ordinary typing) must not
        // contaminate — the very next clean tap still fires.
        detector.handleInterveningInput()            // heldSet empty → no-op
        XCTAssertFalse(detector.handleFlags(cmdOpt)) // arm
        XCTAssertTrue(detector.handleFlags([]),
                      "A stray key at rest must not poison a subsequent clean tap")
    }

    // MARK: - ModifierOnlyHotkeyMonitor classification

    func testMonitorClassify_FlagsChangedStripsNoiseToFlags() {
        let input = ModifierOnlyHotkeyMonitor.detectorInput(
            for: .flagsChanged,
            modifierFlags: [.command, .option, .capsLock]
        )
        XCTAssertEqual(input, .flags([.command, .option]))
    }

    func testMonitorClassify_KeyDownIsIntervening() {
        XCTAssertEqual(
            ModifierOnlyHotkeyMonitor.detectorInput(for: .keyDown, modifierFlags: []),
            .intervening
        )
    }

    func testMonitorClassify_MouseDownsAreIntervening() {
        let mouseDowns: [NSEvent.EventType] = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        for eventType in mouseDowns {
            XCTAssertEqual(
                ModifierOnlyHotkeyMonitor.detectorInput(for: eventType, modifierFlags: []),
                .intervening,
                "\(eventType) must count as intervening input"
            )
        }
    }

    func testMonitorClassify_ScrollAndGesturesAreIntervening() {
        let gestures: [NSEvent.EventType] = [.scrollWheel, .magnify, .rotate, .swipe]
        for eventType in gestures {
            XCTAssertEqual(
                ModifierOnlyHotkeyMonitor.detectorInput(for: eventType, modifierFlags: [.command]),
                .intervening,
                "\(eventType) must count as intervening input"
            )
        }
    }

    func testMonitorClassify_IrrelevantTypeIsIgnored() {
        XCTAssertEqual(
            ModifierOnlyHotkeyMonitor.detectorInput(for: .keyUp, modifierFlags: [.command]),
            .ignore
        )
        XCTAssertEqual(
            ModifierOnlyHotkeyMonitor.detectorInput(for: .mouseMoved, modifierFlags: []),
            .ignore
        )
    }

    // MARK: - ModifierOnlyHotkeyMonitor lifecycle (smoke)

    // A headless xctest process may not deliver real global events and
    // `addGlobalMonitorForEvents` may return nil there, so the absolute install
    // result is environment-dependent; what is invariant is that start/stop
    // handle the token safely and report a consistent result across cycles.
    func testMonitorLifecycle_StartAfterStopReportsSameResult() {
        let monitor = ModifierOnlyHotkeyMonitor(
            carbonModifiers: UInt32(optionKey | cmdKey),
            callback: {}
        )
        let started = monitor.start()
        monitor.stop()
        let restarted = monitor.start()
        XCTAssertEqual(started, restarted,
                       "start() after stop() must report the same install result")
        monitor.stop()
    }

    func testMonitorLifecycle_RepeatedStartStopIsIdempotent() {
        let monitor = ModifierOnlyHotkeyMonitor(
            carbonModifiers: UInt32(controlKey | shiftKey),
            callback: {}
        )
        let first = monitor.start()
        let second = monitor.start() // must not install a second monitor
        XCTAssertEqual(first, second, "Repeated start() must not change monitor state")
        monitor.stop()
        monitor.stop() // second stop is a no-op — must not crash
    }

    // MARK: - HotkeyManager registration routing

    // These exercise the real `register()`/`unregister()` switch (not just the
    // pure `kind()` decision, which the `testKind_*` tests already cover),
    // asserting an observable effect via `registrationFailed`. The stored key
    // code is saved and restored so the shared UserDefaults suite is untouched.

    func testRegister_KeyedPathSucceeds() {
        withStoredHotkey(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(optionKey | cmdKey)) {
            let manager = HotkeyManager(callback: {})
            manager.register()
            XCTAssertFalse(manager.registrationFailed,
                           "Registering a fresh keyed hotkey (⌥⌘S) must succeed")
            manager.unregister()
        }
    }

    func testRegister_ModifierOnlyPathIsDeterministicAndSafe() {
        withStoredHotkey(
            keyCode: HotkeyManager.modifierOnlyKeyCode,
            modifiers: UInt32(optionKey | cmdKey)
        ) {
            let manager = HotkeyManager(callback: {})
            manager.register()
            let first = manager.registrationFailed
            manager.unregister()
            manager.register()
            let second = manager.registrationFailed
            manager.unregister()
            // The global-monitor install result is environment-dependent in a
            // headless process, but identical register() calls must agree — and
            // the register()/unregister() cycle must not crash or leak.
            XCTAssertEqual(first, second,
                           "Identical modifier-only register() calls must report the same result")
        }
    }

    // `start()` returns whether the global monitor is installed. In a headless
    // process `addGlobalMonitorForEvents` may return nil, so the absolute value
    // is environment-dependent; what is invariant is that a repeated start
    // reflects the same monitor state (idempotent, no second install).
    func testMonitorStart_ReturnsConsistentInstallResult() {
        let monitor = ModifierOnlyHotkeyMonitor(
            carbonModifiers: UInt32(optionKey | cmdKey),
            callback: {}
        )
        let first = monitor.start()
        let second = monitor.start()
        XCTAssertEqual(first, second, "Repeated start must reflect the same monitor state")
        monitor.stop()
    }

    // MARK: - Display formatting

    // The formatter emits modifier glyphs in control, option, shift, command
    // order, then the key glyph. For a modifier-only sentinel it must omit the
    // key glyph entirely and render just the modifier symbols.

    func testFormat_ModifierOnlyOmitsKeyGlyph() {
        XCTAssertEqual(
            HotkeyDisplayHelper.format(
                keyCode: HotkeyManager.modifierOnlyKeyCode,
                modifiers: UInt32(optionKey | cmdKey)
            ),
            "\u{2325}\u{2318}" // ⌥⌘
        )
    }

    func testFormat_KeyedShortcutIncludesKeyGlyph() {
        XCTAssertEqual(
            HotkeyDisplayHelper.format(
                keyCode: UInt32(kVK_ANSI_S),
                modifiers: UInt32(optionKey | cmdKey)
            ),
            "\u{2325}\u{2318}S" // ⌥⌘S
        )
    }

    // Note: the recorder's `flagsChanged` peak-accumulation + release-to-empty
    // path is driven by live `NSEvent`s and firstResponder state, so it is
    // verified manually (Post-Completion). Its validity rule
    // (`isValidModifierOnlyCombo`) is covered by the combo-validation tests
    // above.

    // MARK: - Helpers

    /// Runs `body` with the stored hotkey temporarily set to the given values,
    /// restoring whatever was in UserDefaults afterwards so the shared suite is
    /// not mutated across tests.
    private func withStoredHotkey(keyCode: UInt32, modifiers: UInt32, _ body: () -> Void) {
        let defaults = UserDefaults.standard
        let keyCodeKey = "hotkeyKeyCode"
        let modifiersKey = "hotkeyModifiers"
        let originalKeyCode = defaults.object(forKey: keyCodeKey)
        let originalModifiers = defaults.object(forKey: modifiersKey)
        defer {
            if let originalKeyCode {
                defaults.set(originalKeyCode, forKey: keyCodeKey)
            } else {
                defaults.removeObject(forKey: keyCodeKey)
            }
            if let originalModifiers {
                defaults.set(originalModifiers, forKey: modifiersKey)
            } else {
                defaults.removeObject(forKey: modifiersKey)
            }
        }
        defaults.hotkeyKeyCode = keyCode
        defaults.hotkeyModifiers = modifiers
        body()
    }

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
