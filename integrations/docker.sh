#!/bin/bash

# ============================================
# EasyInstall Docker Compose Integration
# ============================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

DOCKER_COMPOSE_VERSION="3.8"
DOCKER_NETWORK="easyinstall-net"
DOCKER_VOLUME_PREFIX="easyinstall"

setup_docker() {
    echo -e "${YELLOW}🐳 Setting up Docker for EasyInstall...${NC}"
    
    # Install Docker if not present
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}   Installing Docker...${NC}"
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        rm get-docker.sh
    fi
    
    # Install Docker Compose if not present
    if ! command -v docker-compose &> /dev/null; then
        echo -e "${YELLOW}   Installing Docker Compose...${NC}"
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
    fi
    
    # Create Docker network
    docker network create $DOCKER_NETWORK 2>/dev/null || true
    
    echo -e "${GREEN}   ✅ Docker setup complete${NC}"
}

create_docker_compose() {
    local DOMAIN=$1
    local TYPE=${2:-wordpress}  # wordpress, php, html
    
    echo -e "${YELLOW}📦 Creating Docker Compose for $DOMAIN ($TYPE)...${NC}"
    
    mkdir -p "/opt/easyinstall/docker/$DOMAIN"
    cd "/opt/easyinstall/docker/$DOMAIN"
    
    # Generate passwords
    DB_PASS=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c20)
    REDIS_PASS=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c20)
    
    case $TYPE in
        wordpress)
            cat > docker-compose.yml <<EOF
version: '$DOCKER_COMPOSE_VERSION'

services:
  db:
    image: mariadb:10.11
    container_name: ${DOMAIN//./-}-db
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: ${DB_PASS}
      MYSQL_DATABASE: wordpress
      MYSQL_USER: wpuser
      MYSQL_PASSWORD: ${DB_PASS}
    volumes:
      - ${DOCKER_VOLUME_PREFIX}-db-${DOMAIN//./-}:/var/lib/mysql
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      timeout: 20s
      retries: 10

  wordpress:
    image: wordpress:latest
    container_name: ${DOMAIN//./-}-wp
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
    environment:
      WORDPRESS_DB_HOST: db:3306
      WORDPRESS_DB_USER: wpuser
      WORDPRESS_DB_PASSWORD: ${DB_PASS}
      WORDPRESS_DB_NAME: wordpress
      WORDPRESS_CONFIG_EXTRA: |
        define('WP_REDIS_HOST', 'redis');
        define('WP_REDIS_PORT', 6379);
        define('WP_REDIS_PASSWORD', '${REDIS_PASS}');
        define('WP_CACHE', true);
        define('DISALLOW_FILE_EDIT', false);
    volumes:
      - ${DOCKER_VOLUME_PREFIX}-wp-${DOMAIN//./-}:/var/www/html
      - ./php.ini:/usr/local/etc/php/conf.d/custom.ini
    networks:
      - ${DOCKER_NETWORK}
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.${DOMAIN//./-}.rule=Host(\`$DOMAIN\`)"
      - "traefik.http.services.${DOMAIN//./-}.loadbalancer.server.port=80"

  redis:
    image: redis:7-alpine
    container_name: ${DOMAIN//./-}-redis
    restart: unless-stopped
    command: redis-server --requirepass ${REDIS_PASS}
    volumes:
      - ${DOCKER_VOLUME_PREFIX}-redis-${DOMAIN//./-}:/data
    networks:
      - ${DOCKER_NETWORK}

  nginx:
    image: nginx:alpine
    container_name: ${DOMAIN//./-}-nginx
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf
      - ${DOCKER_VOLUME_PREFIX}-wp-${DOMAIN//./-}:/var/www/html
    networks:
      - ${DOCKER_NETWORK}
    ports:
      - "80"
      - "443"

networks:
  ${DOCKER_NETWORK}:
    external: true
EOF

            # Create custom php.ini
            cat > php.ini <<EOF
memory_limit = 256M
upload_max_filesize = 64M
post_max_size = 64M
max_execution_time = 300
max_input_time = 300
date.timezone = UTC
opcache.enable = 1
opcache.memory_consumption = 128
opcache.interned_strings_buffer = 8
opcache.max_accelerated_files = 10000
opcache.revalidate_freq = 2
opcache.fast_shutdown = 1
EOF

            # Create nginx config
            cat > nginx.conf <<EOF
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;
    root /var/www/html;
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php$ {
        fastcgi_pass wordpress:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\. {
        deny all;
    }
}
EOF
            ;;
            
        php)
            cat > docker-compose.yml <<EOF
version: '$DOCKER_COMPOSE_VERSION'

services:
  php:
    image: php:8.2-fpm
    container_name: ${DOMAIN//./-}-php
    restart: unless-stopped
    volumes:
      - ./public:/var/www/html
      - ./php.ini:/usr/local/etc/php/conf.d/custom.ini
    networks:
      - ${DOCKER_NETWORK}

  nginx:
    image: nginx:alpine
    container_name: ${DOMAIN//./-}-nginx
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf
      - ./public:/var/www/html
    networks:
      - ${DOCKER_NETWORK}
    ports:
      - "80"
      - "443"

networks:
  ${DOCKER_NETWORK}:
    external: true
EOF

            mkdir -p public
            cat > public/index.php <<EOF
<?php
phpinfo();
EOF

            cat > nginx.conf <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    root /var/www/html;
    index index.php;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php$ {
        fastcgi_pass php:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
}
EOF

            cat > php.ini <<EOF
memory_limit = 128M
upload_max_filesize = 32M
post_max_size = 32M
max_execution_time = 120
EOF
            ;;
    esac
    
    # Create .env file
    cat > .env <<EOF
DOMAIN=$DOMAIN
DB_PASS=$DB_PASS
REDIS_PASS=$REDIS_PASS
EOF
    
    chmod 600 .env
    
    echo -e "${GREEN}   ✅ Docker Compose created at /opt/easyinstall/docker/$DOMAIN${NC}"
    echo -e "${YELLOW}   To start: cd /opt/easyinstall/docker/$DOMAIN && docker-compose up -d${NC}"
}

deploy_docker_stack() {
    local DOMAIN=$1
    
    cd "/opt/easyinstall/docker/$DOMAIN"
    docker-compose up -d
    
    echo -e "${GREEN}✅ Docker stack deployed for $DOMAIN${NC}"
    echo -e "${BLUE}   Access at: http://$DOMAIN${NC}"
}

docker_command() {
    case "$1" in
        setup)
            setup_docker
            ;;
        create)
            if [ -z "$2" ]; then
                echo -e "${RED}Usage: easyinstall docker create domain.com [wordpress|php]${NC}"
                exit 1
            fi
            create_docker_compose "$2" "$3"
            ;;
        deploy)
            if [ -z "$2" ]; then
                echo -e "${RED}Usage: easyinstall docker deploy domain.com${NC}"
                exit 1
            fi
            deploy_docker_stack "$2"
            ;;
        list)
            echo -e "${YELLOW}📋 Docker deployments:${NC}"
            for d in /opt/easyinstall/docker/*/; do
                if [ -d "$d" ]; then
                    DOMAIN=$(basename "$d")
                    echo "  🌐 $DOMAIN"
                fi
            done
            ;;
        stop)
            if [ -z "$2" ]; then
                echo -e "${RED}Usage: easyinstall docker stop domain.com${NC}"
                exit 1
            fi
            cd "/opt/easyinstall/docker/$2" && docker-compose down
            ;;
        *)
            echo "EasyInstall Docker Commands:"
            echo "  setup                    - Install Docker and Docker Compose"
            echo "  create domain.com [type] - Create Docker Compose config"
            echo "  deploy domain.com        - Deploy Docker stack"
            echo "  list                     - List all Docker deployments"
            echo "  stop domain.com          - Stop Docker stack"
            echo ""
            echo "Types: wordpress (default), php"
            ;;
    esac
}
