#!/bin/bash
set -euo pipefail

# deploy_iam.sh
# Comprehensive deployment script for Infra-IAM
# Location: /opt/docker/Infra-Iam-PKI/scripts/infra-iam/deploy_iam.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IAM_DIR="$(cd "$SCRIPT_DIR/../../infra-iam" && pwd)"

# Colors
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

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}⚠ Not running as root. Some operations (chown) may require sudo.${NC}"
fi

# Step 1: Validate configuration
echo -e "${BLUE}[Step 1/7] Validating configuration...${NC}"
chmod +x "$SCRIPT_DIR/validate_iam_config.sh"
if "$SCRIPT_DIR/validate_iam_config.sh" --pre-deploy; then
    echo -e "${GREEN}✓ Configuration validated${NC}"
else
    echo -e "${RED}✗ Configuration validation failed${NC}"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Step 2: Create required directories
echo ""
echo -e "${BLUE}[Step 2/7] Creating directory structure...${NC}"
mkdir -p "$IAM_DIR"/{keycloak_data,caddy_data,logs/watchtower,certs}
echo -e "${GREEN}✓ Directories created${NC}"

# Step 3: Set permissions
echo ""
echo -e "${BLUE}[Step 3/7] Setting permissions...${NC}"
# Extract PUID/PGID stripping quotes
PUID=$(grep "^PUID=" "$IAM_DIR/.env" | cut -d= -f2- | tr -d '"')
PGID=$(grep "^PGID=" "$IAM_DIR/.env" | cut -d= -f2- | tr -d '"')

if [ -n "$PUID" ] && [ -n "$PGID" ]; then
    echo "  Applying ownership ($PUID:$PGID) to data and certs..."
    chown -R "$PUID:$PGID" "$IAM_DIR"/{keycloak_data,caddy_data,logs,certs} 2>/dev/null || \
        echo -e "${YELLOW}⚠ Could not set ownership (may need sudo)${NC}"
    chmod 600 "$IAM_DIR/.env" 2>/dev/null || true
    echo -e "${GREEN}✓ Permissions set${NC}"
else
    echo -e "${YELLOW}⚠ Could not read PUID/PGID from .env, skipping permissions fix${NC}"
fi

# Step 4: Check for Certificate Enrollment (Token Prompt)
echo ""
echo -e "${BLUE}[Step 4/7] Checking for Enrollment Token...${NC}"
CRT_FILE="$IAM_DIR/certs/keycloak.crt"
export STEP_TOKEN=""

if [ ! -f "$CRT_FILE" ]; then
    echo -e "${YELLOW}⚠ Host Certificate not found ($CRT_FILE)${NC}"
    echo "Ideally, you should have generated a token on your PKI host using 'generate_token.sh'."
    echo ""
    read -p "Enter Step-CA Token: " INPUT_TOKEN
    
    if [ -n "$INPUT_TOKEN" ]; then
        # Export for docker compose to pick up
        export STEP_TOKEN="$INPUT_TOKEN"
        echo -e "${GREEN}✓ Token captured. Will perform enrollment on startup.${NC}"
    else
        echo -e "${RED}Warning: No token provided. Startup may fail if certificates are missing.${NC}"
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
else
    echo -e "${GREEN}✓ Certificate exists, skipping enrollment.${NC}"
fi

# Step 5: Pull/build images
echo ""
echo -e "${BLUE}[Step 5/7] Building and pulling images...${NC}"
cd "$IAM_DIR"
docker compose build
echo -e "${GREEN}✓ Images ready${NC}"

# Step 6: Deploy
echo ""
echo -e "${BLUE}[Step 6/7] Deploying services...${NC}"
# Explicitly pass the STEP_TOKEN variable to the command
STEP_TOKEN="${STEP_TOKEN}" docker compose up -d

echo "Waiting for services to initialize..."
sleep 10

# Step 7: Verify deployment
echo ""
echo -e "${BLUE}[Step 7/7] Verifying deployment...${NC}"

# Post-deployment validation
"$SCRIPT_DIR/validate_iam_config.sh" --post-deploy || echo -e "${YELLOW}⚠ Post-deploy checks found issues${NC}"

# Check container status
echo ""
echo "Container status:"
docker compose ps

# Check Keycloak Health
echo ""
echo "Waiting for Keycloak to be healthy..."
RETRIES=60
while [ $RETRIES -gt 0 ]; do
    if docker compose ps keycloak | grep -q "healthy"; then
        echo -e "${GREEN}✓ Keycloak is healthy${NC}"
        break
    fi
    echo -n "."
    sleep 2
    ((RETRIES--))
done

# Final summary
echo ""
echo -e "${BLUE}=== Deployment Summary ===${NC}"
DOMAIN_SSO=$(grep "^DOMAIN_SSO=" "$IAM_DIR/.env" | cut -d= -f2- | tr -d '"')
echo "  SSO URL:    https://$DOMAIN_SSO"
echo "  Admin User: admin"
echo "  Password:   (See .env: KC_ADMIN_PASSWORD)"
echo ""
echo -e "${GREEN}✅ Deployment completed!${NC}"
