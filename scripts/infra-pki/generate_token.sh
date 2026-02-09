#!/bin/bash
set -euo pipefail
#
# generate_token.sh
# Run this on the CA server (infra-pki) to generate a standardized enrollment token.
#

WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../infra-pki" && pwd)"
SECRETS_DIR="$WORKDIR/secrets"
ENV_FILE="$WORKDIR/.env"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Helper to read env or secret
get_config() {
    local env_var=$1
    local secret_file=$2
    local val=""

    # 1. Try Secret File first
    if [ -f "$SECRETS_DIR/$secret_file" ]; then
        val=$(cat "$SECRETS_DIR/$secret_file")
    # 2. Try Env File
    elif [ -f "$ENV_FILE" ]; then
        val=$(grep "^$env_var=" "$ENV_FILE" | cut -d= -f2 || true)
    fi
    echo "$val"
}

header() {
    clear
    echo -e "${BLUE}=== Step CA Token Generator ===${NC}"
    echo "This script generates a one-time token for a remote host to join the PKI."
    echo ""
}

# 1. Gather Config
CA_URL="https://localhost:9000" # Default internal URL, maybe need public facing?
# Try to get public URL if possible, otherwise default to configured CA_DNS
DOMAIN_CA=$(get_config "DOMAIN_CA" "none")
if [ -n "$DOMAIN_CA" ]; then
    CA_URL="https://$DOMAIN_CA"
fi

# Get CA Fingerprint
FINGERPRINT_FILE="$WORKDIR/step_data/fingerprint"
if [ ! -f "$FINGERPRINT_FILE" ]; then
    echo -e "${RED}Error: Fingerprint file not found at $FINGERPRINT_FILE.${NC}"
    echo "Ensure the stack is running: docker compose up -d"
    exit 1
fi
FINGERPRINT=$(cat "$FINGERPRINT_FILE")

# Get SSH Provisioner Password
SSH_PASSWORD=$(get_config "SSH_HOST_PROVISIONER_PASSWORD" "ssh_host_password")

if [ -z "$SSH_PASSWORD" ] || [ "$SSH_PASSWORD" == "change_me_ssh_host_password" ]; then
    echo -e "${RED}Warning: SSH Host Provisioner Password not set or is default.${NC}"
    read -sp "Enter SSH Host Provisioner Password: " SSH_PASSWORD
    echo ""
fi

# 2. Input
header
read -p "Enter Remote Hostname (e.g., database-01): " HOSTNAME
if [ -z "$HOSTNAME" ]; then echo "Hostname required."; exit 1; fi

echo ""
echo "Select Token Type:"
echo "1. SSH Host (authorize host for SSH)"
# echo "2. User (authorize user for SSH - Future)"
echo ""
read -p "Choice [1]: " TYPE

# --- Auto-Detect SSH Provisioner ---
echo "Detecting SSH Provisioner..."

# Verify container is running first
if ! docker ps --format '{{.Names}}' | grep -q "^step-ca$"; then
    echo -e "${RED}Error: 'step-ca' container is not running.${NC}"
    echo "Please start the stack with: docker compose up -d"
    exit 1
fi

# Look for a provisioner that looks like an SSH Host JWK provisioner
# We use '|| true' to prevent script exit if grep finds nothing (set -e is active)
DETECTED_SSH_PROV=$(docker exec step-ca step ca provisioner list 2>/dev/null | grep -B 5 '"type": "JWK"' | grep '"name":' | grep "ssh-host" | head -n 1 | cut -d'"' -f4 || true)

if [ -n "$DETECTED_SSH_PROV" ]; then
    PROVISIONER="$DETECTED_SSH_PROV"
    echo "Auto-detected SSH Provisioner: '$PROVISIONER'"
else
    PROVISIONER="ssh-host-jwk" # Default fallback
    echo "Could not auto-detect SSH provisioner. Using default: '$PROVISIONER'"
fi

# 3. Generate
echo ""
echo "Generating token for '$HOSTNAME'..."

# We need to run step inside the container to ensure version match and network access if needed, 
# BUT 'step ca token' is offline if we have the provisioner password. 
# However, we don't have the provisioner KEY locally easily (it's in the volume).
# EASIEST: Generate via the running container asking the CA.
# BUT: 'step ca token' needs admin access or a provisioner password.

# Docker approach:
# Create a temporary file for the password to ensure security
PW_FILE=$(mktemp)
chmod 600 "$PW_FILE"
printf "%s" "$SSH_PASSWORD" > "$PW_FILE"

# Copy password to container to avoid stdin/TTY issues
# Use a unique temp filename to avoid collisions
CONTAINER_PW_FILE="/home/step/temp_token_pw_$(date +%s)"
docker cp "$PW_FILE" "step-ca:$CONTAINER_PW_FILE"
docker exec step-ca chown step:step "$CONTAINER_PW_FILE"

# Execute step ca token using the file inside the container
TOKEN=$(docker exec step-ca step ca token "$HOSTNAME" \
    --provisioner "$PROVISIONER" \
    --key /home/step/secrets/ssh_host_jwk_key \
    --password-file "$CONTAINER_PW_FILE" \
    --ssh \
    --host)

# Cleanup inside container
docker exec step-ca rm -f "$CONTAINER_PW_FILE"

# Cleanup local temp file
rm -f "$PW_FILE"

# 4. Output
echo -e "${GREEN}>>> Token Generated Successfully <<<${NC}"
echo ""
echo "----------------------------------------------------------------"
echo "CA URL:      $CA_URL"
echo "Fingerprint: $FINGERPRINT"
echo "Token:       $TOKEN"
echo "----------------------------------------------------------------"

# 5. Generate .env file
ENV_OUTPUT="${HOSTNAME}_join_pki.env"
cat <<EOF > "$ENV_OUTPUT"
# join_pki.env for $HOSTNAME
CA_URL="$CA_URL"
FINGERPRINT="$FINGERPRINT"
TOKEN="$TOKEN"
ENABLE_RENEWAL="true"
EOF

echo ""
echo -e "${GREEN}Generated config file: ${BLUE}$ENV_OUTPUT${NC}"
echo ""
echo "Next Steps:"
echo "1. Copy 'scripts/infra-pki/client/join_pki.sh' AND '$ENV_OUTPUT' to the remote host."
echo "2. Rename '$ENV_OUTPUT' to 'join_pki.env' on the remote host (place next to script)."
echo "3. Run: sudo ./join_pki.sh ssh-host"
echo ""
