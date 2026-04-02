# Homebrew formula for qstatus CLI
# ABOUTME: Homebrew formula for installing the QStatus CLI tool
# To install: brew tap stevengonsalvez/qstatus && brew install qstatus-cli

class QstatusCli < Formula
  desc "Real-time CLI dashboard for AI usage monitoring (Claude, Copilot, Codex)"
  homepage "https://github.com/stevengonsalvez/qstatus"
  version "2.0.0"
  license "MIT"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/stevengonsalvez/qstatus/releases/download/v2.0.0/qstatus-cli-macos-arm64.tar.gz"
      sha256 "PLACEHOLDER_ARM64_SHA256"
    else
      url "https://github.com/stevengonsalvez/qstatus/releases/download/v2.0.0/qstatus-cli-macos-x86_64.tar.gz"
      sha256 "PLACEHOLDER_X86_64_SHA256"
    end
  end

  def install
    bin.install "q-status" => "qstatus"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/qstatus --version 2>&1", 0)
  end
end
