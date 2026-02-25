#!/bin/bash

# ============================================
# EasyInstall Podman/Containerd Support
# ============================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

setup_podman() {
    echo -e "${YELLOW}📦 Setting up Podman...${NC}"
    
    # Install Podman
    if ! command -v podman &> /dev/null; then
        apt update
        apt install -y podman podman-compose
    fi
    
    # Configure rootless
    echo "kernel.unprivileged_userns_clone=1" > /etc/sysctl.d/00-local-userns.conf
    sysctl -p /etc/sysctl.d/00-local-userns.conf
    
    # Create podman network
    podman network create easyinstall-net 2>/dev/null || true
    
    echo -e "${GREEN}   ✅ Podman setup complete${NC}"
}

setup_containerd() {
    echo -e "${YELLOW}📦 Setting up Containerd...${NC}"
    
    # Install containerd
    if ! command -v containerd &> /dev/null; then
        apt update
        apt install -y containerd
    fi
    
    # Configure containerd
    mkdir -p /etc/containerd
    containerd config default > /etc/containerd/config.toml
    
    # Enable cgroups
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    
    systemctl restart containerd
    systemctl enable containerd
    
    # Install nerdctl
    if ! command -v nerdctl &> /dev/null; then
        curl -L https://github.com/containerd/nerdctl/releases/latest/download/nerdctl-full-$(uname -m).tar.gz -o nerdctl.tar.gz
        tar Cxzvvf /usr/local/bin nerdctl.tar.gz
        rm nerdctl.tar.gz
    fi
    
    echo -e "${GREEN}   ✅ Containerd setup complete${NC}"
}

create_podman_pod() {
    local DOMAIN=$1
    local TYPE=${2:-wordpress}
    
    echo -e "${YELLOW}📦 Creating Podman pod for $DOMAIN...${NC}"
    
    mkdir -p "/opt/easyinstall/podman/$DOMAIN"
    cd "/opt/easyinstall/podman/$DOMAIN"
    
    # Generate passwords
    DB_PASS=$(openssl rand -base64 24)
    REDIS_PASS=$(openssl rand -base64 24)
    
    case $TYPE in
        wordpress)
            cat > pod.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${DOMAIN//./-}-pod
  labels:
    app: wordpress
spec:
  containers:
  - name: db
    image: docker.io/mariadb:10.11
    env:
    - name: MYSQL_ROOT_PASSWORD
      value: "${DB_PASS}"
    - name: MYSQL_DATABASE
      value: "wordpress"
    - name: MYSQL_USER
      value: "wpuser"
    - name: MYSQL_PASSWORD
      value: "${DB_PASS}"
    volumeMounts:
    - name: db-data
      mountPath: /var/lib/mysql
    ports:
    - containerPort: 3306
      hostPort: 3306
    
  - name: wordpress
    image: docker.io/wordpress:latest
    env:
    - name: WORDPRESS_DB_HOST
      value: "127.0.0.1"
    - name: WORDPRESS_DB_USER
      value: "wpuser"
    - name: WORDPRESS_DB_PASSWORD
      value: "${DB_PASS}"
    - name: WORDPRESS_DB_NAME
      value: "wordpress"
    - name: WORDPRESS_CONFIG_EXTRA
      value: |
        define('WP_REDIS_HOST', '127.0.0.1');
        define('WP_REDIS_PORT', 6379);
        define('WP_REDIS_PASSWORD', '${REDIS_PASS}');
    volumeMounts:
    - name: wp-data
      mountPath: /var/www/html
    ports:
    - containerPort: 80
      hostPort: 8080
    
  - name: redis
    image: docker.io/redis:7-alpine
    args: ["redis-server", "--requirepass", "${REDIS_PASS}"]
    volumeMounts:
    - name: redis-data
      mountPath: /data
    ports:
    - containerPort: 6379
      hostPort: 6379
    
  volumes:
  - name: db-data
    hostPath:
      path: /opt/easyinstall/podman/$DOMAIN/data/db
  - name: wp-data
    hostPath:
      path: /opt/easyinstall/podman/$DOMAIN/data/wp
  - name: redis-data
    hostPath:
      path: /opt/easyinstall/podman/$DOMAIN/data/redis
EOF

            # Create directories
            mkdir -p data/{db,wp,redis}
            
            # Create systemd service
            cat > "/etc/systemd/system/podman-${DOMAIN//./-}.service" <<EOF
[Unit]
Description=Podman pod for $DOMAIN
After=network.target

[Service]
Type=forking
ExecStart=/usr/bin/podman play kube /opt/easyinstall/podman/$DOMAIN/pod.yaml
ExecStop=/usr/bin/podman pod stop ${DOMAIN//./-}-pod
ExecStopPost=/usr/bin/podman pod rm ${DOMAIN//./-}-pod
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
            ;;
    esac
    
    echo -e "${GREEN}   ✅ Podman pod created at /opt/easyinstall/podman/$DOMAIN${NC}"
}

deploy_podman() {
    local DOMAIN=$1
    
    cd "/opt/easyinstall/podman/$DOMAIN"
    
    # Create directories
    mkdir -p data
    
    # Start pod
    podman play kube pod.yaml
    
    # Enable systemd service
    systemctl daemon-reload
    systemctl enable "podman-${DOMAIN//./-}.service"
    systemctl start "podman-${DOMAIN//./-}.service"
    
    echo -e "${GREEN}✅ Podman pod deployed for $DOMAIN${NC}"
}

podman_command() {
    case "$1" in
        setup)
            setup_podman
            ;;
        setup-containerd)
            setup_containerd
            ;;
        create)
            if [ -z "$2" ]; then
                echo -e "${RED}Usage: easyinstall podman create domain.com [wordpress]${NC}"
                exit 1
            fi
            create_podman_pod "$2" "$3"
            ;;
        deploy)
            if [ -z "$2" ]; then
                echo -e "${RED}Usage: easyinstall podman deploy domain.com${NC}"
                exit 1
            fi
            deploy_podman "$2"
            ;;
        list)
            echo -e "${YELLOW}📋 Podman pods:${NC}"
            podman pod ps
            ;;
        stop)
            if [ -z "$2" ]; then
                echo -e "${RED}Usage: easyinstall podman stop domain.com${NC}"
                exit 1
            fi
            systemctl stop "podman-${2//./-}.service"
            ;;
        *)
            echo "EasyInstall Podman Commands:"
            echo "  setup                    - Install and configure Podman"
            echo "  setup-containerd         - Install and configure Containerd"
            echo "  create domain.com [type] - Create Podman pod config"
            echo "  deploy domain.com        - Deploy Podman pod"
            echo "  list                     - List all Podman pods"
            echo "  stop domain.com          - Stop Podman pod"
            ;;
    esac
}
