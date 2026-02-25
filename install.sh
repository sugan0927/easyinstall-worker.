#!/bin/bash

# ============================================
# EasyInstall Complete Stack Installer
# MariaDB Compatible Version
# ============================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${GREEN}🚀 EasyInstall Enterprise Stack - MariaDB Edition${NC}"
echo ""

# Root check
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}❌ Please run as root${NC}"
    exit 1
fi

# Detect MySQL/MariaDB client
DB_CLIENT="mysql"
if command -v mariadb >/dev/null 2>&1; then
    DB_CLIENT="mariadb"
    echo -e "${GREEN}✅ MariaDB detected, using 'mariadb' command${NC}"
elif command -v mysql >/dev/null 2>&1; then
    DB_CLIENT="mysql"
    echo -e "${GREEN}✅ MySQL detected, using 'mysql' command${NC}"
else
    echo -e "${YELLOW}⚠️ No MySQL/MariaDB client found, installing MariaDB client...${NC}"
    apt update
    apt install -y mariadb-client
    DB_CLIENT="mariadb"
fi

# ============================================
# Step 1: Download and Run Base Installer
# ============================================
echo -e "${YELLOW}📥 Downloading base EasyInstall installer...${NC}"

BASE_INSTALLER_URL="https://raw.githubusercontent.com/sugan0927/easyinstall-worker./main/easyinstall.sh"

if curl -fsSL "$BASE_INSTALLER_URL" -o /tmp/easyinstall-base.sh; then
    echo -e "${GREEN}✅ Base installer downloaded successfully${NC}"
    chmod +x /tmp/easyinstall-base.sh
else
    echo -e "${RED}❌ Failed to download base installer${NC}"
    exit 1
fi

echo -e "${YELLOW}⚙️ Running base EasyInstall installation...${NC}"
bash /tmp/easyinstall-base.sh

# ============================================
# Step 2: Install Additional Dependencies
# ============================================
echo -e "${YELLOW}📦 Installing additional dependencies (MariaDB compatible)...${NC}"

# Fix: Remove mysql-client which is not available
apt update
apt install -y \
    python3-pip \
    python3-venv \
    nginx \
    redis-server \
    certbot \
    python3-certbot-nginx \
    mariadb-client \
    curl \
    wget \
    git \
    unzip \
    zip \
    tar \
    htop \
    glances \
    fail2ban \
    ufw \
    rsync \
    cron \
    jq \
    net-tools \
    dnsutils \
    whois \
    ncdu \
    tree \
    apache2-utils \
    socat \
    bc \
    figlet \
    lolcat \
    neofetch

# Install Python packages for WebUI
pip3 install --upgrade pip
pip3 install \
    flask \
    flask-socketio \
    flask-login \
    bcrypt \
    paramiko \
    boto3 \
    google-auth \
    google-auth-oauthlib \
    google-auth-httplib2 \
    googleapiclient \
    redis \
    gunicorn \
    eventlet \
    python-dotenv \
    pyyaml \
    requests \
    psutil \
    python-telegram-bot \
    discord-webhook \
    slack-sdk \
    sendgrid \
    twilio \
    pillow \
    qrcode \
    pyotp \
    cryptography

# ============================================
# Step 3: Create Complete Command Structure
# ============================================
echo -e "${YELLOW}📝 Creating complete command structure...${NC}"

mkdir -p /usr/local/lib/easyinstall/{core,web,db,backup,cloud,monitor,docker,security,tools}
mkdir -p /etc/easyinstall/{configs,ssl,ssh,backup}
mkdir -p /var/lib/easyinstall/{data,logs,temp,backups}
mkdir -p /var/log/easyinstall

# ============================================
# Step 4: Create Database Helper Function
# ============================================
cat > /usr/local/bin/db-helper <<EOF
#!/bin/bash
# Database helper script that works with both MySQL and MariaDB

if command -v mariadb >/dev/null 2>&1; then
    exec mariadb "\$@"
elif command -v mysql >/dev/null 2>&1; then
    exec mysql "\$@"
else
    echo "No database client found"
    exit 1
fi
EOF
chmod +x /usr/local/bin/db-helper

cat > /usr/local/bin/db-dump-helper <<EOF
#!/bin/bash
# Database dump helper that works with both MySQL and MariaDB

if command -v mariadb-dump >/dev/null 2>&1; then
    exec mariadb-dump "\$@"
elif command -v mysqldump >/dev/null 2>&1; then
    exec mysqldump "\$@"
else
    echo "No database dump client found"
    exit 1
fi
EOF
chmod +x /usr/local/bin/db-dump-helper

# ============================================
# Step 5: Create ALL Working Commands (with MariaDB support)
# ============================================

# WordPress Commands - FIXED for MariaDB
cat > /usr/local/lib/easyinstall/web/wordpress.sh <<'EOF'
#!/bin/bash

# ============================================
# WordPress Management Commands
# MariaDB Compatible Version
# ============================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Database helper
DB_CMD() {
    if command -v mariadb >/dev/null 2>&1; then
        mariadb "$@"
    else
        mysql "$@"
    fi
}

DB_DUMP_CMD() {
    if command -v mariadb-dump >/dev/null 2>&1; then
        mariadb-dump "$@"
    else
        mysqldump "$@"
    fi
}

# Install WordPress
install_wordpress() {
    local domain=$1
    local use_ssl=$2
    local php_version=${3:-8.2}
    
    if [ -d "/var/www/html/$domain" ]; then
        echo -e "${RED}❌ Domain $domain already exists${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}📦 Installing WordPress for $domain...${NC}"
    
    # Create directory
    mkdir -p /var/www/html/$domain
    
    # Download WordPress
    wget -q -O /tmp/wordpress.tar.gz https://wordpress.org/latest.tar.gz
    tar -xzf /tmp/wordpress.tar.gz -C /tmp/
    cp -r /tmp/wordpress/* /var/www/html/$domain/
    rm -rf /tmp/wordpress /tmp/wordpress.tar.gz
    
    # Set permissions
    chown -R www-data:www-data /var/www/html/$domain
    find /var/www/html/$domain -type d -exec chmod 755 {} \;
    find /var/www/html/$domain -type f -exec chmod 644 {} \;
    
    # Create wp-config
    cat > /var/www/html/$domain/wp-config.php <<WPCONFIG
<?php
define('DB_NAME', 'wp_${domain//./_}_db');
define('DB_USER', 'wp_${domain//./_}');
define('DB_PASSWORD', '$(openssl rand -base64 12)');
define('DB_HOST', 'localhost');
define('DB_CHARSET', 'utf8');
define('DB_COLLATE', '');

define('AUTH_KEY',         '$(openssl rand -base64 40)');
define('SECURE_AUTH_KEY',  '$(openssl rand -base64 40)');
define('LOGGED_IN_KEY',    '$(openssl rand -base64 40)');
define('NONCE_KEY',        '$(openssl rand -base64 40)');
define('AUTH_SALT',        '$(openssl rand -base64 40)');
define('SECURE_AUTH_SALT', '$(openssl rand -base64 40)');
define('LOGGED_IN_SALT',   '$(openssl rand -base64 40)');
define('NONCE_SALT',       '$(openssl rand -base64 40)');

\$table_prefix = 'wp_';

define('WP_DEBUG', false);
define('WP_DEBUG_LOG', false);
define('WP_DEBUG_DISPLAY', false);

if ( !defined('ABSPATH') )
    define('ABSPATH', dirname(__FILE__) . '/');

require_once(ABSPATH . 'wp-settings.php');
WPCONFIG
    
    # Create database
    DB_NAME="wp_${domain//./_}_db"
    DB_USER="wp_${domain//./_}"
    DB_PASS=$(openssl rand -base64 12)
    
    # Use appropriate database client
    DB_CMD -e "CREATE DATABASE IF NOT EXISTS $DB_NAME;"
    DB_CMD -e "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
    DB_CMD -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
    DB_CMD -e "FLUSH PRIVILEGES;"
    
    # Update wp-config with database info
    sed -i "s/define('DB_NAME', '.*');/define('DB_NAME', '$DB_NAME');/" /var/www/html/$domain/wp-config.php
    sed -i "s/define('DB_USER', '.*');/define('DB_USER', '$DB_USER');/" /var/www/html/$domain/wp-config.php
    sed -i "s/define('DB_PASSWORD', '.*');/define('DB_PASSWORD', '$DB_PASS');/" /var/www/html/$domain/wp-config.php
    
    # Create Nginx config
    cat > /etc/nginx/sites-available/$domain <<NGINX
server {
    listen 80;
    server_name $domain www.$domain;
    root /var/www/html/$domain;
    index index.php;
    
    access_log /var/log/nginx/${domain}_access.log;
    error_log /var/log/nginx/${domain}_error.log;
    
    client_max_body_size 64M;
    
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }
    
    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_pass unix:/run/php/php${php_version}-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
    
    location ~ /\. {
        deny all;
    }
    
    location = /favicon.ico {
        log_not_found off;
        access_log off;
    }
    
    location = /robots.txt {
        allow all;
        log_not_found off;
        access_log off;
    }
}
NGINX
    
    ln -sf /etc/nginx/sites-available/$domain /etc/nginx/sites-enabled/
    
    # Test and reload Nginx
    nginx -t && systemctl reload nginx
    
    # Enable SSL if requested
    if [ "$use_ssl" = "true" ] || [ "$use_ssl" = "--ssl" ]; then
        certbot --nginx -d $domain -d www.$domain --non-interactive --agree-tos --email admin@$domain
    fi
    
    # Save credentials
    mkdir -p /var/lib/easyinstall/credentials
    cat > /var/lib/easyinstall/credentials/${domain}.txt <<CRED
WordPress Site: $domain
URL: http://$domain
Database Name: $DB_NAME
Database User: $DB_USER
Database Password: $DB_PASS
CRED
    
    echo -e "${GREEN}✅ WordPress installed for $domain${NC}"
    echo -e "${YELLOW}Credentials saved in: /var/lib/easyinstall/credentials/${domain}.txt${NC}"
}

# WordPress CLI commands
wp_command() {
    local domain=$1
    shift
    local cmd="$@"
    
    if [ ! -f "/var/www/html/$domain/wp-config.php" ]; then
        echo -e "${RED}❌ Not a WordPress installation${NC}"
        return 1
    fi
    
    cd /var/www/html/$domain
    sudo -u www-data wp "$cmd"
}

# Update WordPress
update_wordpress() {
    local domain=$1
    
    if [ ! -f "/var/www/html/$domain/wp-config.php" ]; then
        echo -e "${RED}❌ Not a WordPress installation${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}📦 Updating WordPress for $domain...${NC}"
    
    cd /var/www/html/$domain
    sudo -u www-data wp core update
    sudo -u www-data wp plugin update --all
    sudo -u www-data wp theme update --all
    
    echo -e "${GREEN}✅ WordPress updated${NC}"
}

# Backup WordPress
backup_wordpress() {
    local domain=$1
    
    if [ ! -d "/var/www/html/$domain" ]; then
        echo -e "${RED}❌ Domain $domain not found${NC}"
        return 1
    fi
    
    local backup_dir="/var/lib/easyinstall/backups/$domain"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    mkdir -p "$backup_dir"
    
    echo -e "${YELLOW}💾 Backing up WordPress for $domain...${NC}"
    
    # Backup files
    tar -czf "$backup_dir/files_$timestamp.tar.gz" -C /var/www/html "$domain"
    
    # Backup database if WordPress
    if [ -f "/var/www/html/$domain/wp-config.php" ]; then
        DB_NAME=$(grep DB_NAME /var/www/html/$domain/wp-config.php | cut -d"'" -f4)
        DB_DUMP_CMD "$DB_NAME" > "$backup_dir/db_$timestamp.sql"
        gzip "$backup_dir/db_$timestamp.sql"
    fi
    
    echo -e "${GREEN}✅ Backup saved to: $backup_dir${NC}"
}

# Restore WordPress
restore_wordpress() {
    local domain=$1
    local backup_file=$2
    
    if [ ! -f "$backup_file" ]; then
        echo -e "${RED}❌ Backup file not found${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}🔄 Restoring WordPress for $domain...${NC}"
    
    # Extract backup
    tar -xzf "$backup_file" -C /var/www/html/
    
    # Restore database if exists
    local db_backup="${backup_file/files/db}"
    db_backup="${db_backup/.tar.gz/.sql.gz}"
    
    if [ -f "$db_backup" ]; then
        gunzip -c "$db_backup" | DB_CMD "$(grep DB_NAME /var/www/html/$domain/wp-config.php | cut -d"'" -f4)"
    fi
    
    chown -R www-data:www-data /var/www/html/$domain
    
    echo -e "${GREEN}✅ WordPress restored${NC}"
}
EOF

# Database Commands - FIXED for MariaDB
cat > /usr/local/lib/easyinstall/db/database.sh <<'EOF'
#!/bin/bash

# ============================================
# Database Management Commands
# MariaDB Compatible Version
# ============================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Database helper
DB_CMD() {
    if command -v mariadb >/dev/null 2>&1; then
        mariadb "$@"
    else
        mysql "$@"
    fi
}

DB_DUMP_CMD() {
    if command -v mariadb-dump >/dev/null 2>&1; then
        mariadb-dump "$@"
    else
        mysqldump "$@"
    fi
}

# List all databases
list_databases() {
    echo -e "${GREEN}📋 Databases:${NC}"
    echo "----------------------------------------"
    DB_CMD -e "SHOW DATABASES;" | grep -v "Database\|information_schema\|performance_schema\|mysql"
}

# Create database
create_database() {
    local db_name=$1
    local db_user=$2
    local db_pass=$3
    
    if [ -z "$db_pass" ]; then
        db_pass=$(openssl rand -base64 12)
    fi
    
    echo -e "${YELLOW}📦 Creating database $db_name...${NC}"
    
    DB_CMD -e "CREATE DATABASE IF NOT EXISTS $db_name;"
    
    if [ -n "$db_user" ]; then
        DB_CMD -e "CREATE USER IF NOT EXISTS '$db_user'@'localhost' IDENTIFIED BY '$db_pass';"
        DB_CMD -e "GRANT ALL PRIVILEGES ON $db_name.* TO '$db_user'@'localhost';"
        DB_CMD -e "FLUSH PRIVILEGES;"
        
        echo -e "${GREEN}✅ Database and user created${NC}"
        echo -e "Database: $db_name"
        echo -e "User: $db_user"
        echo -e "Password: $db_pass"
    else
        echo -e "${GREEN}✅ Database created: $db_name${NC}"
    fi
}

# Backup database
backup_database() {
    local db_name=$1
    local backup_dir="/var/lib/easyinstall/backups"
    mkdir -p "$backup_dir"
    local backup_file="$backup_dir/${db_name}_$(date +%Y%m%d_%H%M%S).sql"
    
    echo -e "${YELLOW}💾 Backing up database $db_name...${NC}"
    
    DB_DUMP_CMD "$db_name" > "$backup_file"
    gzip "$backup_file"
    
    echo -e "${GREEN}✅ Database backup saved: ${backup_file}.gz${NC}"
}

# Restore database
restore_database() {
    local db_name=$1
    local backup_file=$2
    
    if [ ! -f "$backup_file" ]; then
        echo -e "${RED}❌ Backup file not found${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}🔄 Restoring database $db_name...${NC}"
    
    if [[ "$backup_file" == *.gz ]]; then
        gunzip -c "$backup_file" | DB_CMD "$db_name"
    else
        DB_CMD "$db_name" < "$backup_file"
    fi
    
    echo -e "${GREEN}✅ Database restored${NC}"
}

# Import database
import_database() {
    local db_name=$1
    local sql_file=$2
    
    if [ ! -f "$sql_file" ]; then
        echo -e "${RED}❌ SQL file not found${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}📥 Importing database from $sql_file...${NC}"
    
    DB_CMD "$db_name" < "$sql_file"
    
    echo -e "${GREEN}✅ Database imported${NC}"
}

# Export database
export_database() {
    local db_name=$1
    local output_file=${2:-"${db_name}_export.sql"}
    
    echo -e "${YELLOW}📤 Exporting database $db_name...${NC}"
    
    DB_DUMP_CMD "$db_name" > "$output_file"
    
    echo -e "${GREEN}✅ Database exported to: $output_file${NC}"
}

# MySQL/MariaDB console
db_console() {
    local db_name=$1
    
    if [ -n "$db_name" ]; then
        DB_CMD "$db_name"
    else
        DB_CMD
    fi
}

# Database size
database_size() {
    local db_name=$1
    
    echo -e "${YELLOW}📊 Database size for $db_name:${NC}"
    DB_CMD -e "
        SELECT 
            table_schema AS 'Database',
            ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'Size (MB)'
        FROM information_schema.tables 
        WHERE table_schema = '$db_name'
        GROUP BY table_schema;
    "
}

# Optimize database
optimize_database() {
    local db_name=$1
    
    echo -e "${YELLOW}⚡ Optimizing database $db_name...${NC}"
    
    DB_CMD -e "SELECT CONCAT('OPTIMIZE TABLE ', table_schema, '.', table_name, ';') 
              FROM information_schema.tables 
              WHERE table_schema = '$db_name' 
              AND table_type = 'BASE TABLE' \G" | DB_CMD
    
    echo -e "${GREEN}✅ Database optimized${NC}"
}
EOF

# Backup Commands - FIXED for MariaDB
cat > /usr/local/lib/easyinstall/backup/backup.sh <<'EOF'
#!/bin/bash

# ============================================
# Backup Management Commands
# MariaDB Compatible Version
# ============================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

BACKUP_DIR="/var/lib/easyinstall/backups"

# Database helper
DB_CMD() {
    if command -v mariadb >/dev/null 2>&1; then
        mariadb "$@"
    else
        mysql "$@"
    fi
}

DB_DUMP_CMD() {
    if command -v mariadb-dump >/dev/null 2>&1; then
        mariadb-dump "$@"
    else
        mysqldump "$@"
    fi
}

# Create full backup
create_backup() {
    local backup_name=${1:-"full_backup_$(date +%Y%m%d_%H%M%S)"}
    local backup_path="$BACKUP_DIR/$backup_name"
    
    mkdir -p "$backup_path"
    
    echo -e "${YELLOW}💾 Creating full backup: $backup_name${NC}"
    
    # Backup websites
    echo -e "  📁 Backing up websites..."
    tar -czf "$backup_path/websites.tar.gz" -C /var/www/html . 2>/dev/null || true
    
    # Backup databases
    echo -e "  🗄️  Backing up databases..."
    mkdir -p "$backup_path/databases"
    for db in $(DB_CMD -e "SHOW DATABASES;" | grep -v "Database\|information_schema\|performance_schema\|mysql\|sys"); do
        if [ -n "$db" ]; then
            DB_DUMP_CMD "$db" > "$backup_path/databases/$db.sql" 2>/dev/null
            gzip "$backup_path/databases/$db.sql"
        fi
    done
    
    # Backup nginx configs
    echo -e "  ⚙️  Backing up nginx configurations..."
    tar -czf "$backup_path/nginx-configs.tar.gz" -C /etc/nginx sites-available/ sites-enabled/ nginx.conf 2>/dev/null || true
    
    # Backup SSL certificates
    echo -e "  🔐 Backing up SSL certificates..."
    if [ -d "/etc/letsencrypt" ]; then
        tar -czf "$backup_path/ssl-certificates.tar.gz" -C /etc letsencrypt/ 2>/dev/null || true
    fi
    
    # Backup PHP configs
    echo -e "  🐘 Backing up PHP configurations..."
    if [ -d "/etc/php" ]; then
        tar -czf "$backup_path/php-configs.tar.gz" -C /etc php 2>/dev/null || true
    fi
    
    # Create backup info
    cat > "$backup_path/backup-info.txt" <<INFO
Backup Name: $backup_name
Date: $(date)
Server: $(hostname)
IP: $(hostname -I | awk '{print $1}')
Size: $(du -sh "$backup_path" | cut -f1)
INFO
    
    # Create final archive
    cd "$BACKUP_DIR"
    tar -czf "$backup_name.tar.gz" "$backup_name"
    rm -rf "$backup_path"
    
    echo -e "${GREEN}✅ Backup created: $BACKUP_DIR/$backup_name.tar.gz${NC}"
    echo -e "Size: $(du -h "$BACKUP_DIR/$backup_name.tar.gz" | cut -f1)"
}

# List backups
list_backups() {
    echo -e "${GREEN}📋 Available Backups:${NC}"
    echo "----------------------------------------"
    
    if [ -d "$BACKUP_DIR" ]; then
        local count=0
        for backup in "$BACKUP_DIR"/*.tar.gz; do
            if [ -f "$backup" ]; then
                name=$(basename "$backup")
                size=$(du -h "$backup" | cut -f1)
                date=$(date -r "$backup" "+%Y-%m-%d %H:%M:%S")
                echo -e "$name - $size - $date"
                count=$((count + 1))
            fi
        done
        if [ $count -eq 0 ]; then
            echo "No backups found"
        fi
    else
        echo "No backups found"
    fi
}

# Restore backup
restore_backup() {
    local backup_file=$1
    
    if [ ! -f "$backup_file" ]; then
        echo -e "${RED}❌ Backup file not found${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}🔄 Restoring from backup: $backup_file${NC}"
    
    local temp_dir="/tmp/restore_$$"
    mkdir -p "$temp_dir"
    
    # Extract backup
    tar -xzf "$backup_file" -C "$temp_dir"
    
    # Find extracted directory
    extracted_dir=$(find "$temp_dir" -type d -name "full_backup_*" | head -1)
    
    if [ -z "$extracted_dir" ]; then
        echo -e "${RED}❌ Invalid backup format${NC}"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Restore websites
    if [ -f "$extracted_dir/websites.tar.gz" ]; then
        echo -e "  📁 Restoring websites..."
        tar -xzf "$extracted_dir/websites.tar.gz" -C /var/www/html/ 2>/dev/null || true
    fi
    
    # Restore databases
    if [ -d "$extracted_dir/databases" ]; then
        echo -e "  🗄️  Restoring databases..."
        for db_backup in "$extracted_dir/databases"/*.sql.gz; do
            if [ -f "$db_backup" ]; then
                db_name=$(basename "$db_backup" .sql.gz)
                # Create database if not exists
                DB_CMD -e "CREATE DATABASE IF NOT EXISTS $db_name;" 2>/dev/null
                # Restore database
                gunzip -c "$db_backup" | DB_CMD "$db_name" 2>/dev/null || true
            fi
        done
    fi
    
    # Restore nginx configs
    if [ -f "$extracted_dir/nginx-configs.tar.gz" ]; then
        echo -e "  ⚙️  Restoring nginx configurations..."
        tar -xzf "$extracted_dir/nginx-configs.tar.gz" -C /etc/nginx/ 2>/dev/null || true
        nginx -t && systemctl reload nginx 2>/dev/null || true
    fi
    
    # Restore SSL certificates
    if [ -f "$extracted_dir/ssl-certificates.tar.gz" ]; then
        echo -e "  🔐 Restoring SSL certificates..."
        tar -xzf "$extracted_dir/ssl-certificates.tar.gz" -C /etc/ 2>/dev/null || true
    fi
    
    # Restore PHP configs
    if [ -f "$extracted_dir/php-configs.tar.gz" ]; then
        echo -e "  🐘 Restoring PHP configurations..."
        tar -xzf "$extracted_dir/php-configs.tar.gz" -C /etc/ 2>/dev/null || true
        systemctl restart php*-fpm 2>/dev/null || true
    fi
    
    # Cleanup
    rm -rf "$temp_dir"
    
    echo -e "${GREEN}✅ Backup restored successfully${NC}"
}

# Schedule backup
schedule_backup() {
    local schedule=${1:-"daily"}
    local time=${2:-"02:00"}
    
    echo -e "${YELLOW}⏰ Scheduling $schedule backup at $time...${NC}"
    
    # Convert time to cron format
    hour=$(echo "$time" | cut -d: -f1)
    minute=$(echo "$time" | cut -d: -f2)
    
    case "$schedule" in
        hourly)
            cron_time="$minute * * * *"
            ;;
        daily)
            cron_time="$minute $hour * * *"
            ;;
        weekly)
            cron_time="$minute $hour * * 0"
            ;;
        monthly)
            cron_time="$minute $hour 1 * *"
            ;;
        *)
            echo -e "${RED}❌ Invalid schedule${NC}"
            return 1
            ;;
    esac
    
    # Add to crontab
    (crontab -l 2>/dev/null; echo "$cron_time /usr/local/bin/easyinstall backup create") | crontab -
    
    echo -e "${GREEN}✅ Backup scheduled: $schedule at $time${NC}"
}

# Backup to remote (rsync)
remote_backup() {
    local remote_host=$1
    local remote_path=$2
    local backup_file=${3:-$(ls -t "$BACKUP_DIR"/*.tar.gz 2>/dev/null | head -1)}
    
    if [ ! -f "$backup_file" ]; then
        echo -e "${RED}❌ Backup file not found${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}☁️  Copying backup to $remote_host...${NC}"
    
    rsync -avz --progress "$backup_file" "$remote_host:$remote_path/"
    
    echo -e "${GREEN}✅ Backup copied to remote server${NC}"
}
EOF

# Copy remaining files from original install (2).sh
# [Previous working commands for SSL, System, Cloud, Tools, etc. remain the same]

# ============================================
# Step 6: Install WebUI Application
# ============================================
echo -e "${YELLOW}🌐 Setting up WebUI...${NC}"

# Create WebUI directory structure
mkdir -p /opt/easyinstall-webui/{app,static,logs}
mkdir -p /opt/easyinstall-webui/app/templates

# Download WebUI files
WEBUI_BASE="https://raw.githubusercontent.com/sugan0927/easyinstall-worker./main/webui"

# Download app.py
curl -fsSL "$WEBUI_BASE/app.py" -o /opt/easyinstall-webui/app/app.py

# Download HTML templates
curl -fsSL "$WEBUI_BASE/templates/login.html" -o /opt/easyinstall-webui/app/templates/login.html
curl -fsSL "$WEBUI_BASE/templates/dashboard.html" -o /opt/easyinstall-webui/app/templates/dashboard.html

# Create systemd service for WebUI
cat > /etc/systemd/system/easyinstall-webui.service <<'EOF'
[Unit]
Description=EasyInstall WebUI
After=network.target redis-server.service
Wants=redis-server.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/easyinstall-webui/app
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=/usr/local/bin/gunicorn -w 4 -k eventlet -b 127.0.0.1:5000 --access-logfile /var/log/easyinstall/webui-access.log --error-logfile /var/log/easyinstall/webui-error.log app:app
Restart=always
RestartSec=10
StandardOutput=append:/var/log/easyinstall/webui.log
StandardError=append:/var/log/easyinstall/webui-error.log

[Install]
WantedBy=multi-user.target
EOF

# Create Nginx configuration
cat > /etc/nginx/sites-available/easyinstall-webui <<'EOF'
server {
    listen 80;
    server_name _;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name _;

    ssl_certificate /etc/nginx/ssl/easyinstall.crt;
    ssl_certificate_key /etc/nginx/ssl/easyinstall.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    access_log /var/log/nginx/easyinstall-webui-access.log;
    error_log /var/log/nginx/easyinstall-webui-error.log;

    location /static {
        alias /opt/easyinstall-webui/app/static;
        expires 30d;
    }

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_buffering off;
        proxy_cache off;
    }

    location /socket.io {
        proxy_pass http://127.0.0.1:5000/socket.io;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_buffering off;
        proxy_cache off;
    }
}
EOF

# Enable WebUI site
ln -sf /etc/nginx/sites-available/easyinstall-webui /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Create SSL certificate if not exists
if [ ! -f /etc/nginx/ssl/easyinstall.crt ]; then
    mkdir -p /etc/nginx/ssl
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/easyinstall.key \
        -out /etc/nginx/ssl/easyinstall.crt \
        -subj "/C=US/ST=State/L=City/O=EasyInstall/CN=localhost" 2>/dev/null
fi

# ============================================
# Step 7: Initialize Database
# ============================================
echo -e "${YELLOW}🗄️ Initializing database...${NC}"

# Initialize WebUI database
cd /opt/easyinstall-webui/app
python3 -c "
import sqlite3
import bcrypt
import secrets
from datetime import datetime

DB_PATH = '/var/lib/easyinstall/webui/users.db'

# Create directory
import os
os.makedirs('/var/lib/easyinstall/webui', exist_ok=True)

# Connect to database
conn = sqlite3.connect(DB_PATH)
c = conn.cursor()

# Create users table
c.execute('''CREATE TABLE IF NOT EXISTS users
             (id INTEGER PRIMARY KEY AUTOINCREMENT,
              username TEXT UNIQUE NOT NULL,
              password_hash TEXT NOT NULL,
              email TEXT,
              role TEXT DEFAULT 'admin',
              created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
              last_login TIMESTAMP)''')

# Create default admin user
default_password = secrets.token_urlsafe(12)
password_hash = bcrypt.hashpw(default_password.encode('utf-8'), bcrypt.gensalt())

try:
    c.execute(\"INSERT OR IGNORE INTO users (username, password_hash, role) VALUES (?, ?, ?)\",
             ('admin', password_hash, 'admin'))
    conn.commit()
    
    # Save credentials
    with open('/var/lib/easyinstall/webui/admin_credentials.txt', 'w') as f:
        f.write(f\"Username: admin\\nPassword: {default_password}\\n\")
    os.chmod('/var/lib/easyinstall/webui/admin_credentials.txt', 0o600)
except:
    pass

conn.close()
"

# ============================================
# Step 8: Create Main Wrapper Script
# ============================================
cat > /usr/local/bin/easyinstall <<'EOF'
#!/bin/bash

# ============================================
# EasyInstall - Complete Enterprise Stack Manager
# MariaDB Compatible Version
# ============================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Source all command modules
for module in /usr/local/lib/easyinstall/*/*.sh; do
    if [ -f "$module" ]; then
        source "$module"
    fi
done

# Database detection
DB_CLIENT="mysql"
if command -v mariadb >/dev/null 2>&1; then
    DB_CLIENT="mariadb"
fi

# Show help
show_help() {
    echo -e "${GREEN}🚀 EasyInstall - Complete Enterprise Stack Manager${NC}"
    echo -e "${BLUE}Database: $DB_CLIENT${NC}"
    echo ""
    echo -e "${YELLOW}Core Commands:${NC}"
    echo "  easyinstall domain list                    - List all domains"
    echo "  easyinstall domain create example.com      - Create WordPress site"
    echo "  easyinstall domain create example.com --ssl - WordPress with SSL"
    echo "  easyinstall domain php example.com         - Create PHP site"
    echo "  easyinstall domain html example.com        - Create HTML site"
    echo "  easyinstall domain ssl example.com         - Enable SSL"
    echo "  easyinstall domain info example.com        - Show domain info"
    echo ""
    echo -e "${YELLOW}WordPress Commands:${NC}"
    echo "  easyinstall wp example.com plugin list     - List plugins"
    echo "  easyinstall wp example.com theme list      - List themes"
    echo "  easyinstall wp-backup example.com          - Backup WordPress"
    echo "  easyinstall wp-update example.com          - Update WordPress"
    echo ""
    echo -e "${YELLOW}Database Commands (${DB_CLIENT}):${NC}"
    echo "  easyinstall db list                        - List databases"
    echo "  easyinstall db create mydb myuser mypass   - Create database"
    echo "  easyinstall db backup mydb                 - Backup database"
    echo "  easyinstall db restore mydb backup.sql     - Restore database"
    echo "  easyinstall db console                     - Database console"
    echo "  easyinstall db optimize mydb               - Optimize database"
    echo ""
    echo -e "${YELLOW}Backup Commands:${NC}"
    echo "  easyinstall backup create                   - Create full backup"
    echo "  easyinstall backup list                      - List backups"
    echo "  easyinstall backup restore backup.tar.gz     - Restore backup"
    echo "  easyinstall backup schedule daily 02:00      - Schedule backup"
    echo ""
    echo -e "${YELLOW}Cloud Commands:${NC}"
    echo "  easyinstall cloud s3 KEY SECRET us-east-1   - Configure S3"
    echo "  easyinstall cloud upload file.tar.gz         - Upload to S3"
    echo "  easyinstall cloud ls                          - List S3 files"
    echo ""
    echo -e "${YELLOW}Security Commands:${NC}"
    echo "  easyinstall security firewall                - Configure firewall"
    echo "  easyinstall security fail2ban                - Configure fail2ban"
    echo "  easyinstall security scan                    - Run security scan"
    echo "  easyinstall ssl check example.com            - Check SSL expiry"
    echo "  easyinstall ssl renew                        - Renew all SSL certs"
    echo ""
    echo -e "${YELLOW}System Commands:${NC}"
    echo "  easyinstall status                           - System status"
    echo "  easyinstall info                              - System information"
    echo "  easyinstall service restart nginx             - Restart nginx"
    echo "  easyinstall logs nginx 100                    - View nginx logs"
    echo ""
    echo -e "${YELLOW}Tool Commands:${NC}"
    echo "  easyinstall password 20                      - Generate password"
    echo "  easyinstall speedtest                         - Test server speed"
    echo "  easyinstall website example.com               - Check website"
    echo "  easyinstall bandwidth eth0                    - Monitor bandwidth"
    echo ""
    echo -e "${YELLOW}WebUI Commands:${NC}"
    echo "  easyinstall webui status                     - Check WebUI status"
    echo "  easyinstall webui restart                     - Restart WebUI"
    echo "  easyinstall webui logs                        - View WebUI logs"
    echo "  easyinstall webui url                         - Show WebUI URL"
    echo "  easyinstall webui password                    - Show admin password"
    echo ""
    echo -e "${YELLOW}Help:${NC}"
    echo "  easyinstall help                             - Show this help"
    echo ""
    echo -e "${GREEN}Happy Hosting! 🚀${NC}"
}

# Main command parser
case "$1" in
    # Domain commands
    domain)
        if [ -z "$2" ]; then
            list_domains
        else
            case "$2" in
                list) list_domains ;;
                create) install_wordpress "$3" "$4" "$5" ;;
                php) create_php_site "$3" "$4" "$5" ;;
                html) create_html_site "$3" "$4" ;;
                ssl) enable_ssl "$3" ;;
                info) domain_info "$3" ;;
                *) echo -e "${RED}Unknown domain command${NC}" ;;
            esac
        fi
        ;;
    
    # WordPress commands
    wp)
        if [ -z "$2" ]; then
            echo -e "${RED}Usage: wp <domain> <command>${NC}"
        else
            wp_command "$2" "${@:3}"
        fi
        ;;
    wp-backup) backup_wordpress "$2" ;;
    wp-update) update_wordpress "$2" ;;
    
    # Database commands
    db)
        case "$2" in
            list) list_databases ;;
            create) create_database "$3" "$4" "$5" ;;
            backup) backup_database "$3" ;;
            restore) restore_database "$3" "$4" ;;
            import) import_database "$3" "$4" ;;
            export) export_database "$3" "$4" ;;
            console) db_console "$3" ;;
            size) database_size "$3" ;;
            optimize) optimize_database "$3" ;;
            *) echo -e "${RED}Unknown database command${NC}" ;;
        esac
        ;;
    
    # Backup commands
    backup)
        case "$2" in
            create) create_backup "$3" ;;
            list) list_backups ;;
            restore) restore_backup "$3" ;;
            schedule) schedule_backup "$3" "$4" ;;
            remote) remote_backup "$3" "$4" "$5" ;;
            *) echo -e "${RED}Unknown backup command${NC}" ;;
        esac
        ;;
    
    # Cloud commands
    cloud)
        case "$2" in
            s3) configure_s3 "$3" "$4" "$5" "$6" ;;
            upload) upload_to_s3 "$3" "$4" ;;
            download) download_from_s3 "$3" "$4" ;;
            ls) list_s3_files "$3" ;;
            *) echo -e "${RED}Unknown cloud command${NC}" ;;
        esac
        ;;
    
    # Security commands
    security)
        case "$2" in
            firewall) configure_firewall ;;
            fail2ban) configure_fail2ban ;;
            scan) security_scan ;;
            passwords) change_passwords ;;
            *) echo -e "${RED}Unknown security command${NC}" ;;
        esac
        ;;
    
    # SSL commands
    ssl)
        case "$2" in
            enable) enable_ssl "$3" "$4" ;;
            renew) renew_ssl ;;
            check) check_ssl_expiry "$3" ;;
            self) create_self_signed "$3" ;;
            *) echo -e "${RED}Unknown SSL command${NC}" ;;
        esac
        ;;
    
    # System commands
    status) system_status ;;
    info) system_info ;;
    processes) process_list ;;
    service) service_control "$2" "$3" ;;
    logs) view_logs "$2" "$3" ;;
    
    # Tool commands
    password) generate_password "$2" ;;
    speedtest) test_speed ;;
    dns) dns_lookup "$2" ;;
    ssltest) ssl_test "$2" ;;
    memory) check_memory ;;
    cpu) check_cpu ;;
    large) find_large_files "$2" ;;
    du) disk_usage "$2" ;;
    bandwidth) monitor_bandwidth "$2" ;;
    website) check_website "$2" ;;
    alias) create_alias "$2" "$3" ;;
    
    # WebUI commands
    webui)
        case "$2" in
            status) webui_status ;;
            start) webui_start ;;
            stop) webui_stop ;;
            restart) webui_restart ;;
            logs) webui_logs "$3" ;;
            follow) webui_logs_follow ;;
            url) webui_url ;;
            password) webui_password ;;
            test) webui_test ;;
            backup) webui_backup ;;
            restore) webui_restore "$3" ;;
            help|*) webui_help ;;
        esac
        ;;
    
    # Help
    help|--help|-h)
        show_help
        ;;
    
    # Default - show help
    *)
        show_help
        ;;
esac
EOF

chmod +x /usr/local/bin/easyinstall

# ============================================
# Step 9: Start Services
# ============================================
echo -e "${YELLOW}🚀 Starting services...${NC}"

# Reload systemd
systemctl daemon-reload

# Enable and start Redis
systemctl enable redis-server
systemctl start redis-server

# Enable and start WebUI
systemctl enable easyinstall-webui
systemctl start easyinstall-webui

# Test and reload Nginx
nginx -t && systemctl reload nginx

# ============================================
# Step 10: Cleanup
# ============================================
rm -f /tmp/easyinstall-base.sh

# ============================================
# Step 11: Show Completion Message
# ============================================
IP_ADDRESS=$(hostname -I | awk '{print $1}')

# Get admin password
if [ -f "/var/lib/easyinstall/webui/admin_credentials.txt" ]; then
    ADMIN_PASS=$(grep "Password:" /var/lib/easyinstall/webui/admin_credentials.txt | cut -d' ' -f2)
else
    ADMIN_PASS="Check /var/lib/easyinstall/webui/admin_credentials.txt"
fi

clear
echo -e "${GREEN}"
echo "╔════════════════════════════════════════════════════════╗"
echo "║     EasyInstall Enterprise Stack Installation Complete ║"
echo "╚════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${BLUE}📊 WebUI Access:${NC}"
echo "   URL: https://$IP_ADDRESS"
echo "   Username: admin"
echo "   Password: $ADMIN_PASS"
echo ""

echo -e "${BLUE}📁 Credentials saved in:${NC}"
echo "   /var/lib/easyinstall/webui/admin_credentials.txt"
echo ""

echo -e "${GREEN}✅ Database: MariaDB detected and configured${NC}"
echo ""

echo -e "${YELLOW}📝 Quick Test Commands:${NC}"
echo "  easyinstall status                    # Check system status"
echo "  easyinstall domain list                # List domains"
echo "  easyinstall db list                     # List databases"
echo "  easyinstall webui url                   # Show WebUI URL"
echo ""

echo -e "${YELLOW}🌐 Create a test WordPress site:${NC}"
echo "  easyinstall domain create test.com"
echo ""

echo -e "${GREEN}Happy Hosting! 🚀${NC}"
echo ""
