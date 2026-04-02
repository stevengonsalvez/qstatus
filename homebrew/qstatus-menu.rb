# Homebrew Cask formula for QStatus Menubar app
# ABOUTME: Homebrew Cask formula for installing the QStatus menubar application
# To install: brew tap stevengonsalvez/qstatus && brew install --cask qstatus-menu

cask "qstatus-menu" do
  version "2.0.0"
  sha256 "PLACEHOLDER_DMG_SHA256"

  url "https://github.com/stevengonsalvez/qstatus/releases/download/v#{version}/QStatus.dmg"
  name "QStatus"
  desc "Native macOS menubar app for real-time AI usage monitoring (Claude, Copilot, Codex)"
  homepage "https://github.com/stevengonsalvez/qstatus"

  auto_updates false
  depends_on macos: ">= :ventura"

  app "QStatus.app"

  uninstall quit: "com.qlips.qstatus"

  zap trash: [
    "~/Library/Preferences/com.qlips.qstatus.plist",
    "~/Library/Application Support/QStatus",
  ]
end
