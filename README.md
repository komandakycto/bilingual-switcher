# Bilingual Switcher

A lightweight macOS menu bar app that converts selected text between **English** (QWERTY) and **Russian** (ЙЦУКЕН) keyboard layouts with a single hotkey.

If you type `Ghbdtn!` when you meant `Привет!` — just select the text, press the hotkey, and it's fixed.

## Features

- **Instant conversion** — select text, press hotkey, done
- **Auto-detection** — detects whether text is Latin or Cyrillic and converts in the right direction
- **Configurable hotkey** — set any key combination in Preferences
- **Launch at Login** — start automatically with macOS
- **Privacy-first** — runs 100% locally, no network access, no telemetry
- **Lightweight** — native Swift, no Electron, minimal resource usage

## Installation

### Download

Download the latest `.dmg` from [Releases](https://github.com/komandakycto/bilingual-switcher/releases), open it, and drag the app to Applications.

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

1. **Launch** the app — it appears as a keyboard icon in the menu bar
2. **Grant Accessibility permission** when prompted (required to read/replace selected text)
3. **Select** the wrongly-typed text in any app
4. **Press the hotkey** (default: `⌃⌥S` — Control+Option+S)
5. The text is converted in place

### Changing the hotkey

Menu bar icon → Preferences → click the shortcut field → press your desired key combination → Save.

### Examples

| You typed | You get |
|-----------|---------|
| `Ghbdtn!` | `Привет!` |
| `Руддщ` | `Hello` |
| `Dctv ghbdtn` | `Всем привет` |
| `Рфззн Ишкесфн` | `Happy Birthday` |

## How it works

The app maintains a complete mapping of physical key positions between QWERTY and ЙЦУКЕН (Russian PC) layouts. When triggered:

1. Copies the selected text (simulates ⌘C)
2. Detects whether the text is Latin or Cyrillic
3. Converts each character to its counterpart on the other layout
4. Pastes the result (simulates ⌘V)
5. Restores your original clipboard

## Requirements

- macOS 13.0 (Ventura) or later
- Accessibility permission

## Keyboard layout

Uses the **Russian — PC** layout mapping (standard ЙЦУКЕН), which matches the layout most Russian speakers use on macOS. This is the same mapping that PuntoSwitcher used.

## License

[MIT](LICENSE)
