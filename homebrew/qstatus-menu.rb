# Homebrew Cask formula for QStatus Menubar app
# ABOUTME: Homebrew Cask formula for installing the QStatus menubar application
# To use: brew tap yourusername/qstatus && brew install --cask qstatus-menu

cask "qstatus-menu" do
  version "1.0.0"
  sha256 "REPLACE_WITH_ACTUAL_SHA256"

  url "https://github.com/yourusername/qstatus/releases/download/v#{version}/QStatus.dmg"
  name "Q Status"
  desc "Menubar app for monitoring Q (Claude) usage"
  homepage "https://github.com/yourusername/qstatus"

  auto_updates false
  depends_on macos: ">= :big_sur"

  app "Q Status.app"

  uninstall quit: "com.qlips.qstatus"

  zap trash: [
    "~/Library/Preferences/com.qlips.qstatus.plist",
    "~/Library/Application Support/Q Status",
  ]
end