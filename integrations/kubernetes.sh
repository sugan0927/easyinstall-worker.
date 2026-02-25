#!/bin/bash

# ============================================
# EasyInstall Kubernetes Support
# ============================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

K8S_NAMESPACE="easyinstall"

setup_kubectl() {
    echo -e "${YELLOW}☸️  Setting up Kubernetes tools...${NC}"
    
    # Install kubectl if not present
    if ! command -v kubectl &> /dev/null; then
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        chmod +x kubectl
        mv kubectl /usr/local/bin/
    fi
    
    # Install helm if not present
    if ! command -v helm &> /dev/null; then
        curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
        chmod +x get_helm.sh
        ./get_helm.sh
        rm get_helm.sh
    fi
    
    # Create namespace
    kubectl create namespace $K8S_NAMESPACE 2>/dev/null || true
    
    echo -e "${GREEN}   ✅ Kubernetes tools ready${NC}"
}

create_k8s_manifest() {
    local DOMAIN=$1
    local TYPE=${2:-wordpress}
    
    echo -e "${YELLOW}📦 Creating Kubernetes manifests for $DOMAIN...${NC}"
    
    mkdir -p "/opt/easyinstall/k8s/$DOMAIN"
    cd "/opt/easyinstall/k8s/$DOMAIN"
    
    # Generate secrets
    DB_PASS=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9')
    DB_PASS_B64=$(echo -n "$DB_PASS" | base64)
    
    # Create namespace
    cat > namespace.yaml <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ${DOMAIN//./-}
---
EOF

    # Create secrets
    cat > secrets.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${DOMAIN//./-}-db-secret
  namespace: ${DOMAIN//./-}
type: Opaque
data:
  root-password: ${DB_PASS_B64}
  user-password: ${DB_PASS_B64}
---
apiVersion: v1
kind: Secret
metadata:
  name: ${DOMAIN//./-}-wp-secret
  namespace: ${DOMAIN//./-}
type: Opaque
data:
  auth-key: $(openssl rand -base64 32 | base64)
  secure-auth-key: $(openssl rand -base64 32 | base64)
  logged-in-key: $(openssl rand -base64 32 | base64)
  nonce-key: $(openssl rand -base64 32 | base64)
EOF

    # Create configmap
    cat > configmap.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${DOMAIN//./-}-config
  namespace: ${DOMAIN//./-}
data:
  php.ini: |
    memory_limit = 256M
    upload_max_filesize = 64M
    post_max_size = 64M
    max_execution_time = 300
  nginx.conf: |
    server {
        listen 80;
        server_name $DOMAIN;
        root /var/www/html;
        index index.php;
        
        location / {
            try_files \$uri \$uri/ /index.php?\$args;
        }
        
        location ~ \.php$ {
            fastcgi_pass localhost:9000;
            fastcgi_index index.php;
            fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
            include fastcgi_params;
        }
    }
EOF

    # Create persistent volumes
    cat > pvc.yaml <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${DOMAIN//./-}-wp-data
  namespace: ${DOMAIN//./-}
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${DOMAIN//./-}-db-data
  namespace: ${DOMAIN//./-}
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
EOF

    # Create deployments
    case $TYPE in
        wordpress)
            cat > deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${DOMAIN//./-}-db
  namespace: ${DOMAIN//./-}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${DOMAIN//./-}-db
  template:
    metadata:
      labels:
        app: ${DOMAIN//./-}-db
    spec:
      containers:
      - name: mariadb
        image: mariadb:10.11
        env:
        - name: MYSQL_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: ${DOMAIN//./-}-db-secret
              key: root-password
        - name: MYSQL_DATABASE
          value: wordpress
        - name: MYSQL_USER
          value: wpuser
        - name: MYSQL_PASSWORD
          valueFrom:
            secretKeyRef:
              name: ${DOMAIN//./-}-db-secret
              key: user-password
        ports:
        - containerPort: 3306
        volumeMounts:
        - name: db-data
          mountPath: /var/lib/mysql
      volumes:
      - name: db-data
        persistentVolumeClaim:
          claimName: ${DOMAIN//./-}-db-data
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${DOMAIN//./-}-wordpress
  namespace: ${DOMAIN//./-}
spec:
  replicas: 2
  selector:
    matchLabels:
      app: ${DOMAIN//./-}-wordpress
  template:
    metadata:
      labels:
        app: ${DOMAIN//./-}-wordpress
    spec:
      containers:
      - name: wordpress
        image: wordpress:latest
        env:
        - name: WORDPRESS_DB_HOST
          value: ${DOMAIN//./-}-db
        - name: WORDPRESS_DB_USER
          value: wpuser
        - name: WORDPRESS_DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: ${DOMAIN//./-}-db-secret
              key: user-password
        - name: WORDPRESS_DB_NAME
          value: wordpress
        ports:
        - containerPort: 80
        volumeMounts:
        - name: wp-data
          mountPath: /var/www/html
      volumes:
      - name: wp-data
        persistentVolumeClaim:
          claimName: ${DOMAIN//./-}-wp-data
EOF
            ;;
    esac

    # Create services
    cat > service.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: ${DOMAIN//./-}-db
  namespace: ${DOMAIN//./-}
spec:
  selector:
    app: ${DOMAIN//./-}-db
  ports:
  - port: 3306
    targetPort: 3306
---
apiVersion: v1
kind: Service
metadata:
  name: ${DOMAIN//./-}-wordpress
  namespace: ${DOMAIN//./-}
spec:
  selector:
    app: ${DOMAIN//./-}-wordpress
  ports:
  - port: 80
    targetPort: 80
  type: LoadBalancer
EOF

    # Create ingress
    cat > ingress.yaml <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${DOMAIN//./-}-ingress
  namespace: ${DOMAIN//./-}
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  tls:
  - hosts:
    - $DOMAIN
    secretName: ${DOMAIN//./-}-tls
  rules:
  - host: $DOMAIN
    http:
      paths:
      - pathType: Prefix
        path: "/"
        backend:
          service:
            name: ${DOMAIN//./-}-wordpress
            port:
              number: 80
EOF

    # Create kustomization
    cat > kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: ${DOMAIN//./-}
resources:
  - namespace.yaml
  - secrets.yaml
  - configmap.yaml
  - pvc.yaml
  - deployment.yaml
  - service.yaml
  - ingress.yaml
EOF

    echo -e "${GREEN}   ✅ Kubernetes manifests created at /opt/easyinstall/k8s/$DOMAIN${NC}"
}

deploy_k8s() {
    local DOMAIN=$1
    
    cd "/opt/easyinstall/k8s/$DOMAIN"
    kubectl apply -k .
    
    echo -e "${GREEN}✅ Kubernetes deployment created for $DOMAIN${NC}"
    echo -e "${BLUE}   Watch: kubectl get all -n ${DOMAIN//./-} -w${NC}"
}

k8s_command() {
    case "$1" in
        setup)
            setup_kubectl
            ;;
        create)
            if [ -z "$2" ]; then
                echo -e "${RED}Usage: easyinstall k8s create domain.com [wordpress]${NC}"
                exit 1
            fi
            create_k8s_manifest "$2" "$3"
            ;;
        deploy)
            if [ -z "$2" ]; then
                echo -e "${RED}Usage: easyinstall k8s deploy domain.com${NC}"
                exit 1
            fi
            deploy_k8s "$2"
            ;;
        list)
            echo -e "${YELLOW}📋 Kubernetes deployments:${NC}"
            kubectl get namespaces | grep -E '^[a-z0-9-]+' | grep -v 'kube-' | grep -v 'default' | while read ns; do
                echo "  🌐 $ns"
            done
            ;;
        *)
            echo "EasyInstall Kubernetes Commands:"
            echo "  setup                    - Install kubectl and helm"
            echo "  create domain.com [type] - Create Kubernetes manifests"
            echo "  deploy domain.com        - Deploy to Kubernetes"
            echo "  list                     - List all deployments"
            ;;
    esac
}
