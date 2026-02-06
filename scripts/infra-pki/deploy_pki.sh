#!/bin/bash
set -euo pipefail

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

# Check if running as root (needed for some operations)
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}⚠ Not running as root. Some operations may require sudo.${NC}"
fi

# Step 1: Validate configuration
echo -e "${BLUE}[Step 1/7] Validating configuration...${NC}"
if [ -f "$SCRIPT_DIR/validate_config.sh" ]; then
    chmod +x "$SCRIPT_DIR/validate_config.sh"
    if "$SCRIPT_DIR/validate_config.sh"; then
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

# Step 2: Fix Caddyfile if needed
echo ""
echo -e "${BLUE}[Step 2/7] Checking Caddyfile...${NC}"
if ! docker run --rm \
    -v "$PKI_DIR/caddy/Caddyfile:/etc/caddy/Caddyfile" \
    -e ALLOWED_IPS="127.0.0.1/32" \
    infra-pki-caddy:latest \
    caddy validate --config /etc/caddy/Caddyfile 2>&1 | grep -q "Valid"; then
    
    echo -e "${YELLOW}⚠ Caddyfile has errors. Applying fix...${NC}"
    
    # Backup current Caddyfile
    cp "$PKI_DIR/caddy/Caddyfile" "$PKI_DIR/caddy/Caddyfile.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Apply fixed Caddyfile
    cat > "$PKI_DIR/caddy/Caddyfile" <<'EOF'
{
	admin off
	layer4 {
		:9000 {
			@allowed remote_ip {$ALLOWED_IPS}
			route @allowed {
				proxy step-ca:9000
			}
		}
	}
	log {
		output file /var/log/caddy/access.log {
			roll_size 10mb
			roll_keep 5
			roll_keep_for 720h
		}
		format json
		level INFO
	}
}
EOF
    echo -e "${GREEN}✓ Caddyfile fixed${NC}"
else
    echo -e "${GREEN}✓ Caddyfile is valid${NC}"
fi

# Step 3: Create required directories
echo ""
echo -e "${BLUE}[Step 3/7] Creating directory structure...${NC}"
mkdir -p "$PKI_DIR"/{step_data,db_data,logs/{step-ca,postgres,caddy,watchtower}}
echo -e "${GREEN}✓ Directories created${NC}"

# Step 4: Set permissions
echo ""
echo -e "${BLUE}[Step 4/7] Setting permissions...${NC}"
PUID=$(grep "^PUID=" "$PKI_DIR/.env" | cut -d= -f2)
PGID=$(grep "^PGID=" "$PKI_DIR/.env" | cut -d= -f2)

if [ -n "$PUID" ] && [ -n "$PGID" ]; then
    chown -R "$PUID:$PGID" "$PKI_DIR"/{step_data,db_data,logs} 2>/dev/null || \
        echo -e "${YELLOW}⚠ Could not set ownership (may need sudo)${NC}"
    chmod 700 "$PKI_DIR/.env" 2>/dev/null || true
    echo -e "${GREEN}✓ Permissions set${NC}"
else
    echo -e "${YELLOW}⚠ Could not read PUID/PGID from .env${NC}"
fi

# Step 5: Pull/build images
echo ""
echo -e "${BLUE}[Step 5/7] Building and pulling images...${NC}"
cd "$PKI_DIR"
docker compose build --pull
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

if [ $RETRIES -eq 0 ]; then
    echo -e "${RED}✗ step-ca did not become healthy${NC}"
    echo "Check logs: docker compose logs step-ca"
    exit 1
fi

# Check CA health endpoint
echo ""
echo "Testing CA health endpoint..."
if curl -k -s https://localhost:9000/health | grep -q "ok"; then
    echo -e "${GREEN}✓ CA health endpoint responding${NC}"
else
    echo -e "${RED}✗ CA health endpoint not responding${NC}"
fi

# Check fingerprint
echo ""
echo "Checking fingerprint..."
if [ -f "$PKI_DIR/step_data/fingerprint" ]; then
    FINGERPRINT=$(cat "$PKI_DIR/step_data/fingerprint")
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
echo "  Fingerprint: $PKI_DIR/step_data/fingerprint"
echo "  Root CA:     $PKI_DIR/step_data/certs/root_ca.crt"
echo "  Logs:        $PKI_DIR/logs/"
echo ""
echo "Next steps:"
echo "  1. Verify: curl -k https://localhost:9000/health"
echo "  2. View logs: cd $PKI_DIR && docker compose logs -f"
echo "  3. Generate token: $SCRIPT_DIR/generate_token.sh"
echo ""

if [ -f "$PKI_DIR/step_data/fingerprint" ]; then
    echo -e "${GREEN}✅ Deployment completed successfully!${NC}"
else
    echo -e "${YELLOW}⚠️  Deployment completed but fingerprint not yet available${NC}"
    echo "   Wait a few seconds and check: cat $PKI_DIR/step_data/fingerprint"
fi