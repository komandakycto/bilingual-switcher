cask "bilingual-switcher" do
  version "1.2.2"
  sha256 "496748ab6e16f9c5c5fd74a0927c410a3f79aa50c804604ba8445997e5eedc37"

  url "https://github.com/komandakycto/bilingual-switcher/releases/download/v1.2.2/BilingualSwitcher.zip"
  name "Bilingual Switcher"
  desc "Convert selected text between keyboard layouts with a hotkey"
  homepage "https://github.com/komandakycto/bilingual-switcher"

  app "BilingualSwitcher.app"

  zap trash: [
    "~/Library/Preferences/com.komandakycto.bilingual-switcher.plist",
  ]

  caveats <<~EOS
    Bilingual Switcher is not notarized by Apple, so macOS blocks its first launch.
    Approve it once: click Done, then System Settings → Privacy & Security → Open Anyway.
    Or remove the quarantine flag:
      xattr -dr com.apple.quarantine #{appdir}/BilingualSwitcher.app
  EOS
end
