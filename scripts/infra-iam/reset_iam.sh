#!/bin/bash
set -e

# reset_iam.sh
# Purpose: Completely reset the Infra-IAM environment (Stop containers & Wipe Data)
# Location: scripts/infra-iam/reset_iam.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../infra-iam" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}=== DANGER: RESET INFRA-IAM ===${NC}"
echo "Target Directory: $PROJECT_DIR"
echo ""
echo "This action will:"
echo "  1. Stop and remove all Infra-IAM containers and volumes."
echo "  2. PERMANENTLY DELETE all Keycloak data, database records, and certificates."
echo "     (Wiping 'keycloak_data', 'caddy_data', 'certs', and 'logs')"
echo ""
echo -e "${YELLOW}This cannot be undone.${NC}"
echo ""

read -rp "Are you sure you want to proceed? (type 'yes' to confirm): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 1
fi

if [ ! -d "$PROJECT_DIR" ]; then
    echo "Error: Project directory not found at $PROJECT_DIR"
    exit 1
fi

echo ""
echo -e "${GREEN}1. Stopping containers and removing volumes...${NC}"
(cd "$PROJECT_DIR" && docker compose down -v) 2>/dev/null || echo "Docker compose down failed (maybe already stopped)."

echo ""
echo -e "${GREEN}2. Wiping data directories...${NC}"

wipe_and_recreate() {
    local dir="$1"
    echo "   Wiping $dir..."
    if [ -d "$PROJECT_DIR/${dir:?}" ]; then
        rm -rf "$PROJECT_DIR/${dir:?}" 2>/dev/null || sudo rm -rf "$PROJECT_DIR/${dir:?}"
    fi
    mkdir -p "$PROJECT_DIR/${dir:?}"
}

wipe_and_recreate "keycloak_data"
wipe_and_recreate "caddy_data"
wipe_and_recreate "certs"
wipe_and_recreate "logs"
mkdir -p "$PROJECT_DIR/logs/watchtower"

echo ""
echo -e "${GREEN}>>> RESET COMPLETE <<<${NC}"
echo "You can now rebuild the environment:"
echo "  cd $SCRIPT_DIR"
echo "  sudo ./deploy_iam.sh"
echo ""
