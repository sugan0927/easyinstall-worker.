#!/bin/bash

# ============================================
# EasyInstall MicroVM Isolation (Firecracker/Youki)
# ============================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

setup_firecracker() {
    echo -e "${YELLOW}🔥 Setting up Firecracker MicroVM...${NC}"
    
    # Download Firecracker
    ARCH="$(uname -m)"
    LATEST=$(curl -s https://api.github.com/repos/firecracker-microvm/firecracker/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    curl -L "https://github.com/firecracker-microvm/firecracker/releases/download/${LATEST}/firecracker-${LATEST}-${ARCH}.tgz" | tar -xz
    
    # Install Firecracker
    mv release-${LATEST}-${ARCH}/firecracker-${LATEST}-${ARCH} /usr/local/bin/firecracker
    chmod +x /usr/local/bin/firecracker
    
    # Create jailer directory
    mkdir -p /var/lib/firecracker
    
    # Setup KVM permissions
    setfacl -m u:${USER}:rw /dev/kvm 2>/dev/null || chmod 666 /dev/kvm
    
    echo -e "${GREEN}   ✅ Firecracker installed${NC}"
}

setup_youki() {
    echo -e "${YELLOW}📦 Setting up Youki container runtime...${NC}"
    
    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source $HOME/.cargo/env
    
    # Build Youki
    git clone https://github.com/containers/youki.git
    cd youki
    cargo build --release --features seccomp
    
    # Install Youki
    cp ./youki /usr/local/bin/
    cp ./youki /usr/local/bin/youki
    
    # Configure as default runtime
    mkdir -p /etc/containerd
    cat > /etc/containerd/config.toml <<EOF
version = 2
[plugins."io.containerd.grpc.v1.cri".containerd]
  default_runtime_name = "youki"
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.youki]
  runtime_type = "io.containerd.youki.v2"
  pod_annotations = []
  privileged_without_host_devices = false
EOF
    
    systemctl restart containerd
    
    echo -e "${GREEN}   ✅ Youki runtime configured${NC}"
}

create_firecracker_vm() {
    local DOMAIN=$1
    
    echo -e "${YELLOW}🔥 Creating Firecracker MicroVM for $DOMAIN...${NC}"
    
    mkdir -p "/var/lib/firecracker/$DOMAIN"
    cd "/var/lib/firecracker/$DOMAIN"
    
    # Download kernel and rootfs
    curl -fsSL -o vmlinux "https://s3.amazonaws.com/spec.ccfc.min/img/quickstart_guide/${ARCH}/kernels/vmlinux.bin"
    curl -fsSL -o rootfs.ext4 "https://s3.amazonaws.com/spec.ccfc.min/img/quickstart_guide/${ARCH}/rootfs/bionic.rootfs.ext4"
    
    # Create config file
    cat > vm-config.json <<EOF
{
  "boot-source": {
    "kernel_image_path": "/var/lib/firecracker/$DOMAIN/vmlinux",
    "boot_args": "console=ttyS0 reboot=k panic=1 pci=off"
  },
  "drives": [
    {
      "drive_id": "rootfs",
      "path_on_host": "/var/lib/firecracker/$DOMAIN/rootfs.ext4",
      "is_root_device": true,
      "is_read_only": false
    }
  ],
  "machine-config": {
    "vcpu_count": 2,
    "mem_size_mib": 512,
    "smt": false
  },
  "network-interfaces": [
    {
      "iface_id": "eth0",
      "guest_mac": "$(printf '02:FC:00:%02X:%02X:%02X' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))",
      "host_dev_name": "tap0"
    }
  ]
}
EOF

    # Create tap device
    ip tuntap add tap0 mode tap
    ip addr add 172.16.0.1/24 dev tap0
    ip link set tap0 up
    
    # Enable IP forwarding
    echo 1 > /proc/sys/net/ipv4/ip_forward
    iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
    iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    iptables -A FORWARD -i tap0 -o eth0 -j ACCEPT
    
    # Create systemd service
    cat > "/etc/systemd/system/firecracker-${DOMAIN//./-}.service" <<EOF
[Unit]
Description=Firecracker MicroVM for $DOMAIN
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/firecracker --api-sock /tmp/firecracker-${DOMAIN//./-}.socket --config-file /var/lib/firecracker/$DOMAIN/vm-config.json
ExecStop=/bin/kill \$MAINPID
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    
    echo -e "${GREEN}   ✅ Firecracker MicroVM configured at /var/lib/firecracker/$DOMAIN${NC}"
}

create_youki_container() {
    local DOMAIN=$1
    
    echo -e "${YELLOW}📦 Creating Youki container for $DOMAIN...${NC}"
    
    mkdir -p "/var/lib/youki/$DOMAIN"
    cd "/var/lib/youki/$DOMAIN"
    
    # Create OCI bundle
    mkdir rootfs
    docker export $(docker create wordpress) | tar -C rootfs -xf -
    
    # Create config.json
    youki spec --rootless
    
    # Modify config for WordPress
    cat > config.json <<EOF
{
  "ociVersion": "1.0.2",
  "process": {
    "terminal": true,
    "user": {
      "uid": 0,
      "gid": 0
    },
    "args": [
      "apache2-foreground"
    ],
    "env": [
      "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
      "WORDPRESS_DB_HOST=127.0.0.1",
      "WORDPRESS_DB_USER=wpuser",
      "WORDPRESS_DB_PASSWORD=$(openssl rand -base64 24)",
      "WORDPRESS_DB_NAME=wordpress"
    ],
    "cwd": "/var/www/html",
    "capabilities": {
      "bounding": [
        "CAP_AUDIT_WRITE",
        "CAP_KILL",
        "CAP_NET_BIND_SERVICE"
      ],
      "effective": [
        "CAP_AUDIT_WRITE",
        "CAP_KILL",
        "CAP_NET_BIND_SERVICE"
      ],
      "inheritable": [
        "CAP_AUDIT_WRITE",
        "CAP_KILL",
        "CAP_NET_BIND_SERVICE"
      ],
      "permitted": [
        "CAP_AUDIT_WRITE",
        "CAP_KILL",
        "CAP_NET_BIND_SERVICE"
      ]
    },
    "rlimits": [
      {
        "type": "RLIMIT_NOFILE",
        "hard": 1024,
        "soft": 1024
      }
    ]
  },
  "root": {
    "path": "rootfs",
    "readonly": false
  },
  "hostname": "$DOMAIN",
  "mounts": [
    {
      "destination": "/proc",
      "type": "proc",
      "source": "proc"
    },
    {
      "destination": "/dev",
      "type": "tmpfs",
      "source": "tmpfs",
      "options": [
        "nosuid",
        "strictatime",
        "mode=755",
        "size=65536k"
      ]
    },
    {
      "destination": "/dev/pts",
      "type": "devpts",
      "source": "devpts",
      "options": [
        "nosuid",
        "noexec",
        "newinstance",
        "ptmxmode=0666",
        "mode=0620",
        "gid=5"
      ]
    },
    {
      "destination": "/sys",
      "type": "sysfs",
      "source": "sysfs",
      "options": [
        "nosuid",
        "noexec",
        "nodev",
        "ro"
      ]
    }
  ],
  "linux": {
    "resources": {
      "devices": [
        {
          "allow": false,
          "access": "rwm"
        }
      ],
      "memory": {
        "limit": 536870912,
        "swap": 536870912
      },
      "cpu": {
        "shares": 1024,
        "quota": 100000,
        "period": 100000
      }
    },
    "namespaces": [
      {
        "type": "pid"
      },
      {
        "type": "network"
      },
      {
        "type": "ipc"
      },
      {
        "type": "uts"
      },
      {
        "type": "mount"
      }
    ]
  }
}
EOF

    echo -e "${GREEN}   ✅ Youki container configured at /var/lib/youki/$DOMAIN${NC}"
}

microvm_command() {
    case "$1" in
        setup-firecracker)
            setup_firecracker
            ;;
        setup-youki)
            setup_youki
            ;;
        create-firecracker)
            if [ -z "$2" ]; then
                echo -e "${RED}Usage: easyinstall microvm create-firecracker domain.com${NC}"
                exit 1
            fi
            create_firecracker_vm "$2"
            ;;
        create-youki)
            if [ -z "$2" ]; then
                echo -e "${RED}Usage: easyinstall microvm create-youki domain.com${NC}"
                exit 1
            fi
            create_youki_container "$2"
            ;;
        start)
            if [ -z "$2" ]; then
                echo -e "${RED}Usage: easyinstall microvm start domain.com${NC}"
                exit 1
            fi
            systemctl start "firecracker-${2//./-}.service"
            ;;
        stop)
            if [ -z "$2" ]; then
                echo -e "${RED}Usage: easyinstall microvm stop domain.com${NC}"
                exit 1
            fi
            systemctl stop "firecracker-${2//./-}.service"
            ;;
        *)
            echo "EasyInstall MicroVM Commands:"
            echo "  setup-firecracker          - Install Firecracker"
            echo "  setup-youki                 - Install Youki runtime"
            echo "  create-firecracker domain   - Create Firecracker MicroVM"
            echo "  create-youki domain         - Create Youki container"
            echo "  start domain                 - Start MicroVM"
            echo "  stop domain                  - Stop MicroVM"
            ;;
    esac
}
