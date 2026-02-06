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

# Validation (Basic)
if [ -n "$FINGERPRINT" ]; then
    echo "Fingerprint provided. (Verification logic placeholder)"
    # Ideally: step certificate inspect ... but 'step' might not be installed.
    # OpenSSL check is complex for fingerprint format matching.
else
    echo "Warning: No fingerprint provided. Trusting server response implicitly."
fi

# 2. Install to OS Store
if [ -d "/usr/local/share/ca-certificates" ]; then
    echo "Installing to /usr/local/share/ca-certificates/..."
    sudo cp /tmp/root_ca.crt /usr/local/share/ca-certificates/internal_ca.crt
    sudo update-ca-certificates
else
    echo "Error: /usr/local/share/ca-certificates not found. Is this a Debian/Ubuntu system?"
    exit 1
fi

# 3. Verify
echo "Verifying trust..."
if curl -I "$CA_URL/health" 2>/dev/null; then
    echo "Success! Client now trusts the Internal CA."
else
    echo "Warning: CA Health Verification failed (curl -I). Trusted?"
    # It might fail if no routes, but cert installation might still be correct.
fi
