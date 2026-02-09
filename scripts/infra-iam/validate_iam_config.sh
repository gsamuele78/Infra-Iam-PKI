#!/bin/bash
set -euo pipefail

# validate_iam_config.sh
# Validates all Infra-IAM configuration files before deployment
# Location: /opt/docker/Infra-Iam-PKI/scripts/infra-iam/validate_iam_config.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IAM_DIR="$(cd "$SCRIPT_DIR/../../infra-iam" && pwd)"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Default mode
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

echo -e "${BLUE}=== Infra-IAM Configuration Validator (Mode: $MODE) ===${NC}"
echo "Checking: $IAM_DIR"
echo ""

# Function to report errors
error() {
    echo -e "${RED}✗ ERROR: $1${NC}"
    ERRORS=$((ERRORS+1))
}

# Function to report warnings
warning() {
    echo -e "${YELLOW}⚠ WARNING: $1${NC}"
    WARNINGS=$((WARNINGS+1))
}

# Function to report success
success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# ==========================================
# PRE-DEPLOYMENT CHECKS
# ==========================================
if [[ "$MODE" == "all" || "$MODE" == "pre" ]]; then

# Check 1: .env file exists
echo "Checking .env file..."
if [ ! -f "$IAM_DIR/.env" ]; then
    error ".env file not found at $IAM_DIR/.env"
else
    success ".env file exists"
    
    # Check for required variables
    REQUIRED_VARS=("PUID" "PGID" "DOMAIN_SSO" "DOMAIN_CA" "DB_PASSWORD" "KC_ADMIN_PASSWORD" "CA_URL" "AD_HOST")
    
    for var in "${REQUIRED_VARS[@]}"; do
        if ! grep -q "^${var}=" "$IAM_DIR/.env"; then
            error "Required variable $var not found in .env"
        fi
    done
    
    # Check for example/default passwords
    if grep -q "change_me" "$IAM_DIR/.env"; then
        warning ".env contains default 'change_me' passwords"
    fi
fi

# Check 2: Docker Compose file
echo ""
echo "Checking docker-compose.yml..."
if [ ! -f "$IAM_DIR/docker-compose.yml" ]; then
    error "docker-compose.yml not found"
else
    success "docker-compose.yml exists"
    
    if command -v docker compose &> /dev/null; then
        if docker compose -f "$IAM_DIR/docker-compose.yml" config > /dev/null 2>&1; then
            success "docker-compose.yml syntax is valid"
        else
            error "docker-compose.yml has syntax errors"
            docker compose -f "$IAM_DIR/docker-compose.yml" config 2>&1 | head -10
        fi
    fi
fi

# Check 3: Network Check (Optional - can we reach CA_URL)
echo ""
echo "Checking CA connectivity..."
# Strip quotes and extract host
CA_URL_VAL=$(grep "^CA_URL=" "$IAM_DIR/.env" | cut -d= -f2- | tr -d '"' || echo "")
if [ -n "$CA_URL_VAL" ]; then
    CA_HOST=$(echo "$CA_URL_VAL" | sed -e 's|^[^/]*//||' -e 's|/.*$||')
    if [[ "$CA_HOST" == *":"* ]]; then
        CA_PORT=${CA_HOST##*:}
        CA_HOST=${CA_HOST%:*}
    else
        CA_PORT=443
    fi

    echo "  Testing connection to $CA_HOST:$CA_PORT..."
    if timeout 2 bash -c "cat < /dev/tcp/$CA_HOST/$CA_PORT" 2>/dev/null; then
        success "CA endpoint is reachable"
    else
        warning "CA endpoint ($CA_HOST:$CA_PORT) is not reachable. Ensure CA is running."
    fi
fi

fi # END PRE-DEPLOY CHECKS

# ==========================================
# POST-DEPLOYMENT CHECKS
# ==========================================
if [[ "$MODE" == "all" || "$MODE" == "post" ]]; then

# Check 4: Keycloak Health
echo ""
echo "Checking Keycloak Health..."
if docker compose -f "$IAM_DIR/docker-compose.yml" ps keycloak | grep -q "Up"; then
    echo "  Testing Keycloak /health/ready..."
    # Rely on Docker healthcheck primarily but can also curl if port is exposed or via exec
    if docker compose -f "$IAM_DIR/docker-compose.yml" ps keycloak | grep -q "healthy"; then
        success "Keycloak is Healthy"
    else
        warning "Keycloak is not yet reported as Healthy. Waiting or check logs."
    fi
else
    warning "Keycloak container is not running"
fi

# Check 5: Postgres Health
echo ""
echo "Checking Database Health..."
if docker compose -f "$IAM_DIR/docker-compose.yml" ps db | grep -q "Up"; then
    if docker compose -f "$IAM_DIR/docker-compose.yml" exec -T db pg_isready -U keycloak > /dev/null 2>&1; then
        success "Database is accepting connections"
    else
        error "Database is not ready"
    fi
else
    warning "Database container is not running"
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
