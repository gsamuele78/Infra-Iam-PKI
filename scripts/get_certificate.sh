#!/bin/bash
set -euo pipefail

# Script to request a certificate from the internal PKI using Docker
# Usage: ./get_certificate.sh <hostname> [san1,san2,...]

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <hostname> [san1,san2,...]"
    exit 1
fi

HOSTNAME=$1
SANS=${2:-$HOSTNAME}
WORKDIR=$(pwd)
CERT_DIR="$WORKDIR/certs"
PROVISIONER="admin" # Default provisioner

# --- 1. Load Configuration ---
# Try to source .env files from typical locations
if [ -f "$WORKDIR/../infra-pki/.env" ]; then
    source "$WORKDIR/../infra-pki/.env"
elif [ -f "$WORKDIR/.env" ]; then
    source "$WORKDIR/.env"
fi

# Set defaults if not in .env
CA_URL="${CA_URL:-https://localhost:9000}"
CA_PASSWORD="${CA_PASSWORD:-}" # Required for OTT generation

# --- 2. Fingerprint Handling ---
if [ -z "${FINGERPRINT:-}" ]; then
    echo "FINGERPRINT not found in .env."
    # Attempt to fetch from CA (insecurely for verification)
    echo "Fetching CA root..."
    FETCHED_FINGERPRINT=$(docker run --rm smallstep/step-cli step ca root --ca-url "$CA_URL" /dev/null --insecure --print-fingerprint | tr -d '\r')
    
    if [ -z "$FETCHED_FINGERPRINT" ]; then
        echo "Error: Could not fetch fingerprint from $CA_URL"
        exit 1
    fi

    echo "Fetched Fingerprint: $FETCHED_FINGERPRINT"
    echo "CA URL: $CA_URL"
    
    read -p "Do you trust this fingerprint? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
    FINGERPRINT="$FETCHED_FINGERPRINT"
else
    echo "Using trusted FINGERPRINT from environment."
fi

mkdir -p "$CERT_DIR"

# --- 3. Authentication (OTT) ---
echo "Generating One-Time Token (OTT)..."
if [ -z "$CA_PASSWORD" ]; then
    echo "Error: CA_PASSWORD is required to generate a token."
    read -sp "Enter CA Provisioner Password: " CA_PASSWORD
    echo
fi

# Generate Token using Docker
# We pipe the password to avoid showing it in process list
TOKEN=$(docker run --rm -i \
    smallstep/step-cli \
    sh -c "step ca token $HOSTNAME --ca-url '$CA_URL' --root /dev/null --password-file /dev/stdin --provisioner '$PROVISIONER'" <<< "$CA_PASSWORD")

echo "Requesting certificate for $HOSTNAME (SANs: $SANS)..."

# --- 4. Request Certificate ---
docker run --rm \
    -v "$CERT_DIR":/home/step \
    --user $(id -u):$(id -g) \
    smallstep/step-cli \
    step ca certificate "$HOSTNAME" /home/step/$HOSTNAME.crt /home/step/$HOSTNAME.key \
    --san "$SANS" \
    --token "$TOKEN" \
    --ca-url "$CA_URL" \
    --fingerprint "$FINGERPRINT"

echo "Done. Certificates saved in $CERT_DIR"
