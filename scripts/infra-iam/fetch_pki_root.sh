#!/bin/bash
set -euo pipefail

# fetch_pki_root.sh
# Fetches the Root CA certificate from a remote Step-CA server.
# Optimized for running inside 'step-cli' container (Native, no Docker wrap).

# Resolve Project Root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IAM_DIR="$(cd "$SCRIPT_DIR/../../infra-iam" && pwd)"

# Default Output
DEFAULT_OUTPUT="$IAM_DIR/certs/root_ca.crt"
# Use absolute path if provided, otherwise default. Inside container /certs/root_ca.crt is usually passed.
OUTPUT_FILE=${1:-$DEFAULT_OUTPUT}

# Load Environment from multiple possible locations
ENV_LOCATIONS=("/app/.env" "$IAM_DIR/.env")
for loc in "${ENV_LOCATIONS[@]}"; do
    if [ -f "$loc" ]; then
        echo "Loading env from $loc..."
        # Extract variables manually to avoid shell pollution or failures in restricted shells
        CA_URL=$(grep "^CA_URL=" "$loc" | cut -d= -f2- | tr -d '"' || echo "${CA_URL:-}")
        FINGERPRINT=$(grep "^FINGERPRINT=" "$loc" | cut -d= -f2- | tr -d '"' || echo "${FINGERPRINT:-}")
    fi
done

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
