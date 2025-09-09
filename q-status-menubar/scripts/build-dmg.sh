#!/usr/bin/env bash
set -euo pipefail

APP_NAME="QStatusMenubar"
BUILD_DIR="build"
DMG_NAME="$APP_NAME.dmg"

echo "This script assumes you have an Xcode app target named $APP_NAME configured with LSUIElement=1."
echo "It archives, exports, signs (Developer ID), and builds a DMG."

mkdir -p "$BUILD_DIR"
xcodebuild -scheme "$APP_NAME" -configuration Release -archivePath "$BUILD_DIR/$APP_NAME.xcarchive" archive
xcodebuild -exportArchive -archivePath "$BUILD_DIR/$APP_NAME.xcarchive" -exportOptionsPlist ExportOptions.plist -exportPath "$BUILD_DIR"

APP_PATH="$BUILD_DIR/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
  echo "App not found at $APP_PATH. Ensure your export options are correct." >&2
  exit 1
fi

which create-dmg >/dev/null 2>&1 || {
  echo "create-dmg not found. Install via Homebrew: brew install create-dmg" >&2
  exit 1
}

create-dmg --overwrite --volname "$APP_NAME" --window-size 480 320 --icon-size 96 \
  --app-drop-link 360 200 --icon "$APP_PATH" 120 200 "$BUILD_DIR/$DMG_NAME" "$BUILD_DIR/"

echo "DMG at $BUILD_DIR/$DMG_NAME"

