#!/bin/bash
set -euo pipefail

# validate_config.sh
# Validates all Infra-PKI configuration files before deployment
# Location: /opt/docker/Infra-Iam-PKI/scripts/infra-pki/validate_config.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKI_DIR="$SCRIPT_DIR/../../infra-pki"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

ERRORS=0
WARNINGS=0

echo -e "${BLUE}=== Infra-PKI Configuration Validator ===${NC}"
echo "Checking: $PKI_DIR"
echo ""

# Function to report errors
error() {
    echo -e "${RED}✗ ERROR: $1${NC}"
    ((ERRORS++))
}

# Function to report warnings
warning() {
    echo -e "${YELLOW}⚠ WARNING: $1${NC}"
    ((WARNINGS++))
}

# Function to report success
success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Check 1: .env file exists
echo "Checking .env file..."
if [ ! -f "$PKI_DIR/.env" ]; then
    error ".env file not found at $PKI_DIR/.env"
else
    success ".env file exists"
    
    # Check for required variables
    REQUIRED_VARS=("PUID" "PGID" "DOMAIN_CA" "CA_PASSWORD" "POSTGRES_DB" "POSTGRES_USER" "POSTGRES_PASSWORD" "ALLOWED_IPS")
    
    for var in "${REQUIRED_VARS[@]}"; do
        if ! grep -q "^${var}=" "$PKI_DIR/.env"; then
            error "Required variable $var not found in .env"
        fi
    done
    
    # Check for example/default passwords
    if grep -q "change_me" "$PKI_DIR/.env"; then
        warning ".env contains default 'change_me' passwords"
    fi
    
    if grep -q "example.com" "$PKI_DIR/.env"; then
        warning ".env contains example domain 'example.com'"
    fi
fi

# Check 2: Docker Compose file
echo ""
echo "Checking docker-compose.yml..."
if [ ! -f "$PKI_DIR/docker-compose.yml" ]; then
    error "docker-compose.yml not found"
else
    success "docker-compose.yml exists"
    
    # Validate Docker Compose syntax
    if command -v docker compose &> /dev/null; then
        if docker compose -f "$PKI_DIR/docker-compose.yml" config > /dev/null 2>&1; then
            success "docker-compose.yml syntax is valid"
        else
            error "docker-compose.yml has syntax errors"
            docker compose -f "$PKI_DIR/docker-compose.yml" config 2>&1 | head -10
        fi
    else
        warning "docker compose command not available, skipping validation"
    fi
fi

# Check 3: Caddyfile
echo ""
echo "Checking Caddyfile..."
if [ ! -f "$PKI_DIR/caddy/Caddyfile" ]; then
    error "Caddyfile not found at $PKI_DIR/caddy/Caddyfile"
else
    success "Caddyfile exists"
    
    # Check Caddyfile syntax using docker
    echo "  Validating Caddyfile syntax..."
    
    # Build caddy image if needed
    if ! docker images | grep -q "infra-pki-caddy"; then
        echo "  Building Caddy image for validation..."
        (cd "$PKI_DIR" && docker compose build caddy > /dev/null 2>&1)
    fi
    
    # Validate Caddyfile
    if docker run --rm \
        -v "$PKI_DIR/caddy/Caddyfile:/etc/caddy/Caddyfile" \
        -e ALLOWED_IPS="127.0.0.1/32" \
        infra-pki-caddy:latest \
        caddy validate --config /etc/caddy/Caddyfile 2>&1 | grep -q "Valid"; then
        success "Caddyfile syntax is valid"
    else
        error "Caddyfile has syntax errors"
        docker run --rm \
            -v "$PKI_DIR/caddy/Caddyfile:/etc/caddy/Caddyfile" \
            -e ALLOWED_IPS="127.0.0.1/32" \
            infra-pki-caddy:latest \
            caddy validate --config /etc/caddy/Caddyfile 2>&1 | head -10
    fi
fi

# Check 4: Caddy Dockerfile
echo ""
echo "Checking Caddy Dockerfile..."
if [ ! -f "$PKI_DIR/caddy/Dockerfile" ]; then
    error "Caddy Dockerfile not found"
else
    success "Caddy Dockerfile exists"
fi

# Check 5: Init script
echo ""
echo "Checking init script..."
if [ ! -f "$SCRIPT_DIR/init_step_ca.sh" ]; then
    error "init_step_ca.sh not found at $SCRIPT_DIR/init_step_ca.sh"
else
    success "init_step_ca.sh exists"
    
    if [ -x "$SCRIPT_DIR/init_step_ca.sh" ]; then
        success "init_step_ca.sh is executable"
    else
        warning "init_step_ca.sh is not executable (will work in container anyway)"
    fi
fi

# Check 6: Required directories
echo ""
echo "Checking directory structure..."
REQUIRED_DIRS=("step_data" "db_data" "logs" "logs/step-ca" "logs/postgres" "logs/caddy" "logs/watchtower" "caddy")

for dir in "${REQUIRED_DIRS[@]}"; do
    if [ ! -d "$PKI_DIR/$dir" ]; then
        success "Directory $dir does not exist (will be created on first run)"
    fi
done

# Check 7: File permissions
echo ""
echo "Checking file permissions..."
if [ -f "$PKI_DIR/.env" ]; then
    PERMS=$(stat -c %a "$PKI_DIR/.env" 2>/dev/null || stat -f %A "$PKI_DIR/.env" 2>/dev/null)
    if [ "$PERMS" -gt "600" ]; then
        warning ".env file permissions are $PERMS (should be 600 for security)"
    else
        success ".env file permissions are secure ($PERMS)"
    fi
fi

# Check 8: Network configuration
echo ""
echo "Checking network configuration..."
if grep -q "ALLOWED_IPS=" "$PKI_DIR/.env"; then
    ALLOWED_IPS=$(grep "^ALLOWED_IPS=" "$PKI_DIR/.env" | cut -d= -f2)
    if [ -z "$ALLOWED_IPS" ]; then
        error "ALLOWED_IPS is empty"
    else
        success "ALLOWED_IPS is configured: $ALLOWED_IPS"
        
        # Check if localhost is allowed
        if echo "$ALLOWED_IPS" | grep -q "127.0.0.1"; then
            success "Localhost access is enabled"
        else
            warning "Localhost (127.0.0.1) is not in ALLOWED_IPS"
        fi
    fi
fi

# Check 9: Image availability
echo ""
echo "Checking Docker images..."
REQUIRED_IMAGES=("smallstep/step-ca:0.29.0" "smallstep/step-cli:0.29.0" "postgres:15-alpine")

for image in "${REQUIRED_IMAGES[@]}"; do
    if docker images | grep -q "${image%:*}" | grep -q "${image#*:}"; then
        success "Image $image is available"
    else
        warning "Image $image not found locally (will be pulled on first run)"
    fi
done

# Check 10: Port availability
echo ""
echo "Checking port availability..."
if command -v netstat &> /dev/null; then
    if netstat -tuln | grep -q ":9000 "; then
        error "Port 9000 is already in use"
    else
        success "Port 9000 is available"
    fi
elif command -v ss &> /dev/null; then
    if ss -tuln | grep -q ":9000 "; then
        error "Port 9000 is already in use"
    else
        success "Port 9000 is available"
    fi
else
    warning "Cannot check port availability (netstat/ss not available)"
fi

# Check 11: Docker daemon
echo ""
echo "Checking Docker daemon..."
if docker info > /dev/null 2>&1; then
    success "Docker daemon is running"
else
    error "Docker daemon is not running or not accessible"
fi

# Check 12: PostgreSQL Connectivity (if running)
echo ""
echo "Checking PostgreSQL..."
# Source .env if available to get credentials
if [ -f "$PKI_DIR/.env" ]; then
    source "$PKI_DIR/.env"
    # Check if we can reach the DB container if it's running
    if docker compose -f "$PKI_DIR/docker-compose.yml" ps postgres | grep -q "Up"; then
        echo "  Testing Postgres connection inside container..."
        if docker compose -f "$PKI_DIR/docker-compose.yml" exec -T postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"; then
             success "PostgreSQL is accepting connections"
        else
             error "PostgreSQL is running but not accepting connections"
        fi
    else
        warning "PostgreSQL container is not running (cannot verify connection now)"
    fi
    
    # Check 13: Step-CA Config DB Connection
    # Verify if ca.json exists and uses postgres
    CA_JSON="$PKI_DIR/step_data/config/ca.json"
    if [ -f "$CA_JSON" ]; then
        echo "  Checking Step-CA database configuration..."
        if grep -q '"type": "postgresql"' "$CA_JSON" || grep -q '"type":"postgresql"' "$CA_JSON"; then
            success "Step-CA is configured to use PostgreSQL"
        elif grep -q '"type": "badgerv2"' "$CA_JSON"; then
             error "Step-CA is configured to use BadgerDB (embedded). Reset required for Postgres."
        else
             warning "Unknown Step-CA DB type in ca.json"
        fi
    fi

    # Check 14: Cross-Container Connectivity (Step-CA -> Postgres)
    echo "  Testing network path from step-ca to postgres:5432..."
    if docker compose -f "$PKI_DIR/docker-compose.yml" ps step-ca | grep -q "Up"; then
        # Use bash /dev/tcp as step-ca container has bash installed
        if docker compose -f "$PKI_DIR/docker-compose.yml" exec -T step-ca bash -c 'timeout 3 bash -c "cat < /dev/null > /dev/tcp/postgres/5432" 2>/dev/null'; then
             success "step-ca can reach postgres:5432"
        else
             error "step-ca CANNOT reach postgres:5432"
             echo "    > Possible causes: DNS failure for 'postgres', Docker network isolation, or Postgres not ready."
        fi
    else
         warning "step-ca container is not running (cannot verify cross-container connection)"
    fi
fi

# Summary
echo ""
echo "=== Validation Summary ==="
echo -e "Errors:   ${RED}$ERRORS${NC}"
echo -e "Warnings: ${YELLOW}$WARNINGS${NC}"
echo ""

if [ $ERRORS -gt 0 ]; then
    echo -e "${RED}❌ Validation FAILED - Please fix errors before deploying${NC}"
    exit 1
elif [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Validation passed with warnings - Review before deploying${NC}"
    exit 0
else
    echo -e "${GREEN}✅ Validation PASSED - Configuration is ready for deployment${NC}"
    exit 0
fi