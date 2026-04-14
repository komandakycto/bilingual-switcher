<p align="center">
  <a href="https://github.com/komandakycto/bilingual-switcher/actions/workflows/ci.yml"><img src="https://github.com/komandakycto/bilingual-switcher/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/komandakycto/bilingual-switcher/releases/latest"><img src="https://img.shields.io/github/v/release/komandakycto/bilingual-switcher?style=flat-square&label=download" alt="Download"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2013%2B-blue?style=flat-square" alt="Platform">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/komandakycto/bilingual-switcher?style=flat-square" alt="License"></a>
</p>

<p align="center">
A lightweight macOS menu bar app that converts selected text between<br>
<strong>English</strong> (QWERTY) and <strong>Russian</strong> (ЙЦУКЕН) keyboard layouts with a single hotkey.
</p>

---

If you type `Ghbdtn!` when you meant `Привет!` — just select the text, press the hotkey, and it's fixed.

## Features

- **Instant conversion** — select text, press hotkey, done
- **Auto-detection** — detects whether text is Latin or Cyrillic and converts in the right direction
- **Configurable hotkey** — set any key combination in Preferences
- **Auto-switch keyboard layout** — optionally switch to the target language after conversion
- **Launch at Login** — start automatically with macOS
- **Auto-updates** — built-in update checking via Sparkle
- **Privacy-first** — runs 100% locally, no network access, no telemetry
- **Lightweight** — native Swift, no Electron, minimal resource usage

## Install

### Homebrew (coming soon)

```bash
brew install --cask bilingual-switcher
```

### Manual download

Download the latest `.dmg` from [Releases](https://github.com/komandakycto/bilingual-switcher/releases), open it, and drag the app to Applications.

> **Note:** The app is not notarized with Apple. On first launch, right-click the app → Open, or go to System Settings → Privacy & Security → click "Open Anyway".

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
4. **Press the hotkey** (default: `⌃⌥S` — Control + Option + S)
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
