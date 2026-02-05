#!/bin/bash
set -euo pipefail

# join_pki.sh
# Automates joining a Linux host to the Smallstep PKI.
# Features: .env support, Smart Menu, Verification, Auto-Renewal.

# Default Config
ENV_FILE="$(dirname "$0")/join_pki.env"
STEP_PATH="/root/.step"
SYSTEMD_DIR="/etc/systemd/system"
CA_URL=""
FINGERPRINT=""
TOKEN=""
ENABLE_RENEWAL="true"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# --- HELPERS ---

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Error: Must run as root.${NC}"
        exit 1
    fi
}

load_env() {
    if [ -f "$ENV_FILE" ]; then
        echo "Loading config from $ENV_FILE..."
        # Source checks to prevent eval injection not strictly needed if file is trusted, 
        # but manual parsing is safer for simple vars.
        CA_URL=$(grep "^CA_URL=" "$ENV_FILE" | cut -d= -f2- | tr -d '"' || echo "$CA_URL")
        FINGERPRINT=$(grep "^FINGERPRINT=" "$ENV_FILE" | cut -d= -f2- | tr -d '"' || echo "$FINGERPRINT")
        TOKEN=$(grep "^TOKEN=" "$ENV_FILE" | cut -d= -f2- | tr -d '"' || echo "$TOKEN")
        ENABLE_RENEWAL=$(grep "^ENABLE_RENEWAL=" "$ENV_FILE" | cut -d= -f2- | tr -d '"' || echo "$ENABLE_RENEWAL")
    fi
}

save_env() {
    echo "Saving config to $ENV_FILE..."
    cat <<EOF > "$ENV_FILE"
CA_URL="$CA_URL"
FINGERPRINT="$FINGERPRINT"
TOKEN="$TOKEN"
ENABLE_RENEWAL="$ENABLE_RENEWAL"
EOF
    chmod 600 "$ENV_FILE"
}

status_icon() {
    if [ -n "$1" ]; then echo -e "${GREEN}OK${NC}"; else echo -e "${RED}MISSING${NC}"; fi
}

# --- ACTIONS ---

install_dependencies() {
    echo -e "${BLUE}>>> Checking Dependencies...${NC}"
    if ! command -v step &>/dev/null; then
        echo "Installing 'step' CLI..."
        ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m)
        if [[ "$ARCH" == "x86_64" ]]; then ARCH="amd64"; 
        elif [[ "$ARCH" == "aarch64" ]]; then ARCH="arm64"; fi
        
        VERSION=$(curl -s https://api.github.com/repos/smallstep/cli/releases/latest | grep tag_name | cut -d '"' -f 4 | sed 's/v//')
        wget -q "https://github.com/smallstep/cli/releases/download/v${VERSION}/step_linux_${VERSION}_${ARCH}.tar.gz" -O /tmp/step.tar.gz
        tar -xf /tmp/step.tar.gz -C /tmp
        mv /tmp/step_${VERSION}/bin/step /usr/local/bin/
        chmod +x /usr/local/bin/step
        rm -rf /tmp/step*
        echo -e "${GREEN}step CLI installed.${NC}"
    else
        echo -e "${GREEN}step CLI is present.${NC}"
    fi
}

bootstrap_trust() {
    echo -e "${BLUE}>>> Bootstrapping Trust...${NC}"
    install_dependencies
    
    if [ -z "$CA_URL" ] || [ -z "$FINGERPRINT" ]; then
        echo -e "${RED}Error: CA_URL and FINGERPRINT required.${NC}"
        return 1
    fi
    
    step ca bootstrap --ca-url "$CA_URL" --fingerprint "$FINGERPRINT" --force
    step certificate install "$STEP_PATH/certs/root_ca.crt"
    echo -e "${GREEN}Root CA installed to system store.${NC}"
}

enroll_ssh() {
    echo -e "${BLUE}>>> Enrolling SSH Host...${NC}"
    
    if [ -z "$TOKEN" ]; then
        echo -e "${RED}Error: Enrollment TOKEN required.${NC}"
        return 1
    fi
    
    # 1. Bootstrap first
    bootstrap_trust || return 1
    
    # 2. Configure SSH
    echo "Requesting Host Certificate..."
    step ssh config --host --token "$TOKEN" --force
    echo -e "${GREEN}SSH Configured.${NC}"
    
    # 3. Setup Renewal
    if [ "$ENABLE_RENEWAL" == "true" ]; then
        setup_renewal
    fi
    
    verify_cert
}

setup_renewal() {
    echo "Configuring Systemd Auto-Renewal..."
    cat <<EOF > "$SYSTEMD_DIR/step-ssh-renew.service"
[Unit]
Description=Renew Step SSH Host Certificate
After=network-online.target

[Service]
Type=oneshot
User=root
Environment=STEPPATH=$STEP_PATH
ExecStart=/usr/local/bin/step ssh renew --force $STEP_PATH/ssh/ssh_host_ecdsa_key-cert.pub $STEP_PATH/ssh/ssh_host_ecdsa_key
ExecStartPost=/usr/sbin/service ssh restart
EOF

    cat <<EOF > "$SYSTEMD_DIR/step-ssh-renew.timer"
[Unit]
Description=Timer for Step SSH Host Certificate Renewal

[Timer]
OnCalendar=weekly
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable --now step-ssh-renew.timer
    echo -e "${GREEN}Auto-renewal enabled.${NC}"
}

verify_cert() {
    echo -e "${BLUE}>>> Verifying Certificate...${NC}"
    CERT_FILE="/etc/ssh/ssh_host_ecdsa_key-cert.pub"
    
    if [ -f "$CERT_FILE" ]; then
        echo -e "Certificate File: ${GREEN}FOUND${NC} ($CERT_FILE)"
        echo "---------------------------------------------------"
        step ssh inspect "$CERT_FILE" | grep -E "Type:|Key ID:|Valid:|Issuer:"
        echo "---------------------------------------------------"
    else
        echo -e "${RED}Certificate file not found at $CERT_FILE${NC}"
    fi
    
    echo -n "Systemd Timer Status: "
    if systemctl is-active --quiet step-ssh-renew.timer; then
        echo -e "${GREEN}ACTIVE${NC}"
    else
        echo -e "${RED}INACTIVE${NC}"
    fi
}

edit_config() {
    echo "Updating Configuration..."
    read -p "CA URL [$CA_URL]: " new_url
    [ -n "$new_url" ] && CA_URL="$new_url"
    
    read -p "Fingerprint [$FINGERPRINT]: " new_fp
    [ -n "$new_fp" ] && FINGERPRINT="$new_fp"
    
    read -p "Token [$TOKEN]: " new_token
    [ -n "$new_token" ] && TOKEN="$new_token"
    
    read -p "Enable Renewal (true/false) [$ENABLE_RENEWAL]: " new_ren
    [ -n "$new_ren" ] && ENABLE_RENEWAL="$new_ren"
    
    save_env
}

uninstall() {
    echo -e "${RED}>>> Uninstalling...${NC}"
    systemctl disable --now step-ssh-renew.timer 2>/dev/null || true
    rm -f "$SYSTEMD_DIR/step-ssh-renew.service" "$SYSTEMD_DIR/step-ssh-renew.timer"
    systemctl daemon-reload
    
    if [ -f "$STEP_PATH/certs/root_ca.crt" ]; then
        step certificate uninstall "$STEP_PATH/certs/root_ca.crt" || true
    fi
    rm -rf "$STEP_PATH"
    echo -e "${GREEN}Uninstalled. (Check /etc/ssh/sshd_config manually for leftovers).${NC}"
}

# --- MAIN MENU ---

show_menu() {
    header() {
        clear
        echo "======================================"
        echo "   PKI Client Join Script"
        echo "======================================"
        echo -e "CA URL:      $(status_icon "$CA_URL") $CA_URL"
        echo -e "Fingerprint: $(status_icon "$FINGERPRINT") ${FINGERPRINT:0:10}..."
        echo -e "Token:       $(status_icon "$TOKEN") ${TOKEN:0:10}..."
        echo -e "Auto-Renew:  $ENABLE_RENEWAL"
        echo "======================================"
    }

    while true; do
        header
        echo "1. Edit Configuration / Load .env"
        echo "2. Bootstrap Trust Only (Root CA)"
        echo "3. Enroll as SSH Host (Full Setup)"
        echo "4. Verify Certificate & Status"
        echo "5. Uninstall"
        echo "6. Exit"
        echo "--------------------------------------"
        read -p "Select [1-6]: " choice
        
        case $choice in
            1) edit_config ;;
            2) bootstrap_trust; read -p "Press Enter..." ;;
            3) enroll_ssh; read -p "Press Enter..." ;;
            4) verify_cert; read -p "Press Enter..." ;;
            5) uninstall; read -p "Press Enter..." ;;
            6) exit 0 ;;
            *) echo "Invalid option"; sleep 1 ;;
        esac
    done
}

# STARTUP
check_root
load_env

# CLI Args or Menu
if [ "$#" -gt 0 ]; then
    case $1 in
        ssh-host) enroll_ssh ;;
        trust) bootstrap_trust ;;
        verify) verify_cert ;;
        driver) install_dependencies ;; 
        uninstall) uninstall ;;
        *) echo "Usage: $0 {ssh-host|trust|verify|uninstall}" ;;
    esac
else
    show_menu
fi
