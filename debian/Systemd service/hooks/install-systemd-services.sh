#!/bin/bash
# Install Systemd Services for EasyInstall

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}🚀 Installing EasyInstall Systemd Services${NC}"

# Copy service files
cp autoheal.service /lib/systemd/system/
cp glances.service /lib/systemd/system/

# Copy hook scripts
mkdir -p /usr/share/easyinstall/hooks
cp enable-theme-editor.sh /usr/share/easyinstall/hooks/
cp post-install.sh /usr/share/easyinstall/hooks/
chmod +x /usr/share/easyinstall/hooks/*.sh

# Reload systemd
systemctl daemon-reload

# Enable services
systemctl enable autoheal
systemctl enable glances

# Start services
systemctl start autoheal
systemctl start glances

echo -e "${GREEN}✅ Services installed and started${NC}"
echo -e "${YELLOW}📝 Check status: systemctl status autoheal glances${NC}"