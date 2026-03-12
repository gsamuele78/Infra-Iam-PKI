#!/bin/bash
set -euo pipefail

# reset_iam.sh
# Reset completo dell'ambiente Infra-IAM: ferma i container e cancella tutti i dati.
# Location: scripts/infra-iam/reset_iam.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../infra-iam" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}=== DANGER: RESET INFRA-IAM ===${NC}"
echo "Target Directory: $PROJECT_DIR"
echo ""
echo "Questa operazione:"
echo "  1. Ferma e rimuove tutti i container Infra-IAM."
echo "  2. CANCELLA DEFINITIVAMENTE:"
echo "     certs/           (certificati PKI)"
echo "     data/db/         (database PostgreSQL)"
echo "     data/caddy/      (stato ACME/TLS Caddy)"
echo "     logs/            (tutti i log)"
echo ""
echo -e "${YELLOW}Operazione irreversibile.${NC}"
echo ""

read -rp "Sei sicuro? (scrivi 'yes' per confermare): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Annullato."
    exit 1
fi

if [ ! -d "$PROJECT_DIR" ]; then
    echo "Error: directory non trovata: $PROJECT_DIR"
    exit 1
fi

echo ""
echo -e "${GREEN}1. Fermo i container e rimuovo i volumi...${NC}"
(cd "$PROJECT_DIR" && docker compose down -v) 2>/dev/null \
    || echo "docker compose down fallito (forse già fermato)."

echo ""
echo -e "${GREEN}2. Cancello le directory dati...${NC}"

wipe_dir() {
    local rel="$1"
    local full="$PROJECT_DIR/$rel"
    echo "   Cancello $rel..."
    if [ -d "$full" ]; then
        rm -rf "$full" 2>/dev/null || sudo rm -rf "$full"
    fi
}

wipe_dir "certs"
wipe_dir "data/db"
wipe_dir "data/caddy"
wipe_dir "logs"

echo ""
echo -e "${GREEN}3. Ricreo la struttura directory vuota...${NC}"
# Le directory vengono ricreate vuote; deploy_iam.sh imposterà
# i permessi corretti al prossimo avvio.
mkdir -p "$PROJECT_DIR/certs"
mkdir -p "$PROJECT_DIR/data/db"
mkdir -p "$PROJECT_DIR/data/caddy"
mkdir -p "$PROJECT_DIR/logs/watchtower"
echo "   Struttura ricreata (permessi da impostare al prossimo deploy)."

echo ""
echo -e "${GREEN}>>> RESET COMPLETATO <<<${NC}"
echo "Per riavviare l'ambiente:"
echo "  cd $SCRIPT_DIR"
echo "  sudo ./deploy_iam.sh"
echo ""
