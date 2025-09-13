# Homebrew Distribution Setup

This guide explains how to distribute QStatus via Homebrew for easy installation.

## 🍺 Installation Commands (For Users)

Once set up, users can install with:

```bash
# Add your tap
brew tap yourusername/qstatus

# Install CLI
brew install qstatus-cli

# Install Menubar app
brew install --cask qstatus-menu

# Or install both
brew install qstatus-cli && brew install --cask qstatus-menu
```

## 📦 Release Process

### 1. Build Release Assets

```bash
cd qstatus-menubar

# Build everything for release
make release

# This creates:
# - releases/qstatus-cli-macos.tar.gz (CLI binary)
# - releases/QStatus.dmg (Menubar app installer)
# - releases/QStatus.app.zip (Direct app)
```

### 2. Create GitHub Release

1. Go to GitHub → Releases → Create new release
2. Tag as `v1.0.0` (or your version)
3. Upload these files:
   - `QStatus.dmg` (for Homebrew Cask)
   - `qstatus-cli-macos.tar.gz` (for Homebrew Formula)
   - `QStatus.app.zip` (optional, direct download)
   - `install.sh` (for curl install method)

### 3. Update Homebrew Formulas

After creating the release, update the SHA256 hashes:

```bash
# Get SHA256 for CLI
shasum -a 256 releases/qstatus-cli-macos.tar.gz

# Get SHA256 for DMG
shasum -a 256 releases/QStatus.dmg
```

Update in:
- `homebrew/qstatus-cli.rb` - Update SHA256 and version
- `homebrew/qstatus-menu.rb` - Update SHA256 and version

### 4. Create Homebrew Tap

Create a new repository called `homebrew-qstatus`:

```bash
# Create new repo on GitHub: yourusername/homebrew-qstatus

# Clone it
git clone https://github.com/yourusername/homebrew-qstatus.git
cd homebrew-qstatus

# Copy formulas
cp ../qstatus/homebrew/qstatus-cli.rb Formula/
cp ../qstatus/homebrew/qstatus-menu.rb Casks/

# Commit and push
git add .
git commit -m "Add QStatus formulas"
git push
```

## 🔄 Automated Release with GitHub Actions

Update `.github/workflows/release.yml`:

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    runs-on: macos-latest
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Install Rust
      uses: actions-rs/toolchain@v1
      with:
        toolchain: stable
        
    - name: Build CLI
      run: |
        cd qstatus-cli
        cargo build --release
        
    - name: Build Menubar App
      run: |
        cd qstatus-menubar
        swift build -c release
        
    - name: Create App Bundle and DMG
      run: |
        cd qstatus-menubar
        make package-menubar
        make dmg
        
    - name: Package Release Assets
      run: |
        cd qstatus-menubar
        mkdir -p releases
        tar -czf releases/qstatus-cli-macos.tar.gz -C ../qstatus-cli/target/release qstatus-cli
        zip -r releases/QStatus.app.zip QStatus.app
        cp QStatus.dmg releases/
        cp install.sh releases/
        
    - name: Generate SHA256
      run: |
        cd qstatus-menubar/releases
        shasum -a 256 qstatus-cli-macos.tar.gz > qstatus-cli-macos.tar.gz.sha256
        shasum -a 256 QStatus.dmg > QStatus.dmg.sha256
        
    - name: Create Release
      uses: softprops/action-gh-release@v1
      with:
        files: |
          qstatus-menubar/releases/qstatus-cli-macos.tar.gz
          qstatus-menubar/releases/qstatus-cli-macos.tar.gz.sha256
          qstatus-menubar/releases/QStatus.dmg
          qstatus-menubar/releases/QStatus.dmg.sha256
          qstatus-menubar/releases/QStatus.app.zip
          qstatus-menubar/releases/install.sh
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        
    - name: Update Homebrew Tap
      run: |
        # This would update your homebrew-qstatus repo
        # with new versions and SHA256 hashes
```

## 📝 Version Bumping

When releasing a new version:

1. Update version in:
   - `qstatus-cli/Cargo.toml`
   - `qstatus-menubar/Package.swift`
   - `qstatus-menubar/Makefile` (CFBundleVersion)
   - `homebrew/qstatus-cli.rb`
   - `homebrew/qstatus-menu.rb`

2. Tag the release:
```bash
git tag -a v1.0.1 -m "Release v1.0.1"
git push origin v1.0.1
```

## 🎯 Final User Experience

Users can then simply:

```bash
# One-time setup
brew tap yourusername/qstatus

# Install everything
brew install qstatus-cli
brew install --cask qstatus-menu

# Update later
brew upgrade qstatus-cli
brew upgrade --cask qstatus-menu
```

## 📊 Benefits

- ✅ **Simple installation**: Just `brew install`
- ✅ **Easy updates**: `brew upgrade` handles everything
- ✅ **Dependency management**: Homebrew handles requirements
- ✅ **Professional distribution**: Standard macOS package manager
- ✅ **DMG included**: The Cask formula installs from the DMG
- ✅ **Version management**: Homebrew tracks versions

## 🔍 Testing Your Formulas

Before publishing:

```bash
# Test the CLI formula
brew install --build-from-source homebrew/qstatus-cli.rb

# Test the Cask formula
brew install --cask homebrew/qstatus-menu.rb

# Audit formulas
brew audit --strict qstatus-cli
brew audit --cask qstatus-menu
```

## 📚 Resources

- [Homebrew Formula Cookbook](https://docs.brew.sh/Formula-Cookbook)
- [Homebrew Cask Cookbook](https://docs.brew.sh/Cask-Cookbook)
- [Creating a Homebrew Tap](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap)