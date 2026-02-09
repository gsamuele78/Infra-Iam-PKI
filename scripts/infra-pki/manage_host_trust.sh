#!/bin/bash
set -euo pipefail

# Script to manage Trust of the Step-CA Root Certificate on the host
# Supports: Debian/Ubuntu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CA_CERT_PATH="$SCRIPT_DIR/../../infra-pki/step_data/certs/root_ca.crt"
FINGERPRINT_PATH="$SCRIPT_DIR/../../infra-pki/step_data/fingerprint"
SYSTEM_TRUST_DIR="/usr/local/share/ca-certificates"
TRUSTED_CERT_NAME="internal-infra-root-ca.crt"

check_root_user() {
    if [ "$EUID" -ne 0 ]; then
        echo "Please run as root (use sudo)."
        exit 1
    fi
}

install_trust() {
    echo "Installing Root CA to system trust store..."
    if [ ! -f "$CA_CERT_PATH" ]; then
        echo "Error: Root CA certificate not found at $CA_CERT_PATH"
        echo "Ensure the infra-pki container has initialized and generated certificates."
        exit 1
    fi

    cp "$CA_CERT_PATH" "$SYSTEM_TRUST_DIR/$TRUSTED_CERT_NAME"
    chmod 644 "$SYSTEM_TRUST_DIR/$TRUSTED_CERT_NAME"
    update-ca-certificates
    echo "Success: Certificate installed and trust store updated."
    
    if [ -f "$FINGERPRINT_PATH" ]; then
        echo "Fingerprint: $(cat "$FINGERPRINT_PATH")"
    fi
}

uninstall_trust() {
    echo "Removing Root CA from system trust store..."
    if [ -f "$SYSTEM_TRUST_DIR/$TRUSTED_CERT_NAME" ]; then
        rm -f "$SYSTEM_TRUST_DIR/$TRUSTED_CERT_NAME"
        
        # Use --fresh to clean up symlinks completely (rebuilds from scratch)
        update-ca-certificates --fresh >/dev/null 2>&1
        
        # Verify removal
        if [ ! -f "$SYSTEM_TRUST_DIR/$TRUSTED_CERT_NAME" ]; then
             echo -e "\033[0;32mSuccess:\033[0m Certificate removed."
             echo "System Trust Store rebuilt (old links cleared)."
        else
             echo -e "\033[0;31mError:\033[0m Failed to remove certificate file."
        fi
    else
        echo "Certificate not found in trust store ($SYSTEM_TRUST_DIR/$TRUSTED_CERT_NAME)."
        echo "Nothing to remove."
    fi
}

show_menu() {
    echo "========================================"
    echo "  Infra-PKI Host Trust Manager"
    echo "========================================"
    echo "1. Install/Trust Root CA"
    echo "2. Uninstall/Remove Root CA"
    echo "3. View Root CA Fingerprint"
    echo "4. Exit"
    echo "========================================"
    read -p "Select an option [1-4]: " choice
    case $choice in
        1) check_root_user; install_trust ;;
        2) check_root_user; uninstall_trust ;;
        3) 
            INSTALLED_CERT="$SYSTEM_TRUST_DIR/$TRUSTED_CERT_NAME"
            echo ""
            echo "--- Installed Certificate (System Trust Store) ---"
            
            if [ -f "$INSTALLED_CERT" ]; then
                echo "Status: INSTALLED"
                echo "Path:   $INSTALLED_CERT"
                echo ""
                if command -v openssl &>/dev/null; then
                    # Get Cert Details
                    openssl x509 -in "$INSTALLED_CERT" -noout -subject -issuer -dates
                    echo "Fingerprint (SHA256):"
                    openssl x509 -in "$INSTALLED_CERT" -noout -fingerprint -sha256 | cut -d= -f2
                else
                    echo "OpenSSL not found. Cannot display details."
                fi
            else
                echo "Status: NOT INSTALLED"
                echo "Expected Path: $INSTALLED_CERT"
            fi
            
            echo ""
            echo "--- Source Certificate (Step-CA) ---"
            if [ -f "$FINGERPRINT_PATH" ]; then
                echo "Expected Fingerprint: $(cat "$FINGERPRINT_PATH")"
            else
                 echo "Fingerprint file not found (step-ca might not be ready)."
            fi
            echo "------------------------------------"
            ;;
        4) exit 0 ;;
        *) echo "Invalid option." ;;
    esac
}

# Main logic
if [ $# -eq 0 ]; then
    while true; do
        show_menu
        echo ""
        read -p "Press Enter to continue..."
    done
else
    # Non-interactive mode args
    case $1 in
        install) check_root_user; install_trust ;;
        uninstall) check_root_user; uninstall_trust ;;
        *) echo "Usage: $0 {install|uninstall} or run without args for menu." ;;
    esac
fi
