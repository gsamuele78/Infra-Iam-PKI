#!/bin/bash
set -euo pipefail

# verify_pki.sh - Comprehensive PKI Health Check & Troubleshooting

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Dependency Assertions (HC-13) ---
for bin in docker curl nc grep; do
    if ! command -v "$bin" >/dev/null 2>&1; then
        echo -e "${RED}Error: required binary '$bin' is not installed.${NC}" >&2
        exit 1
    fi
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="$SCRIPT_DIR/../../infra-pki"
cd "$WORKDIR" || { echo "Error: Could not enter $WORKDIR"; exit 1; }

echo -e "${BLUE}========================================"
echo -e "   PKI Infrastructure Verification"
echo -e "========================================${NC}"
echo "Time: $(date)"
echo ""

# --- 0. Optional Dependency Check ---
if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}Warning: 'jq' is not installed. Output parsing will be limited.${NC}"
fi

# --- 1. Container Health ---
echo -e "${BLUE}1. Checking Container Health...${NC}"
CONTAINERS=("step-ca" "step-ca-db" "step-ca-proxy" "step-ca-configurator")
ALL_HEALTHY=true

# Check ALLOWED_IPS from .env (project-standard parsing: strip quotes, keep full value)
ALLOWED_IPS=$(grep "^ALLOWED_IPS=" .env | cut -d= -f2- | tr -d '"' || echo "Unknown")
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

# 2a. TRUE internal check: run step ca health INSIDE the container.
# This bypasses Caddy entirely — if this fails, the problem is step-ca/DB.
if docker exec step-ca step ca health 2>/dev/null | grep -q "ok"; then
    echo -e "  - Step-CA process (direct, in-container): ${GREEN}OK${NC}"
else
    echo -e "  - Step-CA process (direct, in-container): ${RED}FAILED${NC}"
    ALL_HEALTHY=false
    echo -e "    ${YELLOW}Hint: Check 'docker logs step-ca'. Verify DB connection and password.${NC}"
fi

# 2b. Subnet drift detector: the pki-net bridge subnet MUST be in ALLOWED_IPS.
# Host-originated connections reach Caddy with the bridge gateway as source IP;
# if the subnet is missing, Caddy L4 silently drops them (curl code 000).
PKI_NET_SUBNET=$(docker network inspect pki-net --format '{{(index .IPAM.Config 0).Subnet}}' 2>/dev/null || echo "")
if [ -z "$PKI_NET_SUBNET" ]; then
    echo -e "  - pki-net subnet: ${RED}NOT FOUND (network missing?)${NC}"
    ALL_HEALTHY=false
elif echo "$ALLOWED_IPS" | grep -qF "$PKI_NET_SUBNET"; then
    echo -e "  - pki-net subnet ($PKI_NET_SUBNET) in ALLOWED_IPS: ${GREEN}OK${NC}"
else
    echo -e "  - pki-net subnet ($PKI_NET_SUBNET) in ALLOWED_IPS: ${RED}MISSING — SUBNET DRIFT${NC}"
    ALL_HEALTHY=false
    echo -e "    ${YELLOW}Hint: Caddy L4 will DROP all host-originated connections (code 000).${NC}"
    echo -e "    ${YELLOW}Fix: add '$PKI_NET_SUBNET' to ALLOWED_IPS in .env, then 'docker compose restart caddy'.${NC}"
fi

# Check via Caddy proxy (published port). This is NOT a direct step-ca check:
# host -> Caddy L4 (remote_ip allowlist) -> step-ca:9000.
# Priority: 1. STEP_CA_URL (if set), 2. DOMAIN_CA (if set, +9000), 3. Localhost:9000
STEP_CA_URL=$(grep "^STEP_CA_URL=" .env | cut -d= -f2- | tr -d '"' || true)
DOMAIN_CA=$(grep "^DOMAIN_CA=" .env | cut -d= -f2- | tr -d '"' || true)

if [ -n "$STEP_CA_URL" ]; then
    CA_URL="$STEP_CA_URL"
elif [ -n "$DOMAIN_CA" ]; then
    CA_URL="https://${DOMAIN_CA}:9000"
else
    CA_URL="https://localhost:9000"
fi
echo -e "  - Target CA URL: ${YELLOW}$CA_URL${NC}"

# 1. TCP Check (NOTE: passes even if your IP is blocked — Caddy accepts, then drops)
if nc -z localhost 9000; then
    echo -e "  - Caddy Port 9000 (TCP):      ${GREEN}OPEN${NC}"
else
    echo -e "  - Caddy Port 9000 (TCP):      ${RED}CLOSED${NC}"
    ALL_HEALTHY=false
fi

# 2c. Via Caddy L4 proxy from the host (source IP = pki-net gateway)
if curl -sk "https://localhost:9000/health" --max-time 2 | grep -q "ok"; then
    echo -e "  - Via Caddy L4 proxy (host -> localhost:9000): ${GREEN}OK${NC}"
else
    HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" "https://localhost:9000/health" --max-time 3 || echo "ERR")
    echo -e "  - Via Caddy L4 proxy (host -> localhost:9000): ${RED}FAILED (Code: $HTTP_CODE)${NC}"
    ALL_HEALTHY=false
    echo -e "    ${YELLOW}Hint: Code '000'/'ERR' = Caddy dropped the connection (IP allowlist), NOT a certificate problem.${NC}"
    echo -e "    ${YELLOW}Hint: Verify the pki-net subnet check above and ALLOWED_IPS: $ALLOWED_IPS${NC}"
fi

# 2d. External URL check (through DNS + Caddy)
if [ "$CA_URL" != "https://localhost:9000" ]; then
    if curl -sk "$CA_URL/health" --max-time 2 | grep -q "ok"; then
        echo -e "  - External Health Endpoint ($CA_URL): ${GREEN}OK${NC}"
    else
        HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" "$CA_URL/health" --max-time 3 || echo "ERR")
        echo -e "  - External Health Endpoint ($CA_URL): ${RED}FAILED (Code: $HTTP_CODE)${NC}"
        ALL_HEALTHY=false
        echo -e "    ${YELLOW}Hint: Caddy uses IP Whitelisting (configured: $ALLOWED_IPS).${NC}"
        echo -e "    ${YELLOW}Hint: From this host, hairpin traffic arrives from the pki-net gateway, not your public IP.${NC}"
        echo -e "    ${YELLOW}Hint: If Code is '000' or 'ERR', your IP is likely blocked by Caddy or DNS is wrong.${NC}"
    fi
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
            ALL_HEALTHY=false
            echo -e "    ${YELLOW}Hint: Run './configure_pki.sh' or restart 'step-ca-configurator' container.${NC}"
        fi
    done
else
    echo -e "  - ${RED}Critical: Cannot list provisioners. Step-CA API not reachable.${NC}"
    ALL_HEALTHY=false
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
     ALL_HEALTHY=false
fi
echo ""

# --- Summary ---
echo -e "${BLUE}========================================"
if [ "$ALL_HEALTHY" == "true" ]; then
    echo -e "   ${GREEN}SYSTEM STATUS: OPERATIONAL${NC}"
    echo -e "========================================${NC}"
else
    echo -e "   ${RED}SYSTEM STATUS: ISSUES DETECTED${NC}"
    echo -e "   Review hints above or strictly check 'docker compose logs'."
    echo -e "========================================${NC}"
    exit 1
fi
