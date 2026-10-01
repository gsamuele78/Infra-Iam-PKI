#!/bin/bash
set -euo pipefail

# scripts/infra-pki/renew_certificate.sh
# Renew a certificate with Step CA, from cron or by hand. Runs step-cli in a
# container, so the host only needs docker.
#
# Usage: ./renew_certificate.sh <crt_file> <key_file>
#
# Environment:
#   STEP_CA_URL / DOMAIN_CA   CA URL (default https://localhost:9000)
#   ROOT_CA_FILE              root used for TLS to the CA (default: root_ca.crt next to
#                             the cert). Fetch it once with `step ca root --fingerprint`.
#   RENEW_EXPIRES_IN          renew when less than this is left (default 33%)
#
# Exit codes: 0 renewed | 10 still valid, nothing done | 2 cert/key missing (skipped)
#             | 1 error. 'step ca renew' has no --fingerprint flag: trust is --root.

for _bin in docker realpath; do
    command -v "$_bin" >/dev/null 2>&1 || { echo "ERROR: required binary '$_bin' not found" >&2; exit 1; }
done

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <crt_file> <key_file>"
    exit 1
fi

CRT_FILE=$(realpath "$1")
KEY_FILE=$(realpath "$2")
# Priority: STEP_CA_URL -> https://DOMAIN_CA:9000 -> https://localhost:9000
if [ -n "${STEP_CA_URL:-}" ]; then
    CA_URL="$STEP_CA_URL"
elif [ -n "${DOMAIN_CA:-}" ]; then
    CA_URL="https://${DOMAIN_CA}:9000"
else
    CA_URL="https://localhost:9000"
fi
ROOT_CA_FILE="${ROOT_CA_FILE:-$(dirname "$CRT_FILE")/root_ca.crt}"
RENEW_EXPIRES_IN="${RENEW_EXPIRES_IN:-33%}"
STEP_CLI_IMAGE="smallstep/step-cli:0.29.0"

if [ ! -f "$CRT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
    echo "Warning: Certificate or Key file not found ($CRT_FILE). Skipping."
    exit 2
fi
if [ ! -s "$ROOT_CA_FILE" ]; then
    echo "ERROR: root CA '$ROOT_CA_FILE' missing. Fetch it with:" >&2
    echo "  step ca root '$ROOT_CA_FILE' --ca-url '$CA_URL' --fingerprint <fingerprint>" >&2
    exit 1
fi
ROOT_CA_FILE=$(realpath "$ROOT_CA_FILE")

step_cli() {
    docker run --rm \
        --network host \
        -v "$(dirname "$CRT_FILE")":/home/step \
        -v "$ROOT_CA_FILE":/run/step-root/root_ca.crt:ro \
        --user "$(id -u):$(id -g)" \
        "$STEP_CLI_IMAGE" step "$@"
}

CRT_IN="/home/step/$(basename "$CRT_FILE")"
KEY_IN="/home/step/$(basename "$KEY_FILE")"

echo "Checking expiration for $CRT_FILE..."
# needs-renewal: 0 = renew now, 1 = still valid, other = error.
rc=0
step_cli certificate needs-renewal "$CRT_IN" --expires-in "$RENEW_EXPIRES_IN" >/dev/null 2>&1 || rc=$?
case "$rc" in
    0) ;;
    1) echo "Certificate still valid (more than $RENEW_EXPIRES_IN left)."; exit 10 ;;
    *) echo "ERROR: cannot evaluate $CRT_FILE (needs-renewal exit $rc)." >&2; exit 1 ;;
esac

if ! step_cli ca renew "$CRT_IN" "$KEY_IN" \
        --ca-url "$CA_URL" --root /run/step-root/root_ca.crt --force; then
    echo "ERROR: renewal failed (see the step output above)." >&2
    exit 1
fi
echo "Certificate renewed."
exit 0
