#!/bin/bash
# docker-deploy/deploy.sh
# Master Deployment Script for Botanical Docker Infrastructure
# Handles .env validation, build, and verification.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

# Dependency Assertion (HC-13)
command -v docker >/dev/null 2>&1 || { echo "ERROR: docker is required but not installed."; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "ERROR: curl is required but not installed."; exit 1; }

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "[DEPLOY] $1"; }
error() { echo -e "${RED}[ERROR] $1${NC}"; exit 1; }

# 1. Pre-Flight Validation
log "Running Pre-flight Validation..."
if [ -f "${SCRIPT_DIR}/scripts/validate_deployment.sh" ]; then
    "${SCRIPT_DIR}/scripts/validate_deployment.sh" || {
        error "Validation failed. Please fix the reported errors."
    }
else
    log "${RED}WARNING: Validation script not found. Skipping.${NC}"
fi

# 1b. Check PKI Trust (Optional but recommended)
if [ -f "${SCRIPT_DIR}/scripts/manage_pki_trust.sh" ]; then
    # We can perform a quiet check or just remind the user
    # For now, let's just log a reminder if not trusted?
    # Or simplified: checks are done manually.
    log "Tip: Run 'scripts/manage_pki_trust.sh' to install internal CA certificates if needed."
fi

log "Loading Configuration from .env..."
# Only read explicitly rather than sourcing to prevent arbitrary execution
AUTH_BACKEND=$(grep "^AUTH_BACKEND=" "$ENV_FILE" | cut -d= -f2- | tr -d '"' || echo "")
HOST_DOMAIN=$(grep "^HOST_DOMAIN=" "$ENV_FILE" | cut -d= -f2- | tr -d '"' || echo "")
RSTUDIO_PORT=$(grep "^RSTUDIO_PORT=" "$ENV_FILE" | cut -d= -f2- | tr -d '"' || echo "8787")
HTTPS_PORT=$(grep "^HTTPS_PORT=" "$ENV_FILE" | cut -d= -f2- | tr -d '"' || echo "443")

log "Target Backend: ${GREEN}${AUTH_BACKEND}${NC}"
log "Domain: ${HOST_DOMAIN}"

# 2. Build & Launch
log "Building and Starting Docker Stack..."

COMPOSE_CMD="docker compose --profile ${AUTH_BACKEND} --profile portal"

log "Running: $COMPOSE_CMD up -d --build"
$COMPOSE_CMD up -d --build

# 3. Verification
log "Waiting for services to initialize..."
sleep 5

if docker compose ps | grep -q "Up"; then
    log "${GREEN}Services are running!${NC}"
else
    error "Services failed to start. Check 'docker compose logs'."
fi

# Simple Health Check
log "Verifying RStudio port..."
if command -v curl &>/dev/null; then
    if curl --silent --fail "http://localhost:${RSTUDIO_PORT:-8787}" >/dev/null; then
        log "${GREEN}RStudio is responding on port ${RSTUDIO_PORT:-8787}${NC}"
    else
        log "${RED}WARNING: RStudio not responding on localhost:${RSTUDIO_PORT:-8787}${NC}"
    fi
else
    log "curl not found, skipping health probe."
fi

log "Deployment Complete."
log "Access Portal at: https://${HOST_DOMAIN}:${HTTPS_PORT:-443}"
log "Access RStudio at: http://<HOST-IP>:${RSTUDIO_PORT:-8787}"
