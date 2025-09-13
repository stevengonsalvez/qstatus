# Homebrew formula for qstatus CLI
# ABOUTME: Homebrew formula for installing the QStatus CLI tool
# To use: brew tap yourusername/qstatus && brew install qstatus-cli

class QstatusCli < Formula
  desc "CLI dashboard for monitoring Q (Claude) usage"
  homepage "https://github.com/yourusername/qstatus"
  version "1.0.0"
  
  if OS.mac? && Hardware::CPU.arm?
    url "https://github.com/yourusername/qstatus/releases/download/v1.0.0/qstatus-cli-macos-arm64.tar.gz"
    sha256 "REPLACE_WITH_ACTUAL_SHA256"
  elsif OS.mac? && Hardware::CPU.intel?
    url "https://github.com/yourusername/qstatus/releases/download/v1.0.0/qstatus-cli-macos-x86_64.tar.gz"
    sha256 "REPLACE_WITH_ACTUAL_SHA256"
  end

  def install
    bin.install "qstatus-cli" => "qstatus"
  end

  test do
    assert_match "QStatus Monitor", shell_output("#{bin}/qstatus --help")
  end
end