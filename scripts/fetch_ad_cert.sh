#!/bin/bash
set -euo pipefail

# Script to fetch AD CA certificate for LDAPS trust
# Usage: ./fetch_ad_cert.sh <ad_host> <port> [output_file]

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <ad_host> <port> [output_file]"
    echo "Example: $0 ad.biome.unibo.it 636 ad_root_ca.crt"
    exit 1
fi

AD_HOST=$1
AD_PORT=$2
OUTPUT_FILE=${3:-ad_root_ca.crt}

echo "Fetching certificate chain from ${AD_HOST}:${AD_PORT}..."

# Fetch certs, show them, and save the last one (usually root or the specific server cert if self-signed chain)
# We rely on openssl. Note: This saves the whole chain usually.
echo | openssl s_client -showcerts -connect "${AD_HOST}:${AD_PORT}" 2>/dev/null | awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/{ print $0 }' > "$OUTPUT_FILE"

if [ -s "$OUTPUT_FILE" ]; then
    echo "Certificate saved to $OUTPUT_FILE"
    echo "You can mount this file in Keycloak/other services to enable LDAPS trust."
else
    echo "Error: Verification failed or no certificate retrieved."
    rm -f "$OUTPUT_FILE"
    exit 1
fi
