<p align="center">
  <img src="docs/social_preview.png" alt="Bilingual Switcher" width="640">
</p>

<p align="center">
  <a href="https://github.com/komandakycto/bilingual-switcher/actions/workflows/ci.yml"><img src="https://github.com/komandakycto/bilingual-switcher/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/komandakycto/bilingual-switcher/releases/latest"><img src="https://img.shields.io/github/v/release/komandakycto/bilingual-switcher?style=flat-square&label=download" alt="Download"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2013%2B-blue?style=flat-square" alt="Platform">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/komandakycto/bilingual-switcher?style=flat-square" alt="License"></a>
</p>

<p align="center">
A lightweight macOS menu bar app that converts selected text between<br>
any two keyboard layouts with a single hotkey.<br>
Supports <strong>any language pair</strong> — English, Russian, French, German, Spanish, and more.
</p>

---

If you type `Ghbdtn!` when you meant `Привет!` — just select the text, press the hotkey, and it's fixed.

## Features

- **Instant conversion** — select text, press hotkey, done
- **Any language pair** — dynamically reads your installed keyboard layouts via macOS APIs, no hardcoded mappings
- **Auto-detection** — detects which layout produced the text and converts to the other
- **Configurable hotkey** — set any key combination in Preferences
- **Auto-switch keyboard layout** — optionally switch to the target language after conversion
- **Launch at Login** — start automatically with macOS
- **Auto-updates** — built-in update checking via Sparkle
- **Privacy-first** — no telemetry, no data collection. Only network access is optional update checks via Sparkle
- **Lightweight** — native Swift, no Electron, minimal resource usage

## Install

### Homebrew (recommended)

```bash
brew tap komandakycto/bilingual-switcher https://github.com/komandakycto/bilingual-switcher.git
brew install --cask bilingual-switcher
```

Homebrew automatically strips the macOS quarantine flag — the app opens without Gatekeeper prompts.

### Manual download

Download the latest `.dmg` from [Releases](https://github.com/komandakycto/bilingual-switcher/releases), open it, and drag the app to Applications.

**Gatekeeper notice:** The app is ad-hoc signed (not notarized with Apple). Before first launch:

```bash
xattr -cr /Applications/BilingualSwitcher.app
```

Or: try to open the app, get blocked, then go to **System Settings → Privacy & Security** → scroll down → **Open Anyway**.

You can verify the download integrity with SHA256 checksums from the [release page](https://github.com/komandakycto/bilingual-switcher/releases).

### Build from source

Requires Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/komandakycto/bilingual-switcher.git
cd bilingual-switcher
make setup     # downloads Sparkle framework
make
make install   # copies to /Applications
```

## Usage

1. **Launch** the app — it appears as an icon in the menu bar
2. **Grant Accessibility permission** when prompted (required to read/replace selected text)
3. **Select** the wrongly-typed text in any app
4. **Press the hotkey** (default: `⌥⌘S` — Option + Command + S)
5. The text is converted in place

### Changing the hotkey

Menu bar icon → Preferences → click the shortcut field → press your desired combination → Save.

### Examples

| You typed | You get |
|-----------|---------|
| `Ghbdtn!` | `Привет!` |
| `Руддщ` | `Hello` |
| `Dctv ghbdtn` | `Всем привет` |
| `Рфззн Ишкесфн` | `Happy Birthday` |

## How it works

The app maintains a complete character mapping of physical key positions between QWERTY and ЙЦУКЕН (Russian PC) layouts. When triggered:

1. Copies the selected text (simulates `⌘C`)
2. Detects whether the text is Latin or Cyrillic
3. Converts each character to its counterpart on the other layout
4. Pastes the result (simulates `⌘V`)
5. Restores your original clipboard

## Requirements

- macOS 13.0 (Ventura) or later
- Accessibility permission (prompted on first launch)

## Keyboard layout

Uses the **Russian — PC** layout mapping (standard ЙЦУКЕН), which matches the layout most Russian speakers use on macOS. This is the same mapping that PuntoSwitcher used.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for build instructions and guidelines.

## License

[MIT](LICENSE)
