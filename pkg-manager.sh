#!/bin/bash
# EasyInstall Package Manager
# Handles package operations during script execution

PKG_NAME="easyinstall"
PKG_VERSION="3.0"
PKG_STATE_DIR="/var/lib/easyinstall"
PKG_CONFIG_DIR="/etc/easyinstall"
PKG_LOG_DIR="/var/log/easyinstall"
PKG_BACKUP_DIR="/var/backups/easyinstall"
PKG_HOOKS_DIR="/usr/share/easyinstall/hooks"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================
# Package Manager Core Functions
# ============================================

init_package_system() {
    # Create necessary directories
    mkdir -p "$PKG_STATE_DIR" "$PKG_CONFIG_DIR" "$PKG_LOG_DIR" "$PKG_BACKUP_DIR" "$PKG_HOOKS_DIR"
    
    # Initialize state file if not exists
    if [ ! -f "$PKG_STATE_DIR/installed" ]; then
        echo "{}" > "$PKG_STATE_DIR/installed"
    fi
    
    # Set proper permissions
    chmod 755 "$PKG_STATE_DIR" "$PKG_CONFIG_DIR" "$PKG_LOG_DIR" "$PKG_HOOKS_DIR"
    chmod 644 "$PKG_STATE_DIR/installed"
    
    # Create default config if not exists
    if [ ! -f "$PKG_CONFIG_DIR/config" ]; then
        cat > "$PKG_CONFIG_DIR/config" <<EOF
# EasyInstall Configuration
# Generated: $(date)

# Installation paths
INSTALL_PATH="/usr/local/easyinstall"
BACKUP_PATH="$PKG_BACKUP_DIR"

# Auto-update settings
AUTO_UPDATE="true"
UPDATE_CHECK_INTERVAL="86400"  # 24 hours

# Service settings
ENABLE_AUTOHEAL="true"
MONITORING_INTERVAL="60"

# Backup settings
BACKUP_RETENTION_DAYS="7"
REMOTE_BACKUP_ENABLED="false"

# Security settings
ENABLE_MODSECURITY="true"
ENABLE_FAIL2BAN="true"
AUTO_UPDATE_KEYS="true"

# Performance settings
PHP_MEMORY_LIMIT="256M"
REDIS_MAXMEMORY="64mb"
MYSQL_BUFFER_POOL="64M"

# WordPress settings
ENABLE_THEME_EDITOR="true"  # Enable theme/plugin editor by default
DISABLE_XMLRPC="false"       # XML-RPC enabled by default
EOF
        chmod 644 "$PKG_CONFIG_DIR/config"
    fi
}

# ============================================
# Component Tracking
# ============================================

mark_component_installed() {
    local component="$1"
    local version="$2"
    local timestamp=$(date +%s)
    
    # Update state file
    local tmp_file=$(mktemp)
    if [ -f "$PKG_STATE_DIR/installed" ]; then
        if command -v jq >/dev/null 2>&1; then
            jq --arg comp "$component" \
               --arg ver "$version" \
               --arg time "$timestamp" \
               '.[$comp] = {"version": $ver, "installed": $time}' \
               "$PKG_STATE_DIR/installed" > "$tmp_file"
            mv "$tmp_file" "$PKG_STATE_DIR/installed"
        else
            # Fallback if jq not available
            echo "$component:$version:$timestamp" >> "$PKG_STATE_DIR/installed.simple"
        fi
    fi
    
    # Log installation
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INSTALLED: $component v$version" >> "$PKG_LOG_DIR/install.log"
}

is_component_installed() {
    local component="$1"
    if [ -f "$PKG_STATE_DIR/installed" ]; then
        if command -v jq >/dev/null 2>&1; then
            jq -e --arg comp "$component" '.[$comp]' "$PKG_STATE_DIR/installed" >/dev/null 2>&1
            return $?
        else
            grep -q "^$component:" "$PKG_STATE_DIR/installed.simple" 2>/dev/null
            return $?
        fi
    fi
    return 1
}

get_component_version() {
    local component="$1"
    if [ -f "$PKG_STATE_DIR/installed" ]; then
        if command -v jq >/dev/null 2>&1; then
            jq -r --arg comp "$component" '.[$comp].version // "0"' "$PKG_STATE_DIR/installed" 2>/dev/null || echo "0"
        else
            grep "^$component:" "$PKG_STATE_DIR/installed.simple" 2>/dev/null | cut -d: -f2 || echo "0"
        fi
    else
        echo "0"
    fi
}

# ============================================
# Transaction Support
# ============================================

TRANSACTION_LOG="/var/lib/easyinstall/transaction.log"
TRANSACTION_ACTIVE=false

begin_transaction() {
    local component="$1"
    TRANSACTION_ACTIVE=true
    echo "BEGIN:$(date +%s):$component" > "$TRANSACTION_LOG"
    echo "COMPONENT: $component" >> "$TRANSACTION_LOG"
}

commit_transaction() {
    local component="$1"
    local version="$2"
    if [ "$TRANSACTION_ACTIVE" = true ]; then
        echo "COMMIT:$(date +%s)" >> "$TRANSACTION_LOG"
        mark_component_installed "$component" "$version"
        TRANSACTION_ACTIVE=false
        rm -f "$TRANSACTION_LOG"
    fi
}

rollback_transaction() {
    if [ "$TRANSACTION_ACTIVE" = true ]; then
        echo "ROLLBACK:$(date +%s)" >> "$TRANSACTION_LOG"
        echo "⚠️ Transaction rolled back" >> "$PKG_LOG_DIR/error.log"
        TRANSACTION_ACTIVE=false
        rm -f "$TRANSACTION_LOG"
        return 1
    fi
}

# ============================================
# Package Manager Commands
# ============================================

handle_package_command() {
    case "$1" in
        --pkg-update)
            update_package "$2"
            ;;
        --pkg-remove)
            remove_package "${2:-all}"
            ;;
        --pkg-status)
            show_package_status
            ;;
        --pkg-list)
            list_components
            ;;
        --pkg-verify)
            verify_installation
            ;;
        --pkg-backup)
            backup_configuration
            ;;
        --pkg-restore)
            restore_configuration "$2"
            ;;
        *)
            echo "Package Manager Commands:"
            echo "  --pkg-update [component]  - Update specific component or all"
            echo "  --pkg-remove [component]  - Remove component"
            echo "  --pkg-status               - Show installation status"
            echo "  --pkg-list                  - List installed components"
            echo "  --pkg-verify                - Verify installation integrity"
            echo "  --pkg-backup                - Backup configuration"
            echo "  --pkg-restore [file]        - Restore configuration"
            ;;
    esac
}

update_package() {
    local component="$1"
    
    echo -e "${YELLOW}🔄 Updating EasyInstall package...${NC}"
    
    # Check for updates in repository
    local latest_version=$(curl -s https://api.github.com/repos/sugandodrai/easyinstall/releases/latest | jq -r .tag_name 2>/dev/null || echo "$PKG_VERSION")
    
    if [ "$latest_version" != "$PKG_VERSION" ] && [ "$latest_version" != "null" ]; then
        echo -e "${GREEN}📦 New version available: $latest_version (current: $PKG_VERSION)${NC}"
        read -p "Update? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # Backup current configuration
            backup_configuration
            
            # Download and run updater
            cd /tmp
            curl -L "https://github.com/sugandodrai/easyinstall/archive/$latest_version.tar.gz" | tar xz
            cd "easyinstall-$latest_version"
            ./install.sh --update
            echo -e "${GREEN}✅ Update completed${NC}"
        fi
    else
        echo -e "${GREEN}✅ Already at latest version: $PKG_VERSION${NC}"
    fi
    
    # Update specific component if requested
    if [ -n "$component" ] && [ "$component" != "all" ]; then
        echo -e "${YELLOW}🔄 Updating component: $component${NC}"
        # Trigger component update
        if [ -f "/usr/local/bin/easyinstall" ]; then
            easyinstall update-component "$component"
        fi
    fi
}

remove_package() {
    local component="$1"
    
    if [ "$component" = "all" ] || [ "$component" = "full" ]; then
        echo -e "${RED}⚠️  This will completely remove EasyInstall and all components${NC}"
        read -p "Are you sure? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}🗑️  Removing EasyInstall...${NC}"
            
            # Backup configuration
            backup_configuration
            
            # Stop services
            systemctl stop autoheal 2>/dev/null
            systemctl stop nginx 2>/dev/null
            systemctl stop php*-fpm 2>/dev/null
            
            # Remove files
            rm -f /usr/local/bin/easyinstall
            rm -f /usr/local/bin/easy-*
            rm -f /usr/local/bin/xmlrpc-manager
            rm -f /usr/local/bin/install-wordpress
            rm -f /usr/local/bin/autoheal
            rm -f /usr/local/bin/update-wp-keys
            rm -rf /usr/share/easyinstall
            rm -rf /etc/easyinstall
            
            # Remove services
            rm -f /etc/systemd/system/autoheal.service
            rm -f /etc/systemd/system/glances.service
            systemctl daemon-reload
            
            echo -e "${GREEN}✅ EasyInstall removed. Configuration backed up to $PKG_BACKUP_DIR${NC}"
            echo "To restore: easyinstall --pkg-restore $PKG_BACKUP_DIR/backup-file.tar.gz"
        fi
    else
        echo -e "${YELLOW}🔄 Removing component: $component${NC}"
        # Call component removal
        if [ -f "/usr/local/bin/easyinstall" ]; then
            easyinstall remove-component "$component"
        fi
        mark_component_installed "$component" "removed"
    fi
}

show_package_status() {
    echo -e "${GREEN}📊 EasyInstall Package Status${NC}"
    echo "=============================="
    echo "Version: $PKG_VERSION"
    echo "Installation Date: $(stat -c %y /usr/local/bin/easyinstall 2>/dev/null | cut -d' ' -f1 || echo 'Unknown')"
    echo ""
    
    echo -e "${YELLOW}📦 Installed Components:${NC}"
    if [ -f "$PKG_STATE_DIR/installed" ]; then
        if command -v jq >/dev/null 2>&1; then
            jq -r 'to_entries[] | "  • \(.key): v\(.value.version) (installed: \(.value.installed | strflocaltime("%Y-%m-%d")))"' "$PKG_STATE_DIR/installed" 2>/dev/null || echo "  None"
        else
            cat "$PKG_STATE_DIR/installed.simple" 2>/dev/null | while IFS=: read comp ver time; do
                date_str=$(date -d "@$time" "+%Y-%m-%d" 2>/dev/null || echo "unknown")
                echo "  • $comp: v$ver (installed: $date_str)"
            done
        fi
    else
        echo "  No components tracked"
    fi
    
    echo ""
    echo -e "${YELLOW}🔧 Service Status:${NC}"
    for service in nginx php*-fpm mariadb redis-server memcached fail2ban autoheal netdata; do
        if systemctl is-active --quiet $service 2>/dev/null; then
            echo -e "  ${GREEN}✅${NC} $service: running"
        else
            echo -e "  ${RED}❌${NC} $service: stopped"
        fi
    done
    
    echo ""
    echo -e "${YELLOW}⚙️  WordPress Settings:${NC}"
    echo "  • Theme/Plugin Editor: ENABLED (DISALLOW_FILE_EDIT = false)"
    echo "  • XML-RPC: ENABLED by default (use 'easyinstall xmlrpc disable' to block)"
}

list_components() {
    echo -e "${GREEN}📦 EasyInstall Components:${NC}"
    echo "  • nginx              - Web server"
    echo "  • php                - PHP processor"
    echo "  • mariadb            - Database"
    echo "  • redis              - Object cache"
    echo "  • memcached          - Memory cache"
    echo "  • fail2ban           - Security"
    echo "  • modsecurity        - WAF"
    echo "  • autoheal           - Self-healing"
    echo "  • netdata            - Monitoring"
    echo "  • glances            - System monitor"
    echo "  • xmlrpc             - XML-RPC manager"
    echo "  • security-keys      - WordPress key rotator"
    echo "  • backup             - Backup system"
    echo "  • cdn                - CDN integration"
    echo "  • panel              - Multi-site panel"
    echo "  • remote             - Remote storage"
    echo "  • commands           - CLI commands"
}

verify_installation() {
    echo -e "${GREEN}🔍 Verifying EasyInstall installation...${NC}"
    local errors=0
    local warnings=0
    
    # Check critical binaries
    echo -e "\n${YELLOW}Checking binaries...${NC}"
    local binaries=("nginx" "mysql" "php" "redis-server" "memcached")
    for bin in "${binaries[@]}"; do
        if command -v $bin >/dev/null 2>&1; then
            echo -e "  ${GREEN}✅${NC} $bin found"
        else
            echo -e "  ${RED}❌${NC} $bin missing"
            ((errors++))
        fi
    done
    
    # Check critical files
    echo -e "\n${YELLOW}Checking configuration files...${NC}"
    local files=("/etc/nginx/nginx.conf" "/etc/mysql/my.cnf" "/root/.my.cnf" "/etc/nginx/security-headers.conf")
    for file in "${files[@]}"; do
        if [ -f "$file" ]; then
            echo -e "  ${GREEN}✅${NC} $file exists"
        else
            echo -e "  ${RED}❌${NC} $file missing"
            ((errors++))
        fi
    done
    
    # Check services
    echo -e "\n${YELLOW}Checking services...${NC}"
    local services=("nginx" "mariadb" "redis-server" "memcached" "fail2ban")
    for service in "${services[@]}"; do
        if systemctl is-active --quiet $service 2>/dev/null; then
            echo -e "  ${GREEN}✅${NC} $service running"
        else
            echo -e "  ${RED}❌${NC} $service not running"
            ((errors++))
        fi
    done
    
    # Check autoheal
    if systemctl is-active --quiet autoheal 2>/dev/null; then
        echo -e "  ${GREEN}✅${NC} autoheal running"
    else
        echo -e "  ${YELLOW}⚠️${NC} autoheal not running (optional)"
        ((warnings++))
    fi
    
    # Check WordPress configuration
    if [ -f "/var/www/html/wordpress/wp-config.php" ]; then
        echo -e "\n${YELLOW}Checking WordPress configuration...${NC}"
        if grep -q "DISALLOW_FILE_EDIT.*false" "/var/www/html/wordpress/wp-config.php"; then
            echo -e "  ${GREEN}✅${NC} Theme/Plugin Editor: ENABLED"
        else
            echo -e "  ${YELLOW}⚠️${NC} Theme/Plugin Editor: DISABLED (set DISALLOW_FILE_EDIT to false to enable)"
        fi
    fi
    
    echo ""
    if [ $errors -eq 0 ]; then
        echo -e "${GREEN}✅ Installation verified successfully${NC}"
        if [ $warnings -gt 0 ]; then
            echo -e "${YELLOW}⚠️  Found $warnings warnings${NC}"
        fi
        return 0
    else
        echo -e "${RED}❌ Found $errors issues${NC}"
        return 1
    fi
}

backup_configuration() {
    local backup_file="$PKG_BACKUP_DIR/easyinstall-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    
    echo -e "${YELLOW}💾 Backing up EasyInstall configuration to $backup_file${NC}"
    
    tar -czf "$backup_file" \
        /etc/easyinstall \
        /var/lib/easyinstall \
        /usr/local/bin/easyinstall \
        /usr/local/bin/easy-* \
        /usr/local/bin/xmlrpc-manager \
        /usr/local/bin/install-wordpress \
        /usr/local/bin/autoheal \
        /usr/local/bin/update-wp-keys \
        2>/dev/null || true
    
    echo -e "${GREEN}✅ Backup completed: $(du -h "$backup_file" | cut -f1)${NC}"
    echo "$backup_file" > "$PKG_STATE_DIR/latest-backup"
}

restore_configuration() {
    local backup_file="$1"
    
    if [ -z "$backup_file" ]; then
        if [ -f "$PKG_STATE_DIR/latest-backup" ]; then
            backup_file=$(cat "$PKG_STATE_DIR/latest-backup")
        else
            echo -e "${RED}❌ No backup file specified${NC}"
            return 1
        fi
    fi
    
    if [ ! -f "$backup_file" ]; then
        echo -e "${RED}❌ Backup file not found: $backup_file${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}🔄 Restoring from backup: $backup_file${NC}"
    
    # Stop services
    systemctl stop autoheal 2>/dev/null
    systemctl stop nginx 2>/dev/null
    
    # Restore
    tar -xzf "$backup_file" -C /
    
    # Restart services
    systemctl daemon-reload
    systemctl start nginx 2>/dev/null
    systemctl start autoheal 2>/dev/null
    
    echo -e "${GREEN}✅ Configuration restored${NC}"
}

# Initialize on source
init_package_system