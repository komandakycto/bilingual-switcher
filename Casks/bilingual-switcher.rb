cask "bilingual-switcher" do
  version "1.1.0"
  sha256 "fb5f533ab53adb256a51f70453d0bddac84599ae6c0bd6299432332e6465a8b2"

  url "https://github.com/komandakycto/bilingual-switcher/releases/download/v1.1.0/BilingualSwitcher.zip"
  name "Bilingual Switcher"
  desc "Convert selected text between keyboard layouts with a hotkey"
  homepage "https://github.com/komandakycto/bilingual-switcher"

  app "BilingualSwitcher.app"

  zap trash: [
    "~/Library/Preferences/com.komandakycto.bilingual-switcher.plist",
  ]
end
