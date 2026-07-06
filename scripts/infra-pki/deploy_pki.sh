#!/bin/bash
set -euo pipefail

# fix
# deploy_pki.sh
# Comprehensive deployment script for Infra-PKI
# Location: /opt/docker/Infra-Iam-PKI/scripts/infra-pki/deploy_pki.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKI_DIR="$SCRIPT_DIR/../../infra-pki"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}"
cat << "EOF"
╔═══════════════════════════════════════╗
║   Infra-PKI Deployment Script         ║
║   Smallstep CA + PostgreSQL + Caddy   ║
╚═══════════════════════════════════════╝
EOF
echo -e "${NC}"

# Argument Parsing
DOCKER_LOGIN=false
if [[ "$*" == *"--login"* ]]; then
    DOCKER_LOGIN=true
fi

# Check if running as root (needed for some operations)
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}⚠ Not running as root. Some operations may require sudo.${NC}"
fi

# Docker Login (Optional)
if [ "$DOCKER_LOGIN" = "true" ]; then
    echo ""
    echo -e "${BLUE}[Docker Login] Authenticating with Docker Hub...${NC}"
    echo "Note: Login allows up to 200 pulls/6 hours (Free) instead of 100."
    echo "Enter your Docker Hub credentials:"
    
    if docker login; then
        echo -e "${GREEN}✓ Docker Login successful${NC}"
    else
        echo -e "${RED}✗ Docker Login failed${NC}"
        read -p "Continue without login? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
fi

# Step 1: Validate configuration
echo -e "${BLUE}[Step 1/7] Validating configuration (Pre-flight)...${NC}"
if [ -f "$SCRIPT_DIR/validate_config.sh" ]; then
    chmod +x "$SCRIPT_DIR/validate_config.sh"
    # Run only pre-deployment checks (static analysis)
    if "$SCRIPT_DIR/validate_config.sh" --pre-deploy; then
        echo -e "${GREEN}✓ Configuration validated${NC}"
    else
        echo -e "${RED}✗ Configuration validation failed${NC}"
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
else
    echo -e "${YELLOW}⚠ validate_config.sh not found, skipping validation${NC}"
fi

# Step 2: Validate Caddyfile (fail-fast — the Caddyfile is NEVER auto-rewritten:
# a previous auto-fix silently dropped the :80 certs/fingerprint site block,
# which breaks IAM/OOD cross-host bootstrap)
echo ""
echo -e "${BLUE}[Step 2/7] Checking Caddyfile...${NC}"

# The compose file tags the local build as infra-pki-caddy:local.
# Build it first if missing (fresh host) so validation can run.
if ! docker image inspect infra-pki-caddy:local >/dev/null 2>&1; then
    echo "  Building Caddy image for validation..."
    (cd "$PKI_DIR" && docker compose build caddy)
fi

if ! docker run --rm \
    -v "$PKI_DIR/caddy/Caddyfile:/etc/caddy/Caddyfile" \
    -e ALLOWED_IPS="127.0.0.1/32" \
    infra-pki-caddy:local \
    caddy validate --config /etc/caddy/Caddyfile 2>&1 | grep -q "Valid"; then

    echo -e "${RED}✗ Caddyfile validation failed. Aborting deployment.${NC}"
    echo -e "${YELLOW}  Inspect the errors with:${NC}"
    echo -e "${YELLOW}    docker run --rm -v \"$PKI_DIR/caddy/Caddyfile:/etc/caddy/Caddyfile\" -e ALLOWED_IPS=\"127.0.0.1/32\" infra-pki-caddy:local caddy validate --config /etc/caddy/Caddyfile${NC}"
    echo -e "${YELLOW}  Reference config: infra-pki/caddy/Caddyfile in git (restore with 'git checkout -- infra-pki/caddy/Caddyfile').${NC}"
    exit 1
else
    echo -e "${GREEN}✓ Caddyfile is valid${NC}"
fi

# Step 3: Create required directories
echo ""
echo -e "${BLUE}[Step 3/7] Creating directory structure...${NC}"
mkdir -p "$PKI_DIR"/{step_data,db_data,logs/{step-ca,postgres,caddy,watchtower}}
echo -e "${GREEN}✓ Directories created${NC}"

# Step 4: Set permissions (HC-10: MUST exit 1 if permission setup fails)
echo ""
echo -e "${BLUE}[Step 4/7] Setting permissions...${NC}"
PUID=$(grep "^PUID=" "$PKI_DIR/.env" | cut -d= -f2- | tr -d '"')
PGID=$(grep "^PGID=" "$PKI_DIR/.env" | cut -d= -f2- | tr -d '"')

if [ -z "$PUID" ] || [ -z "$PGID" ]; then
    echo -e "${RED}✗ Could not read PUID/PGID from .env — aborting.${NC}"
    exit 1
fi

if ! chown -R "$PUID:$PGID" "$PKI_DIR"/{step_data,db_data,logs} 2>/dev/null; then
    # chown fails for non-root users even when ownership is already correct.
    # Verify actual ownership before deciding to abort.
    OWNERSHIP_OK=true
    for dir in "$PKI_DIR/step_data" "$PKI_DIR/db_data" "$PKI_DIR/logs"; do
        CURRENT=$(stat -c '%u:%g' "$dir" 2>/dev/null || echo "unknown")
        if [ "$CURRENT" != "$PUID:$PGID" ]; then
            OWNERSHIP_OK=false
            echo -e "${RED}  ✗ $dir is owned by $CURRENT (expected $PUID:$PGID)${NC}"
        fi
    done
    if [ "$OWNERSHIP_OK" != "true" ]; then
        echo -e "${RED}✗ Permission setup failed. Re-run with sudo. Aborting (containers would fail with cryptic 'Permission denied').${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Ownership already correct ($PUID:$PGID)${NC}"
fi
chmod 700 "$PKI_DIR/.env" 2>/dev/null || true
echo -e "${GREEN}✓ Permissions set${NC}"

# Step 5: Pull/build images
echo ""
echo -e "${BLUE}[Step 5/7] Building and pulling images...${NC}"
cd "$PKI_DIR"
docker compose build
echo -e "${GREEN}✓ Images ready${NC}"

# Step 6: Deploy
echo ""
echo -e "${BLUE}[Step 6/7] Deploying services...${NC}"
docker compose up -d

echo "Waiting for services to initialize..."
sleep 15

# Step 7: Verify deployment
echo ""
echo -e "${BLUE}[Step 7/7] Verifying deployment...${NC}"

# Post-deployment validation (Runtime connectivity checks)
if [ -f "$SCRIPT_DIR/validate_config.sh" ]; then
    echo "Running post-deployment validation..."
    "$SCRIPT_DIR/validate_config.sh" --post-deploy || echo -e "${YELLOW}⚠ Post-deploy checks found issues${NC}"
fi

# Check container status
echo "Container status:"
docker compose ps

# Wait for step-ca to be healthy
echo ""
echo "Waiting for step-ca to be healthy..."
RETRIES=30
while [ $RETRIES -gt 0 ]; do
    if docker compose ps step-ca | grep -q "healthy"; then
        echo -e "${GREEN}✓ step-ca is healthy${NC}"
        break
    fi
    echo -n "."
    sleep 2
    ((RETRIES--))
done



# Wait for Caddy (proxy) to be healthy
echo ""
echo "Waiting for Caddy proxy to be healthy..."
RETRIES=30
while [ $RETRIES -gt 0 ]; do
    if docker compose ps caddy | grep -q "healthy"; then
        echo -e "${GREEN}✓ caddy is healthy${NC}"
        break
    fi
    echo -n "."
    sleep 2
    ((RETRIES--))
done

if [ $RETRIES -eq 0 ]; then
    echo -e "${YELLOW}⚠ caddy did not become healthy (proceeding anyway, check logs)${NC}"
    docker compose logs caddy --tail=20
fi

# Check CA health endpoint
echo ""
echo "Testing CA health endpoint..."
# Capture output for debugging
HTTP_STATUS=$(curl -k -s -o /dev/null -w "%{http_code}" https://localhost:9000/health || echo "fail")

if [ "$HTTP_STATUS" == "200" ]; then
    echo -e "${GREEN}✓ CA health endpoint responding (Status: 200)${NC}"
else
    echo -e "${RED}✗ CA health endpoint check failed${NC}"
    echo -e "${RED}  Status Code: $HTTP_STATUS${NC}"
    echo -e "${YELLOW}  Troubleshoot: curl -v -k https://localhost:9000/health${NC}"
fi

# Check fingerprint
echo ""
echo "Checking fingerprint..."
if [ -f "$PKI_DIR/step_data/fingerprint/root_ca.fingerprint" ]; then
    FINGERPRINT=$(cat "$PKI_DIR/step_data/fingerprint/root_ca.fingerprint")
    echo -e "${GREEN}✓ Fingerprint: $FINGERPRINT${NC}"
else
    echo -e "${YELLOW}⚠ Fingerprint file not found yet${NC}"
fi

# Check provisioners
echo ""
echo "Checking provisioners..."
if docker compose exec -T step-ca step ca provisioner list 2>/dev/null; then
    echo -e "${GREEN}✓ Provisioners configured${NC}"
else
    echo -e "${YELLOW}⚠ Could not list provisioners (may still be initializing)${NC}"
fi

# Final summary
echo ""
echo -e "${BLUE}=== Deployment Summary ===${NC}"
echo ""
echo "Status: $(docker compose ps --format '{{.Service}}: {{.Status}}' | head -5)"
echo ""
echo "Access URLs:"
echo "  CA Health: https://localhost:9000/health"
echo "  CA Roots:  https://localhost:9000/roots.pem"
echo ""
echo "Important files:"
echo "  Fingerprint: $PKI_DIR/step_data/fingerprint/root_ca.fingerprint"
echo "  Root CA:     $PKI_DIR/step_data/certs/root_ca.crt"
echo "  Logs:        $PKI_DIR/logs/"
echo ""
echo "Next steps:"
echo "  1. Verify: curl -k https://localhost:9000/health"
echo "  2. View logs: cd $PKI_DIR && docker compose logs -f"
echo "  3. Generate token: $SCRIPT_DIR/generate_token.sh"
echo ""

if [ -f "$PKI_DIR/step_data/fingerprint/root_ca.fingerprint" ]; then
    echo -e "${GREEN}✅ Deployment completed successfully!${NC}"
else
    echo -e "${YELLOW}⚠️  Deployment completed but fingerprint not yet available${NC}"
    echo "   Wait a few seconds and check: cat $PKI_DIR/step_data/fingerprint/root_ca.fingerprint"
fi
# SEC-001: Secure .env permissions on deploy
chmod 600 .env 2>/dev/null || true
