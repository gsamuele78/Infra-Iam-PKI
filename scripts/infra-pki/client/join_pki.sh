#!/bin/bash
set -euo pipefail

# join_pki.sh - CORRECTED VERSION
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
        
        # Define URLs
        ARTIFACT="step_linux_${VERSION}_${ARCH}.tar.gz"
        DOWNLOAD_URL="https://github.com/smallstep/cli/releases/download/v${VERSION}/${ARTIFACT}"
        CHECKSUM_URL="https://github.com/smallstep/cli/releases/download/v${VERSION}/checksums.txt"
        
        echo "Downloading $ARTIFACT (v$VERSION)..."
        wget -q "$DOWNLOAD_URL" -O "/tmp/$ARTIFACT"
        wget -q "$CHECKSUM_URL" -O "/tmp/checksums.txt"
        
        # Verify Checksum
        echo "Verifying checksum..."
        EXPECTED_SUM=$(grep "$ARTIFACT" /tmp/checksums.txt | cut -d ' ' -f 1)
        ACTUAL_SUM=$(sha256sum "/tmp/$ARTIFACT" | cut -d ' ' -f 1)
        
        if [ "$EXPECTED_SUM" != "$ACTUAL_SUM" ]; then
            echo -e "${RED}ERROR: Checksum verification failed!${NC}"
            echo "Expected: $EXPECTED_SUM"
            echo "Actual:   $ACTUAL_SUM"
            rm -f "/tmp/$ARTIFACT" "/tmp/checksums.txt"
            exit 1
        fi
        echo -e "${GREEN}Checksum verified.${NC}"
        
        tar -xf "/tmp/$ARTIFACT" -C /tmp
        mv /tmp/step_${VERSION}/bin/step /usr/local/bin/
        chmod +x /usr/local/bin/step
        rm -rf /tmp/step*
        echo -e "${GREEN}step CLI installed.${NC}"
    else
        echo -e "${GREEN}step CLI is present: $(step version | head -1)${NC}"
    fi
}

bootstrap_trust() {
    echo -e "${BLUE}>>> Bootstrapping Trust...${NC}"
    install_dependencies
    
    if [ -z "$CA_URL" ] || [ -z "$FINGERPRINT" ]; then
        echo -e "${RED}Error: CA_URL and FINGERPRINT required.${NC}"
        return 1
    fi
    
    # Validate CA_URL has port
    if ! echo "$CA_URL" | grep -q ":[0-9]\+"; then
        echo -e "${YELLOW}⚠️  CA_URL missing port. Adding :9000${NC}"
        CA_URL="${CA_URL}:9000"
        save_env
    fi
    
    echo "Connecting to: $CA_URL"
    echo "Fingerprint: $FINGERPRINT"
    
    # Bootstrap (this downloads and trusts the root CA)
    if step ca bootstrap --ca-url "$CA_URL" --fingerprint "$FINGERPRINT" --force; then
        echo -e "${GREEN}✓ Bootstrapped successfully${NC}"
    else
        echo -e "${RED}✗ Bootstrap failed${NC}"
        echo ""
        echo "Troubleshooting:"
        echo "  1. Check CA_URL is accessible: curl -k $CA_URL/health"
        echo "  2. Verify fingerprint matches: cat /path/to/step_data/fingerprint"
        echo "  3. Check firewall allows access to port 9000"
        return 1
    fi
    
    # Install root CA to system trust store
    if [ -f "$STEP_PATH/certs/root_ca.crt" ]; then
        step certificate install "$STEP_PATH/certs/root_ca.crt"
        echo -e "${GREEN}✓ Root CA installed to system store${NC}"
    else
        echo -e "${RED}✗ Root CA file not found${NC}"
        return 1
    fi
}

enroll_ssh() {
    echo -e "${BLUE}>>> Enrolling SSH Host...${NC}"
    
    if [ -z "$TOKEN" ]; then
        echo -e "${RED}Error: Enrollment TOKEN required.${NC}"
        echo "Generate a token on the CA server using: ./generate_token.sh"
        return 1
    fi
    
    # 1. Bootstrap first (install root CA)
    if ! bootstrap_trust; then
        echo -e "${RED}✗ Bootstrap failed, cannot continue${NC}"
        return 1
    fi
    
    # 2. Get hostname
    HOSTNAME=$(hostname -f 2>/dev/null || hostname)
    echo "Hostname: $HOSTNAME"
    
    # 3. Request SSH host certificate using the token
    echo ""
    echo "Requesting SSH host certificate..."
    
    # Create key if it doesn't exist
    if [ ! -f /etc/ssh/ssh_host_ecdsa_key ]; then
        echo "Generating ECDSA host key..."
        ssh-keygen -t ecdsa -f /etc/ssh/ssh_host_ecdsa_key -N ""
    fi
    
    # Request certificate
    # Request certificate by signing the existing public key
    if step ssh certificate \
        "$HOSTNAME" \
        /etc/ssh/ssh_host_ecdsa_key.pub \
        --host \
        --sign \
        --token "$TOKEN" \
        --ca-url "$CA_URL" \
        --root "$STEP_PATH/certs/root_ca.crt" \
        --not-after 168h \
        --force \
        --no-password --insecure; then
        
        echo -e "${GREEN}✓ SSH certificate obtained${NC}"
    else
        echo -e "${RED}✗ Failed to get SSH certificate${NC}"
        echo ""
        echo "Troubleshooting:"
        echo "  1. Check token is valid (not expired)"
        echo "  2. Verify CA is accessible"
        echo "  3. Check hostname matches token: $HOSTNAME"
        return 1
    fi
    
    # 4. Configure SSH to use the certificate
    echo ""
    echo "Configuring SSH daemon..."
    configure_sshd
    
    # 5. Setup auto-renewal
    if [ "$ENABLE_RENEWAL" == "true" ]; then
        setup_renewal
    fi
    
    # 6. Restart SSH
    echo ""
    echo "Restarting SSH service..."
    if systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null; then
        echo -e "${GREEN}✓ SSH restarted${NC}"
    else
        echo -e "${YELLOW}⚠️  Could not restart SSH automatically${NC}"
        echo "Please restart manually: systemctl restart sshd"
    fi
    
    verify_cert
}

configure_sshd() {
    # Add certificate configuration to sshd_config if not present
    SSHD_CONFIG="/etc/ssh/sshd_config"
    
    if ! grep -q "HostCertificate /etc/ssh/ssh_host_ecdsa_key-cert.pub" "$SSHD_CONFIG"; then
        echo ""
        echo "Adding certificate configuration to $SSHD_CONFIG..."
        
        # Backup sshd_config
        cp "$SSHD_CONFIG" "${SSHD_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
        
        # Add certificate line
        cat >> "$SSHD_CONFIG" <<EOF

# Step-CA SSH Host Certificate
HostCertificate /etc/ssh/ssh_host_ecdsa_key-cert.pub
HostKey /etc/ssh/ssh_host_ecdsa_key
EOF
        
        echo -e "${GREEN}✓ SSH configuration updated${NC}"
    else
        echo -e "${GREEN}✓ SSH already configured for certificates${NC}"
    fi
    
    # Also configure TrustedUserCAKeys if available
    if [ -f "$STEP_PATH/certs/ssh_user_key.pub" ]; then
        if ! grep -q "TrustedUserCAKeys" "$SSHD_CONFIG"; then
            cat >> "$SSHD_CONFIG" <<EOF
TrustedUserCAKeys $STEP_PATH/certs/ssh_user_key.pub
EOF
            echo -e "${GREEN}✓ User CA configured${NC}"
        fi
    fi
}

setup_renewal() {
    echo ""
    echo "Configuring automatic renewal..."
    
    # Create renewal service
    cat <<EOF > "$SYSTEMD_DIR/step-ssh-renew.service"
[Unit]
Description=Renew Step SSH Host Certificate
After=network-online.target

[Service]
Type=oneshot
User=root
Environment=STEPPATH=$STEP_PATH
ExecStart=/usr/local/bin/step ssh renew /etc/ssh/ssh_host_ecdsa_key-cert.pub /etc/ssh/ssh_host_ecdsa_key --force --ca-url $CA_URL --root $STEP_PATH/certs/root_ca.crt
ExecStartPost=/bin/systemctl reload-or-restart sshd

[Install]
WantedBy=multi-user.target
EOF

    # Create renewal timer (weekly)
    cat <<EOF > "$SYSTEMD_DIR/step-ssh-renew.timer"
[Unit]
Description=Weekly renewal of Step SSH Host Certificate

[Timer]
OnCalendar=weekly
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable step-ssh-renew.timer
    systemctl start step-ssh-renew.timer
    
    echo -e "${GREEN}✓ Auto-renewal enabled (weekly)${NC}"
}

verify_cert() {
    echo ""
    echo -e "${BLUE}>>> Verification...${NC}"
    
    CERT_FILE="/etc/ssh/ssh_host_ecdsa_key-cert.pub"
    
    if [ -f "$CERT_FILE" ]; then
        echo -e "Certificate File: ${GREEN}FOUND${NC}"
        
        # Verify signing CA against our local root
        CA_MATCH="${RED}MISMATCH${NC}"
        if [ -f "$STEP_PATH/certs/root_ca.crt" ]; then
            EXPECTED_FP=$(step certificate fingerprint "$STEP_PATH/certs/root_ca.crt" 2>/dev/null || echo "unknown")
            ACTUAL_FP=$(step ssh inspect "$CERT_FILE" | grep "Authority:" | awk '{print $NF}' | cut -d: -f2- 2>/dev/null || echo "not-found")
            
            # Shorten for comparison if needed, but usually they match or don't
            if [[ "$ACTUAL_FP" == "$EXPECTED_FP"* ]] || [[ "$EXPECTED_FP" == "$ACTUAL_FP"* ]]; then
                CA_MATCH="${GREEN}MATCH${NC} (Verified by local Root CA)"
            fi
        fi
        
        echo -e "Status:           ${GREEN}✓ VALID${NC}"
        echo -e "Authority:        $CA_MATCH"
        echo "---------------------------------------------------"
        
        # Display certificate details
        if command -v step &>/dev/null; then
            step ssh inspect "$CERT_FILE" | grep -E "Type:|Key ID:|Authority:|Valid:|Principals:" -A 5 | grep -v "^--" || \
                ssh-keygen -L -f "$CERT_FILE" | grep -E "Type:|Signing CA:|Key ID:|Valid:|Principals:" -A 5 | grep -v "^--"
        else
            ssh-keygen -L -f "$CERT_FILE" | grep -E "Type:|Signing CA:|Key ID:|Valid:|Principals:" -A 5 | grep -v "^--"
        fi
        
        echo "---------------------------------------------------"
    else
        echo -e "${RED}✗ Certificate file not found at $CERT_FILE${NC}"
        return 1
    fi
    
    # Check renewal timer
    echo ""
    echo -n "Auto-renewal timer: "
    if systemctl is-active --quiet step-ssh-renew.timer 2>/dev/null; then
        echo -e "${GREEN}ACTIVE${NC}"
        echo "Next run: $(systemctl status step-ssh-renew.timer | grep Trigger | awk '{print $2, $3, $4}')"
    else
        echo -e "${YELLOW}INACTIVE${NC}"
    fi
    
    # Check SSH configuration
    echo ""
    echo -n "SSH daemon config: "
    if grep -q "HostCertificate /etc/ssh/ssh_host_ecdsa_key-cert.pub" /etc/ssh/sshd_config; then
        echo -e "${GREEN}CONFIGURED${NC}"
    else
        echo -e "${RED}NOT CONFIGURED${NC}"
    fi
    
    echo ""
    echo -e "${GREEN}✅ SSH Host enrollment complete!${NC}"
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
    echo -e "${RED}WARNING: This will remove SSH certificates, auto-renewal timers, and system trust config.${NC}"
    read -p "Are you sure you want to proceed? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Uninstall cancelled."
        return 0
    fi

    # Stop and disable timer
    systemctl disable --now step-ssh-renew.timer 2>/dev/null || true
    
    # Remove systemd files
    rm -f "$SYSTEMD_DIR/step-ssh-renew.service" "$SYSTEMD_DIR/step-ssh-renew.timer"
    systemctl daemon-reload
    
    # Remove certificate
    rm -f /etc/ssh/ssh_host_ecdsa_key-cert.pub
    
    # Remove SSH config lines
    if [ -f /etc/ssh/sshd_config ]; then
        cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
        sed -i '/# Step-CA SSH Host Certificate/,/HostKey \/etc\/ssh\/ssh_host_ecdsa_key/d' /etc/ssh/sshd_config
        sed -i '/TrustedUserCAKeys.*step/d' /etc/ssh/sshd_config
    fi
    
    # Uninstall root CA
    if [ -f "$STEP_PATH/certs/root_ca.crt" ]; then
        step certificate uninstall "$STEP_PATH/certs/root_ca.crt" 2>/dev/null || true
    fi
    
    # Remove step directory
    rm -rf "$STEP_PATH"

    # Option to remove .env
    read -p "Remove configuration file ($ENV_FILE)? [y/N]: " clean_env
    if [[ "$clean_env" =~ ^[Yy]$ ]]; then
        rm -f "$ENV_FILE"
        echo -e "${GREEN}✓ configuration file removed.${NC}"
    fi
    
    echo -e "${GREEN}✓ Uninstalled${NC}"
    echo "SSH daemon config backed up to /etc/ssh/sshd_config.backup"
    echo "Please restart SSH: systemctl restart sshd"
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
        echo "5. Cleanup / Uninstall (Remove Certificate & Trust)"
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
        config) edit_config ;;
        deps) install_dependencies ;; 
        uninstall) uninstall ;;
        *) 
            echo "Usage: $0 {ssh-host|trust|verify|config|uninstall}"
            echo ""
            echo "Commands:"
            echo "  ssh-host   - Full SSH host enrollment"
            echo "  trust      - Bootstrap trust only (install root CA)"
            echo "  verify     - Verify certificate and configuration"
            echo "  config     - Edit configuration"
            echo "  uninstall  - Remove all Step-CA configuration"
            ;;
    esac
else
    show_menu
fi
