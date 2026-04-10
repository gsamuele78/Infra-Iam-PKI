#!/bin/bash
set -euo pipefail

# deploy_rstudio.sh
# Deployment script per Infra-RStudio: valida, crea filesystem, builda, avvia.
# Location: scripts/infra-rstudio/deploy_rstudio.sh
#
# Responsabilità:
#   1. Valida la configurazione (.env, docker-compose.yml)
#   2. Crea la struttura di directory bind-mount sull'host
#   3. Verifica PKI trust (Root CA installata sull'host)
#   4. Builda le immagini Docker
#   5. Avvia lo stack (docker compose up -d)
#   6. Verifica lo stato post-deploy
#
# Nota: infra-rstudio usa network_mode:host — i container condividono
# lo stack di rete dell'host per il passthrough dei socket SSSD/Winbind.
# Questo è intenzionale e documentato come eccezione architetturale.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RSTUDIO_DIR="$(cd "$SCRIPT_DIR/../../infra-rstudio" && pwd)"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()   { echo -e "${BLUE}[DEPLOY]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
ok()    { echo -e "${GREEN}✓${NC} $1"; }

echo -e "${BLUE}"
cat << "EOF"
╔═══════════════════════════════════════╗
║   Infra-RStudio Deployment Script     ║
║   RStudio + Nginx + Telemetry         ║
╚═══════════════════════════════════════╝
EOF
echo -e "${NC}"

if [ "$EUID" -ne 0 ]; then
    warn "Non root: le operazioni chown potrebbero richiedere sudo."
fi

# ---------------------------------------------------------------------------
# Step 1: Validate configuration
# ---------------------------------------------------------------------------
echo -e "${BLUE}[Step 1/6] Validating configuration...${NC}"
if [ -f "$SCRIPT_DIR/validate_rstudio.sh" ]; then
    chmod +x "$SCRIPT_DIR/validate_rstudio.sh"
    if "$SCRIPT_DIR/validate_rstudio.sh" --pre-deploy; then
        ok "Configuration validated"
    else
        echo -e "${RED}✗ Configuration validation failed${NC}"
        read -rp "Continue anyway? (y/N) " reply
        [[ "$reply" =~ ^[Yy]$ ]] || exit 1
    fi
else
    warn "validate_rstudio.sh not found. Performing basic checks..."
    # Basic checks inline
    if [ ! -f "$RSTUDIO_DIR/.env" ]; then
        error ".env file not found at $RSTUDIO_DIR/.env"
    fi
    ok ".env file exists"
    command -v docker > /dev/null 2>&1 || error "docker not found"
    docker compose version > /dev/null 2>&1 || error "Docker Compose plugin not available"
    ok "Docker dependencies present"
fi

# ---------------------------------------------------------------------------
# Step 2: Read AUTH_BACKEND from .env (safe grep, no source)
# ---------------------------------------------------------------------------
echo -e "${BLUE}[Step 2/6] Reading configuration...${NC}"
AUTH_BACKEND=$(grep "^AUTH_BACKEND=" "$RSTUDIO_DIR/.env" | cut -d= -f2- | tr -d '"' || echo "")
HOST_DOMAIN=$(grep "^HOST_DOMAIN=" "$RSTUDIO_DIR/.env" | cut -d= -f2- | tr -d '"' || echo "")

if [ -z "$AUTH_BACKEND" ]; then
    warn "AUTH_BACKEND not set in .env — defaulting to 'sssd'"
    AUTH_BACKEND="sssd"
fi
ok "Backend: $AUTH_BACKEND | Domain: ${HOST_DOMAIN:-NOT SET}"

# ---------------------------------------------------------------------------
# Step 3: Check PKI Trust (host-level Root CA)
# ---------------------------------------------------------------------------
echo -e "${BLUE}[Step 3/6] Checking PKI Trust...${NC}"
STEP_CA_ROOT=$(grep "^STEP_CA_ROOT_PATH=" "$RSTUDIO_DIR/.env" | cut -d= -f2- | tr -d '"' || echo "")
if [ -n "$STEP_CA_ROOT" ] && [ -f "$STEP_CA_ROOT" ]; then
    ok "PKI Root CA found at $STEP_CA_ROOT"
else
    CA_URL=$(grep "^STEP_CA_URL=" "$RSTUDIO_DIR/.env" | cut -d= -f2- | tr -d '"' || echo "")
    CA_FP=$(grep "^STEP_FINGERPRINT=" "$RSTUDIO_DIR/.env" | cut -d= -f2- | tr -d '"' || echo "")
    if [ -n "$CA_URL" ]; then
        warn "Root CA not found on host. Attempting fetch from $CA_URL..."
        FETCH_SCRIPT="$SCRIPT_DIR/../../scripts/infra-pki/client/fetch_pki_root.sh"
        if [ -f "$FETCH_SCRIPT" ]; then
            if "$FETCH_SCRIPT" "$CA_URL" "$CA_FP" "${STEP_CA_ROOT:-/etc/ssl/certs/step-ca-root.crt}"; then
                ok "Root CA fetched and installed"
            else
                warn "Root CA fetch failed — containers may fail TLS verification"
            fi
        else
            warn "fetch_pki_root.sh not found at $FETCH_SCRIPT"
            warn "Tip: Run scripts/infra-pki/client/fetch_pki_root.sh manually to install the Root CA"
        fi
    else
        warn "No STEP_CA_URL configured — PKI trust not established"
    fi
fi

# ---------------------------------------------------------------------------
# Step 4: Build images
# ---------------------------------------------------------------------------
echo -e "${BLUE}[Step 4/6] Building Docker images...${NC}"

COMPOSE_PROFILES="--profile $AUTH_BACKEND --profile portal"
# Add optional profiles if configured
ENABLE_OIDC=$(grep "^ENABLE_OIDC=" "$RSTUDIO_DIR/.env" | cut -d= -f2- | tr -d '"' || echo "")
ENABLE_AI=$(grep "^ENABLE_AI=" "$RSTUDIO_DIR/.env" | cut -d= -f2- | tr -d '"' || echo "")
[ "$ENABLE_OIDC" = "true" ] && COMPOSE_PROFILES="$COMPOSE_PROFILES --profile oidc"
[ "$ENABLE_AI" = "true" ] && COMPOSE_PROFILES="$COMPOSE_PROFILES --profile ai"

echo ""
echo -e "${YELLOW}Deploy configuration:${NC}"
echo "  Backend  : $AUTH_BACKEND"
echo "  Domain   : ${HOST_DOMAIN:-NOT SET}"
echo "  Profiles : $COMPOSE_PROFILES"
echo "  Command  : docker compose $COMPOSE_PROFILES up -d --build"
echo ""
read -rp "Proceed? (y/N) " -n 1 confirm
echo ""
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    log "Aborted by user."
    exit 0
fi

cd "$RSTUDIO_DIR"
docker compose $COMPOSE_PROFILES build
ok "Images built"

# ---------------------------------------------------------------------------
# Step 5: Start stack
# ---------------------------------------------------------------------------
echo -e "${BLUE}[Step 5/6] Starting stack...${NC}"
docker compose $COMPOSE_PROFILES up -d
ok "Stack started"

# ---------------------------------------------------------------------------
# Step 6: Post-deploy verification
# ---------------------------------------------------------------------------
echo -e "${BLUE}[Step 6/6] Post-deploy verification...${NC}"

echo "  Waiting for rstudio_pet to become healthy (max 120s)..."
RETRIES=60
while [ "$RETRIES" -gt 0 ]; do
    STATUS=$(docker inspect --format='{{.State.Health.Status}}' rstudio_pet 2>/dev/null || echo "starting")
    if [ "$STATUS" = "healthy" ]; then
        ok "RStudio container healthy"
        break
    fi
    echo -n "."
    sleep 2
    (( RETRIES-- )) || true
done
[ "$RETRIES" -eq 0 ] && warn "RStudio not yet healthy — check: docker compose logs rstudio-${AUTH_BACKEND}"

# Post-deploy validation if available
if [ -f "$SCRIPT_DIR/validate_rstudio.sh" ]; then
    if ! "$SCRIPT_DIR/validate_rstudio.sh" --post-deploy; then
        warn "Post-deploy checks reported warnings."
    fi
fi

echo ""
docker compose ps
echo ""
echo -e "${BLUE}=== Deployment Summary ===${NC}"
echo "  Portal    : https://${HOST_DOMAIN:-localhost}"
echo "  RStudio   : http://$(hostname -I | awk '{print $1}'):${RSTUDIO_PORT:-8787}"
echo "  Backend   : $AUTH_BACKEND"
echo ""
echo -e "${GREEN}✅ Deployment completed!${NC}"
