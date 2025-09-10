cask "q-status-menubar" do
  version "0.1.0"
  sha256 :no_check
  url "https://example.com/QStatusMenubar.dmg"
  name "Q-Status Menubar"
  desc "Amazon Q CLI token usage menubar monitor"
  homepage "https://example.com/q-status-menubar"

  app "QStatusMenubar.app"

  zap trash: [
    "~/Library/Preferences/com.example.qstatus.plist",
    "~/.config/q-status/"
  ]
end

