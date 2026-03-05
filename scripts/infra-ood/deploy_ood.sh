#!/bin/bash
set -euo pipefail

# deploy_ood.sh
# Comprehensive deployment script for Infra-OOD
# Location: scripts/infra-ood/deploy_ood.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OOD_DIR="$(cd "$SCRIPT_DIR/../../infra-ood" && pwd)"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}"
cat << "EOF"
╔═══════════════════════════════════════╗
║   Infra-OOD Deployment Script         ║
║   Open OnDemand Portal                ║
╚═══════════════════════════════════════╝
EOF
echo -e "${NC}"

echo -e "${BLUE}[Step 1/3] Creating directory structure...${NC}"
mkdir -p "$OOD_DIR"/{certs,data}
echo -e "${GREEN}✓ Directories created${NC}"

echo ""
echo -e "${BLUE}[Step 2/3] Setting permissions...${NC}"
PUID=$(grep "^PUID=" "$OOD_DIR/.env" | cut -d= -f2- | tr -d '"' || echo "1000")
PGID=$(grep "^PGID=" "$OOD_DIR/.env" | cut -d= -f2- | tr -d '"' || echo "1000")

echo "  Applying ownership ($PUID:$PGID) to data and certs..."
if ! chown -R "$PUID:$PGID" "$OOD_DIR"/{certs,data} 2>/dev/null; then
    echo -e "${RED}✗ CRITICAL: Could not set ownership (requires sudo). Aborting to prevent container permission denied errors.${NC}"
    exit 1
fi
chmod 600 "$OOD_DIR/.env" 2>/dev/null || true
echo -e "${GREEN}✓ Permissions set${NC}"

echo ""
echo -e "${BLUE}[Step 3/3] Deploying services...${NC}"
cd "$OOD_DIR"
docker compose build
docker compose up -d

echo ""
echo -e "${GREEN}✅ Deployment completed!${NC}"
