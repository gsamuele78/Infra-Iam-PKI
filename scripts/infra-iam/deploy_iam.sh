#!/bin/bash
set -euo pipefail

# deploy_iam.sh
# Deployment script per Infra-IAM: crea filesystem, imposta permessi, avvia lo stack.
# Location: scripts/infra-iam/deploy_iam.sh
#
# Responsabilità:
#   1. Valida la configurazione (.env, docker-compose.yml, raggiungibilità CA)
#   2. Crea la struttura di directory bind-mount sul host con i permessi corretti
#   3. Builda le immagini Docker
#   4. Avvia lo stack (docker compose up -d)
#   5. Verifica lo stato post-deploy
#
# Struttura directory gestita (relativa a infra-iam/):
#   certs/              → certificati PKI  (chown PUID:PGID, chmod 750)
#   data/db/            → PostgreSQL data  (chown root:root, chmod 755)
#                          postgres:alpine gestisce internamente via gosu
#   data/caddy/         → Caddy ACME/TLS  (chown PUID:PGID, chmod 750)
#   logs/watchtower/    → log watchtower   (chown PUID:PGID, chmod 750)
#
# Nota: iam-init nel compose fa SOLO fetch_pki_root.sh (richiede step-cli
# dentro il container). Il filesystem setup è responsabilità di questo script.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IAM_DIR="$(cd "$SCRIPT_DIR/../../infra-iam" && pwd)"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}"
cat << "EOF"
╔═══════════════════════════════════════╗
║   Infra-IAM Deployment Script         ║
║   Keycloak + PostgreSQL + Caddy       ║
╚═══════════════════════════════════════╝
EOF
echo -e "${NC}"

if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}⚠ Non root: le operazioni chown potrebbero richiedere sudo.${NC}"
fi

# ---------------------------------------------------------------------------
# Step 1: Valida configurazione
# ---------------------------------------------------------------------------
echo -e "${BLUE}[Step 1/6] Validating configuration...${NC}"
chmod +x "$SCRIPT_DIR/validate_iam_config.sh"
if "$SCRIPT_DIR/validate_iam_config.sh" --pre-deploy; then
    echo -e "${GREEN}✓ Configuration validated${NC}"
else
    echo -e "${RED}✗ Configuration validation failed${NC}"
    read -rp "Continue anyway? (y/N) " reply
    [[ "$reply" =~ ^[Yy]$ ]] || exit 1
fi

# ---------------------------------------------------------------------------
# Step 2: Leggi PUID/PGID dal .env
# ---------------------------------------------------------------------------
PUID=$(grep "^PUID=" "$IAM_DIR/.env" | cut -d= -f2- | tr -d '"')
PGID=$(grep "^PGID=" "$IAM_DIR/.env" | cut -d= -f2- | tr -d '"')

if [ -z "$PUID" ] || [ -z "$PGID" ]; then
    echo -e "${RED}✗ PUID/PGID non trovati in .env — impossibile impostare i permessi.${NC}"
    exit 1
fi

# ---------------------------------------------------------------------------
# Step 3: Crea struttura directory e imposta permessi
# ---------------------------------------------------------------------------
echo -e "${BLUE}[Step 2/6] Creating directory structure and setting permissions...${NC}"

# certs/ — step-cli scrive root_ca.crt qui; keycloak/caddy leggono
mkdir -p "$IAM_DIR/certs"
chown -R "$PUID:$PGID" "$IAM_DIR/certs"
chmod 750 "$IAM_DIR/certs"
echo "  certs/              → $PUID:$PGID  chmod 750"

# data/db/ — postgres:alpine entrypoint richiede root per chown interno
mkdir -p "$IAM_DIR/data/db"
chown root:root "$IAM_DIR/data/db"
chmod 755 "$IAM_DIR/data/db"
echo "  data/db/            → root:root    chmod 755"

# data/caddy/ — caddy gira come PUID:PGID
mkdir -p "$IAM_DIR/data/caddy"
chown -R "$PUID:$PGID" "$IAM_DIR/data/caddy"
chmod 750 "$IAM_DIR/data/caddy"
echo "  data/caddy/         → $PUID:$PGID  chmod 750"

# logs/watchtower/
mkdir -p "$IAM_DIR/logs/watchtower"
chown -R "$PUID:$PGID" "$IAM_DIR/logs/watchtower"
chmod 750 "$IAM_DIR/logs/watchtower"
echo "  logs/watchtower/    → $PUID:$PGID  chmod 750"

# .env: leggibile solo da root/owner
chmod 600 "$IAM_DIR/.env"
echo "  .env                → chmod 600"

echo -e "${GREEN}✓ Directory structure ready${NC}"

# ---------------------------------------------------------------------------
# Step 4: Enrollment token (solo se non c'è già un certificato)
# ---------------------------------------------------------------------------
echo -e "${BLUE}[Step 3/6] Checking for enrollment token...${NC}"
CRT_FILE="$IAM_DIR/certs/keycloak.crt"
export STEP_TOKEN=""

if [ ! -f "$CRT_FILE" ]; then
    echo -e "${YELLOW}⚠ Certificato non trovato ($CRT_FILE)${NC}"
    echo "  Genera un token sul PKI host con: scripts/infra-pki/generate_token.sh"
    echo ""
    read -rp "  Incolla il token Step-CA (invio per saltare): " INPUT_TOKEN
    if [ -n "$INPUT_TOKEN" ]; then
        export STEP_TOKEN="$INPUT_TOKEN"
        echo -e "${GREEN}✓ Token acquisito — enrollment alla partenza.${NC}"
    else
        echo -e "${YELLOW}⚠ Nessun token. Lo stack partirà senza enrollment automatico.${NC}"
    fi
else
    echo -e "${GREEN}✓ Certificato esistente — enrollment non necessario.${NC}"
fi

# ---------------------------------------------------------------------------
# Step 5: Build immagini
# ---------------------------------------------------------------------------
echo -e "${BLUE}[Step 4/6] Building Docker images...${NC}"
cd "$IAM_DIR"
docker compose build
echo -e "${GREEN}✓ Images built${NC}"

# ---------------------------------------------------------------------------
# Step 6: Avvio stack
# ---------------------------------------------------------------------------
echo -e "${BLUE}[Step 5/6] Starting stack...${NC}"
STEP_TOKEN="${STEP_TOKEN}" docker compose up -d
echo -e "${GREEN}✓ Stack started${NC}"

# ---------------------------------------------------------------------------
# Step 7: Verifica post-deploy
# ---------------------------------------------------------------------------
echo -e "${BLUE}[Step 6/6] Post-deploy verification...${NC}"

echo "  Attendo Keycloak healthy (max 120s)..."
RETRIES=60
while [ "$RETRIES" -gt 0 ]; do
    if docker compose ps keycloak 2>/dev/null | grep -q "healthy"; then
        echo -e "${GREEN}✓ Keycloak healthy${NC}"
        break
    fi
    echo -n "."
    sleep 2
    (( RETRIES-- )) || true
done
[ "$RETRIES" -eq 0 ] && echo -e "\n${YELLOW}⚠ Keycloak non ancora healthy — controlla: docker compose logs keycloak${NC}"

if ! "$SCRIPT_DIR/validate_iam_config.sh" --post-deploy; then
    echo -e "${RED}✗ Post-deploy checks failed.${NC}"
    exit 1
fi

echo ""
docker compose ps

DOMAIN_SSO=$(grep "^DOMAIN_SSO=" "$IAM_DIR/.env" | cut -d= -f2- | tr -d '"')
echo ""
echo -e "${BLUE}=== Deployment Summary ===${NC}"
echo "  SSO URL  : https://$DOMAIN_SSO"
echo "  Admin    : admin  (password in .env KC_ADMIN_PASSWORD)"
echo ""
echo -e "${GREEN}✅ Deployment completed!${NC}"
