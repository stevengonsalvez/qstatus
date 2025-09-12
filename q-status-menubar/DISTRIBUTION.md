# Distribution Guide

This guide explains how to distribute Q-Status from your GitHub repository.

## 📦 Creating a Release

### 1. Prepare Release Assets

```bash
# Build and package everything
make release

# This creates in the releases/ directory:
# - q-status-cli-macos.tar.gz (CLI binary)
# - QStatus.app.zip (Menubar app)
# - QStatus.dmg (Installer disk image)
```

### 2. Create GitHub Release

#### Manual Method:

1. Go to your repository on GitHub
2. Click "Releases" → "Create a new release"
3. Create a new tag (e.g., `v1.0.0`)
4. Upload the files from `releases/` directory:
   - `QStatus.dmg` - Main installer for most users
   - `QStatus.app.zip` - Direct app download
   - `q-status-cli-macos.tar.gz` - CLI only
   - `install.sh` - Installation script
5. Add release notes

#### Automated Method (with GitHub Actions):

```bash
# Tag your release
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0

# GitHub Actions will automatically build and create the release
```

## 🎯 Distribution Options

### Option 1: Direct Downloads

Users can download directly from your releases page:
```
https://github.com/yourusername/q-status/releases
```

### Option 2: Install Script

Users can install with one command:
```bash
curl -sSL https://github.com/yourusername/q-status/releases/latest/download/install.sh | bash
```

### Option 3: DMG Installer

Most user-friendly option:
1. Download `QStatus.dmg`
2. Open and drag to Applications
3. Launch from Applications

## 📝 Release Checklist

Before creating a release:

- [ ] Update version numbers in:
  - [ ] `q-status-cli/Cargo.toml`
  - [ ] `q-status-menubar/Package.swift`
  - [ ] `Makefile` (CFBundleVersion)
- [ ] Test both apps thoroughly
- [ ] Update CHANGELOG.md
- [ ] Update README screenshots if UI changed
- [ ] Run `make clean && make release` to verify build
- [ ] Test installation on a clean system

## 🔐 Code Signing (Optional)

For distribution outside the Mac App Store without Gatekeeper warnings:

### 1. Get Developer Certificate

1. Join Apple Developer Program ($99/year)
2. Create Developer ID Application certificate
3. Download and install in Keychain

### 2. Sign the App

```bash
# Find your certificate
security find-identity -v -p codesigning

# Sign the app
codesign --force --deep --sign "Developer ID Application: Your Name" QStatus.app

# Verify signature
codesign --verify --verbose QStatus.app
```

### 3. Notarize (for macOS 10.15+)

```bash
# Create ZIP for notarization
ditto -c -k --keepParent QStatus.app QStatus.zip

# Submit for notarization
xcrun notarytool submit QStatus.zip --apple-id your@email.com --team-id TEAMID --wait

# Staple the ticket
xcrun stapler staple QStatus.app
```

## 📊 Download Instructions for Users

Add this to your README or release notes:

### For Most Users (DMG):
1. Download `QStatus.dmg` from [Releases](https://github.com/yourusername/q-status/releases)
2. Open the DMG file
3. Drag Q Status to Applications
4. Launch from Applications or Spotlight
5. Click "Open" if macOS warns about unidentified developer

### For Power Users (Direct):
```bash
# Quick install
curl -sSL https://github.com/yourusername/q-status/releases/latest/download/install.sh | bash
```

### For CLI Only:
```bash
# Download and extract
curl -L https://github.com/yourusername/q-status/releases/latest/download/q-status-cli-macos.tar.gz | tar xz
# Move to PATH
sudo mv q-status-cli /usr/local/bin/q-status
```

## 🚀 Homebrew Distribution (Future)

To distribute via Homebrew:

1. Create a Formula:
```ruby
class QStatus < Formula
  desc "Real-time monitoring for Q (Claude) usage"
  homepage "https://github.com/yourusername/q-status"
  url "https://github.com/yourusername/q-status/releases/download/v1.0.0/q-status-cli-macos.tar.gz"
  sha256 "HASH_HERE"
  version "1.0.0"

  def install
    bin.install "q-status-cli" => "q-status"
  end

  caveats do
    <<~EOS
      For the menubar app, download from:
      https://github.com/yourusername/q-status/releases
    EOS
  end
end
```

2. Submit to homebrew-core or create your own tap

## 📈 Analytics

Track downloads using GitHub API:
```bash
curl -s https://api.github.com/repos/yourusername/q-status/releases/latest \
  | jq '.assets[] | {name: .name, downloads: .download_count}'
```

## 🔄 Update Mechanism

Consider adding auto-update functionality:

1. Add version check in app
2. Check GitHub releases API for updates
3. Notify user when update available
4. Direct to download page

## 📮 Support

For distribution issues:
- Check GitHub Actions logs for build failures
- Verify all assets are properly uploaded
- Test downloads on different macOS versions
- Monitor GitHub Issues for user reports