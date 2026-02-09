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
# --- Auto-Detect Admin Provisioner ---
echo "Detecting Admin Provisioner..."
# Try to list provisioners from the running container to find the Admin one
# We look for type "JWK" which usually implies the admin/default provisioner in this stack
DETECTED_PROV=$(docker exec step-ca step ca provisioner list 2>/dev/null | grep -B 5 '"type": "JWK"' | grep '"name":' | head -n 1 | cut -d'"' -f4)

if [ -n "$DETECTED_PROV" ]; then
    PROVISIONER="$DETECTED_PROV"
    echo "Auto-detected Provisioner: '$PROVISIONER'"
else
    PROVISIONER="Admin JWK" # Fallback default
    echo "Could not auto-detect. Using default: '$PROVISIONER'"
fi

# --- 1. Load Configuration ---
# Try to source .env files from typical locations
if [ -f "$WORKDIR/../infra-pki/.env" ]; then
    source "$WORKDIR/../infra-pki/.env"
elif [ -f "$WORKDIR/.env" ]; then
    source "$WORKDIR/.env"
fi

# Set defaults if not in .env
# Priority: STEP_CA_URL -> https://DOMAIN_CA:9000 -> https://localhost:9000
if [ -n "${STEP_CA_URL:-}" ]; then
    CA_URL="$STEP_CA_URL"
elif [ -n "${DOMAIN_CA:-}" ]; then
    CA_URL="https://${DOMAIN_CA}:9000"
else
    CA_URL="https://localhost:9000"
fi

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
# --- 3. Authentication (OTT) ---
echo "Generating One-Time Token (OTT)..."
if [ -z "$CA_PASSWORD" ]; then
    echo "Error: CA_PASSWORD is required to generate a token."
    read -sp "Enter CA Provisioner Password: " CA_PASSWORD
    echo
fi

# Generate Token using Docker
# Must use host network to reach localhost:9000 if that's where CA is
# Or use the specific network "infra-iam-pki_default" if available.
# --network host is simplest for a management script running on the host.

TOKEN=$(docker run --rm -i \
    --network host \
    smallstep/step-cli \
    sh -c "printf '%s' \"$CA_PASSWORD\" | step ca token $HOSTNAME --ca-url '$CA_URL' --root /dev/null --password-file /dev/stdin --provisioner '$PROVISIONER'")

echo "Requesting certificate for $HOSTNAME (SANs: $SANS)..."

# --- 4. Request Certificate ---
docker run --rm \
    --network host \
    -v "$CERT_DIR":/home/step \
    --user $(id -u):$(id -g) \
    smallstep/step-cli \
    step ca certificate "$HOSTNAME" /home/step/$HOSTNAME.crt /home/step/$HOSTNAME.key \
    --san "$SANS" \
    --token "$TOKEN" \
    --ca-url "$CA_URL" \
    --fingerprint "$FINGERPRINT"

echo "Done. Certificates saved in $CERT_DIR"
