#!/bin/bash
set -euo pipefail

# fetch_ad_info.sh
# Connects to an AD server via LDAPS (port 636) to:
# 1. Fetch the Certificate Chain
# 2. Extract the Root CA
# 3. Display the SHA256 Fingerprint

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <AD_HOST>"
    echo "Example: $0 dcrpersonale01.personale.dir.unibo.it"
    exit 1
fi

AD_HOST=$1
PORT=636
OUTPUT_CERT="ad_root_ca.crt"

echo "Connecting to $AD_HOST:$PORT..."

# Fetch the certificates
# We use echo | openssl to close the connection after handshake
# -showcerts prints the entire chain
echo | openssl s_client -showcerts -connect "$AD_HOST:$PORT" 2>/dev/null > /tmp/ad_chain.pem

if [ ! -s /tmp/ad_chain.pem ]; then
    echo "Error: Could not connect or fetch certificates from $AD_HOST"
    exit 1
fi

echo "Connection successful."
echo ""

# Extract the last certificate in the chain (usually the Root CA in a well-ordered chain)
# Or just taking the server cert if it's self-signed.
# For robust usage, we often want the Root CA. 
# This simple awk script extracts all certs.
awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/' /tmp/ad_chain.pem > /tmp/all_certs.pem

# Let's save them
mv /tmp/all_certs.pem "$OUTPUT_CERT"
echo "Saved certificate chain to: $OUTPUT_CERT"

# Calculate Fingerprint of the server certificate (the peer certificate)
# openssl s_client returns the peer cert by default if we don't use -showcerts, 
# but we used -showcerts.
# Let's cleanly get the peer cert for fingerprinting.
echo | openssl s_client -connect "$AD_HOST:$PORT" 2>/dev/null | openssl x509 -noout -fingerprint -sha256 > /tmp/ad_fingerprint.txt

FINGERPRINT=$(cat /tmp/ad_fingerprint.txt | cut -d= -f2)

echo "---------------------------------------------------"
echo "AD Server Fingerprint (SHA256):"
echo "$FINGERPRINT"
echo "---------------------------------------------------"
echo "Note: Use this fingerprint if you need to pin the certificate."
echo "Note: The file '$OUTPUT_CERT' contains the certificate chain."
echo "You can view it with: openssl x509 -in $OUTPUT_CERT -text -noout"
