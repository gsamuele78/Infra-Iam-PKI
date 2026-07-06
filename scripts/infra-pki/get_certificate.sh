#!/bin/bash
set -euo pipefail

# --- Dependency Assertions (HC-13) ---
for bin in docker grep; do
    if ! command -v "$bin" >/dev/null 2>&1; then
        echo "Error: required binary '$bin' is not installed." >&2
        exit 1
    fi
done

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
# Read config with the project-standard pattern (never source .env: unsafe
# with special characters in passwords). Exported env vars take precedence;
# .env only fills values that are unset/empty.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE=""
if [ -f "$SCRIPT_DIR/../../infra-pki/.env" ]; then
    ENV_FILE="$SCRIPT_DIR/../../infra-pki/.env"
elif [ -f "$WORKDIR/.env" ]; then
    ENV_FILE="$WORKDIR/.env"
fi

read_env() {
    [ -n "$ENV_FILE" ] || return 0
    grep "^$1=" "$ENV_FILE" | cut -d= -f2- | tr -d '"' || true
}

STEP_CA_URL="${STEP_CA_URL:-$(read_env STEP_CA_URL)}"
DOMAIN_CA="${DOMAIN_CA:-$(read_env DOMAIN_CA)}"
CA_PASSWORD="${CA_PASSWORD:-$(read_env CA_PASSWORD)}" # Required for OTT generation
FINGERPRINT="${FINGERPRINT:-$(read_env FINGERPRINT)}"

# Set defaults if not in .env
# Priority: STEP_CA_URL -> https://DOMAIN_CA:9000 -> https://localhost:9000
if [ -n "${STEP_CA_URL:-}" ]; then
    CA_URL="$STEP_CA_URL"
elif [ -n "${DOMAIN_CA:-}" ]; then
    CA_URL="https://${DOMAIN_CA}:9000"
else
    CA_URL="https://localhost:9000"
fi

# --- 2. Fingerprint Handling ---
if [ -z "${FINGERPRINT:-}" ]; then
    echo "FINGERPRINT not found in .env."
    # Attempt to fetch from CA (insecurely for verification)
    echo "Fetching CA root..."
    FETCHED_FINGERPRINT=$(docker run --rm smallstep/step-cli:0.29.0 step ca root --ca-url "$CA_URL" /dev/null --insecure --print-fingerprint | tr -d '\r')
    
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

# HC-04: write the password to a temp file — NEVER inline it in the docker
# command (it would leak via 'ps aux' and 'docker inspect').
# HC-14: trap guarantees cleanup on exit/error.
PASS_FILE=$(mktemp)
trap 'rm -f "$PASS_FILE"' EXIT ERR
chmod 600 "$PASS_FILE"
printf '%s' "$CA_PASSWORD" > "$PASS_FILE"

# Generate Token using Docker
# Must use host network to reach localhost:9000 if that's where CA is
# Or use the specific network "infra-iam-pki_default" if available.
# --network host is simplest for a management script running on the host.

TOKEN=$(docker run --rm \
    --network host \
    -v "$PASS_FILE":/run/secrets/ca_password:ro \
    smallstep/step-cli:0.29.0 \
    step ca token "$HOSTNAME" --ca-url "$CA_URL" --root /dev/null --password-file /run/secrets/ca_password --provisioner "$PROVISIONER")

echo "Requesting certificate for $HOSTNAME (SANs: $SANS)..."

# --- 4. Request Certificate ---
docker run --rm \
    --network host \
    -v "$CERT_DIR":/home/step \
    --user $(id -u):$(id -g) \
    smallstep/step-cli:0.29.0 \
    step ca certificate "$HOSTNAME" /home/step/$HOSTNAME.crt /home/step/$HOSTNAME.key \
    --san "$SANS" \
    --token "$TOKEN" \
    --ca-url "$CA_URL" \
    --fingerprint "$FINGERPRINT"

echo "Done. Certificates saved in $CERT_DIR"
