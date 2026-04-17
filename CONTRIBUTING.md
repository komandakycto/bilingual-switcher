# Contributing

## Build from source

```bash
git clone https://github.com/komandakycto/bilingual-switcher.git
cd bilingual-switcher
make setup   # downloads Sparkle framework
make         # builds the .app bundle
make run     # builds and launches
```

## Run tests

```bash
make test        # XCTest suite (47 tests)
make test-asan   # same tests with AddressSanitizer (requires native arm64)
make lint        # SwiftLint in --strict mode (enforced in CI)
```

Tests that require specific keyboard layouts (e.g., Russian) skip gracefully via `XCTSkip` if the layout isn't installed.

## Project structure

```
Sources/           Swift source files (app logic)
Tests/             XCTest test files
Resources/         App icon, menu bar icon
Casks/             Homebrew cask formula (auto-updated by release CI)
scripts/           Icon generation script
docs/              Social preview, Sparkle appcast (auto-updated by release CI)
Vendor/            Sparkle framework (gitignored, downloaded via make setup)
```

## Makefile targets

| Target | Description |
|--------|-------------|
| `make` | Build universal binary (.app bundle) |
| `make setup` | Download Sparkle framework |
| `make run` | Build and launch |
| `make install` | Copy to /Applications |
| `make test` | Run XCTest suite |
| `make test-asan` | Run tests with AddressSanitizer |
| `make lint` | Run SwiftLint (--strict) |
| `make dmg` | Create distributable DMG |
| `make zip` | Create ZIP for Sparkle updates |
| `make icons` | Regenerate app icon from script |
| `make clean` | Remove build artifacts |

## Submitting changes

1. Create a branch from `main`
2. Make your changes
3. Run `make test` and `make lint` to verify
4. Open a pull request

CI runs SwiftLint, Semgrep security scanning, tests, and AddressSanitizer checks on every PR.
