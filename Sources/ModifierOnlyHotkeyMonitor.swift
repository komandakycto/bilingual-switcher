import AppKit

/// Thin AppKit glue that drives a `ModifierTapDetector` from a single passive
/// global `NSEvent` monitor. It installs one non-consuming
/// `addGlobalMonitorForEvents` covering the modifier-flag, key-down and
/// mouse-down events, translates each observed event into a detector input,
/// and invokes the bound callback when a clean modifier-only tap completes on
/// full release.
///
/// Permission: this needs only the **Accessibility** grant the app already
/// holds for its `CGEvent` injection. A global monitor may observe key events
/// when the app is trusted for accessibility, and mouse-down events need no
/// grant at all. No Input Monitoring grant is required — that gates
/// `CGEventTap`, which this design deliberately avoids. See the plan's
/// "Task 1 finding".
///
/// The app runs as `.accessory` (never focused during a conversion), so no
/// local monitor is installed here — the preferences recorder captures its own
/// events separately.
final class ModifierOnlyHotkeyMonitor {
    /// What to feed the detector for a given event, decided by a pure static
    /// classifier so routing is unit-testable without a live event loop.
    enum DetectorInput: Equatable {
        /// A `flagsChanged` transition to this normalized held-modifier set.
        case flags(NSEvent.ModifierFlags)
        /// A key-down or mouse-down that contaminates an armed gesture.
        case intervening
        /// An event type the detector does not care about.
        case ignore
    }

    /// Event types the single global monitor subscribes to: modifier-flag
    /// changes plus the intervening inputs the trigger contract recognizes — a
    /// non-modifier key press and the three mouse-down buttons.
    ///
    /// Scroll and trackpad gestures are deliberately NOT monitored. The
    /// contract only excludes an intervening key or mouse *click*, not scroll;
    /// and inertial (momentum) scroll delivers `.scrollWheel` events *after* the
    /// user's fingers have left the trackpad, so contaminating on scroll would
    /// silently suppress an otherwise-clean modifier tap — a missed legitimate
    /// trigger, worse than the rare spurious fire it would prevent.
    ///
    /// Keep the intervening event types in sync with `detectorInput`'s
    /// `.intervening` case — an event subscribed here but missing there routes
    /// to `.ignore` and silently fails to contaminate an armed gesture.
    static let monitoredEvents: NSEvent.EventTypeMask = [
        .flagsChanged, .keyDown,
        .leftMouseDown, .rightMouseDown, .otherMouseDown
    ]

    /// Value-type state machine held as a `var` so its mutations persist
    /// across events.
    private var detector: ModifierTapDetector
    private let callback: () -> Void
    private var monitor: Any?

    /// - Parameters:
    ///   - carbonModifiers: the bound combo as a Carbon modifier mask (the
    ///     shape UserDefaults stores); converted to a normalized flag set here.
    ///   - callback: invoked on the main run loop when a clean tap fires.
    init(carbonModifiers: UInt32, callback: @escaping () -> Void) {
        let targetSet = HotkeyModifierHelper.flags(fromCarbon: carbonModifiers)
        self.detector = ModifierTapDetector(targetSet: targetSet)
        self.callback = callback
    }

    /// Pure classifier mapping an event type + its flags to a detector input.
    /// Unit-testable without installing a real global tap.
    static func detectorInput(
        for eventType: NSEvent.EventType,
        modifierFlags: NSEvent.ModifierFlags
    ) -> DetectorInput {
        switch eventType {
        case .flagsChanged:
            return .flags(HotkeyModifierHelper.normalize(modifierFlags))
        // Keep this list in sync with `monitoredEvents` — anything the monitor
        // subscribes to but omits here would fall through to `.ignore`. Scroll
        // and trackpad gestures are intentionally absent (see `monitoredEvents`);
        // they classify as `.ignore` and never contaminate an armed gesture.
        case .keyDown,
             .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return .intervening
        default:
            return .ignore
        }
    }

    /// Installs the single global monitor. No-op if already started, so
    /// repeated `start()` calls never leak a second monitor. Returns whether the
    /// monitor is installed afterwards — `false` means
    /// `addGlobalMonitorForEvents` returned nil, which `HotkeyManager` maps to a
    /// registration failure.
    @discardableResult
    func start() -> Bool {
        if monitor == nil {
            monitor = NSEvent.addGlobalMonitorForEvents(matching: Self.monitoredEvents) { [weak self] event in
                self?.handle(event)
            }
        }
        return monitor != nil
    }

    /// Removes the global monitor. Idempotent.
    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    /// Feeds one observed event into the detector and fires on a clean tap.
    /// Global monitor callbacks already arrive on the main run loop, so the
    /// stored callback runs on the main thread without an extra dispatch.
    private func handle(_ event: NSEvent) {
        switch Self.detectorInput(for: event.type, modifierFlags: event.modifierFlags) {
        case .flags(let heldSet):
            if detector.handleFlags(heldSet) {
                callback()
            }
        case .intervening:
            detector.handleInterveningInput()
        case .ignore:
            break
        }
    }

    deinit {
        stop()
    }
}
