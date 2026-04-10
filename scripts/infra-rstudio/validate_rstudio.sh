#!/bin/bash
set -euo pipefail

# validate_rstudio.sh
# Validates all Infra-RStudio configuration before/after deployment.
# Location: scripts/infra-rstudio/validate_rstudio.sh
#
# Usage:
#   ./validate_rstudio.sh                 # Run all checks
#   ./validate_rstudio.sh --pre-deploy    # Pre-deploy checks only
#   ./validate_rstudio.sh --post-deploy   # Post-deploy checks only

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RSTUDIO_DIR="$(cd "$SCRIPT_DIR/../../infra-rstudio" && pwd)"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

MODE="all"
ERRORS=0
WARNINGS=0

# Parse arguments
if [ "$#" -ge 1 ]; then
    case "$1" in
        --pre-deploy) MODE="pre" ;;
        --post-deploy) MODE="post" ;;
        *) echo "Usage: $0 [--pre-deploy|--post-deploy]"; exit 1 ;;
    esac
fi

echo -e "${BLUE}=== Infra-RStudio Configuration Validator (Mode: $MODE) ===${NC}"
echo "Checking: $RSTUDIO_DIR"
echo ""

error() {
    echo -e "${RED}✗ ERROR: $1${NC}"
    ERRORS=$((ERRORS+1))
}

warning() {
    echo -e "${YELLOW}⚠ WARNING: $1${NC}"
    WARNINGS=$((WARNINGS+1))
}

success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# ==========================================
# PRE-DEPLOYMENT CHECKS
# ==========================================
if [[ "$MODE" == "all" || "$MODE" == "pre" ]]; then

# Check 1: .env file
echo "Checking .env file..."
if [ ! -f "$RSTUDIO_DIR/.env" ]; then
    error ".env file not found at $RSTUDIO_DIR/.env"
else
    success ".env file exists"

    # Required variables
    REQUIRED_VARS=("AUTH_BACKEND" "HOST_DOMAIN" "HOST_HOME_DIR" "HOST_PROJECT_ROOT")
    for var in "${REQUIRED_VARS[@]}"; do
        if ! grep -q "^${var}=" "$RSTUDIO_DIR/.env"; then
            error "Required variable $var not found in .env"
        fi
    done

    # Check AUTH_BACKEND value
    AB_VAL=$(grep "^AUTH_BACKEND=" "$RSTUDIO_DIR/.env" | cut -d= -f2- | tr -d '"')
    if [[ "$AB_VAL" != "sssd" && "$AB_VAL" != "samba" ]]; then
        error "AUTH_BACKEND must be 'sssd' or 'samba', got: '$AB_VAL'"
    fi

    # Check for default/placeholder passwords
    if grep -q "change_me" "$RSTUDIO_DIR/.env"; then
        warning ".env contains default 'change_me' values"
    fi
fi

# Check 2: Docker Compose syntax
echo ""
echo "Checking docker-compose.yml..."
if [ ! -f "$RSTUDIO_DIR/docker-compose.yml" ]; then
    error "docker-compose.yml not found"
else
    success "docker-compose.yml exists"
    if command -v docker &> /dev/null && docker compose version &> /dev/null; then
        if docker compose -f "$RSTUDIO_DIR/docker-compose.yml" config --quiet 2>/dev/null; then
            success "docker-compose.yml syntax is valid"
        else
            error "docker-compose.yml has syntax errors"
        fi
    fi
fi

# Check 3: SSSD/Winbind socket availability on host
echo ""
echo "Checking auth backend socket..."
AB_VAL=$(grep "^AUTH_BACKEND=" "$RSTUDIO_DIR/.env" 2>/dev/null | cut -d= -f2- | tr -d '"' || echo "sssd")
if [ "$AB_VAL" = "sssd" ]; then
    PIPES_PATH=$(grep "^HOST_SSS_PIPES=" "$RSTUDIO_DIR/.env" | cut -d= -f2- | tr -d '"' || echo "/var/lib/sss/pipes")
    if [ -d "$PIPES_PATH" ]; then
        success "SSSD pipes directory exists at $PIPES_PATH"
    else
        warning "SSSD pipes directory not found at $PIPES_PATH — container auth will fail"
    fi
elif [ "$AB_VAL" = "samba" ]; then
    WINBIND_PATH=$(grep "^HOST_WINBINDD_DIR=" "$RSTUDIO_DIR/.env" | cut -d= -f2- | tr -d '"' || echo "/var/run/samba/winbindd")
    if [ -d "$WINBIND_PATH" ]; then
        success "Winbind directory exists at $WINBIND_PATH"
    else
        warning "Winbind directory not found at $WINBIND_PATH — container auth will fail"
    fi
fi

# Check 4: PKI Root CA trust
echo ""
echo "Checking PKI trust..."
ROOT_CA=$(grep "^STEP_CA_ROOT_PATH=" "$RSTUDIO_DIR/.env" 2>/dev/null | cut -d= -f2- | tr -d '"' || echo "")
if [ -n "$ROOT_CA" ] && [ -f "$ROOT_CA" ]; then
    # Check expiry
    EXPIRY=$(openssl x509 -enddate -noout -in "$ROOT_CA" 2>/dev/null | cut -d= -f2 || echo "")
    if [ -n "$EXPIRY" ]; then
        EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s 2>/dev/null || echo "0")
        NOW_EPOCH=$(date +%s)
        DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))
        if [ "$DAYS_LEFT" -lt 7 ]; then
            warning "Root CA expires in $DAYS_LEFT days!"
        else
            success "Root CA valid ($DAYS_LEFT days remaining)"
        fi
    else
        success "Root CA certificate present at $ROOT_CA"
    fi
else
    warning "No PKI Root CA found — internal TLS verification may fail"
fi

# Check 5: SSL certificate for Nginx
echo ""
echo "Checking SSL certificates..."
SSL_CERT=$(grep "^SSL_CERT_PATH=" "$RSTUDIO_DIR/.env" 2>/dev/null | cut -d= -f2- | tr -d '"' || echo "")
SSL_KEY=$(grep "^SSL_KEY_PATH=" "$RSTUDIO_DIR/.env" 2>/dev/null | cut -d= -f2- | tr -d '"' || echo "")
if [ -n "$SSL_CERT" ] && [ -f "$SSL_CERT" ]; then
    success "SSL certificate present at $SSL_CERT"
else
    warning "SSL certificate not found (Nginx portal will not start)"
fi
if [ -n "$SSL_KEY" ] && [ -f "$SSL_KEY" ]; then
    success "SSL key present"
else
    warning "SSL key not found"
fi

fi # END PRE-DEPLOY CHECKS

# ==========================================
# POST-DEPLOYMENT CHECKS
# ==========================================
if [[ "$MODE" == "all" || "$MODE" == "post" ]]; then

# Check 6: RStudio container health
echo ""
echo "Checking RStudio container..."
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "rstudio_pet"; then
    STATUS=$(docker inspect --format='{{.State.Health.Status}}' rstudio_pet 2>/dev/null || echo "unknown")
    if [ "$STATUS" = "healthy" ]; then
        success "RStudio container is Healthy"
    else
        warning "RStudio container status: $STATUS"
    fi
else
    warning "RStudio container (rstudio_pet) is not running"
fi

# Check 7: RStudio port responding
echo ""
echo "Checking RStudio port..."
RSTUDIO_PORT=$(grep "^RSTUDIO_PORT=" "$RSTUDIO_DIR/.env" 2>/dev/null | cut -d= -f2- | tr -d '"' || echo "8787")
if curl -sf "http://127.0.0.1:${RSTUDIO_PORT}/auth-sign-in" > /dev/null 2>&1; then
    success "RStudio responding on port $RSTUDIO_PORT"
else
    warning "RStudio not responding on port $RSTUDIO_PORT"
fi

# Check 8: Telemetry API
echo ""
echo "Checking Telemetry API..."
if curl -sf "http://127.0.0.1:8000/api/v1/health" > /dev/null 2>&1; then
    success "Telemetry API responding"
else
    warning "Telemetry API not responding on port 8000"
fi

fi # END POST-DEPLOY CHECKS

# Summary
echo ""
echo "=== Validation Summary ($MODE) ==="
echo -e "Errors:   ${RED}$ERRORS${NC}"
echo -e "Warnings: ${YELLOW}$WARNINGS${NC}"
echo ""

if [ $ERRORS -gt 0 ]; then
    echo -e "${RED}❌ Validation FAILED${NC}"
    exit 1
elif [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Validation passed with warnings${NC}"
    exit 0
else
    echo -e "${GREEN}✅ Validation PASSED${NC}"
    exit 0
fi
