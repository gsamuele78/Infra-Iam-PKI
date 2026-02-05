#!/bin/bash
set -euo pipefail

# Script to renew a certificate using Step CA
# Usage: ./renew_certificate.sh <crt_file> <key_file>
# Can be run via Cron. Expects files to be owned by the user running docker (or fix permissions after).

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <crt_file> <key_file>"
    exit 1
fi

CRT_FILE=$(realpath "$1")
KEY_FILE=$(realpath "$2")
CA_URL="https://ca.biome.unibo.it:9000"

# Check if file exists
if [ ! -f "$CRT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
    echo "Warning: Certificate or Key file not found ($CRT_FILE). Skipping."
    exit 2
fi

echo "Checking expiration for $CRT_FILE..."
# Check if needs renewal (e.g., expires in < 24h). 
# 'step ca renew' automatically checks if it needs renewal (default ~66% of lifetime).
# It returns 0 if renewed, non-0 if failed or not needed? 
# Actually step ca renew errors if not needed unless --force is used, but we don't want to force everyday.
# We want "if renewed -> restart".
# Usage: step ca renew ... || exit_code

# We use --expires-in to force check? No, default behavior is good.
# Problem: 'step ca renew' might fail if not ready to renew.

# Better logic:
# 1. Check if eligible.
# 2. If yes, renew.
# 3. If renewed, return 0. Else return 2.

# For now, simplistic approach: use --force only if we determine it's close to expiry?
# Or just run it and capture output?

# If we run 'step ca renew', it updates the file in place.
# We can check timestamp before and after.

TS_BEFORE=$(stat -c %Y "$CRT_FILE")
docker run --rm \
    -v "$(dirname "$CRT_FILE")":/home/step \
    --user $(id -u):$(id -g) \
    smallstep/step-cli \
    step ca renew "/home/step/$(basename "$CRT_FILE")" "/home/step/$(basename "$KEY_FILE")" \
    --ca-url "$CA_URL" || true 
    # || true because it might fail if not renewable yet, and we don't want script to crash script

TS_AFTER=$(stat -c %Y "$CRT_FILE")

if [ "$TS_AFTER" -gt "$TS_BEFORE" ]; then
   echo "Certificate renewed."
   exit 0
else
   echo "Certificate not renewed (not needed or failed)."
   exit 2
fi
