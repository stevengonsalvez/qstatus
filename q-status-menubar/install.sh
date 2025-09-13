#!/bin/bash
# ABOUTME: One-click installer script for QStatus apps
# Downloads, builds, and installs both the CLI and menubar apps

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}QStatus Installer${NC}"
echo "===================="
echo ""

# Check for required tools
check_requirements() {
    echo "Checking requirements..."
    
    # Check for Rust
    if ! command -v cargo &> /dev/null; then
        echo -e "${RED}❌ Rust is not installed${NC}"
        echo "Install Rust first: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
        exit 1
    fi
    
    # Check for Swift
    if ! command -v swift &> /dev/null; then
        echo -e "${RED}❌ Swift is not installed${NC}"
        echo "Install Xcode or Xcode Command Line Tools"
        exit 1
    fi
    
    echo -e "${GREEN}✅ All requirements met${NC}"
}

# Install from local directory
install_local() {
    echo "Installing from local directory..."
    
    # Use the Makefile
    make install
    
    echo ""
    echo -e "${GREEN}✅ Installation complete!${NC}"
    echo ""
    echo "Usage:"
    echo "  CLI: Run 'qstatus-cli' in your terminal"
    echo "  Menubar: Launch 'QStatus Menu' from Applications or Spotlight"
}

# Install from GitHub
install_from_github() {
    echo "Downloading from GitHub..."
    
    # Clone the repository
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    git clone https://github.com/yourusername/qstatus.git
    cd qstatus/q-status-menubar
    
    # Build and install
    make install
    
    # Cleanup
    cd ~
    rm -rf "$TEMP_DIR"
    
    echo ""
    echo -e "${GREEN}✅ Installation complete!${NC}"
    echo ""
    echo "Usage:"
    echo "  CLI: Run 'qstatus-cli' in your terminal"
    echo "  Menubar: Launch 'QStatus Menu' from Applications or Spotlight"
}

# Main installation flow
main() {
    check_requirements
    
    # Check if we're in the project directory
    if [ -f "Makefile" ] && [ -d "q-status-cli" ] && [ -d "q-status-menubar" ]; then
        install_local
    else
        echo "Install from GitHub? (y/n)"
        read -r response
        if [[ "$response" == "y" ]]; then
            install_from_github
        else
            echo "Please run this script from the qstatus project directory"
            exit 1
        fi
    fi
    
    # Ask to launch menubar app
    echo ""
    echo "Launch QStatus Menu app now? (y/n)"
    read -r response
    if [[ "$response" == "y" ]]; then
        open "/Applications/QStatus Menu.app"
        echo -e "${GREEN}✅ QStatus Menu is running in your menubar!${NC}"
    fi
}

# Run main function
main