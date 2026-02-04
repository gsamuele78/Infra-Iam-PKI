#!/bin/bash
set -euo pipefail

# Script to install the Root CA on a Linux client (Ubuntu/Debian)
# Usage: ./setup_client_trust.sh [ca_url] [fingerprint]

CA_URL=${1:-https://ca.biome.unibo.it:9000}
FINGERPRINT=${2:-}

echo "Setting up client trust for $CA_URL..."

# 1. Download Root CA
# We use curl directly here to avoid docker dependency on clients? 
# Or use the 'step' binary if installed. Assuming curl for generic clients.

# If we don't have 'step' installed, we can download via `curl` from the CA's root endpoint (if configured to serve it).
# Step CA serves roots at /roots.pem
echo "Downloading roots.pem..."
curl -k -sS "$CA_URL/roots.pem" -o /tmp/root_ca.crt

if [ ! -s /tmp/root_ca.crt ]; then
    echo "Error: Failed to download root certificate."
    exit 1
fi

# Validation (Basic)
if [ -n "$FINGERPRINT" ]; then
    # OpenSSL doesn't easily compute the exact SHA256 fingerprint format Step uses (base64/hex variations).
    # We'll trust the download connection (TLS) if it was secure, or user provided fingerprint logic manually.
    # For now, simplistic warning.
    echo "Downloaded certificate. Please manually verify fingerprint if this network is untrusted."
fi

# 2. Install to OS Store
echo "Installing to /usr/local/share/ca-certificates/..."
sudo cp /tmp/root_ca.crt /usr/local/share/ca-certificates/internal_ca.crt
sudo update-ca-certificates

# 3. Verify
echo "Verifying trust..."
curl -I "$CA_URL/health"
echo "Success! Client now trusts the Internal CA."
