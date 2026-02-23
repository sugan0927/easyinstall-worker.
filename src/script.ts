
// Bash script content as a raw string
export const EASYINSTALL_SCRIPT = `#!/bin/bash
# EasyInstall v3 - Main Installation Script

echo "EasyInstall Script Started"
echo "Fetching package information..."

# Function to detect OS
detect_os() {
    case "$(uname -s)" in
        Linux*)     echo "Linux";;
        Darwin*)    echo "macOS";;
        CYGWIN*)    echo "Windows (Cygwin)";;
        MINGW*)     echo "Windows (Git Bash)";;
        *)          echo "Unknown";;
    esac
}

# Function to detect package manager
detect_package_manager() {
    if command -v apt-get &> /dev/null; then
        echo "apt-get"
    elif command -v yum &> /dev/null; then
        echo "yum"
    elif command -v dnf &> /dev/null; then
        echo "dnf"
    elif command -v pacman &> /dev/null; then
        echo "pacman"
    elif command -v brew &> /dev/null; then
        echo "brew"
    elif command -v pkg &> /dev/null; then
        echo "pkg"
    else
        echo "unknown"
    fi
}

# Main installation function
install_package() {
    local package_name="$1"
    local package_manager=$(detect_package_manager)
    local os=$(detect_os)
    
    echo "OS: $os"
    echo "Package Manager: $package_manager"
    echo "Installing package: $package_name"
    
    case $package_manager in
        apt-get)
            sudo apt-get update
            sudo apt-get install -y "$package_name"
            ;;
        yum)
            sudo yum install -y "$package_name"
            ;;
        dnf)
            sudo dnf install -y "$package_name"
            ;;
        pacman)
            sudo pacman -S --noconfirm "$package_name"
            ;;
        brew)
            brew install "$package_name"
            ;;
        pkg)
            sudo pkg install -y "$package_name"
            ;;
        *)
            echo "Error: No supported package manager found"
            echo "Please install $package_name manually"
            return 1
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        echo "✓ Package $package_name installed successfully"
    else
        echo "✗ Failed to install $package_name"
        return 1
    fi
}

# Show help
show_help() {
    echo "EasyInstall v3"
    echo "Usage: ./easyinstall.sh [package-name]"
    echo ""
    echo "Examples:"
    echo "  ./easyinstall.sh nginx     # Install nginx"
    echo "  ./easyinstall.sh nodejs    # Install nodejs"
    echo "  ./easyinstall.sh --help    # Show this help"
}

# Main script logic
main() {
    case "$1" in
        ""|--help|-h)
            show_help
            ;;
        *)
            install_package "$1"
            ;;
    esac
}

# Run main function with all arguments
main "$@"
`;

