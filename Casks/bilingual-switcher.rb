cask "bilingual-switcher" do
  version "1.2.0"
  sha256 "f3d0469a6c277386f9f23b6e8335642c701a94368a8259131c327d1f2d9b597f"

  url "https://github.com/komandakycto/bilingual-switcher/releases/download/v1.2.0/BilingualSwitcher.zip"
  name "Bilingual Switcher"
  desc "Convert selected text between keyboard layouts with a hotkey"
  homepage "https://github.com/komandakycto/bilingual-switcher"

  app "BilingualSwitcher.app"

  zap trash: [
    "~/Library/Preferences/com.komandakycto.bilingual-switcher.plist",
  ]
end
