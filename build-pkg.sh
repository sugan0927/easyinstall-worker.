#!/bin/bash
# EasyInstall Package Builder

set -e

PKG_NAME="easyinstall"
PKG_VERSION="3.0"
BUILD_DIR="build"
DEB_DIR="$BUILD_DIR/debian"

echo "📦 Building EasyInstall package v$PKG_VERSION..."

# Clean build directory
rm -rf "$BUILD_DIR"
mkdir -p "$DEB_DIR"

# Create directory structure
mkdir -p "$BUILD_DIR/usr/share/easyinstall"
mkdir -p "$BUILD_DIR/usr/share/easyinstall/hooks"
mkdir -p "$BUILD_DIR/usr/local/bin"
mkdir -p "$BUILD_DIR/etc/easyinstall"
mkdir -p "$BUILD_DIR/var/lib/easyinstall"
mkdir -p "$BUILD_DIR/var/log/easyinstall"
mkdir -p "$BUILD_DIR/var/backups/easyinstall"
mkdir -p "$BUILD_DIR/lib/systemd/system"
mkdir -p "$BUILD_DIR/DEBIAN"

# Copy files
cp easyinstall.sh "$BUILD_DIR/usr/share/easyinstall/"
cp pkg-manager.sh "$BUILD_DIR/usr/share/easyinstall/"

# Copy hook scripts
cat > "$BUILD_DIR/usr/share/easyinstall/hooks/enable-theme-editor.sh" <<'EOF'
#!/bin/bash
# Hook to ensure theme editor is enabled

WP_CONFIG="/var/www/html/wordpress/wp-config.php"

if [ -f "$WP_CONFIG" ]; then
    if grep -q "DISALLOW_FILE_EDIT" "$WP_CONFIG"; then
        sed -i 's/define.*DISALLOW_FILE_EDIT.*true.*/define("DISALLOW_FILE_EDIT", false);/' "$WP_CONFIG"
        sed -i 's/define.*DISALLOW_FILE_EDIT.*TRUE.*/define("DISALLOW_FILE_EDIT", false);/' "$WP_CONFIG"
        echo "✅ Theme editor enabled in existing WordPress installation"
    else
        # Add before the "That's all" line
        sed -i "/.*That's all.*/i define('DISALLOW_FILE_EDIT', false);" "$WP_CONFIG"
        echo "✅ Added theme editor enable to WordPress config"
    fi
fi
EOF
chmod +x "$BUILD_DIR/usr/share/easyinstall/hooks/enable-theme-editor.sh"

cat > "$BUILD_DIR/usr/share/easyinstall/hooks/post-install.sh" <<'EOF'
#!/bin/bash
# Post-installation hook

echo "🔧 Running post-installation tasks..."

# Ensure theme editor is enabled for any existing sites
if [ -d "/var/www/sites" ]; then
    for site in /var/www/sites/*; do
        if [ -f "$site/public/wp-config.php" ]; then
            if grep -q "DISALLOW_FILE_EDIT" "$site/public/wp-config.php"; then
                sed -i 's/define.*DISALLOW_FILE_EDIT.*true.*/define("DISALLOW_FILE_EDIT", false);/' "$site/public/wp-config.php"
                sed -i 's/define.*DISALLOW_FILE_EDIT.*TRUE.*/define("DISALLOW_FILE_EDIT", false);/' "$site/public/wp-config.php"
                echo "  ✅ Enabled editor for site: $(basename $site)"
            fi
        fi
    done
fi

# Create symbolic links
ln -sf /usr/share/easyinstall/easyinstall.sh /usr/local/bin/easyinstall
chmod +x /usr/local/bin/easyinstall

echo "✅ Post-installation complete"
EOF
chmod +x "$BUILD_DIR/usr/share/easyinstall/hooks/post-install.sh"

# Create systemd service file
cat > "$BUILD_DIR/lib/systemd/system/autoheal.service" <<EOF
[Unit]
Description=EasyInstall Auto-Healing Service
After=network.target nginx.service mariadb.service redis-server.service
Wants=nginx.service mariadb.service redis-server.service

[Service]
Type=simple
ExecStart=/usr/local/bin/autoheal
Restart=always
RestartSec=10
User=root
Group=root
Environment=EASYINSTALL_PKG_MODE=true

[Install]
WantedBy=multi-user.target
EOF

# Create default config
cat > "$BUILD_DIR/etc/easyinstall/config" <<EOF
# EasyInstall Configuration
# Generated during package build

# Installation paths
INSTALL_PATH="/usr/local/easyinstall"
BACKUP_PATH="/var/backups/easyinstall"

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

# Create control file
cat > "$BUILD_DIR/DEBIAN/control" <<EOF
Package: easyinstall
Version: $PKG_VERSION
Section: admin
Priority: optional
Architecture: all
Depends: bash (>= 4.0), curl, wget, gnupg2, ca-certificates, lsb-release, apt-transport-https, bc, jq, python3-pip, systemd
Recommends: nginx, mariadb-server, redis-server, memcached, fail2ban, certbot, netdata, glances, rclone, postfix
Maintainer: Sugando Drai <support@easyinstall.local>
Description: EasyInstall Enterprise Stack v3.0
 Ultra-Optimized 512MB VPS → Enterprise Grade Hosting Engine
 Complete with Advanced CDN & Monitoring Features
 .
 Features:
  * Auto-tuning for low-memory VPS (512MB optimized)
  * Nginx with FastCGI cache
  * PHP-FPM with OPcache
  * MariaDB with performance tuning
  * Redis + Memcached
  * ModSecurity WAF
  * Fail2ban with WordPress rules
  * Auto-healing service
  * Netdata + Glances monitoring
  * Automated backups
  * XML-RPC management
  * Multi-site panel support
  * Theme/Plugin Editor ENABLED by default
  * CDN integration (Cloudflare)
  * Remote storage (Google Drive, S3, etc.)
EOF

# Create postinst script
cat > "$BUILD_DIR/DEBIAN/postinst" <<'EOF'
#!/bin/bash

set -e

case "$1" in
    configure)
        echo "📦 Configuring EasyInstall package..."
        
        # Create symlinks
        ln -sf /usr/share/easyinstall/easyinstall.sh /usr/local/bin/easyinstall
        chmod +x /usr/local/bin/easyinstall
        
        # Set permissions
        chmod 755 /usr/share/easyinstall/easyinstall.sh
        chmod 755 /usr/share/easyinstall/pkg-manager.sh
        chmod -R 755 /usr/share/easyinstall/hooks
        
        # Run post-install hook
        if [ -f "/usr/share/easyinstall/hooks/post-install.sh" ]; then
            bash /usr/share/easyinstall/hooks/post-install.sh
        fi
        
        # Enable and start services if they exist
        if [ -f /lib/systemd/system/autoheal.service ]; then
            systemctl daemon-reload
            systemctl enable autoheal 2>/dev/null || true
            systemctl start autoheal 2>/dev/null || true
        fi
        
        echo "✅ EasyInstall package configured"
        echo ""
        echo "Run 'easyinstall help' to get started"
        echo "Run 'easyinstall --pkg-status' for package status"
        echo ""
        echo "📝 Note: WordPress theme/plugin editor is ENABLED by default"
        ;;
        
    abort-upgrade|abort-remove|abort-deconfigure)
        exit 0
        ;;
        
    *)
        echo "postinst called with unknown argument '$1'" >&2
        exit 1
        ;;
esac

exit 0
EOF

# Create prerm script
cat > "$BUILD_DIR/DEBIAN/prerm" <<'EOF'
#!/bin/bash

set -e

case "$1" in
    remove|upgrade|deconfigure)
        echo "🗑️  Preparing to remove EasyInstall..."
        
        # Backup configuration
        if [ -f /usr/share/easyinstall/pkg-manager.sh ]; then
            source /usr/share/easyinstall/pkg-manager.sh
            backup_configuration
        fi
        
        # Stop services
        systemctl stop autoheal 2>/dev/null || true
        systemctl disable autoheal 2>/dev/null || true
        
        # Remove symlinks (but keep files for upgrade)
        if [ "$1" = "remove" ]; then
            rm -f /usr/local/bin/easyinstall
        fi
        ;;
        
    failed-upgrade)
        ;;
        
    *)
        echo "prerm called with unknown argument '$1'" >&2
        exit 1
        ;;
esac

exit 0
EOF

# Make scripts executable
chmod 755 "$BUILD_DIR/DEBIAN/postinst"
chmod 755 "$BUILD_DIR/DEBIAN/prerm"

# Create md5sums
cd "$BUILD_DIR"
find . -type f ! -path "./DEBIAN/*" -exec md5sum {} \; > DEBIAN/md5sums
cd ..

# Build package
cd "$BUILD_DIR"
dpkg-deb --build . "../${PKG_NAME}_${PKG_VERSION}_all.deb"
cd ..

echo "✅ Package built: ${PKG_NAME}_${PKG_VERSION}_all.deb"
echo ""
echo "Install with: sudo dpkg -i ${PKG_NAME}_${PKG_VERSION}_all.deb"
echo "Then run: sudo apt-get install -f"
echo ""
echo "Package contents:"
dpkg -c "${PKG_NAME}_${PKG_VERSION}_all.deb" | head -20
echo "..."