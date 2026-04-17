# Pre-Release Audit: Bilingual Switcher

Date: 2026-04-14

Scope: first public GitHub release readiness, Swift best practices, macOS/AppKit conventions, Apple distribution requirements, and repository hygiene.

Verdict: not ready for a first public release yet. The codebase is small and readable, `make lint`, `make`, `make dmg`, and `plutil -lint Info.plist` all pass, but the current release pipeline and a few core UX paths still need work.

## Verified Checks

- `make lint` passed with `swiftlint --strict`.
- `make` produced `build/BilingualSwitcher.app`.
- `make dmg` produced `build/BilingualSwitcher.dmg`.
- `plutil -lint Info.plist` passed.
- The built app binary is single-architecture on the build host. In this environment it was `x86_64` only.
- `Vendor/Sparkle.framework` is universal (`x86_64` + `arm64`).
- No unit tests or UI tests are present in the repository.

## What Is Already Good

- Source organization is clean for an early-stage menu bar app. Responsibilities are separated into hotkey handling, layout conversion, input-source switching, windows, and app lifecycle.
- SwiftLint is configured and the current source passes strict linting.
- The app uses public macOS frameworks only: `AppKit`, `Carbon`, `ServiceManagement`, `UserNotifications`, and `Sparkle`.
- `LSUIElement` is correctly set for a menu bar utility, and the app uses `NSStatusItem` rather than custom hacks.
- The `NSApp.activate()` availability check in [Sources/AppDelegate.swift](/Users/leonidkorsakov/work/biligual-switcher/Sources/AppDelegate.swift:137) shows some attention to newer AppKit APIs.
- The input-source query is already filtered to keyboard sources in [Sources/InputSourceSwitcher.swift](/Users/leonidkorsakov/work/biligual-switcher/Sources/InputSourceSwitcher.swift:18).

## Release Blockers

### 1. Direct-distribution signing and notarization are not set up

Evidence:

- [Makefile](/Users/leonidkorsakov/work/biligual-switcher/Makefile:36) signs the app with `codesign --force --deep --sign -`, which is ad-hoc signing.
- The built app reports `Signature=adhoc` and no team identifier.
- [Makefile](/Users/leonidkorsakov/work/biligual-switcher/Makefile:71) creates a DMG, but the DMG is not signed, notarized, or stapled.
- [README.md](/Users/leonidkorsakov/work/biligual-switcher/README.md:40) already warns that the app is not notarized.

Impact:

- This is below the bar for a polished first public macOS release.
- Users will hit Gatekeeper friction.
- Sparkle-based updates are much harder to trust and operate cleanly without a proper signing pipeline.

Recommendation:

- Move to Developer ID signing.
- Enable Hardened Runtime.
- Sign the app and the outer DMG.
- Notarize the outer DMG and staple it.
- Test the final artifact on a clean machine, both before and after moving it to `/Applications`.

### 2. Release architecture is host-dependent

Evidence:

- [Makefile](/Users/leonidkorsakov/work/biligual-switcher/Makefile:27) invokes `swiftc` without an explicit multi-arch target or universal build step.
- The app built in this environment is `Mach-O 64-bit executable x86_64`.
- GitHub Actions uses `macos-14` in [.github/workflows/ci.yml](/Users/leonidkorsakov/work/biligual-switcher/.github/workflows/ci.yml:17), which typically means the CI artifact will be built on Apple Silicon instead.

Impact:

- Your release artifact depends on where it was built.
- A local Intel build is not the same product as a CI Apple Silicon build.
- If you advertise `macOS 13+` without an architecture note, users will reasonably expect support across both Intel and Apple Silicon Macs that run Ventura or newer.

Recommendation:

- Ship a universal app, or explicitly declare the release as `arm64`-only.
- If you keep direct `swiftc` builds, build both architectures and merge with `lipo`, or move release builds to a more standard Xcode archive/export path.

### 3. The privacy story conflicts with the updater behavior

Evidence:

- [README.md](/Users/leonidkorsakov/work/biligual-switcher/README.md:25) says the app runs with “no network access”.
- [Sources/AppDelegate.swift](/Users/leonidkorsakov/work/biligual-switcher/Sources/AppDelegate.swift:16) starts `SPUStandardUpdaterController` on launch.
- [Info.plist](/Users/leonidkorsakov/work/biligual-switcher/Info.plist:21) sets `SUFeedURL`.
- [Info.plist](/Users/leonidkorsakov/work/biligual-switcher/Info.plist:23) enables automatic update checks.
- The repository does not contain an `appcast.xml` or a documented release publishing flow for Sparkle.

Impact:

- The current README overpromises on privacy and network behavior.
- For a public release, inaccurate privacy language is a trust problem.
- The updater feature is not self-documented well enough for contributors or future maintainers.

Recommendation:

- Pick one of these paths before release:
- Disable Sparkle until the appcast and signing pipeline are ready.
- Keep Sparkle, but update the README to explain exactly what network access occurs, when it occurs, and what data is not collected.
- Document the release process for publishing the appcast and signing update archives.

### 4. Global hotkey registration failures are silent to the user

Evidence:

- [Sources/HotkeyManager.swift](/Users/leonidkorsakov/work/biligual-switcher/Sources/HotkeyManager.swift:50) checks the return value of `RegisterEventHotKey`.
- On failure, [Sources/HotkeyManager.swift](/Users/leonidkorsakov/work/biligual-switcher/Sources/HotkeyManager.swift:60) only logs to `NSLog`.
- [Sources/PreferencesWindow.swift](/Users/leonidkorsakov/work/biligual-switcher/Sources/PreferencesWindow.swift:126) always saves the shortcut and closes the window.

Impact:

- A user can choose a reserved or conflicting shortcut and think the app is broken.
- This affects the app’s primary feature.

Recommendation:

- Make `register()` return a result or throw.
- Validate the shortcut before dismissing preferences.
- If registration fails, restore the previous shortcut and show a visible error message.

## High-Priority Improvements

### 5. There are no automated tests for the core product logic

Evidence:

- The repo has no `Tests` directory, no XCTest target, and no package or Xcode test configuration.
- `LayoutConverter` in [Sources/LayoutConverter.swift](/Users/leonidkorsakov/work/biligual-switcher/Sources/LayoutConverter.swift:9) is pure logic and is ideal for table-driven tests.

Impact:

- Mapping regressions and direction-detection mistakes will only be caught manually.
- That is risky for the app’s central feature.

Recommendation:

- Add unit tests for:
- known conversion examples from the README
- punctuation and mixed-script inputs
- detection behavior for Latin, Cyrillic, and ambiguous text
- preference defaults and hotkey formatting helpers

### 6. Input-source switching chooses by language only, not by the exact layout the app promises

Evidence:

- [Sources/InputSourceSwitcher.swift](/Users/leonidkorsakov/work/biligual-switcher/Sources/InputSourceSwitcher.swift:33) switches on `languages.first == targetLanguage`.
- The app description in [README.md](/Users/leonidkorsakov/work/biligual-switcher/README.md:78) says conversion is based on the Russian PC layout.

Impact:

- If a user has multiple English or Russian input sources installed, the app may switch to the wrong one.
- The conversion logic and the active keyboard layout can drift out of sync.

Recommendation:

- Match a specific input-source identifier instead of only a language code.
- If you want flexibility, let the user choose which English and Russian layouts should be paired.

### 7. Launch-at-login handling is too optimistic for `SMAppService`

Evidence:

- [Sources/PreferencesWindow.swift](/Users/leonidkorsakov/work/biligual-switcher/Sources/PreferencesWindow.swift:257) reduces launch-at-login to a simple enabled boolean.
- [Sources/PreferencesWindow.swift](/Users/leonidkorsakov/work/biligual-switcher/Sources/PreferencesWindow.swift:263) catches errors only by logging.
- Apple’s `SMAppService.Status` includes states like `requiresApproval`, not just enabled or disabled.

Impact:

- The checkbox can fail to reflect the actual system state.
- Users may need to approve the background item in System Settings and will not get actionable guidance.

Recommendation:

- Handle `status` explicitly.
- When the state is `requiresApproval`, explain what happened and offer to open System Settings.
- Consider using `SMAppService.openSystemSettingsLoginItems()` as the remediation path.

### 8. The Accessibility-permission fallback notification may never be shown

Evidence:

- [Sources/TextSwitcher.swift](/Users/leonidkorsakov/work/biligual-switcher/Sources/TextSwitcher.swift:97) schedules a local notification when Accessibility access is missing.
- The app never calls `UNUserNotificationCenter.requestAuthorization`.

Impact:

- A user can press the hotkey and get no visible feedback.
- The fallback depends on notification permission that the app never asks for.

Recommendation:

- Either request notification authorization in context before relying on this UX path, or avoid notifications here and use a direct alert/open-settings flow from the menu bar app itself.

## Medium-Priority Improvements

### 9. Clipboard handling still relies on fixed timing heuristics

Evidence:

- [Sources/TextSwitcher.swift](/Users/leonidkorsakov/work/biligual-switcher/Sources/TextSwitcher.swift:31) waits `0.15` seconds after simulating copy.
- [Sources/TextSwitcher.swift](/Users/leonidkorsakov/work/biligual-switcher/Sources/TextSwitcher.swift:58) waits `0.4` seconds before restoring the clipboard.

Impact:

- The feature may be flaky in slower apps, Electron apps, web apps, or under load.

Recommendation:

- Replace fixed sleeps with short polling against `pasteboard.changeCount` and a timeout window.
- Keep the current behavior as a fallback if you need to avoid a larger refactor.

### 10. Dependency bootstrap is not integrity-checked

Evidence:

- [Makefile](/Users/leonidkorsakov/work/biligual-switcher/Makefile:90) downloads Sparkle with `curl -sL`.
- The script does not use `--fail` and does not verify a checksum or signature before extracting.

Impact:

- The setup path is more brittle than it needs to be.
- This is avoidable supply-chain risk for a public project.

Recommendation:

- Add `--fail` to `curl`.
- Pin and verify a SHA-256 checksum for the downloaded archive.
- Extract only what the app needs, not the entire release bundle.

### 11. Preferences and About windows use fixed manual frames

Evidence:

- [Sources/PreferencesWindow.swift](/Users/leonidkorsakov/work/biligual-switcher/Sources/PreferencesWindow.swift:18) and [Sources/AboutWindow.swift](/Users/leonidkorsakov/work/biligual-switcher/Sources/AboutWindow.swift:6) construct windows entirely with hard-coded frames.

Impact:

- The UI will not scale well with localization, larger type sizes, or future settings growth.
- Manual frame math becomes a maintenance burden quickly.

Recommendation:

- Move these windows to Auto Layout with `NSStackView` and constraints.

### 12. The status item is missing explicit accessibility metadata

Evidence:

- [Sources/AppDelegate.swift](/Users/leonidkorsakov/work/biligual-switcher/Sources/AppDelegate.swift:39) sets the menu bar image, but the custom-image branch does not assign a tooltip or accessibility label to the button.

Impact:

- VoiceOver and discoverability are weaker than they should be for a menu bar-only app.

Recommendation:

- Set `button.toolTip` and `button.setAccessibilityLabel("Bilingual Switcher")`.

### 13. `checkAccessibilityOnFirstLaunch()` is not actually first-launch-only

Evidence:

- [Sources/AppDelegate.swift](/Users/leonidkorsakov/work/biligual-switcher/Sources/AppDelegate.swift:29) calls the method on every launch.
- [Sources/AppDelegate.swift](/Users/leonidkorsakov/work/biligual-switcher/Sources/AppDelegate.swift:108) passes `kAXTrustedCheckOptionPrompt: true`.

Impact:

- Users who decline initially can be reprompted on later launches with no one-time gating or remembered state.

Recommendation:

- Either rename the method to match its behavior, or gate the prompt behind a stored first-run flag or a user action.

### 14. Repo polish is close, but not finished

Evidence:

- [README.md](/Users/leonidkorsakov/work/biligual-switcher/README.md:30) includes a “Homebrew (coming soon)” install path that does not exist yet.
- The working directory name is `biligual-switcher`, which is misspelled.
- There is no changelog or release checklist in the repo.

Impact:

- These are not code blockers, but they reduce the quality of a first public impression.

Recommendation:

- Remove “coming soon” sections until they are live.
- Rename the repo directory if this typo is still reflected in the public repository name.
- Add a short `CHANGELOG.md` and a release checklist before tagging `v1.0.0`.

## Swift And Apple Best-Practice Summary

| Area | Status | Notes |
| --- | --- | --- |
| Swift readability | Good | Small files, clear naming, low complexity |
| Access control | Good | Mostly disciplined; no major exposure issues |
| API selection | Good | Uses public AppKit, Carbon, ServiceManagement APIs |
| Testing | Weak | No automated tests for the core conversion logic |
| AppKit layout | Weak | Fixed frames throughout settings/about UI |
| Menu bar app fit | Good | `LSUIElement` and `NSStatusItem` usage are appropriate |
| Accessibility UX | Needs work | Status-item labeling and permission fallback need improvement |
| Background items | Mixed | Correct framework, incomplete UX/state handling |
| Direct distribution readiness | Not ready | Ad-hoc signed, not notarized, not stapled |
| Release reproducibility | Needs work | Output architecture depends on build host |

## Recommended Release Gate

Do these before publishing the first GitHub release:

1. Set up Developer ID signing, Hardened Runtime, notarization, and stapling.
2. Decide on universal vs `arm64`-only distribution and make the build pipeline explicit.
3. Resolve the Sparkle/privacy mismatch: either document it properly or disable it for `1.0.0`.
4. Add user-visible validation for hotkey registration failures.
5. Add at least a minimal unit-test suite for layout conversion and preference defaults.
6. Verify the final signed artifact on a clean macOS machine outside the developer environment.

## Reference Links

- Apple: [Packaging Mac software for distribution](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)
- Apple: [Asking permission to use notifications](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications)
- Apple: [UNUserNotificationCenter](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter)
- Apple: [Service Management](https://developer.apple.com/documentation/servicemanagement/)
- Apple: [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- Apple: [SMAppService.Status.notFound](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum/notfound)
- Apple HIG: [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- Apple HIG: [The menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar)
