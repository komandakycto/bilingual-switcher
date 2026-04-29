cask "bilingual-switcher" do
  version "1.0.1"
  sha256 "e2d218bb5db8a3943e99d09d1c411227831e83999bd34551bf1ad5cb8c55bb3d"

  url "https://github.com/komandakycto/bilingual-switcher/releases/download/v1.0.1/BilingualSwitcher.zip"
  name "Bilingual Switcher"
  desc "Convert selected text between keyboard layouts with a hotkey"
  homepage "https://github.com/komandakycto/bilingual-switcher"

  app "BilingualSwitcher.app"

  zap trash: [
    "~/Library/Preferences/com.komandakycto.bilingual-switcher.plist",
  ]
end
