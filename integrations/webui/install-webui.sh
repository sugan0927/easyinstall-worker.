#!/bin/bash

# ============================================
# EasyInstall WebUI Installer
# ============================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}🌐 Installing EasyInstall WebUI${NC}"
echo ""

# Root check
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}❌ Please run as root${NC}"
    exit 1
fi

# Install Python dependencies
echo -e "${YELLOW}📦 Installing Python packages...${NC}"
apt update
apt install -y python3-pip python3-venv nginx redis-server
pip3 install flask flask-socketio flask-login bcrypt paramiko boto3 google-auth google-auth-oauthlib google-auth-httplib2 googleapiclient redis gunicorn eventlet

# Create directories
echo -e "${YELLOW}📁 Creating directories...${NC}"
mkdir -p /opt/easyinstall-webui/{app,static,logs}
mkdir -p /var/lib/easyinstall/webui
mkdir -p /etc/easyinstall/webui

# Copy application files
echo -e "${YELLOW}📄 Copying application files...${NC}"
cp webui/app.py /opt/easyinstall-webui/app/
cp webui/templates/login.html /opt/easyinstall-webui/app/templates/
cp webui/templates/dashboard.html /opt/easyinstall-webui/app/templates/

# Create systemd service
cat > /etc/systemd/system/easyinstall-webui.service <<EOF
[Unit]
Description=EasyInstall WebUI
After=network.target redis.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/easyinstall-webui/app
ExecStart=/usr/local/bin/gunicorn -w 4 -k eventlet -b 127.0.0.1:5000 app:app
Restart=always
RestartSec=10
StandardOutput=append:/var/log/easyinstall/webui.log
StandardError=append:/var/log/easyinstall/webui.error

[Install]
WantedBy=multi-user.target
EOF

# Create Nginx configuration
cat > /etc/nginx/sites-available/easyinstall-webui <<EOF
server {
    listen 80;
    server_name _;
    
    # Redirect to HTTPS
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name _;
    
    # SSL certificates (self-signed for now)
    ssl_certificate /etc/nginx/ssl/easyinstall.crt;
    ssl_certificate_key /etc/nginx/ssl/easyinstall.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    
    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    # Logs
    access_log /var/log/nginx/easyinstall-webui-access.log;
    error_log /var/log/nginx/easyinstall-webui-error.log;
    
    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffering off;
        proxy_cache off;
    }
    
    location /socket.io {
        proxy_pass http://127.0.0.1:5000/socket.io;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_buffering off;
        proxy_cache off;
    }
    
    # Static files
    location /static {
        alias /opt/easyinstall-webui/app/static;
        expires 30d;
    }
}
EOF

# Generate self-signed SSL certificate
echo -e "${YELLOW}🔐 Generating SSL certificate...${NC}"
mkdir -p /etc/nginx/ssl
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/easyinstall.key \
    -out /etc/nginx/ssl/easyinstall.crt \
    -subj "/C=US/ST=State/L=City/O=EasyInstall/CN=localhost"

# Enable site
ln -sf /etc/nginx/sites-available/easyinstall-webui /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test and reload Nginx
nginx -t && systemctl reload nginx

# Start services
echo -e "${YELLOW}🚀 Starting services...${NC}"
systemctl daemon-reload
systemctl enable easyinstall-webui
systemctl start easyinstall-webui
systemctl enable redis-server
systemctl start redis-server

# Get admin credentials
ADMIN_PASS=$(grep -oP 'Password: \K.*' /var/lib/easyinstall/webui/admin_credentials.txt 2>/dev/null || echo "Check /var/lib/easyinstall/webui/admin_credentials.txt")

echo -e "${GREEN}"
echo "============================================"
echo "✅ EasyInstall WebUI Installation Complete!"
echo "============================================"
echo ""
echo "📊 WebUI Access:"
echo "   URL: https://$(hostname -I | awk '{print $1}')"
echo "   Username: admin"
echo "   Password: $ADMIN_PASS"
echo ""
echo "📁 Credentials saved in:"
echo "   /var/lib/easyinstall/webui/admin_credentials.txt"
echo ""
echo "📝 Logs:"
echo "   Application: /var/log/easyinstall/webui.log"
echo "   Nginx: /var/log/nginx/easyinstall-webui-*.log"
echo ""
echo "🔧 Commands:"
echo "   Start:   systemctl start easyinstall-webui"
echo "   Stop:    systemctl stop easyinstall-webui"
echo "   Status:  systemctl status easyinstall-webui"
echo "   Logs:    journalctl -u easyinstall-webui -f"
echo ""
echo -e "${NC}"
