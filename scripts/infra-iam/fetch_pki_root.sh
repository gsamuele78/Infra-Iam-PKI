#!/bin/bash
set -euo pipefail

# fetch_pki_root.sh
# Fetches the Root CA certificate from a remote Step-CA server.
# Optimized for running inside 'step-cli' container (Native, no Docker wrap).

DEFAULT_OUTPUT="/certs/root_ca.crt"
OUTPUT_FILE=${1:-$DEFAULT_OUTPUT}

# Load Environment if present
if [ -f "/app/.env" ]; then
    set -a
    source /app/.env
    set +a
fi

# Args or Env
CA_URL=${CA_URL:-}
FINGERPRINT=${FINGERPRINT:-}

# Check Requirements
if [ -z "$CA_URL" ]; then
    echo "Error: CA_URL is not set (Arg or Env)."
    exit 1
fi

if [ -z "$FINGERPRINT" ]; then
    echo "Error: FINGERPRINT is not set (Arg or Env)."
    exit 1
fi

echo "Fetching Root CA from $CA_URL..."
echo "Fingerprint: $FINGERPRINT"

# step-cli is available natively in the iam-setup container
if ! command -v step &> /dev/null; then
    echo "Error: 'step' command not found. This script is meant to run inside iam-setup container."
    exit 1
fi

step ca root "$OUTPUT_FILE" --ca-url "$CA_URL" --fingerprint "$FINGERPRINT" --force

if [ -s "$OUTPUT_FILE" ]; then
    echo "Success: Root CA saved to $OUTPUT_FILE"
    # Ensure readable by services
    chmod 644 "$OUTPUT_FILE"
else
    echo "Error: Failed to fetch Root CA."
    exit 1
fi
