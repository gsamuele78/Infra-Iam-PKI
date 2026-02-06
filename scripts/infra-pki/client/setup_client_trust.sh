#!/bin/bash
set -euo pipefail

# Script to install the Root CA on a Linux client (Ubuntu/Debian)
# Usage: ./setup_client_trust.sh [ca_url] [fingerprint]

# Default Config
CA_URL=${1:-"https://ca.biome.unibo.it:9000"}
FINGERPRINT=${2:-}

usage() {
    echo "Usage: $0 [ca_url] [fingerprint]"
    echo "  ca_url:      URL of the Step CA (default: $CA_URL)"
    echo "  fingerprint: (Optional) Root CA Fingerprint for verification"
    exit 1
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
fi

echo "Setting up client trust for $CA_URL..."

# 1. Download Root CA
# We use curl directly here to avoid docker dependency on clients.
echo "Downloading roots.pem..."
if ! curl -k -sS "$CA_URL/roots.pem" -o /tmp/root_ca.crt; then
    echo "Error: Failed to download root certificate from $CA_URL/roots.pem"
    echo "Check connectivity or URL."
    exit 1
fi

if [ ! -s /tmp/root_ca.crt ]; then
    echo "Error: Downloaded root certificate is empty."
    exit 1
fi

# Validation
if [ -n "$FINGERPRINT" ]; then
    echo "Verifying Fingerprint..."
    if command -v openssl &>/dev/null; then
        # Calculate SHA256 fingerprint of the downloaded file
        # formatting: SHA256 Fingerprint=XX:XX...
        CALC_FP=$(openssl x509 -in /tmp/root_ca.crt -noout -fingerprint -sha256 | cut -d= -f2 | tr -d :)
        EXPECTED_FP=$(echo "$FINGERPRINT" | tr -d :)
        
        if [[ "${CALC_FP,,}" == "${EXPECTED_FP,,}" ]]; then
            echo -e "Fingerprint Match: \033[0;32mOK\033[0m"
        else
            echo "Error: Fingerprint Mismatch!"
            echo "Expected: $EXPECTED_FP"
            echo "Actual:   $CALC_FP"
            exit 1
        fi
    else
        echo "Warning: 'openssl' not found. Skipping fingerprint verification."
    fi
else
    echo "Warning: No fingerprint provided. Trusting server response implicitly (TOFU)."
fi

# 2. Install to OS Store
if [ -d "/usr/local/share/ca-certificates" ]; then
    # Debian/Ubuntu
    echo "Detected Debian/Ubuntu system."
    SRC_DIR="/usr/local/share/ca-certificates"
    CMD="update-ca-certificates"
    EXT="crt"
    sudo cp /tmp/root_ca.crt "$SRC_DIR/internal_ca.$EXT"
    sudo $CMD
elif [ -d "/etc/pki/ca-trust/source/anchors" ]; then
    # RHEL/Fedora/CentOS
    echo "Detected RHEL/CentOS system."
    SRC_DIR="/etc/pki/ca-trust/source/anchors"
    CMD="update-ca-trust extract"
    EXT="pem" # RHEL often prefers pem extension, though crt usually works
    sudo cp /tmp/root_ca.crt "$SRC_DIR/internal_ca.$EXT"
    sudo $CMD
else
    echo "Error: Unknown OS certificate store location. Install manually from /tmp/root_ca.crt"
    exit 1
fi

# 3. Verify
echo "Verifying trust..."
# Explicitly use curl with the installed CA store (default)
if curl -I "$CA_URL/health" 2>/dev/null; then
    echo "Success! Client now trusts the Internal CA."
else
    echo "Warning: CA Health Verification failed (curl -I). Check network/DNS."
fi
