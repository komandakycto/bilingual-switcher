cask "bilingual-switcher" do
  version "1.0.0"
  sha256 "61a662030ada330614e75c59cd36f7ec20e4037c504f7da7e7def2a51027bcdc"

  url "https://github.com/komandakycto/bilingual-switcher/releases/download/v1.0.0/BilingualSwitcher.zip"
  name "Bilingual Switcher"
  desc "Convert selected text between keyboard layouts with a hotkey"
  homepage "https://github.com/komandakycto/bilingual-switcher"

  app "BilingualSwitcher.app"

  zap trash: [
    "~/Library/Preferences/com.komandakycto.bilingual-switcher.plist",
  ]
end
