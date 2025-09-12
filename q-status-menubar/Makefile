# Q-Status Build and Installation Makefile
# ABOUTME: Unified build system for q-status-cli and q-status-menubar
# Provides easy commands for building, installing, and packaging both apps

.PHONY: all build-cli build-menubar install-cli install-menubar clean release help

# Default target
all: build-cli build-menubar

# Build the Rust CLI app
build-cli:
	@echo "Building q-status-cli..."
	cd ../q-status-cli && cargo build --release
	@echo "✅ CLI built successfully"

# Build the Swift menubar app
build-menubar:
	@echo "Building q-status-menubar..."
	swift build -c release
	@echo "✅ Menubar app built successfully"

# Install CLI to /usr/local/bin
install-cli: build-cli
	@echo "Installing q-status-cli to /usr/local/bin..."
	@sudo cp ../q-status-cli/target/release/q-status-cli /usr/local/bin/q-status
	@sudo chmod +x /usr/local/bin/q-status
	@echo "✅ CLI installed as 'q-status'"

# Build and package menubar app as a macOS .app bundle
package-menubar: build-menubar
	@echo "Creating macOS app bundle..."
	@rm -rf QStatus.app
	@mkdir -p QStatus.app/Contents/MacOS
	@mkdir -p QStatus.app/Contents/Resources
	@cp .build/release/QStatusMenubar QStatus.app/Contents/MacOS/QStatus
	@echo '<?xml version="1.0" encoding="UTF-8"?>' > QStatus.app/Contents/Info.plist
	@echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' >> QStatus.app/Contents/Info.plist
	@echo '<plist version="1.0">' >> QStatus.app/Contents/Info.plist
	@echo '<dict>' >> QStatus.app/Contents/Info.plist
	@echo '    <key>CFBundleName</key>' >> QStatus.app/Contents/Info.plist
	@echo '    <string>Q Status</string>' >> QStatus.app/Contents/Info.plist
	@echo '    <key>CFBundleDisplayName</key>' >> QStatus.app/Contents/Info.plist
	@echo '    <string>Q Status</string>' >> QStatus.app/Contents/Info.plist
	@echo '    <key>CFBundleIdentifier</key>' >> QStatus.app/Contents/Info.plist
	@echo '    <string>com.qlips.qstatus</string>' >> QStatus.app/Contents/Info.plist
	@echo '    <key>CFBundleVersion</key>' >> QStatus.app/Contents/Info.plist
	@echo '    <string>1.0.0</string>' >> QStatus.app/Contents/Info.plist
	@echo '    <key>CFBundlePackageType</key>' >> QStatus.app/Contents/Info.plist
	@echo '    <string>APPL</string>' >> QStatus.app/Contents/Info.plist
	@echo '    <key>CFBundleExecutable</key>' >> QStatus.app/Contents/Info.plist
	@echo '    <string>QStatus</string>' >> QStatus.app/Contents/Info.plist
	@echo '    <key>LSMinimumSystemVersion</key>' >> QStatus.app/Contents/Info.plist
	@echo '    <string>11.0</string>' >> QStatus.app/Contents/Info.plist
	@echo '    <key>LSUIElement</key>' >> QStatus.app/Contents/Info.plist
	@echo '    <true/>' >> QStatus.app/Contents/Info.plist
	@echo '    <key>NSHighResolutionCapable</key>' >> QStatus.app/Contents/Info.plist
	@echo '    <true/>' >> QStatus.app/Contents/Info.plist
	@echo '</dict>' >> QStatus.app/Contents/Info.plist
	@echo '</plist>' >> QStatus.app/Contents/Info.plist
	@echo "✅ App bundle created: QStatus.app"

# Install menubar app to Applications
install-menubar: package-menubar
	@echo "Installing Q Status to /Applications..."
	@rm -rf "/Applications/Q Status.app"
	@cp -R QStatus.app "/Applications/Q Status.app"
	@echo "✅ Q Status installed to Applications"
	@echo "🚀 Launch it from Applications or Spotlight!"

# Install both apps
install: install-cli install-menubar
	@echo "✅ Both apps installed successfully!"

# Create DMG for distribution
dmg: package-menubar
	@echo "Creating DMG for distribution..."
	@rm -f QStatus.dmg
	@mkdir -p dmg-temp
	@cp -R QStatus.app dmg-temp/
	@ln -s /Applications dmg-temp/Applications
	@hdiutil create -volname "Q Status" -srcfolder dmg-temp -ov -format UDZO QStatus.dmg
	@rm -rf dmg-temp
	@echo "✅ DMG created: QStatus.dmg"

# Create release packages
release: build-cli package-menubar
	@echo "Creating release packages..."
	@mkdir -p releases
	# Package CLI as tar.gz
	@tar -czf releases/q-status-cli-macos.tar.gz -C ../q-status-cli/target/release q-status-cli
	# Package menubar app as zip
	@zip -r releases/QStatus.app.zip QStatus.app
	# Create DMG
	@make dmg
	@mv QStatus.dmg releases/
	@echo "✅ Release packages created in releases/"
	@echo "  - q-status-cli-macos.tar.gz"
	@echo "  - QStatus.app.zip"
	@echo "  - QStatus.dmg"

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	cd ../q-status-cli && cargo clean
	swift package clean
	rm -rf QStatus.app
	rm -f QStatus.dmg
	rm -rf releases
	@echo "✅ Cleaned"

# Show help
help:
	@echo "Q-Status Build System"
	@echo ""
	@echo "Quick Install:"
	@echo "  make install         - Build and install both apps"
	@echo ""
	@echo "Individual targets:"
	@echo "  make build-cli       - Build the CLI app"
	@echo "  make build-menubar   - Build the menubar app"
	@echo "  make install-cli     - Install CLI to /usr/local/bin"
	@echo "  make install-menubar - Install menubar app to /Applications"
	@echo ""
	@echo "Distribution:"
	@echo "  make dmg            - Create a DMG installer"
	@echo "  make release        - Create all release packages"
	@echo ""
	@echo "Maintenance:"
	@echo "  make clean          - Remove all build artifacts"
	@echo "  make help           - Show this help message"