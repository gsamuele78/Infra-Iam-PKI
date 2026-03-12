#!/bin/bash
set -euo pipefail

# reset_ood.sh
# Purpose: Completely reset the Infra-OOD environment (Stop containers & Wipe Data)
# Location: scripts/infra-ood/reset_ood.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../infra-ood" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}=== DANGER: RESET INFRA-OOD ===${NC}"
echo "Target Directory: $PROJECT_DIR"
echo ""
echo "This action will:"
echo "  1. Stop and remove all Infra-OOD containers."
echo "  2. PERMANENTLY DELETE all local certificates and fetched data."
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
echo -e "${GREEN}1. Stopping containers...${NC}"
(cd "$PROJECT_DIR" && docker compose down -v) 2>/dev/null || echo "Docker compose down failed (maybe not running)."

echo ""
echo -e "${GREEN}2. Wiping data directories...${NC}"

echo "   Wiping certs..."
if [ -d "$PROJECT_DIR/certs" ]; then
    rm -rf "$PROJECT_DIR/certs" 2>/dev/null || sudo rm -rf "$PROJECT_DIR/certs"
fi
mkdir -p "$PROJECT_DIR/certs"

echo "   Wiping data..."
if [ -d "$PROJECT_DIR/data" ]; then
    rm -rf "$PROJECT_DIR/data" 2>/dev/null || sudo rm -rf "$PROJECT_DIR/data"
fi
mkdir -p "$PROJECT_DIR/data"

echo ""
echo -e "${GREEN}>>> RESET COMPLETE <<<${NC}"
