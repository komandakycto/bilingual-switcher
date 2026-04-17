cask "bilingual-switcher" do
  version "0.0.1-rc2"
  sha256 "7477ada415816a2db6aa8bd4c060d5d75a0ff3fcf3345066a4779f2c4069531b"

  url "https://github.com/komandakycto/bilingual-switcher/releases/download/v0.0.1-rc2/BilingualSwitcher.zip"
  name "Bilingual Switcher"
  desc "Convert selected text between keyboard layouts with a hotkey"
  homepage "https://github.com/komandakycto/bilingual-switcher"

  app "BilingualSwitcher.app"

  zap trash: [
    "~/Library/Preferences/com.komandakycto.bilingual-switcher.plist",
  ]
end
