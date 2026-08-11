cask "bilingual-switcher" do
  version "1.2.1"
  sha256 "9988a789bfc25adef7f867645313263eaaeee14875541737279bf24dd369c191"

  url "https://github.com/komandakycto/bilingual-switcher/releases/download/v1.2.1/BilingualSwitcher.zip"
  name "Bilingual Switcher"
  desc "Convert selected text between keyboard layouts with a hotkey"
  homepage "https://github.com/komandakycto/bilingual-switcher"

  app "BilingualSwitcher.app"

  zap trash: [
    "~/Library/Preferences/com.komandakycto.bilingual-switcher.plist",
  ]
end
