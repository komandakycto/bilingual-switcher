APP_NAME     = BilingualSwitcher
BUNDLE_ID    = com.komandakycto.bilingual-switcher
BUILD_DIR    = build
APP_BUNDLE   = $(BUILD_DIR)/$(APP_NAME).app
DMG_NAME     = $(APP_NAME).dmg
SOURCES      = $(wildcard Sources/*.swift)
SPARKLE_DIR  = Vendor/Sparkle.framework
COMMON_FLAGS = -O \
               -framework Cocoa \
               -framework Carbon \
               -framework ServiceManagement \
               -F Vendor \
               -framework Sparkle \
               -Xlinker -rpath -Xlinker @executable_path/../Frameworks
INSTALL_DIR  = /Applications

SPARKLE_VERSION = 2.9.1
SPARKLE_URL     = https://github.com/sparkle-project/Sparkle/releases/download/$(SPARKLE_VERSION)/Sparkle-$(SPARKLE_VERSION).tar.xz
SPARKLE_SHA256  = c0dde519fd2a43ddfc6a1eb76aec284d7d888fe281414f9177de3164d98ba4c7

.PHONY: all clean install uninstall run dmg icons lint setup

all: $(APP_BUNDLE)

# --- Build (universal binary) ---

$(APP_BUNDLE): $(SOURCES) Info.plist Resources/AppIcon.icns Resources/MenuBarIcon.png $(SPARKLE_DIR)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	@mkdir -p $(APP_BUNDLE)/Contents/Frameworks
	@mkdir -p $(BUILD_DIR)/arch
	swiftc $(COMMON_FLAGS) -target arm64-apple-macos13 $(SOURCES) -o $(BUILD_DIR)/arch/$(APP_NAME)-arm64
	swiftc $(COMMON_FLAGS) -target x86_64-apple-macos13 $(SOURCES) -o $(BUILD_DIR)/arch/$(APP_NAME)-x86_64
	lipo -create $(BUILD_DIR)/arch/$(APP_NAME)-arm64 $(BUILD_DIR)/arch/$(APP_NAME)-x86_64 \
		-output $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	@rm -rf $(BUILD_DIR)/arch
	@cp Info.plist $(APP_BUNDLE)/Contents/Info.plist
	@cp Resources/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/AppIcon.icns
	@cp Resources/MenuBarIcon.png $(APP_BUNDLE)/Contents/Resources/MenuBarIcon.png
	@cp Resources/MenuBarIcon@2x.png $(APP_BUNDLE)/Contents/Resources/MenuBarIcon@2x.png 2>/dev/null || true
	@rsync -a --delete $(SPARKLE_DIR) $(APP_BUNDLE)/Contents/Frameworks/
	@codesign --force --deep --sign - $(APP_BUNDLE)
	@echo "✓ Built $(APP_BUNDLE) (universal)"

# --- Icons ---

icons: Resources/AppIcon.icns

Resources/AppIcon.icns: scripts/generate_icon.swift
	swift scripts/generate_icon.swift

# --- Install ---

install: $(APP_BUNDLE)
	@echo "Installing to $(INSTALL_DIR)..."
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	@cp -R $(APP_BUNDLE) "$(INSTALL_DIR)/"
	@echo "✓ Installed to $(INSTALL_DIR)/$(APP_NAME).app"
	@echo "  Run: open '$(INSTALL_DIR)/$(APP_NAME).app'"

uninstall:
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "✓ Removed from $(INSTALL_DIR)"

# --- Run ---

run: $(APP_BUNDLE)
	@open $(APP_BUNDLE)

# --- DMG ---

dmg: $(APP_BUNDLE)
	@rm -f $(BUILD_DIR)/$(DMG_NAME)
	@mkdir -p $(BUILD_DIR)/dmg-staging
	@cp -R $(APP_BUNDLE) $(BUILD_DIR)/dmg-staging/
	@ln -sf /Applications $(BUILD_DIR)/dmg-staging/Applications
	hdiutil create -volname "$(APP_NAME)" \
		-srcfolder $(BUILD_DIR)/dmg-staging \
		-ov -format UDZO \
		$(BUILD_DIR)/$(DMG_NAME)
	@rm -rf $(BUILD_DIR)/dmg-staging
	@echo "✓ Created $(BUILD_DIR)/$(DMG_NAME)"

# --- Lint ---

lint:
	swiftlint lint --strict

# --- Setup (download dependencies) ---

setup: $(SPARKLE_DIR)

$(SPARKLE_DIR):
	@echo "Downloading Sparkle $(SPARKLE_VERSION)..."
	@mkdir -p Vendor
	@curl -sfL "$(SPARKLE_URL)" -o Vendor/Sparkle.tar.xz
	@echo "$(SPARKLE_SHA256)  Vendor/Sparkle.tar.xz" | shasum -a 256 -c - || \
		(rm -f Vendor/Sparkle.tar.xz && echo "ERROR: Sparkle checksum mismatch" && exit 1)
	@tar xf Vendor/Sparkle.tar.xz -C Vendor
	@rm Vendor/Sparkle.tar.xz
	@echo "✓ Sparkle framework ready"

# --- Clean ---

clean:
	rm -rf $(BUILD_DIR)
