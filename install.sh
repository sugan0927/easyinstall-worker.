#!/bin/bash
# install.sh - EasyInstall Package Installer

echo "🚀 EasyInstall Package Installer"
echo "================================"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Please run as root"
    exit 1
fi

# Build the package
echo "📦 Building package..."
bash build-pkg.sh

# Install the package
echo "📦 Installing package..."
dpkg -i easyinstall_3.0_all.deb

# Fix dependencies
echo "📦 Fixing dependencies..."
apt-get install -f -y

# Run the installer
echo "🚀 Running EasyInstall..."
easyinstall

echo ""
echo "✅ Installation complete!"
echo ""
echo "Quick commands:"
echo "  easyinstall status              - Check system status"
echo "  easyinstall domain example.com  - Install WordPress"
echo "  easyinstall help                 - Show all commands"
echo "  easyinstall --pkg-status         - Check package status"
echo ""
echo "Theme/Plugin Editor: ENABLED by default"