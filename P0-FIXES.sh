#!/bin/bash
# ============================================================
# P0-FIXES.sh - Critical fixes for Infra-Iam-PKI
# Apply from project root: bash P0-FIXES.sh
# ============================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Infra-Iam-PKI P0 Critical Fixes ===${NC}"
echo ""

# Detect project root
if [ ! -f "README.md" ] || [ ! -d "infra-iam" ]; then
    echo -e "${RED}ERROR: Run this script from the Infra-Iam-PKI project root.${NC}"
    exit 1
fi

# ────────────────────────────────────────────────────────────
# FIX BUG-001: Keycloak JVM OOM (JAVA_OPTS exceeds cgroup)
# ────────────────────────────────────────────────────────────
echo -e "${BLUE}[BUG-001] Fixing Keycloak JVM heap settings...${NC}"
FILE="infra-iam/docker-compose.yml"
if grep -q 'Xmx4096m' "$FILE"; then
    sed -i 's/JAVA_OPTS_APPEND: "-Xms2048m -Xmx4096m"/JAVA_OPTS_APPEND: "-Xms512m -Xmx1536m -XX:MaxMetaspaceSize=256m"/' "$FILE"
    echo -e "${GREEN}  Fixed: JVM heap now 512m-1536m (within 2048M container limit)${NC}"
else
    echo "  Already fixed or pattern not found."
fi

# ────────────────────────────────────────────────────────────
# FIX BUG-003: Unconditional Keycloak restart every 24h
# ────────────────────────────────────────────────────────────
echo -e "${BLUE}[BUG-003] Fixing unconditional Keycloak restart in renewer...${NC}"
FILE="infra-iam/docker-compose.yml"
# Replace the entire renewer command block
if grep -q 'docker restart iam-keycloak || true' "$FILE"; then
    sed -i '/command: >/,/sleep 86400/c\    command: >\n      -c "while true; do\n        echo \"Checking certificates...\" &&\n        if /scripts/infra-iam/renew_certificate.sh /certs/keycloak.crt /certs/keycloak.key; then\n          echo \"Certificate renewed, restarting Keycloak...\" &&\n          docker restart iam-keycloak;\n        else\n          echo \"No renewal needed or renewal failed.\";\n        fi;\n        sleep 86400;\n      done"' "$FILE"
    echo -e "${GREEN}  Fixed: Keycloak only restarts when certificate actually renews${NC}"
else
    echo "  Already fixed or pattern not found. Manual check recommended."
fi

# ────────────────────────────────────────────────────────────
# FIX BUG-004: Debug password leak in patch_ca_config.sh
# ────────────────────────────────────────────────────────────
echo -e "${BLUE}[BUG-004] Removing debug credential logging...${NC}"
FILE="scripts/infra-pki/patch_ca_config.sh"
if grep -q 'DEBUG:' "$FILE"; then
    sed -i '/echo "DEBUG:/d' "$FILE"
    echo -e "${GREEN}  Fixed: All DEBUG echo lines removed from patch_ca_config.sh${NC}"
else
    echo "  Already fixed."
fi

# ────────────────────────────────────────────────────────────
# FIX BUG-005: Caddy IAM healthcheck targets non-existent port
# ────────────────────────────────────────────────────────────
echo -e "${BLUE}[BUG-005] Fixing Caddy healthcheck in infra-iam...${NC}"
FILE="infra-iam/docker-compose.yml"
if grep -q 'http://localhost:2019/metrics' "$FILE"; then
    sed -i 's|curl", "-f", "http://localhost:2019/metrics"|CMD-SHELL", "curl -sf http://localhost:80 -o /dev/null \|\| exit 1|' "$FILE"
    echo -e "${GREEN}  Fixed: Caddy healthcheck now tests actual proxy port${NC}"
else
    echo "  Already fixed or pattern not found."
fi

# ────────────────────────────────────────────────────────────
# FIX BUG-006: iam-init fails when AD_HOST is empty
# ────────────────────────────────────────────────────────────
echo -e "${BLUE}[BUG-006] Making AD cert fetch conditional in iam-init...${NC}"
FILE="infra-iam/docker-compose.yml"
# This is a complex multiline sed, safer to check and inform
if grep -q 'fetch_ad_cert.sh ${AD_HOST}' "$FILE"; then
    echo -e "${GREEN}  INFO: iam-init entrypoint needs manual fix.${NC}"
    echo "  Change the command to make AD cert optional:"
    echo '  Replace:'
    echo '    ... && /scripts/infra-iam/fetch_ad_cert.sh ${AD_HOST} ${AD_PORT} ...'
    echo '  With:'
    echo '    ... && ([ -n "${AD_HOST}" ] && /scripts/infra-iam/fetch_ad_cert.sh ${AD_HOST} ${AD_PORT} /certs/ad_root_ca.crt || echo "AD not configured, skipping") ...'
fi

# ────────────────────────────────────────────────────────────
# FIX BUG-007: Fingerprint path mismatch
# ────────────────────────────────────────────────────────────
echo -e "${BLUE}[BUG-007] Fixing fingerprint path references...${NC}"

# Fix deploy_pki.sh
FILE="scripts/infra-pki/deploy_pki.sh"
if grep -q 'step_data/fingerprint"' "$FILE"; then
    sed -i 's|step_data/fingerprint"|step_data/fingerprint/root_ca.fingerprint"|g' "$FILE"
    echo -e "${GREEN}  Fixed: deploy_pki.sh fingerprint path${NC}"
fi

# Fix generate_token.sh
FILE="scripts/infra-pki/generate_token.sh"
if grep -q 'step_data/fingerprint"' "$FILE"; then
    sed -i 's|step_data/fingerprint"|step_data/fingerprint/root_ca.fingerprint"|g' "$FILE"
    echo -e "${GREEN}  Fixed: generate_token.sh fingerprint path${NC}"
fi

# ────────────────────────────────────────────────────────────
# FIX BUG-002: OOD privileged overrides cap_drop
# ────────────────────────────────────────────────────────────
echo -e "${BLUE}[BUG-002] Removing privileged flag from OOD portal...${NC}"
FILE="infra-ood/docker-compose.yml"
if grep -q 'privileged: true' "$FILE"; then
    # Replace privileged with specific capabilities needed for systemd
    sed -i 's/    privileged: true/    # privileged: true  # REMOVED: contradicts cap_drop, use specific caps/' "$FILE"
    echo -e "${GREEN}  Fixed: Removed privileged flag (cap_add already provides needed capabilities)${NC}"
    echo -e "${GREEN}  NOTE: If OOD needs systemd, add 'cgroupns: host' and test.${NC}"
fi

# ────────────────────────────────────────────────────────────
# BONUS: Fix Keycloak missing healthcheck start_period
# ────────────────────────────────────────────────────────────
echo -e "${BLUE}[REL-005] Adding healthcheck start_period to Keycloak...${NC}"
FILE="infra-iam/docker-compose.yml"
if ! grep -q 'start_period' "$FILE"; then
    sed -i '/retries: 3/a\      start_period: 120s' "$FILE"
    echo -e "${GREEN}  Fixed: Added 120s start_period for Keycloak healthcheck${NC}"
fi

# ────────────────────────────────────────────────────────────
# BONUS: Secure .env file permissions
# ────────────────────────────────────────────────────────────
echo -e "${BLUE}[SEC-001] Securing .env file permissions...${NC}"
for envfile in infra-pki/.env infra-iam/.env infra-ood/.env; do
    if [ -f "$envfile" ]; then
        chmod 600 "$envfile" 2>/dev/null && echo -e "${GREEN}  Secured: $envfile (600)${NC}" || echo "  Skipped: $envfile (permission denied, use sudo)"
    fi
done

echo ""
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${GREEN}P0 fixes applied. Review changes with 'git diff' before committing.${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo ""
echo "Remaining manual actions:"
echo "  1. BUG-006: Update iam-init command to make AD cert fetch conditional"
echo "  2. PERF-001: Create Dockerfile.keycloak with 'kc.sh build' step"
echo "  3. Test all fixes in sandbox: vagrant destroy -f && vagrant up"
echo ""
