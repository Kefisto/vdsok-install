#!/usr/bin/env bash
#
# VDSok KMS Server — Quick Deploy
# Deploys vlmcsd in Docker on a Linux VPS
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/Kefisto/vdsok-install/master/kms/deploy.sh | bash
#   or: bash deploy.sh
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

KMS_DIR="/opt/vdsok-kms"
REPO_URL="https://github.com/Kefisto/vdsok-install.git"

# ─────────────────────────────────────
# Check root
# ─────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    error "Run as root: sudo bash $0"
    exit 1
fi

echo -e "${CYAN}"
echo "  ╔══════════════════════════════════════╗"
echo "  ║     VDSok KMS Server (vlmcsd)        ║"
echo "  ╚══════════════════════════════════════╝"
echo -e "${NC}"

# ─────────────────────────────────────
# Install Docker if missing
# ─────────────────────────────────────
install_docker() {
    if command -v docker &>/dev/null; then
        info "Docker already installed: $(docker --version)"
        return 0
    fi

    info "Installing Docker..."

    if command -v apt-get &>/dev/null; then
        apt-get update -qq
        apt-get install -y -qq ca-certificates curl gnupg lsb-release
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg \
            | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null
        chmod a+r /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
            https://download.docker.com/linux/$(. /etc/os-release && echo "$ID") \
            $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
        apt-get update -qq
        apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
    elif command -v yum &>/dev/null; then
        yum install -y yum-utils
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    else
        info "Using convenience script..."
        curl -fsSL https://get.docker.com | sh
    fi

    systemctl enable docker
    systemctl start docker
    info "Docker installed: $(docker --version)"
}

# ─────────────────────────────────────
# Install docker-compose standalone if plugin not available
# ─────────────────────────────────────
ensure_compose() {
    if docker compose version &>/dev/null; then
        info "Docker Compose plugin: $(docker compose version)"
        COMPOSE_CMD="docker compose"
    elif command -v docker-compose &>/dev/null; then
        info "docker-compose standalone: $(docker-compose --version)"
        COMPOSE_CMD="docker-compose"
    else
        info "Installing docker-compose..."
        curl -fsSL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
            -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        COMPOSE_CMD="docker-compose"
    fi
}

# ─────────────────────────────────────
# Get KMS files
# ─────────────────────────────────────
setup_kms_dir() {
    if [[ -f "$KMS_DIR/docker-compose.yml" ]]; then
        info "KMS directory exists at $KMS_DIR, updating..."
        cd "$KMS_DIR"
        if [[ -d .git ]]; then
            git pull --quiet 2>/dev/null || true
        fi
        return
    fi

    info "Cloning vdsok-install repository..."
    if command -v git &>/dev/null; then
        git clone --depth 1 "$REPO_URL" /tmp/vdsok-install-kms 2>/dev/null
        mkdir -p "$KMS_DIR"
        cp /tmp/vdsok-install-kms/kms/* "$KMS_DIR/"
        rm -rf /tmp/vdsok-install-kms
    else
        mkdir -p "$KMS_DIR"
        for f in docker-compose.yml Dockerfile; do
            curl -fsSL "https://raw.githubusercontent.com/Kefisto/vdsok-install/master/kms/$f" \
                -o "$KMS_DIR/$f"
        done
    fi

    info "KMS files installed to $KMS_DIR"
}

# ─────────────────────────────────────
# Firewall
# ─────────────────────────────────────
configure_firewall() {
    info "Configuring firewall for port 1688/tcp..."

    if command -v ufw &>/dev/null; then
        ufw allow 1688/tcp comment "VDSok KMS" 2>/dev/null || true
        info "  ufw: port 1688/tcp allowed"
    elif command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --add-port=1688/tcp 2>/dev/null || true
        firewall-cmd --reload 2>/dev/null || true
        info "  firewalld: port 1688/tcp allowed"
    else
        if iptables -L INPUT -n 2>/dev/null | grep -q "1688"; then
            info "  iptables: port 1688 already open"
        else
            iptables -I INPUT -p tcp --dport 1688 -j ACCEPT 2>/dev/null || true
            info "  iptables: port 1688/tcp allowed"
        fi
    fi
}

# ─────────────────────────────────────
# Build & Start
# ─────────────────────────────────────
start_kms() {
    cd "$KMS_DIR"
    info "Building and starting vlmcsd container..."
    $COMPOSE_CMD up -d --build

    sleep 3

    if docker ps --filter "name=vdsok-kms" --filter "status=running" -q | grep -q .; then
        info "KMS container is running!"
    else
        error "Container failed to start. Logs:"
        $COMPOSE_CMD logs --tail=20
        exit 1
    fi
}

# ─────────────────────────────────────
# Verify
# ─────────────────────────────────────
verify_kms() {
    info "Verifying KMS server on port 1688..."

    if command -v nc &>/dev/null; then
        if nc -z 127.0.0.1 1688 2>/dev/null; then
            info "Port 1688 is responding — KMS is live!"
        else
            warn "Port 1688 not responding yet (container may still be starting)"
        fi
    elif command -v ncat &>/dev/null; then
        if ncat -z 127.0.0.1 1688 2>/dev/null; then
            info "Port 1688 is responding — KMS is live!"
        else
            warn "Port 1688 not responding yet"
        fi
    else
        warn "nc/ncat not found, skipping port check"
    fi
}

# ─────────────────────────────────────
# Summary
# ─────────────────────────────────────
show_summary() {
    local server_ip
    server_ip=$(curl -s4 ifconfig.me 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || echo "<YOUR_IP>")

    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  KMS server deployed successfully!${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  Container:  ${GREEN}vdsok-kms${NC} (vlmcsd)"
    echo -e "  Port:       ${GREEN}1688/tcp${NC}"
    echo -e "  Server IP:  ${GREEN}$server_ip${NC}"
    echo -e "  Directory:  $KMS_DIR"
    echo ""
    echo -e "${YELLOW}  DNS: Create an A record:${NC}"
    echo -e "    kms.vdsok.com  ->  $server_ip"
    echo ""
    echo -e "${YELLOW}  Test from a Windows machine:${NC}"
    echo -e "    slmgr /skms $server_ip"
    echo -e "    slmgr /ato"
    echo ""
    echo -e "${YELLOW}  Manage:${NC}"
    echo -e "    cd $KMS_DIR"
    echo -e "    $COMPOSE_CMD logs -f       # view logs"
    echo -e "    $COMPOSE_CMD restart       # restart"
    echo -e "    $COMPOSE_CMD down          # stop"
    echo -e "    $COMPOSE_CMD up -d --build # rebuild"
    echo ""
}

# ─────────────────────────────────────
# Main
# ─────────────────────────────────────
main() {
    install_docker
    ensure_compose
    setup_kms_dir
    configure_firewall
    start_kms
    verify_kms
    show_summary
}

main "$@"
