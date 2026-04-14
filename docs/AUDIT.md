# Project Audit: Bilingual Switcher v1.0.0

**Date:** 2026-04-14
**Scope:** Full pre-release code review — Swift best practices, Apple guidelines, code quality

## Overall Impression

Clean, focused, well-structured ~900 LOC menu bar app. Good separation of concerns across 8 source files. For a first release this is solid work. Issues below are ranked by severity.

---

## CRITICAL — Fix Before Release

### 1. Latin range detection includes non-letter characters

**File:** `Sources/LayoutConverter.swift:66`

```swift
if (0x0041...0x007A).contains(scalar.value) // Basic Latin letters
```

This range `0x0041–0x007A` includes `[\]^_\`` (codes 0x5B–0x60) which are punctuation, not letters. This will miscount punctuation as Latin characters, skewing auto-detection.

**Fix:** Use two ranges `(0x0041...0x005A)` (A-Z) and `(0x0061...0x007A)` (a-z), or use `scalar.properties.isAlphabetic`.

### 2. Clipboard restore races with paste

**File:** `Sources/TextSwitcher.swift:58`

The 200ms delay before restoring the clipboard is a heuristic. On slower machines or when the target app has paste latency (e.g., Electron apps, browsers with heavy JS), the clipboard can be restored before the app finishes reading it. There's no guaranteed solution, but 200ms is on the low side.

**Suggestion:** Bump to 300–500ms. Consider making this configurable in a future version. This is a known limitation of the clipboard-based approach — document it.

### 3. Missing character mappings

**File:** `Sources/LayoutConverter.swift:44-48`

The shifted number row mapping is incomplete:

| Key         | English | Russian | Status  |
|-------------|---------|---------|---------|
| Shift+1     | `!`     | `!`     | Missing |
| Shift+5     | `%`     | `%`     | Missing |
| Shift+8     | `*`     | `*`     | Missing |
| Shift+9     | `(`     | `(`     | Missing |
| Shift+0     | `)`     | `)`     | Missing |

Users typing numbers with Shift will get inconsistent conversion.

---

## HIGH — Should Fix Before Release

### 4. `setupMenuBar()` is not `private`

**File:** `Sources/AppDelegate.swift:34`

```swift
func setupMenuBar() {
```

Called from `showPreferences` callback to refresh hotkey display, which is fine. But it should be `private` — all other helper methods in `AppDelegate` are already `private`.

### 5. Force-unwrap on System Preferences URL

**File:** `Sources/AppDelegate.swift:124-125`

```swift
let url = URL(
    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
)!
```

Force-unwrap on a string literal URL is technically safe (the string is constant), but Apple's URL scheme changed between macOS versions. Consider adding a `guard let` for defensive coding.

### 6. `globalHotkeyCallback` global mutable state is not thread-safe

**File:** `Sources/HotkeyManager.swift:5`

```swift
private var globalHotkeyCallback: (() -> Void)?
```

This global is set from the main thread in `register()` and read from the Carbon event handler. Carbon event handlers are typically dispatched on the main thread for `GetApplicationEventTarget()`, so this is probably fine in practice, but it's not formally guaranteed. If you ever support multiple instances, this is a data race.

### 7. `ConversionDirection.auto` case handled redundantly

**File:** `Sources/LayoutConverter.swift:93-95`

```swift
case .auto:
    map = englishToRussianMap
```

`.auto` should never reach this branch because it's resolved at line 83-86. This dead code silently defaults to EN→RU, which could mask bugs. Replace with a `fatalError("unreachable")` or restructure the code to make the exhaustive switch impossible.

### 8. No `NSAccessibilityUsageDescription` in Info.plist

The app reads and modifies text via Accessibility APIs and CGEvents but does not declare `NSAccessibilityUsageDescription` in its Info.plist. While not strictly required for consuming Accessibility (you're the client, not the provider), Apple reviewers may look for it if you ever submit to the App Store. For direct distribution this is fine, but worth noting.

---

## MEDIUM — Improve Code Quality

### 9. Frame-based layout throughout UI

**Files:** `Sources/PreferencesWindow.swift`, `Sources/AboutWindow.swift`

All UI uses hardcoded frames (`NSRect(x: 20, y: 260, width: 200, height: 20)`). This:

- Breaks if system font size changes (Accessibility > larger text)
- Doesn't adapt to localized strings of different lengths
- Makes future UI changes tedious

For a v1 menu bar utility this is acceptable, but Auto Layout or `NSStackView` would be more robust. Not blocking for release.

### 10. `restoreClipboard` calls `writeObjects` per item inside a loop

**File:** `Sources/TextSwitcher.swift:69-75`

```swift
for itemDict in items {
    let item = NSPasteboardItem()
    for (type, data) in itemDict {
        item.setData(data, forType: type)
    }
    pasteboard.writeObjects([item])
}
```

Each `writeObjects` call increments `changeCount`. If the original clipboard had multiple items, this calls `writeObjects` N times. Should collect all items first, then call `writeObjects` once:

```swift
let pasteboardItems = items.map { itemDict -> NSPasteboardItem in
    let item = NSPasteboardItem()
    for (type, data) in itemDict { item.setData(data, forType: type) }
    return item
}
pasteboard.writeObjects(pasteboardItems)
```

### 11. `TISCreateInputSourceList` returns all input sources unfiltered

**File:** `Sources/InputSourceSwitcher.swift:18`

```swift
guard let sources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource]
```

Passing `nil` as the filter dictionary returns all input sources. You should filter to only keyboard input sources:

```swift
let filter = [kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource] as CFDictionary
```

This removes the need for the manual category check on lines 23-28 and is more efficient.

### 12. `activate(ignoringOtherApps:)` is deprecated on macOS 14+

**File:** `Sources/AppDelegate.swift:146,154`

```swift
NSApp.activate(ignoringOtherApps: true)
```

Deprecated since macOS 14. Use `NSApp.activate()` on macOS 14+ or `NSApp.yieldActivation(toApplicationWithBundleIdentifier:)`. Since you target macOS 13+, you'd need an availability check.

### 13. Sparkle `tar xf` extracts more than needed

**File:** `Makefile:91`

```makefile
@tar xf Vendor/Sparkle.tar.xz -C Vendor
```

The Sparkle release tarball contains binaries, symbols, XPC services, and documentation. You only need `Sparkle.framework`. Consider extracting only what's needed to keep the Vendor directory clean.

---

## LOW — Polish / Best Practices

### 14. No `@MainActor` annotations

Modern Swift concurrency best practice for macOS 13+ is to annotate UI-touching classes with `@MainActor`. Current code uses GCD (`DispatchQueue.main.asyncAfter`) which works fine, but mixing GCD and Swift concurrency can cause issues as the codebase grows.

### 15. `HotkeyDisplayHelper` and `KeyCodeNames` could be collapsed

**Files:** `Sources/HotkeyManager.swift:119-141`, `Sources/PreferencesWindow.swift:239-249`

Both are small enums with only static methods. They're fine as-is, but they live in separate files. Keeping hotkey display logic in one place would be cleaner.

### 16. No `UserDefaults.register(defaults:)` call

**File:** `Sources/HotkeyManager.swift:87-105`

Default values are handled inline with null-checks (`object(forKey:) == nil`). Apple's recommended pattern is calling `UserDefaults.standard.register(defaults:)` early in app launch. This simplifies all the getters.

### 17. Typo in repository folder name

The folder is `biligual-switcher` (missing the 'n' in bilingual). Not a code issue, but visible in paths. Worth renaming the repo before the public release if you haven't already pushed it.

---

## Apple Guidelines Compliance

| Guideline                       | Status  | Notes                                                                 |
|---------------------------------|---------|-----------------------------------------------------------------------|
| LSUIElement for menu bar app    | Pass    | Correctly set to `true`                                               |
| NSHighResolutionCapable         | Pass    | Retina-ready                                                          |
| Accessibility prompt before use | Pass    | Runtime AX check on first launch                                      |
| No private API usage            | Pass    | All frameworks are public                                             |
| Code signing                    | Partial | Ad-hoc only — fine for direct distribution, not App Store             |
| Sandbox                         | N/A     | Not sandboxed — required for Accessibility API access                 |
| Hardened Runtime                | Missing | Recommended for notarization. Add `--options runtime` to codesign     |
| Notarization                    | Missing | Required for Gatekeeper on macOS 10.15+. Users will see "unidentified developer" warning without it |
| Minimum deployment target       | Pass    | macOS 13.0 in Info.plist                                              |

---

## Swift Best Practices Compliance

| Practice               | Status  | Notes                                                  |
|------------------------|---------|--------------------------------------------------------|
| Access control         | Good    | Minor: `setupMenuBar()` should be private              |
| Memory management      | Good    | `[weak self]` used correctly                           |
| Error handling         | Adequate| Could improve with `Result` types                      |
| Naming conventions     | Good    | Follows Swift API Design Guidelines                    |
| Protocol conformance   | Good    | `NSApplicationDelegate` properly adopted               |
| Value vs reference types| Good   | Enums for stateless helpers, classes for stateful objects|
| Deprecated API usage   | Warning | `activate(ignoringOtherApps:)` deprecated macOS 14     |

---

## Pre-Release Action Items

### Must fix

- [ ] Fix Latin character range detection in `LayoutConverter.detectDirection()` (#1)
- [ ] Complete shifted number row mappings in `LayoutConverter` (#3)
- [ ] Fix `restoreClipboard` to call `writeObjects` once, not per-item (#10)

### Should fix

- [ ] Make `setupMenuBar()` private (#4)
- [ ] Add hardened runtime flag to Makefile codesign step (#Apple Guidelines)
- [ ] Eliminate dead `.auto` case in convert switch or make it unreachable (#7)

### Consider

- [ ] Bump clipboard restore delay to 300-500ms (#2)
- [ ] Rename repo from `biligual-switcher` to `bilingual-switcher` before first public push (#17)
- [ ] Filter `TISCreateInputSourceList` to keyboard sources only (#11)
- [ ] Replace deprecated `activate(ignoringOtherApps:)` with availability check (#12)
