# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

macOS menu bar app that converts selected text between any two installed keyboard layouts (e.g., English↔Russian) via a global hotkey. Uses `UCKeyTranslate` to dynamically read layout data from the OS — no hardcoded mappings.

## Build Commands

```bash
make setup    # Download Sparkle framework (required before first build)
make          # Build universal binary (arm64 + x86_64) → build/BilingualSwitcher.app
make test     # Compile and run XCTest suite (125 tests)
make lint     # SwiftLint in --strict mode (CI enforces this)
make run      # Build + launch the app
make install  # Copy to /Applications
make clean    # Remove build/
```

No SPM or Xcode project — just `swiftc` via Makefile. The test target compiles all `Sources/*.swift` (excluding `main.swift`) + `Tests/*.swift` into an `.xctest` bundle.

## Architecture

**Data flow on hotkey press:**
```
HotkeyManager (Carbon hotkey or NSEvent modifier monitor) → TextSwitcher.switchSelectedText()
  → Cmd+C (copy selected text)
  → LayoutConverter.convert(text) {
      KeyboardLayoutMap.buildReverseMap(source)  // char → physical key
      KeyboardLayoutMap.buildCharacterMap(target) // physical key → char
    }
  → Right Arrow + N×Backspace + Cmd+V (delete original, paste converted)
  → InputSourceSwitcher.switchTo() (optional: activate target layout)
  → Restore original clipboard
```

**Key components:**
- `KeyboardLayoutMap` — UCKeyTranslate wrapper. Enumerates installed layouts via TIS APIs, builds character maps per layout, caches them with NSLock thread safety. Observes `kTISNotifyEnabledKeyboardInputSourcesChanged` to invalidate on layout install/uninstall.
- `LayoutConverter` — Detects source layout by scoring text against each layout's character set (unique chars weighted higher). For 3+ layouts, prefers the currently active layout as target via `TISCopyCurrentKeyboardInputSource`.
- `TextSwitcher` — Orchestrates the copy→convert→paste flow using `CGEvent` keyboard simulation. The Right Arrow + N×Backspace pattern (instead of relying on Cmd+V replacing selection) fixes terminal apps where selection is visual-only.
- `InputSourceSwitcher` — Activates the target layout after conversion. Uses current layout to determine counterpart (not hardcoded indices).
- `HotkeyManager` — Global hotkey registration with a dual path, chosen by a sentinel key code (`modifierOnlyKeyCode = 0xFFFF`). Keyed shortcuts (e.g. ⌥⌘S) use Carbon `RegisterEventHotKey`; modifier-only combos (e.g. ⌥⌘) use a passive global `NSEvent` monitor (`ModifierOnlyHotkeyMonitor`). Both routes share `register()`/`unregister()`/`registrationFailed`. Settings in UserDefaults (`hotkeyKeyCode`/`hotkeyModifiers`, backward compatible). `HotkeyModifierHelper` converts Carbon masks ↔ normalized `NSEvent.ModifierFlags` and validates combos (≥2 modifiers). Needs only Accessibility (already required for CGEvent injection) — no Input Monitoring grant.
- `ModifierTapDetector` — Pure fire-on-full-release state machine (no AppKit), the correctness core, heavily unit-tested. Arms when held modifiers exactly equal the target set; contaminates on any intervening key/mouse-down or extra modifier; fires only when all modifiers release cleanly. Firing on empty guarantees no modifier is held when the synthesized Cmd+C is posted.
- `ModifierOnlyHotkeyMonitor` — Thin AppKit glue: one global `NSEvent` monitor (`.flagsChanged` + key/mouse-down) feeds a `ModifierTapDetector` and invokes the callback on fire.

## SwiftLint Rules

CI runs `swiftlint --strict`. Key limits: line length 200 (error), identifier min 2 chars (exceptions: `id`, `x`, `y`), function body 100 lines, file 1000 lines. Only `Sources/` is linted (not Tests).

## Testing Notes

- Tests require keyboard layouts to be installed on the machine. Missing layouts cause `XCTSkip`, not failures.
- `LayoutConverter.convertText(_:from:to:)` is internal access specifically so tests can call it directly without duplicating conversion logic.
- The dev machine runs under Rosetta (x86_64) — the Makefile test target auto-detects host architecture via `uname -m`.
