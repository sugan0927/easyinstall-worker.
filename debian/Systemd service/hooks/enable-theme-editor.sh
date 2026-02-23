#!/bin/bash
# Enable Theme Editor Hook for EasyInstall
# This hook ensures WordPress theme/plugin editor is enabled
# Location: /usr/share/easyinstall/hooks/enable-theme-editor.sh

set -e

# ============================================
# Configuration
# ============================================
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

WP_MAIN_PATH="/var/www/html/wordpress"
WP_SITES_PATH="/var/www/sites"
CONFIG_FILE="/etc/easyinstall/easyinstall.conf"
LOG_FILE="/var/log/easyinstall/theme-editor.log"

# ============================================
# Logging function
# ============================================
log() {
    echo -e "${GREEN}[THEME-EDITOR]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[THEME-EDITOR WARNING]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" >> "$LOG_FILE"
}

error() {
    echo -e "${RED}[THEME-EDITOR ERROR]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$LOG_FILE"
}

# ============================================
# Create log directory if not exists
# ============================================
mkdir -p /var/log/easyinstall

# ============================================
# Load configuration
# ============================================
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    log "✅ Loaded configuration from $CONFIG_FILE"
else
    warn "⚠️ Configuration file not found, using defaults"
    ENABLE_THEME_EDITOR="true"
fi

# ============================================
# Check if theme editor should be enabled
# ============================================
if [ "$ENABLE_THEME_EDITOR" != "true" ]; then
    log "ℹ️ Theme editor is disabled in configuration, skipping"
    exit 0
fi

# ============================================
# Function to enable editor in wp-config.php
# ============================================
enable_editor_in_wpconfig() {
    local wp_config="$1"
    local site_name="${2:-main}"
    
    if [ ! -f "$wp_config" ]; then
        warn "⚠️ wp-config.php not found for $site_name at: $wp_config"
        return 1
    fi
    
    log "📝 Processing WordPress config for $site_name..."
    
    # Create backup
    cp "$wp_config" "$wp_config.backup.$(date +%Y%m%d-%H%M%S)"
    
    # Check if DISALLOW_FILE_EDIT is already defined
    if grep -q "DISALLOW_FILE_EDIT" "$wp_config"; then
        # Check if it's set to true
        if grep -q "DISALLOW_FILE_EDIT.*true" "$wp_config" || grep -q "DISALLOW_FILE_EDIT.*TRUE" "$wp_config"; then
            # Change to false
            sed -i 's/define.*DISALLOW_FILE_EDIT.*true.*/define("DISALLOW_FILE_EDIT", false);/g' "$wp_config"
            sed -i 's/define.*DISALLOW_FILE_EDIT.*TRUE.*/define("DISALLOW_FILE_EDIT", false);/g' "$wp_config"
            log "  ✅ Changed DISALLOW_FILE_EDIT from true to false for $site_name"
        else
            # Already false
            log "  ✅ DISALLOW_FILE_EDIT already set to false for $site_name"
        fi
    else
        # Add the constant before the "That's all" line
        if grep -q ".*That's all.*" "$wp_config"; then
            sed -i "/.*That's all.*/i define('DISALLOW_FILE_EDIT', false);" "$wp_config"
            log "  ✅ Added DISALLOW_FILE_EDIT = false for $site_name"
        else
            # Add at the end of file
            echo "" >> "$wp_config"
            echo "/** Enable Theme/Plugin Editor */" >> "$wp_config"
            echo "define('DISALLOW_FILE_EDIT', false);" >> "$wp_config"
            log "  ✅ Added DISALLOW_FILE_EDIT = false at end of file for $site_name"
        fi
    fi
    
    # Verify the change
    if grep -q "DISALLOW_FILE_EDIT.*false" "$wp_config"; then
        log "  ✅ Verification passed for $site_name"
        return 0
    else
        error "  ❌ Verification failed for $site_name"
        return 1
    fi
}

# ============================================
# Function to enable editor in wp-config.php for multisite
# ============================================
enable_editor_in_multisite() {
    local site_dir="$1"
    local wp_config="$site_dir/public/wp-config.php"
    
    if [ -f "$wp_config" ]; then
        enable_editor_in_wpconfig "$wp_config" "$(basename "$site_dir")"
    else
        # Check if WordPress is installed but config not created yet
        if [ -f "$site_dir/public/wp-load.php" ]; then
            warn "⚠️ WordPress installed but wp-config.php not found for $(basename "$site_dir")"
            warn "   Editor will be enabled when site is configured"
        fi
    fi
}

# ============================================
# Main execution
# ============================================
log "🚀 Starting Theme Editor Enabler Hook"
log "========================================"

# Track success/failure
SUCCESS_COUNT=0
FAILURE_COUNT=0

# ============================================
# Process main WordPress installation
# ============================================
if [ -d "$WP_MAIN_PATH" ]; then
    log "📁 Checking main WordPress installation at $WP_MAIN_PATH"
    if enable_editor_in_wpconfig "$WP_MAIN_PATH/wp-config.php" "main"; then
        ((SUCCESS_COUNT++))
    else
        ((FAILURE_COUNT++))
    fi
else
    log "ℹ️ Main WordPress not installed yet (will be enabled when installed)"
fi

# ============================================
# Process multi-site installations
# ============================================
if [ -d "$WP_SITES_PATH" ]; then
    log "📁 Checking multi-site installations in $WP_SITES_PATH"
    
    # Loop through all sites
    for site_dir in "$WP_SITES_PATH"/*; do
        if [ -d "$site_dir" ]; then
            enable_editor_in_multisite "$site_dir" && ((SUCCESS_COUNT++)) || ((FAILURE_COUNT++))
        fi
    done
else
    log "ℹ️ No multi-site installations found"
fi

# ============================================
# Ensure future WordPress installations have editor enabled
# ============================================
log "🔧 Configuring future WordPress installations..."

# Create WordPress installer wrapper if needed
INSTALLER_WRAPPER="/usr/local/bin/install-wordpress"
if [ -f "$INSTALLER_WRAPPER" ]; then
    # Backup original
    cp "$INSTALLER_WRAPPER" "$INSTALLER_WRAPPER.backup"
    
    # Ensure the installer creates wp-config.php with editor enabled
    if ! grep -q "DISALLOW_FILE_EDIT" "$INSTALLER_WRAPPER"; then
        # Add editor enable to the installer
        sed -i '/cat >> wp-config/i cat >> wp-config.php <<'"'"'EOL_WP_CONFIG'"'"''\\n\\n/** Enable Theme Editor */\\ndefine("DISALLOW_FILE_EDIT", false);\\nEOL_WP_CONFIG' "$INSTALLER_WRAPPER"
        log "  ✅ Updated WordPress installer to enable editor by default"
    fi
fi

# Update easy-site command for multisite
EASY_SITE="/usr/local/bin/easy-site"
if [ -f "$EASY_SITE" ]; then
    if ! grep -q "DISALLOW_FILE_EDIT" "$EASY_SITE"; then
        # Add editor enable to easy-site create command
        sed -i '/cat >> wp-config/i cat >> wp-config.php <<'"'"'EOL_WP_CONFIG'"'"''\\n\\n/** Enable Theme Editor */\\ndefine("DISALLOW_FILE_EDIT", false);\\nEOL_WP_CONFIG' "$EASY_SITE"
        log "  ✅ Updated easy-site to enable editor for new sites"
    fi
fi

# ============================================
# Create a persistent marker file
# ============================================
MARKER_FILE="/etc/easyinstall/theme-editor-enabled"
date > "$MARKER_FILE"
echo "Theme editor enabled on: $(date)" >> "$MARKER_FILE"
echo "Last run by: $(whoami)" >> "$MARKER_FILE"
chmod 644 "$MARKER_FILE"

# ============================================
# Summary
# ============================================
log "========================================"
log "📊 Theme Editor Enabler Hook Summary"
log "   ✅ Successfully processed: $SUCCESS_COUNT sites"
if [ $FAILURE_COUNT -gt 0 ]; then
    log "   ❌ Failed to process: $FAILURE_COUNT sites"
else
    log "   ✅ All sites processed successfully"
fi
log "========================================"

# Exit with success if at least some worked, or if no sites found
if [ $FAILURE_COUNT -gt 0 ] && [ $SUCCESS_COUNT -eq 0 ]; then
    error "❌ Failed to enable editor on any site"
    exit 1
else
    log "✅ Theme editor hook completed successfully"
    exit 0
fi