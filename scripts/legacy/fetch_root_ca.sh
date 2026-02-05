#!/bin/bash
set -euo pipefail

# Script to fetch the Root CA certificate from the internal PKI
# Usage: ./fetch_root_ca.sh [output_file]

OUTPUT_FILE=${1:-root_ca.crt}
WORKDIR=$(pwd)

# Load configuration
if [ -f "$WORKDIR/../../infra-pki/.env" ]; then
    source "$WORKDIR/../../infra-pki/.env"
elif [ -f "$WORKDIR/.env" ]; then
    source "$WORKDIR/.env"
fi

CA_URL="${CA_URL:-https://localhost:9000}"
FINGERPRINT="${FINGERPRINT:-}"

# Check for fingerprint file in infra-pki if not in env
if [ -z "$FINGERPRINT" ] && [ -f "$WORKDIR/../../infra-pki/step_data/fingerprint" ]; then
    FINGERPRINT=$(cat "$WORKDIR/../../infra-pki/step_data/fingerprint")
    echo "Found fingerprint in infra-pki/step_data: $FINGERPRINT"
fi

echo "Fetching Root CA from $CA_URL..."

if [ -n "$FINGERPRINT" ]; then
    echo "Verifying with fingerprint: $FINGERPRINT"
    docker run --rm smallstep/step-cli step ca root --ca-url "$CA_URL" --fingerprint "$FINGERPRINT" > "$OUTPUT_FILE"
else
    echo "WARNING: No fingerprint found. Fetching INSECURELY."
    echo "Requesting confirmation..."
    
    # Fetch print and ask
    TEMP_FP=$(docker run --rm smallstep/step-cli step ca root --ca-url "$CA_URL" /dev/null --insecure --print-fingerprint | tr -d '\r')
    echo "Server Fingerprint: $TEMP_FP"
    
    read -p "Trust this fingerprint? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
    # Download content
    docker run --rm smallstep/step-cli step ca root --ca-url "$CA_URL" --fingerprint "$TEMP_FP" > "$OUTPUT_FILE"
    
    # Auto-populate .env
    ENV_FILE=""
    if [ -f "$WORKDIR/.env" ]; then ENV_FILE="$WORKDIR/.env"; 
    elif [ -f "$WORKDIR/../infra-iam/.env" ]; then ENV_FILE="$WORKDIR/../infra-iam/.env"; fi
    
    if [ -n "$ENV_FILE" ]; then
        if grep -q "FINGERPRINT=" "$ENV_FILE"; then
            # Replace existing? explicit logic usually better. For now, inform user.
            echo "NOTE: FINGERPRINT already exists in $ENV_FILE. Please verify it matches: $TEMP_FP"
        else
            echo "" >> "$ENV_FILE"
            echo "FINGERPRINT=$TEMP_FP" >> "$ENV_FILE"
            echo "Updated $ENV_FILE with FINGERPRINT."
        fi
    fi
fi

echo "Root CA saved to $OUTPUT_FILE"
