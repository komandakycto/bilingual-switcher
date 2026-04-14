# Contributing

## Build from source

```bash
git clone https://github.com/komandakycto/bilingual-switcher.git
cd bilingual-switcher
make setup   # downloads Sparkle framework
make         # builds the .app bundle
make run     # builds and launches
```

## Project structure

```
Sources/           Swift source files
Resources/         App icon, menu bar icon
scripts/           Icon generation script
Vendor/            Sparkle framework (gitignored, downloaded via make setup)
```

## Lint

[SwiftLint](https://github.com/realm/SwiftLint) is enforced in CI with `--strict` mode.

```bash
make lint
```

## Submitting changes

1. Fork the repo and create a branch from `main`
2. Make your changes
3. Run `make lint` and `make` to verify
4. Open a pull request

## Makefile targets

| Target | Description |
|--------|-------------|
| `make` | Build the app |
| `make setup` | Download Sparkle framework |
| `make run` | Build and launch |
| `make install` | Copy to /Applications |
| `make dmg` | Create distributable DMG |
| `make lint` | Run SwiftLint |
| `make icons` | Regenerate app icon from script |
| `make clean` | Remove build artifacts |
