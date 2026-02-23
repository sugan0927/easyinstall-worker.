#!/bin/bash
# Post-Install Hook for EasyInstall
# Runs after package installation
# Location: /usr/share/easyinstall/hooks/post-install.sh

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[POST-INSTALL]${NC} $1"
}

# Enable theme editor
if [ -f "/usr/share/easyinstall/hooks/enable-theme-editor.sh" ]; then
    log "馃帹 Running theme editor enabler..."
    bash "/usr/share/easyinstall/hooks/enable-theme-editor.sh"
fi

# Enable and start autoheal service
if [ -f "/lib/systemd/system/autoheal.service" ]; then
    log "鈿欙笍 Enabling auto-heal service..."
    systemctl daemon-reload
    systemctl enable autoheal
    systemctl start autoheal
    log "  鉁� Auto-heal service started"
fi

# Enable and start glances
if [ -f "/lib/systemd/system/glances.service" ]; then
    log "馃搳 Enabling Glances monitoring..."
    systemctl enable glances
    systemctl start glances
    log "  鉁� Glances service started"
fi

log "鉁� Post-install hook completed"
