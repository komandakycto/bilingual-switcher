import AppKit

/// Pure state machine that recognizes a "modifier-only tap": the bound modifier
/// combination is pressed and then **fully released**, with no other key or
/// mouse-down in between. It fires exactly once, on the transition to an empty
/// held-modifier set (full release) — never while any modifier is still down.
///
/// Firing only on full release is the correctness hinge: when the callback runs
/// no modifier is physically held, so the downstream conversion flow can post a
/// clean `Cmd+C` (and the terminal backspace-flood keystrokes) with no stray
/// modifier bleed. See the plan's "Trigger state machine" section.
///
/// AppKit-free logic: it operates purely on `NSEvent.ModifierFlags` sets that
/// the caller has already normalized to `{command, option, control, shift}`
/// via `HotkeyModifierHelper.normalize`. Feed it `handleFlags` on every
/// `flagsChanged` and `handleInterveningInput` on every key-down / mouse-down.
struct ModifierTapDetector {
    /// The bound modifier combination (normalized to the four relevant flags).
    private let targetSet: NSEvent.ModifierFlags

    /// True once a clean `heldSet == targetSet` press has been seen and not yet
    /// released or contaminated.
    private var armed = false

    /// True if, while armed, any extra modifier or intervening input arrived —
    /// which disqualifies the current gesture from firing.
    private var contaminated = false

    init(targetSet: NSEvent.ModifierFlags) {
        self.targetSet = targetSet
    }

    /// Handles a `flagsChanged` transition to `heldSet` (currently-held
    /// modifiers, normalized). Returns `true` exactly when the tap fires.
    ///
    /// Branch precedence (must be evaluated in this order):
    /// 1. empty → fire iff `armed && !contaminated`, then reset unconditionally.
    /// 2. `heldSet == targetSet` while not armed → arm.
    /// 3. `heldSet` holds a modifier outside `targetSet` (superset/divergence)
    ///    → contaminate.
    /// 4. otherwise (non-empty strict subset — mid-press/mid-release) → no-op.
    mutating func handleFlags(_ heldSet: NSEvent.ModifierFlags) -> Bool {
        if heldSet.isEmpty {
            let fired = armed && !contaminated
            armed = false
            contaminated = false
            return fired
        }

        if heldSet == targetSet, !armed {
            armed = true
            contaminated = false
            return false
        }

        if !heldSet.subtracting(targetSet).isEmpty {
            contaminated = true
            return false
        }

        return false
    }

    /// Records intervening non-modifier input (a key-down or mouse-down). While
    /// armed this contaminates the gesture so it will not fire on release — this
    /// is what keeps `⌥⌘C` and `⌥⌘`+click working normally.
    mutating func handleInterveningInput() {
        if armed {
            contaminated = true
        }
    }
}
