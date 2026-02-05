#!/bin/bash
set -e

# reset_pki.sh
# Purpose: Completely reset the Infra-PKI environment (Stop containers & Wipe Data)
# Location: scripts/infra-pki/reset_pki.sh

# Resolve Project Root (../../infra-pki relative to this script)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../infra-pki" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}=== DANGER: RESET INFRA-PKI ===${NC}"
echo "Target Directory: $PROJECT_DIR"
echo ""
echo "This action will:"
echo "  1. Stop and remove all Infra-PKI containers."
echo "  2. PERMANENTLY DELETE all certificates, keys, and database data."
echo "     (Wiping 'step_data' and 'db_data')"
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
# Check if directories exist
if [ -d "$PROJECT_DIR/step_data" ]; then
    echo "   Removing contents of $PROJECT_DIR/step_data..."
    # We use sudo appropriately if current user doesn't have permission (likely owned by docker root/user)
    if [ -w "$PROJECT_DIR/step_data" ]; then
         rm -rf "$PROJECT_DIR/step_data/"*
    else
         echo "   (Requesting sudo for file cleanup)"
         sudo rm -rf "$PROJECT_DIR/step_data/"*
    fi
fi

if [ -d "$PROJECT_DIR/db_data" ]; then
    echo "   Removing contents of $PROJECT_DIR/db_data..."
    if [ -w "$PROJECT_DIR/db_data" ]; then
         rm -rf "$PROJECT_DIR/db_data/"*
    else
         sudo rm -rf "$PROJECT_DIR/db_data/"*
    fi
fi

echo ""
echo -e "${GREEN}>>> RESET COMPLETE <<<${NC}"
echo "You can now rebuild the environment:"
echo "  cd $PROJECT_DIR"
echo "  docker compose up --build"
echo ""
