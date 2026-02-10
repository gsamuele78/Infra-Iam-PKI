#!/bin/bash
set -euo pipefail

# renew_certificate.sh
# Handles initial enrollment (if missing) and renewal of certificates via Step-CA.
# Configuration is provided via environment variables (CA_URL, FINGERPRINT, STEP_TOKEN).

CRT_FILE="$1"
KEY_FILE="$2"

# 1. Parse Configuration
# CA_URL and FINGERPRINT should be passed as environment variables by Docker
: "${CA_URL:=${STEP_CA_URL:-https://step-ca:9000}}"
: "${FINGERPRINT:=${STEP_FINGERPRINT:-}}"

echo "Using CA_URL: $CA_URL"

# If no certificate exists, try initial enrollment
if [ ! -f "$CRT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
    echo "Certificate or Key missing. Attempting initial enrollment..."
    
    # Check for STEP_TOKEN environment variable
    if [ -z "${STEP_TOKEN:-}" ]; then
        echo "ERROR: STEP_TOKEN env var is missing."
        echo "Cannot enroll new certificate."
        exit 1
    fi

    echo "Enrolling with Step-CA..."
    step ca certificate "keycloak.internal" "$CRT_FILE" "$KEY_FILE" \
        --token "$STEP_TOKEN" \
        --ca-url "$CA_URL" \
        --fingerprint "$FINGERPRINT" \
        --force

    echo "Enrollment successful."
    chmod 644 "$CRT_FILE"
    chmod 600 "$KEY_FILE"
else
    # Certificate exists, check if it needs renewal
    echo "Checking for renewal..."
    
    # Check if FINGERPRINT is set, if so add it to the command
    FINGERPRINT_ARG=""
    if [ -n "$FINGERPRINT" ]; then
        FINGERPRINT_ARG="--fingerprint=$FINGERPRINT"
    fi

    step ca renew "$CRT_FILE" "$KEY_FILE" \
        --ca-url "$CA_URL" \
        $FINGERPRINT_ARG \
        --force 2>/dev/null || echo "Certificate not yet ready for renewal or renewal failed."
fi
