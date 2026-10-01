#!/bin/bash
set -euo pipefail

# scripts/infra-iam/renew_certificate.sh
# Initial enrollment (if the cert/key are missing) and renewal of the Keycloak
# TLS certificate via Step-CA. Runs non-interactively inside iam-renewer.
#
# Usage: renew_certificate.sh <crt-file> <key-file>
#
# Environment:
#   CA_URL            Step-CA API URL (fallback STEP_CA_URL, then https://step-ca:9000)
#   ROOT_CA_FILE      Root CA for TLS to the CA. Default: <dir of crt-file>/root_ca.crt,
#                     written by iam-init after `step ca root --fingerprint` verification.
#   STEP_TOKEN / STEP_TOKEN_FILE   One-time token, needed only for the first enrollment.
#   RENEW_EXPIRES_IN  Renew when less than this is left (default 33%, i.e. at 2/3
#                     of the lifetime, the step-ca default).
#
# Exit codes (the caller restarts Keycloak only on 0):
#   0   a new certificate was written (enrolled or renewed)
#   10  certificate still valid, nothing to do
#   1   error (missing input, CA unreachable, renewal refused...)
#
# 'step ca certificate' and 'step ca renew' have no --fingerprint flag: trust
# comes from --root, and the root file itself was fingerprint-verified.

readonly EXIT_RENEWED=0
readonly EXIT_NOT_NEEDED=10
readonly EXIT_ERROR=1

if ! command -v step >/dev/null 2>&1; then
    echo "ERROR: required binary 'step' is not installed." >&2
    exit "$EXIT_ERROR"
fi

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <crt-file> <key-file>" >&2
    exit "$EXIT_ERROR"
fi

CRT_FILE="$1"
KEY_FILE="$2"
: "${CA_URL:=${STEP_CA_URL:-https://step-ca:9000}}"
: "${ROOT_CA_FILE:=$(dirname "$CRT_FILE")/root_ca.crt}"
: "${RENEW_EXPIRES_IN:=33%}"

echo "Using CA_URL: $CA_URL (root: $ROOT_CA_FILE)"

if [ ! -s "$ROOT_CA_FILE" ]; then
    echo "ERROR: root CA '$ROOT_CA_FILE' is missing or empty (iam-init must fetch it first)." >&2
    exit "$EXIT_ERROR"
fi

# --- Initial enrollment -----------------------------------------------------
if [ ! -f "$CRT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
    echo "Certificate or key missing. Attempting initial enrollment..."

    if [ -z "${STEP_TOKEN:-}" ] && [ -n "${STEP_TOKEN_FILE:-}" ] && [ -f "$STEP_TOKEN_FILE" ]; then
        STEP_TOKEN=$(tr -d '\n' < "$STEP_TOKEN_FILE")
        echo "Loaded STEP_TOKEN from $STEP_TOKEN_FILE."
    fi

    if [ -z "${STEP_TOKEN:-}" ]; then
        echo "ERROR: STEP_TOKEN (or STEP_TOKEN_FILE) is missing. Cannot enroll." >&2
        exit "$EXIT_ERROR"
    fi

    if ! step ca certificate "keycloak.internal" "$CRT_FILE" "$KEY_FILE" \
            --token "$STEP_TOKEN" \
            --ca-url "$CA_URL" \
            --root "$ROOT_CA_FILE" \
            --force; then
        echo "ERROR: enrollment failed (see the step output above)." >&2
        exit "$EXIT_ERROR"
    fi

    chmod 644 "$CRT_FILE"
    chmod 600 "$KEY_FILE"
    echo "Enrollment successful."
    exit "$EXIT_RENEWED"
fi

# --- Renewal ----------------------------------------------------------------
# needs-renewal: 0 = renew now, 1 = still valid, 2 = file missing, 255 = error.
rc=0
step certificate needs-renewal "$CRT_FILE" --expires-in "$RENEW_EXPIRES_IN" >/dev/null 2>&1 || rc=$?
case "$rc" in
    0)  ;;
    1)  echo "Certificate still valid (more than $RENEW_EXPIRES_IN left). Nothing to do."
        exit "$EXIT_NOT_NEEDED" ;;
    *)  echo "ERROR: cannot evaluate '$CRT_FILE' (needs-renewal exit $rc)." >&2
        exit "$EXIT_ERROR" ;;
esac

echo "Certificate is due for renewal. Renewing..."
if ! step ca renew "$CRT_FILE" "$KEY_FILE" \
        --ca-url "$CA_URL" \
        --root "$ROOT_CA_FILE" \
        --force; then
    echo "ERROR: renewal failed (see the step output above)." >&2
    exit "$EXIT_ERROR"
fi

chmod 644 "$CRT_FILE"
chmod 600 "$KEY_FILE"
echo "Renewal successful."
exit "$EXIT_RENEWED"
