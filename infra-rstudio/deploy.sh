#!/bin/bash
# ⚠️  DEPRECATED — This script is retained for historical reference ONLY.
#
# The canonical operator deploy script is:
#   scripts/infra-rstudio/deploy_rstudio.sh
#
# This file will be removed in a future cleanup pass.
# Do NOT modify or use this file for new deployments.

echo ""
echo "ERROR: This script is DEPRECATED."
echo "Use: scripts/infra-rstudio/deploy_rstudio.sh"
echo ""
exit 1

# ========== ARCHIVED CONTENT BELOW (DO NOT EXECUTE) ==========
# The content below is preserved for reference only.
# It is unreachable due to 'exit 1' above.
# =============================================================

: <<'ARCHIVED'
# deploy.sh — Master Deployment Script for Botanical Docker Infrastructure
# Handles .env validation, build, and verification.
# Follows Pessimistic System Engineering: fail fast, bound resources, assert deps.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

# HC-14: Deterministic cleanup on exit/error
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo -e "${RED}[DEPLOY] Deployment failed with exit code $exit_code${NC}"
    fi
}
trap cleanup EXIT ERR

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()   { echo -e "${BLUE}[DEPLOY]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }

# HC-13: Dependency assertion — verify required external binaries
log "Asserting dependencies..."
for cmd in docker curl; do
    command -v "$cmd" > /dev/null 2>&1 || error "Required binary '$cmd' not found in PATH."
done
docker compose version > /dev/null 2>&1 || error "Docker Compose plugin not available."
ok "All dependencies present."

# 0. Validate .env exists
if [ ! -f "$ENV_FILE" ]; then
    error ".env file not found at $ENV_FILE. Copy .env.example and configure it."
fi

# 1. Pre-Flight Validation
log "Running Pre-flight Validation..."
if [ -f "${SCRIPT_DIR}/scripts/validate_deployment.sh" ]; then
    "${SCRIPT_DIR}/scripts/validate_deployment.sh" || {
        error "Validation failed. Please fix the reported errors."
    }
else
    warn "Validation script not found at scripts/validate_deployment.sh. Skipping."
fi

# 1b. Check PKI Trust (Optional but recommended)
if [ -f "${SCRIPT_DIR}/scripts/manage_pki_trust.sh" ]; then
    log "Tip: Run 'scripts/manage_pki_trust.sh' to install internal CA certificates if needed."
fi

# HC-04: Safe .env parsing (never source .env directly — SEC-003 fix)
log "Loading Configuration from .env (safe parser)..."
PARSE_ENV="${SCRIPT_DIR}/../scripts/common/parse_env.sh"
if [ -f "$PARSE_ENV" ]; then
    # shellcheck source=/dev/null
    . "$PARSE_ENV" "$ENV_FILE"
else
    # Fallback: inline safe grep-based parser
    warn "parse_env.sh not found. Using inline safe parser."
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            val="${BASH_REMATCH[2]}"
            val="${val%\"}"
            val="${val#\"}"
            export "$key"="$val"
        fi
    done < "$ENV_FILE"
fi

log "Target Backend: ${GREEN}${AUTH_BACKEND:-NOT SET}${NC}"
log "Domain: ${HOST_DOMAIN:-NOT SET}"

# HC-10: Confirmation prompt before destructive deploy
echo ""
echo -e "${YELLOW}This will build and start the Docker stack.${NC}"
echo "  Backend : ${AUTH_BACKEND:-NOT SET}"
echo "  Domain  : ${HOST_DOMAIN:-NOT SET}"
echo "  Compose : docker compose --profile ${AUTH_BACKEND:-sssd} --profile portal up -d --build"
echo ""
read -rp "Proceed? (y/N) " -n 1 confirm
echo ""
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    log "Aborted by user."
    exit 0
fi

# 2. Build & Launch
log "Building and Starting Docker Stack..."

COMPOSE_CMD="docker compose --profile ${AUTH_BACKEND:-sssd} --profile portal"

log "Running: $COMPOSE_CMD up -d --build"
$COMPOSE_CMD up -d --build

# 3. Verification
log "Waiting for services to initialize..."
sleep 5

if docker compose ps | grep -q "Up"; then
    ok "Services are running!"
else
    error "Services failed to start. Check 'docker compose logs'."
fi

# Simple Health Check
log "Verifying RStudio port..."
if curl --silent --fail "http://localhost:${RSTUDIO_PORT:-8787}" > /dev/null 2>&1; then
    ok "RStudio is responding on port ${RSTUDIO_PORT:-8787}"
else
    warn "RStudio not responding on localhost:${RSTUDIO_PORT:-8787} — may still be starting."
fi

ok "Deployment Complete."
log "Access Portal at: https://${HOST_DOMAIN:-localhost}:${HTTPS_PORT:-443}"
log "Access RStudio at: http://<HOST-IP>:${RSTUDIO_PORT:-8787}"
ARCHIVED
