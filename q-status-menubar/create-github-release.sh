#!/bin/bash
# ABOUTME: Script to create GitHub release after pushing to GitHub
# Run this after setting up your GitHub repository

set -e

echo "Creating GitHub Release for QStatus v1.0.0"
echo "=========================================="
echo ""

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
    echo "❌ GitHub CLI (gh) is not installed"
    echo "Install with: brew install gh"
    exit 1
fi

# Check if we're in the right directory
if [ ! -f "Makefile" ] || [ ! -d "releases" ]; then
    echo "❌ Please run this script from the q-status-menubar directory"
    exit 1
fi

# Check if release files exist
if [ ! -f "releases/QStatus.dmg" ] || [ ! -f "releases/QStatus.app.zip" ] || [ ! -f "releases/qstatus-cli-macos.tar.gz" ]; then
    echo "❌ Release files not found. Run 'make release' first"
    exit 1
fi

echo "📝 Prerequisites:"
echo "1. Push your repository to GitHub:"
echo "   git remote add origin https://github.com/YOUR_USERNAME/qstatus.git"
echo "   git push -u origin master"
echo "   git push origin v1.0.0"
echo ""
echo "2. Authenticate with GitHub:"
echo "   gh auth login"
echo ""
echo "Once ready, press Enter to create the release..."
read

# Create the release
echo "Creating release..."
cd releases
gh release create v1.0.0 \
  --title "QStatus v1.0.0 - Initial Release" \
  --notes-file ../RELEASE_NOTES.md \
  --draft \
  QStatus.dmg \
  QStatus.app.zip \
  qstatus-cli-macos.tar.gz

echo ""
echo "✅ Draft release created!"
echo ""
echo "Next steps:"
echo "1. Go to https://github.com/YOUR_USERNAME/qstatus/releases"
echo "2. Review the draft release"
echo "3. Edit the release notes if needed"
echo "4. Publish the release when ready"
echo ""
echo "To publish directly from CLI:"
echo "   gh release edit v1.0.0 --draft=false"