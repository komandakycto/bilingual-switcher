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

    /// True if any extra modifier or intervening input arrived while at least
    /// one target modifier was held — which disqualifies the current gesture
    /// from firing. Only a full release (empty `heldSet`) clears it.
    private var contaminated = false

    /// The most recent held-modifier set (normalized). Tracked so that
    /// intervening input can contaminate a gesture that is *building toward* the
    /// target (a non-empty subset), not only a fully-armed one.
    private var heldSet: NSEvent.ModifierFlags = []

    init(targetSet: NSEvent.ModifierFlags) {
        self.targetSet = targetSet
    }

    /// Handles a `flagsChanged` transition to `heldSet` (currently-held
    /// modifiers, normalized). Returns `true` exactly when the tap fires.
    ///
    /// Branch precedence (must be evaluated in this order):
    /// 1. empty → fire iff `armed && !contaminated`, then reset unconditionally.
    ///    Full release is the *only* point that clears contamination.
    /// 2. `heldSet == targetSet` while not armed → arm. This must **not** clear
    ///    contamination: a stray key/click pressed while a partial subset was
    ///    held (before the combo completed) has to survive to block the fire.
    /// 3. `heldSet` holds a modifier outside `targetSet` (superset/divergence)
    ///    → contaminate.
    /// 4. otherwise (non-empty strict subset — mid-press/mid-release) → no-op.
    mutating func handleFlags(_ heldSet: NSEvent.ModifierFlags) -> Bool {
        self.heldSet = heldSet

        if heldSet.isEmpty {
            let fired = armed && !contaminated
            armed = false
            contaminated = false
            return fired
        }

        if heldSet == targetSet, !armed {
            armed = true
            return false
        }

        if !heldSet.subtracting(targetSet).isEmpty {
            contaminated = true
            return false
        }

        return false
    }

    /// Records intervening non-modifier input (a key-down or mouse-down). It
    /// contaminates the gesture whenever **any** modifier
    /// is currently held — i.e. while building toward the combo *or* fully
    /// armed — so it will not fire on release. This is what keeps `⌥⌘C`,
    /// `⌥⌘`+click and "hold ⌘, press a key, then add ⌥" working normally.
    ///
    /// The `heldSet`-non-empty guard is essential: a stray key-down while
    /// nothing is held (ordinary typing) must not poison a later clean tap.
    mutating func handleInterveningInput() {
        if !heldSet.isEmpty {
            contaminated = true
        }
    }
}
