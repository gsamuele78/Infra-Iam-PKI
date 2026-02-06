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
CONTAINERS=("step-ca" "step-ca-db" "caddy" "step-ca-configurator")
ALL_HEALTHY=true

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
             if [ "$container" == "caddy" ]; then
                 echo -e "    ${YELLOW}Hint: Check ALLOWED_IPS in .env. Verify 'wget http://localhost:2019/metrics'.${NC}"
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
CA_URL=$(grep "^STEP_CA_URL=" .env | cut -d= -f2 || echo "https://localhost")
DOMAIN=$(echo "$CA_URL" | awk -F/ '{print $3}' | cut -d: -f1)

if curl -sk "$CA_URL/health" | grep -q "ok"; then
    echo -e "  - External Health Endpoint ($CA_URL): ${GREEN}OK${NC}"
else
    echo -e "  - External Health Endpoint ($CA_URL): ${RED}FAILED${NC}"
    echo -e "    ${YELLOW}Hint: Verify Caddy is running. Ensure '$DOMAIN' resolves to this host.${NC}"
    echo -e "    ${YELLOW}Hint: Test locally with 'curl -k https://localhost:443/health'${NC}"
fi
echo ""

# --- 3. Provisioner validation ---
echo -e "${BLUE}3. Checking Provisioners...${NC}"
if docker exec step-ca step ca provisioner list &>/dev/null; then
    PROV_LIST=$(docker exec step-ca step ca provisioner list)
    
    # Check for critical provisioners
    for needed in "ssh-pop" "Admin JWK" "acme"; do
        if echo "$PROV_LIST" | grep -q "$needed"; then
            echo -e "  - Provisioner '$needed': ${GREEN}FOUND${NC}"
        else
            echo -e "  - Provisioner '$needed': ${RED}MISSING${NC}"
            echo -e "    ${YELLOW}Hint: Run './configure_pki.sh' or restart 'step-ca-configurator' container.${NC}"
        fi
    done
else
    echo -e "  - ${RED}Critical: Cannot list provisioners. Step-CA API not reachable.${NC}"
fi
echo ""

# --- 4. Database Connection ---
echo -e "${BLUE}4. Database Connection...${NC}"
if docker compose exec step-ca-db pg_isready -U step &>/dev/null; then
     echo -e "  - PostgreSQL Reachability: ${GREEN}OK${NC}"
else
     echo -e "  - PostgreSQL Reachability: ${RED}FAILED${NC}"
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