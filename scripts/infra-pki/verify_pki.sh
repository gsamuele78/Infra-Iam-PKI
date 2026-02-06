#!/bin/bash
set -euo pipefail

# verify_pki.sh - Comprehensive PKI Health Check & Troubleshooting

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

WORKDIR="$(dirname "$0")/../../infra-pki"
cd "$WORKDIR" || { echo "Error: Could not enter $WORKDIR"; exit 1; }

echo -e "${BLUE}========================================"
echo -e "   PKI Infrastructure Verification"
echo -e "========================================${NC}"
echo "Time: $(date)"
echo ""

# --- 0. Dependency Check ---
if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}Warning: 'jq' is not installed. Output parsing will be limited.${NC}"
fi

# --- 1. Container Health ---
echo -e "${BLUE}1. Checking Container Health...${NC}"
CONTAINERS=("step-ca" "step-ca-db" "step-ca-proxy" "step-ca-configurator")
ALL_HEALTHY=true

# Check ALLOWED_IPS from .env
ALLOWED_IPS=$(grep "^ALLOWED_IPS=" .env | cut -d= -f2 || echo "Unknown")
echo -e "  - Configuration: ALLOWED_IPS=${YELLOW}${ALLOWED_IPS}${NC}"

for container in "${CONTAINERS[@]}"; do
    if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "running")
        if [ "$STATUS" == "healthy" ]; then
             echo -e "  - $container: ${GREEN}HEALTHY${NC}"
        elif [ "$STATUS" == "running" ]; then
             echo -e "  - $container: ${GREEN}RUNNING${NC} (No healthcheck)"
        else
             echo -e "  - $container: ${RED}UNHEALTHY ($STATUS)${NC}"
             ALL_HEALTHY=false
             
             # Specific troubleshooting for unhealthy containers
             if [ "$container" == "step-ca-proxy" ]; then
                 echo -e "    ${YELLOW}Hint: Caddy is running in Layer 4 (TCP) mode.${NC}"
                 echo -e "    ${YELLOW}Hint: Verify it can bind to port 9000. Check logs: 'docker logs step-ca-proxy'.${NC}"
             fi
        fi
    else
        # Configurator is expected to exit after success
        if [ "$container" == "step-ca-configurator" ]; then
             EXIT_CODE=$(docker inspect --format='{{.State.ExitCode}}' "$container" 2>/dev/null || echo "1")
             if [ "$EXIT_CODE" -eq 0 ]; then
                 echo -e "  - $container: ${GREEN}COMPLETED (Successfully Configured)${NC}"
             else
                 echo -e "  - $container: ${RED}FAILED (Exit Code: $EXIT_CODE)${NC}"
                 ALL_HEALTHY=false
                 echo -e "    ${YELLOW}Hint: Check 'docker logs step-ca-configurator'. Look for auth errors on adding provisioners.${NC}"
             fi
        else
             echo -e "  - $container: ${RED}STOPPED/MISSING${NC}"
             ALL_HEALTHY=false
        fi
    fi
done
echo ""

# --- 2. Step-CA Application Check ---
echo -e "${BLUE}2. Step-CA Application Check...${NC}"

# Check Internal Health (Direct to Port 9000)
if curl -sk https://localhost:9000/health | grep -q "ok"; then
    echo -e "  - Internal Health Endpoint (Port 9000): ${GREEN}OK${NC}"
else
    echo -e "  - Internal Health Endpoint (Port 9000): ${RED}FAILED${NC}"
    echo -e "    ${YELLOW}Hint: Check 'docker logs step-ca'. Verify DB connection and password.${NC}"
fi

# Check External Health (Through Caddy)
# Priority: 1. STEP_CA_URL (if set), 2. DOMAIN_CA (if set, +9000), 3. Localhost:9000
STEP_CA_URL=$(grep "^STEP_CA_URL=" .env | cut -d= -f2 || true)
DOMAIN_CA=$(grep "^DOMAIN_CA=" .env | cut -d= -f2 || true)

if [ -n "$STEP_CA_URL" ]; then
    CA_URL="$STEP_CA_URL"
elif [ -n "$DOMAIN_CA" ]; then
    CA_URL="https://${DOMAIN_CA}:9000"
else
    CA_URL="https://localhost:9000"
fi
echo -e "  - Target CA URL: ${YELLOW}$CA_URL${NC}"

DOMAIN=$(echo "$CA_URL" | awk -F/ '{print $3}' | cut -d: -f1)

# 1. TCP Check
if nc -z localhost 9000; then
    echo -e "  - Caddy Port 9000 (TCP):      ${GREEN}OPEN${NC}"
else
    echo -e "  - Caddy Port 9000 (TCP):      ${RED}CLOSED${NC}"
fi

# 2. Application Check via Proxy
# Caddy Layer 4 = Transparent Proxy. Connection must come from ALLOWED_IPS.
if curl -sk "$CA_URL/health" --max-time 2 | grep -q "ok"; then
    echo -e "  - External Health Endpoint ($CA_URL): ${GREEN}OK${NC}"
else
    # Distinguish between Connection Refused (Caddy down) and Timeout/Empty (IP Blocked)
    HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" "$CA_URL/health" --max-time 3 || echo "ERR")
    
    echo -e "  - External Health Endpoint ($CA_URL): ${RED}FAILED (Code: $HTTP_CODE)${NC}"
    echo -e "    ${YELLOW}Hint: Caddy uses IP Whitelisting (configured: $ALLOWED_IPS).${NC}"
    echo -e "    ${YELLOW}Hint: If Code is '000' or 'ERR', your IP is likely blocked by Caddy or DNS is wrong.${NC}"
fi
echo ""

# --- 3. Provisioner validation ---
echo -e "${BLUE}3. Checking Provisioners...${NC}"
if docker exec step-ca step ca provisioner list &>/dev/null; then
    PROV_LIST=$(docker exec step-ca step ca provisioner list)
    
    # Check for critical provisioners
    # Note: Provisioner names might vary. 'ssh-pop' named 'ssh-host-jwk' in some configs?
    # Let's check generally for SSH and Admin.
    for needed in "ssh" "admin" "acme"; do 
        # Case insensitive grep
        if echo "$PROV_LIST" | grep -iq "$needed"; then
             # Extract verify name
             FOUND_NAME=$(echo "$PROV_LIST" | grep -i "$needed" | head -n 1 | grep -o '"name": *"[^"]*"' | cut -d'"' -f4 || echo "$needed")
            echo -e "  - Provisioner Type '$needed': ${GREEN}FOUND ($FOUND_NAME)${NC}"
        else
            echo -e "  - Provisioner Type '$needed': ${RED}MISSING${NC}"
            echo -e "    ${YELLOW}Hint: Run './configure_pki.sh' or restart 'step-ca-configurator' container.${NC}"
        fi
    done
else
    echo -e "  - ${RED}Critical: Cannot list provisioners. Step-CA API not reachable.${NC}"
fi
echo ""

# --- 4. Database Connection ---
echo -e "${BLUE}4. Database Connection...${NC}"
# Determine DB User from container env
DB_USER=$(docker exec step-ca-db printenv POSTGRES_USER 2>/dev/null || echo "step")
if docker exec step-ca-db pg_isready -U "$DB_USER" &>/dev/null; then
     echo -e "  - PostgreSQL Reachability (User: $DB_USER): ${GREEN}OK${NC}"
else
     echo -e "  - PostgreSQL Reachability (User: $DB_USER): ${RED}FAILED${NC}"
fi
echo ""

# --- Summary ---
echo -e "${BLUE}========================================"
if [ "$ALL_HEALTHY" == "true" ]; then
    echo -e "   ${GREEN}SYSTEM STATUS: OPERATIONAL${NC}"
else
    echo -e "   ${RED}SYSTEM STATUS: ISSUES DETECTED${NC}"
    echo -e "   Review hints above or strictly check 'docker compose logs'."
fi
echo -e "========================================${NC}"