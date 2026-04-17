cask "bilingual-switcher" do
  version "0.0.1-rc1"
  sha256 "0008dcdd273a5c1d2b06e7ae5dabab6cc917f6b57d03a86e16b4733e62ae2fb3"

  url "https://github.com/komandakycto/bilingual-switcher/releases/download/v0.0.1-rc1/BilingualSwitcher.zip"
  name "Bilingual Switcher"
  desc "Convert selected text between keyboard layouts with a hotkey"
  homepage "https://github.com/komandakycto/bilingual-switcher"

  app "BilingualSwitcher.app"

  zap trash: [
    "~/Library/Preferences/com.komandakycto.bilingual-switcher.plist",
  ]
end
