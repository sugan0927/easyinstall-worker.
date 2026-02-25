#!/bin/bash

# ============================================
# EasyInstall Master Installer with Integrations
# ============================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}🚀 EasyInstall Enterprise Stack with Integrations${NC}"
echo ""

# Root check
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}❌ Please run as root${NC}"
    exit 1
fi

# Install base EasyInstall
echo -e "${YELLOW}📦 Installing base EasyInstall...${NC}"

# Fix: Use proper URL encoding for filename with parentheses
curl -fsSL "https://raw.githubusercontent.com/sugan0927/easyinstall-worker./main/easyinstall.sh" -o /tmp/easyinstall.sh

# Alternative: If you rename the file, use this instead
# curl -fsSL https://raw.githubusercontent.com/sugan0927/easyinstall-worker./main/easyinstall.sh -o /tmp/easyinstall.sh

bash /tmp/easyinstall.sh
rm /tmp/easyinstall.sh

# Create integrations directory
mkdir -p /usr/share/easyinstall/integrations

# Download integrations
echo -e "${YELLOW}🔌 Downloading integrations...${NC}"

INTEGRATIONS=("docker" "kubernetes" "podman" "microvm")
BASE_URL="https://raw.githubusercontent.com/sugan0927/easyinstall-worker./main/integrations"

for integration in "${INTEGRATIONS[@]}"; do
    echo -e "   Downloading $integration integration..."
    if curl -fsSL "$BASE_URL/$integration.sh" -o "/usr/share/easyinstall/integrations/$integration.sh"; then
        chmod +x "/usr/share/easyinstall/integrations/$integration.sh"
        echo -e "   ${GREEN}✅ Downloaded $integration${NC}"
    else
        echo -e "   ${YELLOW}⚠️ Could not download $integration (continuing anyway)${NC}"
    fi
done

# Create base command if it doesn't exist
if [ ! -f /usr/local/bin/easyinstall-base ]; then
    ln -sf /usr/local/bin/easyinstall /usr/local/bin/easyinstall-base 2>/dev/null || true
fi

# Create wrapper script
cat > /usr/local/bin/easyinstall-wrapper <<'EOF'
#!/bin/bash

# EasyInstall Wrapper with Integrations

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

BASE_CMD="/usr/local/bin/easyinstall"
INTEGRATIONS_DIR="/usr/share/easyinstall/integrations"

# Source integrations if available
if [ -d "$INTEGRATIONS_DIR" ]; then
    for integration in "$INTEGRATIONS_DIR"/*.sh; do
        if [ -f "$integration" ]; then
            source "$integration"
        fi
    done
fi

# Function to show integration help
show_integration_help() {
    echo -e "${GREEN}EasyInstall Enterprise Stack with Integrations${NC}"
    echo ""
    echo -e "${YELLOW}Available commands:${NC}"
    echo ""
    echo "  Core Commands:"
    echo "    easyinstall domain example.com        - Install WordPress"
    echo "    easyinstall status                    - Check system status"
    echo "    easyinstall help                       - Show all core commands"
    echo ""
    echo "  Integration Commands:"
    echo "    easyinstall docker help                - Docker integration"
    echo "    easyinstall k8s help                   - Kubernetes integration"
    echo "    easyinstall podman help                - Podman integration"
    echo "    easyinstall microvm help               - MicroVM integration"
    echo ""
}

# Handle integration commands
case "$1" in
    docker)
        if [ -z "$2" ] || [ "$2" = "help" ]; then
            if type docker_command &>/dev/null; then
                docker_command
            else
                echo -e "${RED}Docker integration not available${NC}"
            fi
        else
            shift
            if type docker_command &>/dev/null; then
                docker_command "$@"
            else
                echo -e "${RED}Docker integration not available${NC}"
            fi
        fi
        ;;
    k8s|kubernetes)
        if [ -z "$2" ] || [ "$2" = "help" ]; then
            if type k8s_command &>/dev/null; then
                k8s_command
            else
                echo -e "${RED}Kubernetes integration not available${NC}"
            fi
        else
            shift
            if type k8s_command &>/dev/null; then
                k8s_command "$@"
            else
                echo -e "${RED}Kubernetes integration not available${NC}"
            fi
        fi
        ;;
    podman)
        if [ -z "$2" ] || [ "$2" = "help" ]; then
            if type podman_command &>/dev/null; then
                podman_command
            else
                echo -e "${RED}Podman integration not available${NC}"
            fi
        else
            shift
            if type podman_command &>/dev/null; then
                podman_command "$@"
            else
                echo -e "${RED}Podman integration not available${NC}"
            fi
        fi
        ;;
    microvm)
        if [ -z "$2" ] || [ "$2" = "help" ]; then
            if type microvm_command &>/dev/null; then
                microvm_command
            else
                echo -e "${RED}MicroVM integration not available${NC}"
            fi
        else
            shift
            if type microvm_command &>/dev/null; then
                microvm_command "$@"
            else
                echo -e "${RED}MicroVM integration not available${NC}"
            fi
        fi
        ;;
    help|--help|-h)
        show_integration_help
        ;;
    *)
        # Pass through to base command
        if [ -f "$BASE_CMD" ]; then
            exec "$BASE_CMD" "$@"
        else
            echo -e "${RED}Base EasyInstall command not found${NC}"
            exit 1
        fi
        ;;
esac
EOF

chmod +x /usr/local/bin/easyinstall-wrapper

# Replace the original easyinstall with wrapper
mv /usr/local/bin/easyinstall-wrapper /usr/local/bin/easyinstall 2>/dev/null || \
cp /usr/local/bin/easyinstall-wrapper /usr/local/bin/easyinstall

# Clean up
rm -f /usr/local/bin/easyinstall-wrapper 2>/dev/null || true

echo -e "${GREEN}"
echo "============================================"
echo "✅ Installation Complete with Integrations!"
echo "============================================"
echo ""
echo -e "${YELLOW}Available integrations:${NC}"
echo "  docker    - Docker Compose support"
echo "  k8s       - Kubernetes support"
echo "  podman    - Podman/Containerd support"
echo "  microvm   - Firecracker/Youki isolation"
echo ""
echo -e "${YELLOW}Usage examples:${NC}"
echo "  easyinstall domain example.com              # WordPress"
echo "  easyinstall docker create example.com       # Docker"
echo "  easyinstall k8s deploy example.com          # Kubernetes"
echo "  easyinstall podman create example.com       # Podman"
echo "  easyinstall microvm create-firecracker example.com  # MicroVM"
echo ""
echo -e "${GREEN}Run 'easyinstall help' for all core commands${NC}"
echo -e "${NC}"
