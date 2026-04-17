cask "bilingual-switcher" do
  version "1.0.0"
  sha256 "PLACEHOLDER"

  url "https://github.com/komandakycto/bilingual-switcher/releases/download/v#{version}/BilingualSwitcher.zip"
  name "Bilingual Switcher"
  desc "Convert selected text between keyboard layouts with a hotkey"
  homepage "https://github.com/komandakycto/bilingual-switcher"

  app "BilingualSwitcher.app"

  zap trash: [
    "~/Library/Preferences/com.komandakycto.bilingual-switcher.plist",
  ]
end
