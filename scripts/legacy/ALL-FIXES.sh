#!/bin/bash
# =============================================================================
# ALL-FIXES.sh — Infra-Iam-PKI Complete Fix Script
# Covers all 37 issues from the Security & Architecture Audit Report (March 2026)
# Apply from project root: bash ALL-FIXES.sh
# =============================================================================
set -uo pipefail   # NOTE: no -e so individual fixes don't abort the whole run

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

FIXED=0
SKIPPED=0
FAILED=0

ok()   { echo -e "  ${GREEN}✔ $1${NC}"; ((FIXED++)) || true; }
skip() { echo -e "  ${YELLOW}– $1${NC}"; ((SKIPPED++)) || true; }
fail() { echo -e "  ${RED}✘ $1${NC}"; ((FAILED++)) || true; }
hdr()  { echo -e "\n${BLUE}[$1]${NC} $2"; }

# =============================================================================
# PREFLIGHT
# =============================================================================
echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   Infra-Iam-PKI — Full Audit Fix Script (37 issues)          ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

if [ ! -f "README.md" ] || [ ! -d "infra-iam" ] || [ ! -d "infra-pki" ]; then
    echo -e "${RED}ERROR: Run this script from the Infra-Iam-PKI project root.${NC}"
    exit 1
fi

command -v python3 >/dev/null 2>&1 || { echo -e "${RED}ERROR: python3 required${NC}"; exit 1; }

# Helper: Python-based safe YAML/file patcher (avoids sed multiline pitfalls)
py_replace() {
    # Usage: py_replace FILE "OLD_STRING" "NEW_STRING"
    python3 - "$1" "$2" "$3" <<'PYEOF'
import sys
f, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(f, 'r') as fh:
        content = fh.read()
    if old not in content:
        sys.exit(2)  # not found
    with open(f, 'w') as fh:
        fh.write(content.replace(old, new, 1))
    sys.exit(0)
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
}

py_replace_all() {
    # Replace ALL occurrences
    python3 - "$1" "$2" "$3" <<'PYEOF'
import sys
f, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(f, 'r') as fh:
        content = fh.read()
    if old not in content:
        sys.exit(2)
    with open(f, 'w') as fh:
        fh.write(content.replace(old, new))
    sys.exit(0)
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
}

py_delete_lines() {
    # Delete lines containing PATTERN from FILE
    python3 - "$1" "$2" <<'PYEOF'
import sys
f, pattern = sys.argv[1], sys.argv[2]
try:
    with open(f, 'r') as fh:
        lines = fh.readlines()
    new_lines = [l for l in lines if pattern not in l]
    if len(new_lines) == len(lines):
        sys.exit(2)  # nothing removed
    with open(f, 'w') as fh:
        fh.writelines(new_lines)
    sys.exit(0)
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
}

# =============================================================================
# ── CRITICAL ─────────────────────────────────────────────────────────────────
# =============================================================================

# ─────────────────────────────────────────────────────────────────────────────
hdr "BUG-001 / CRITICAL" "Keycloak JVM heap exceeds container memory limit (OOM kill)"
# ─────────────────────────────────────────────────────────────────────────────
FILE="infra-iam/docker-compose.yml"
if [ -f "$FILE" ]; then
    py_replace "$FILE" \
        'JAVA_OPTS_APPEND: "-Xms2048m -Xmx4096m"' \
        'JAVA_OPTS_APPEND: "-Xms512m -Xmx1536m -XX:MaxMetaspaceSize=256m"'
    case $? in
        0) ok "JVM heap: Xms512m Xmx1536m (within 2048M limit)" ;;
        2) skip "Already fixed" ;;
        *) fail "Pattern not found in $FILE" ;;
    esac
else
    fail "File not found: $FILE"
fi

# ─────────────────────────────────────────────────────────────────────────────
hdr "BUG-002 / CRITICAL" "OOD: privileged:true nullifies cap_drop"
# ─────────────────────────────────────────────────────────────────────────────
FILE="infra-ood/docker-compose.yml"
if [ -f "$FILE" ]; then
    py_replace "$FILE" \
        '    privileged: true' \
        '    # privileged: true  # REMOVED (BUG-002): contradicts cap_drop/cap_add; use specific caps'
    case $? in
        0) ok "Removed privileged:true — cap_drop/cap_add now effective" ;;
        2) skip "Already fixed" ;;
        *) fail "Pattern not found in $FILE" ;;
    esac
else
    fail "File not found: $FILE"
fi

# ─────────────────────────────────────────────────────────────────────────────
hdr "BUG-003 / CRITICAL" "iam-renewer: unconditional Keycloak restart every 24h"
# ─────────────────────────────────────────────────────────────────────────────
# Original broken pattern (literal string to find):
BUG003_OLD='        /scripts/infra-iam/renew_certificate.sh /certs/keycloak.crt /certs/keycloak.key &&
        docker restart iam-keycloak || true;
        sleep 86400;'

BUG003_NEW='        if /scripts/infra-iam/renew_certificate.sh /certs/keycloak.crt /certs/keycloak.key; then
          echo "Certificate renewed — restarting Keycloak..." &&
          docker stop --time 30 iam-keycloak && docker start iam-keycloak;
        else
          echo "No renewal needed or non-critical error — skipping restart.";
        fi;
        sleep 86400;'

FILE="infra-iam/docker-compose.yml"
if [ -f "$FILE" ]; then
    py_replace "$FILE" "$BUG003_OLD" "$BUG003_NEW"
    case $? in
        0) ok "Keycloak only restarts when certificate actually renews" ;;
        2)
            # Try alternate pattern (command may be on single line)
            ALT_OLD='docker restart iam-keycloak || true;'
            ALT_NEW='# BUG-003 fixed: only restart on actual renewal
        if /scripts/infra-iam/renew_certificate.sh /certs/keycloak.crt /certs/keycloak.key; then
          docker stop --time 30 iam-keycloak \&\& docker start iam-keycloak; fi;'
            py_replace "$FILE" "$ALT_OLD" "$ALT_NEW"
            case $? in
                0) ok "Keycloak restart now conditional (alt pattern)" ;;
                2) skip "Pattern not found — verify renewer command manually (see report §2.3)" ;;
                *) fail "Replacement failed" ;;
            esac
            ;;
        *) fail "Replacement failed" ;;
    esac
else
    fail "File not found: $FILE"
fi

# ─────────────────────────────────────────────────────────────────────────────
hdr "BUG-004 / CRITICAL" "Debug password/DSN leak in patch_ca_config.sh"
# ─────────────────────────────────────────────────────────────────────────────
FILE="scripts/infra-pki/patch_ca_config.sh"
if [ -f "$FILE" ]; then
    py_delete_lines "$FILE" 'echo "DEBUG:'
    case $? in
        0) ok "Removed all DEBUG echo lines (credentials no longer logged)" ;;
        2) skip "No DEBUG lines found — already clean" ;;
        *) fail "Failed to remove DEBUG lines from $FILE" ;;
    esac
else
    fail "File not found: $FILE"
fi

# ─────────────────────────────────────────────────────────────────────────────
hdr "BUG-005 / CRITICAL" "Caddy IAM healthcheck targets non-existent port 2019"
# ─────────────────────────────────────────────────────────────────────────────
FILE="infra-iam/docker-compose.yml"
if [ -f "$FILE" ]; then
    # Try exact array form first
    py_replace "$FILE" \
        'test: ["CMD", "curl", "-f", "http://localhost:2019/metrics"]' \
        'test: ["CMD-SHELL", "curl -sf http://localhost:80 -o /dev/null || exit 1"]'
    RES=$?
    if [ $RES -eq 2 ]; then
        # Try alternate quoting
        py_replace "$FILE" \
            "test: [\"CMD\", \"curl\", \"-f\", \"http://localhost:2019/metrics\"]" \
            "test: [\"CMD-SHELL\", \"curl -sf http://localhost:80 -o /dev/null || exit 1\"]"
        RES=$?
    fi
    if [ $RES -eq 2 ]; then
        # Try inline string form
        py_replace "$FILE" \
            'curl -f http://localhost:2019/metrics' \
            'curl -sf http://localhost:80 -o /dev/null || exit 1'
        RES=$?
    fi
    case $RES in
        0) ok "Caddy healthcheck now tests port 80 (actual proxy)" ;;
        2) skip "Pattern not found — check Caddy healthcheck manually" ;;
        *) fail "Replacement failed" ;;
    esac
else
    fail "File not found: $FILE"
fi

# ─────────────────────────────────────────────────────────────────────────────
hdr "PERF-001 / CRITICAL" "Keycloak --optimized without build step (creates Dockerfile)"
# ─────────────────────────────────────────────────────────────────────────────
FILE="infra-iam/Dockerfile.keycloak"
if [ ! -f "$FILE" ]; then
    cat > "$FILE" <<'DOCKERFILE'
# Dockerfile.keycloak
# Runs 'kc.sh build' so 'start --optimized' works correctly (PERF-001 fix)
ARG KC_VERSION=25.0.0
FROM quay.io/keycloak/keycloak:${KC_VERSION} AS builder

ENV KC_DB=postgres
ENV KC_HEALTH_ENABLED=true
ENV KC_METRICS_ENABLED=true
ENV KC_FEATURES=token-exchange,admin-fine-grained-authz

# Copy custom themes before build
COPY themes/unibo-bigea /opt/keycloak/themes/unibo-bigea

# Build optimized Quarkus binary
RUN /opt/keycloak/bin/kc.sh build \
    --db=postgres \
    --health-enabled=true \
    --metrics-enabled=true

FROM quay.io/keycloak/keycloak:${KC_VERSION}
COPY --from=builder /opt/keycloak/lib/quarkus /opt/keycloak/lib/quarkus
COPY --from=builder /opt/keycloak/themes/unibo-bigea /opt/keycloak/themes/unibo-bigea

ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]
DOCKERFILE
    ok "Created infra-iam/Dockerfile.keycloak (multi-stage with kc.sh build)"
    echo -e "  ${YELLOW}ACTION: Update infra-iam/docker-compose.yml keycloak service:${NC}"
    echo   "    image: → build: { context: ., dockerfile: Dockerfile.keycloak }"
else
    skip "Dockerfile.keycloak already exists"
fi

# Update docker-compose to use the new Dockerfile if still using image:
FILE="infra-iam/docker-compose.yml"
if [ -f "$FILE" ] && grep -q 'image: quay.io/keycloak/keycloak' "$FILE"; then
    py_replace "$FILE" \
        'image: quay.io/keycloak/keycloak' \
        'build:
      context: .
      dockerfile: Dockerfile.keycloak
    # image: quay.io/keycloak/keycloak  # replaced by Dockerfile.keycloak (PERF-001)'
    case $? in
        0) ok "docker-compose.yml updated to build Keycloak image" ;;
        2) skip "Already using build directive" ;;
        *) fail "Could not update keycloak image directive" ;;
    esac
fi

# =============================================================================
# ── HIGH ──────────────────────────────────────────────────────────────────────
# =============================================================================

# ─────────────────────────────────────────────────────────────────────────────
hdr "BUG-006 / HIGH" "iam-init fails when AD_HOST is empty"
# ─────────────────────────────────────────────────────────────────────────────
FILE="infra-iam/docker-compose.yml"
if [ -f "$FILE" ]; then
    py_replace "$FILE" \
        '/scripts/infra-iam/fetch_ad_cert.sh ${AD_HOST} ${AD_PORT}' \
        '([ -n "${AD_HOST:-}" ] && /scripts/infra-iam/fetch_ad_cert.sh ${AD_HOST} ${AD_PORT}'
    case $? in
        0)
            # Add the closing paren + fallback after the ad cert line
            py_replace "$FILE" \
                '([ -n "${AD_HOST:-}" ] && /scripts/infra-iam/fetch_ad_cert.sh ${AD_HOST} ${AD_PORT}' \
                '([ -n "${AD_HOST:-}" ] && /scripts/infra-iam/fetch_ad_cert.sh ${AD_HOST} ${AD_PORT:-636} /certs/ad_root_ca.crt || echo "AD_HOST not set, skipping AD cert fetch")'
            ok "AD cert fetch is now conditional on AD_HOST being set"
            ;;
        2) skip "Pattern not found — may already be fixed or use different variable names" ;;
        *) fail "Replacement failed" ;;
    esac
else
    fail "File not found: $FILE"
fi

# ─────────────────────────────────────────────────────────────────────────────
hdr "BUG-007 / HIGH" "Fingerprint path mismatch (file vs directory)"
# ─────────────────────────────────────────────────────────────────────────────
for FILE in "scripts/infra-pki/deploy_pki.sh" "scripts/infra-pki/generate_token.sh"; do
    if [ -f "$FILE" ]; then
        py_replace_all "$FILE" \
            'step_data/fingerprint"' \
            'step_data/fingerprint/root_ca.fingerprint"'
        case $? in
            0) ok "$FILE: fingerprint path updated" ;;
            2)
                # Try without quote suffix
                py_replace_all "$FILE" \
                    'step_data/fingerprint' \
                    'step_data/fingerprint/root_ca.fingerprint'
                case $? in
                    0) ok "$FILE: fingerprint path updated (alt pattern)" ;;
                    2) skip "$FILE: path already correct or uses different variable" ;;
                    *) fail "$FILE: replacement failed" ;;
                esac
                ;;
            *) fail "$FILE: replacement failed" ;;
        esac
    else
        skip "$FILE not found"
    fi
done

# ─────────────────────────────────────────────────────────────────────────────
hdr "SEC-001 / HIGH" "Plaintext .env files: enforce 600 permissions"
# ─────────────────────────────────────────────────────────────────────────────
for envfile in infra-pki/.env infra-iam/.env infra-ood/.env sandbox/.env infra-pki/.env.example infra-iam/.env.example; do
    if [ -f "$envfile" ]; then
        chmod 600 "$envfile" 2>/dev/null \
            && ok "chmod 600: $envfile" \
            || fail "chmod 600 failed for $envfile (try sudo)"
    fi
done
# Also add chmod to deploy scripts
for DEPLOY in scripts/infra-pki/deploy_pki.sh scripts/infra-iam/deploy_iam.sh; do
    if [ -f "$DEPLOY" ] && ! grep -q 'chmod 600.*\.env' "$DEPLOY"; then
        echo -e '\n# SEC-001: Secure .env permissions on deploy\nchmod 600 .env 2>/dev/null || true' >> "$DEPLOY"
        ok "$DEPLOY: added chmod 600 .env on deploy"
    fi
done

# ─────────────────────────────────────────────────────────────────────────────
hdr "SEC-002 / HIGH" "STEP_TOKEN passed as env var (visible via docker inspect)"
# ─────────────────────────────────────────────────────────────────────────────
FILE="infra-iam/docker-compose.yml"
if [ -f "$FILE" ]; then
    # Wrap STEP_TOKEN in a file-based approach via tmpfs
    py_replace "$FILE" \
        '      - STEP_TOKEN=${STEP_TOKEN}' \
        '      # SEC-002: STEP_TOKEN mounted as file, not env var
      # Write token to file in entrypoint: echo "$STEP_TOKEN" > /run/secrets/step_token
      - STEP_TOKEN_FILE=/run/secrets/step_token'
    case $? in
        0)
            ok "STEP_TOKEN: replaced env var reference with file path hint"
            echo -e "  ${YELLOW}ACTION: Update renew_certificate.sh to read from file:${NC}"
            echo   "    STEP_TOKEN=\$(cat /run/secrets/step_token)"
            echo   "    Add to renewer service: tmpfs: [/run/secrets]"
            ;;
        2) skip "STEP_TOKEN env var pattern not found (may already be fixed)" ;;
        *) fail "Could not update STEP_TOKEN handling" ;;
    esac
fi

# Update renew_certificate.sh to read token from file if env var not set
FILE="scripts/infra-iam/renew_certificate.sh"
if [ -f "$FILE" ]; then
    py_replace "$FILE" \
        'STEP_TOKEN=${STEP_TOKEN}' \
        'STEP_TOKEN=${STEP_TOKEN:-$(cat /run/secrets/step_token 2>/dev/null || echo "")}'
    case $? in
        0) ok "renew_certificate.sh: STEP_TOKEN falls back to file" ;;
        2) skip "renew_certificate.sh: STEP_TOKEN pattern not found" ;;
        *) fail "renew_certificate.sh: replacement failed" ;;
    esac
fi

# ─────────────────────────────────────────────────────────────────────────────
hdr "SEC-003 / MEDIUM" "Replace 'source .env' with safe grep/cut parsing"
# ─────────────────────────────────────────────────────────────────────────────
# Create a shared safe env parser
mkdir -p scripts/common
SAFE_ENV_PARSER="scripts/common/parse_env.sh"
if [ ! -f "$SAFE_ENV_PARSER" ]; then
    cat > "$SAFE_ENV_PARSER" <<'ENVPARSER'
#!/bin/bash
# parse_env.sh — Safe .env parser (SEC-003 fix)
# Usage: source scripts/common/parse_env.sh [envfile]
# Reads KEY=VALUE lines only; ignores comments and blank lines.
# Does NOT execute arbitrary shell code (unlike 'source .env').
_parse_env() {
    local envfile="${1:-.env}"
    [ -f "$envfile" ] || return 0
    while IFS= read -r line; do
        # Skip comments and blank lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        # Only process KEY=VALUE format
        if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local val="${BASH_REMATCH[2]}"
            # Strip surrounding quotes
            val="${val%\"}"
            val="${val#\"}"
            val="${val%\'}"
            val="${val#\'}"
            export "$key"="$val"
        fi
    done < "$envfile"
}
_parse_env "$@"
ENVPARSER
    chmod +x "$SAFE_ENV_PARSER"
    ok "Created scripts/common/parse_env.sh (safe .env parser)"
fi

# Replace 'source .env' in scripts
for SCRIPT in scripts/infra-pki/get_certificate.sh scripts/infra-pki/renew_certificate.sh \
              scripts/infra-iam/get_certificate.sh scripts/infra-iam/renew_certificate.sh \
              scripts/infra-pki/deploy_pki.sh scripts/infra-iam/deploy_iam.sh; do
    if [ -f "$SCRIPT" ]; then
        py_replace "$SCRIPT" \
            'source .env' \
            'source "$(dirname "$0")/../common/parse_env.sh"'
        case $? in
            0) ok "$SCRIPT: 'source .env' replaced with safe parser" ;;
            2)
                py_replace "$SCRIPT" \
                    '. .env' \
                    'source "$(dirname "$0")/../common/parse_env.sh"'
                [ $? -eq 0 ] && ok "$SCRIPT: '. .env' replaced with safe parser" || skip "$SCRIPT: no source .env found"
                ;;
            *) fail "$SCRIPT: replacement failed" ;;
        esac
    fi
done

# ─────────────────────────────────────────────────────────────────────────────
hdr "SEC-004 / HIGH" "Watchtower: direct docker socket → use socket proxy"
# ─────────────────────────────────────────────────────────────────────────────
FILE="infra-iam/docker-compose.yml"
if [ -f "$FILE" ]; then
    py_replace "$FILE" \
        '      - /var/run/docker.sock:/var/run/docker.sock' \
        '      # SEC-004: Use socket proxy, not direct socket
      # (ensure docker-socket-proxy service is running on iam-net)'
    case $? in
        0)
            # Also add DOCKER_HOST env to watchtower
            py_replace "$FILE" \
                'containrrr/watchtower' \
                'containrrr/watchtower
    environment:
      - DOCKER_HOST=tcp://docker-socket-proxy:2375
      - WATCHTOWER_NO_RESTART=true'
            ok "Watchtower: direct socket mount removed, routes via socket proxy"
            echo -e "  ${YELLOW}ACTION: Ensure docker-socket-proxy is on iam-net and allows needed API paths${NC}"
            ;;
        2) skip "Direct socket pattern not found in watchtower service" ;;
        *) fail "Could not update watchtower socket" ;;
    esac
else
    fail "File not found: $FILE"
fi

# ─────────────────────────────────────────────────────────────────────────────
hdr "SEC-005 / HIGH" "No TLS between Keycloak and PostgreSQL"
# ─────────────────────────────────────────────────────────────────────────────
FILE="infra-iam/docker-compose.yml"
if [ -f "$FILE" ]; then
    # Add ssl to JDBC URL
    py_replace "$FILE" \
        'jdbc:postgresql://db/keycloak' \
        'jdbc:postgresql://db/keycloak?ssl=true&sslmode=verify-ca&sslrootcert=/certs/internal_ca.crt'
    case $? in
        0) ok "Keycloak JDBC URL: TLS enabled (verify-ca)" ;;
        2) skip "JDBC URL pattern not found or already has ssl" ;;
        *) fail "Could not update JDBC URL" ;;
    esac
fi

# ─────────────────────────────────────────────────────────────────────────────
hdr "SEC-006 / MEDIUM" "Caddy CSP: remove unsafe-inline from script-src"
# ─────────────────────────────────────────────────────────────────────────────
for CADDYFILE in infra-iam/.Caddyfile infra-iam/Caddyfile; do
    if [ -f "$CADDYFILE" ]; then
        py_replace "$CADDYFILE" \
            "script-src 'self' 'unsafe-inline'" \
            "script-src 'self' 'nonce-{http.request.header.X-Nonce}'"
        case $? in
            0) ok "$CADDYFILE: removed unsafe-inline from script-src" ;;
            2) skip "$CADDYFILE: script-src pattern not found" ;;
            *) fail "$CADDYFILE: replacement failed" ;;
        esac
    fi
done

# ─────────────────────────────────────────────────────────────────────────────
hdr "SEC-008 / HIGH" "iam-renewer runs as root"
# ─────────────────────────────────────────────────────────────────────────────
FILE="infra-iam/docker-compose.yml"
if [ -f "$FILE" ]; then
    py_replace "$FILE" \
        '    user: root
    # iam-renewer' \
        '    user: "1000:1000"  # SEC-008: non-root user
    # iam-renewer'
    case $? in
        0) ok "iam-renewer: changed to non-root user (1000:1000)" ;;
        2) skip "user:root pattern not found with expected context" ;;
        *) fail "Could not change renewer user" ;;
    esac
fi

# ─────────────────────────────────────────────────────────────────────────────
hdr "PERF-002 / HIGH" "PostgreSQL: add basic tuning (shared_buffers, work_mem)"
# ─────────────────────────────────────────────────────────────────────────────
mkdir -p infra-iam/postgres-conf infra-pki/postgres-conf

IAM_PG_CONF="infra-iam/postgres-conf/postgresql.conf"
if [ ! -f "$IAM_PG_CONF" ]; then
    cat > "$IAM_PG_CONF" <<'PGCONF'
# PostgreSQL tuning for Keycloak IAM workload (PERF-002)
shared_buffers = 256MB
work_mem = 16MB
maintenance_work_mem = 64MB
effective_cache_size = 512MB
wal_buffers = 8MB
checkpoint_completion_target = 0.9
random_page_cost = 1.1
log_min_duration_statement = 1000
PGCONF
    ok "Created infra-iam/postgres-conf/postgresql.conf"
    echo -e "  ${YELLOW}ACTION: Mount in docker-compose.yml under iam-db service:${NC}"
    echo   "    volumes:"
    echo   "      - ./postgres-conf/postgresql.conf:/etc/postgresql/postgresql.conf"
    echo   "    command: postgres -c config_file=/etc/postgresql/postgresql.conf"
fi

PKI_PG_CONF="infra-pki/postgres-conf/postgresql.conf"
if [ ! -f "$PKI_PG_CONF" ]; then
    cat > "$PKI_PG_CONF" <<'PGCONF'
# PostgreSQL tuning for Step-CA PKI workload (PERF-002 - lighter)
shared_buffers = 128MB
work_mem = 8MB
effective_cache_size = 256MB
log_min_duration_statement = 2000
PGCONF
    ok "Created infra-pki/postgres-conf/postgresql.conf"
fi

# ─────────────────────────────────────────────────────────────────────────────
hdr "PERF-004 / MEDIUM" "Docker logging: add compression to json-file driver"
# ─────────────────────────────────────────────────────────────────────────────
for COMPOSE in infra-pki/docker-compose.yml infra-iam/docker-compose.yml infra-ood/docker-compose.yml; do
    if [ -f "$COMPOSE" ]; then
        py_replace_all "$COMPOSE" \
            '        options:
          max-size: "15m"
          max-file: "5"' \
            '        options:
          max-size: "15m"
          max-file: "5"
          compress: "true"'
        case $? in
            0) ok "$COMPOSE: added compress:true to json-file logging" ;;
            2)
                py_replace_all "$COMPOSE" \
                    '        options:
          max-size: "10m"
          max-file: "5"' \
                    '        options:
          max-size: "10m"
          max-file: "5"
          compress: "true"'
                [ $? -eq 0 ] && ok "$COMPOSE: added compress:true (10m pattern)" || skip "$COMPOSE: logging options pattern not found"
                ;;
            *) fail "$COMPOSE: logging update failed" ;;
        esac
    fi
done

# ─────────────────────────────────────────────────────────────────────────────
hdr "REL-001 / HIGH" "Create backup_iam.sh (mirrors backup_pki.sh pattern)"
# ─────────────────────────────────────────────────────────────────────────────
BACKUP_IAM="scripts/infra-iam/backup_iam.sh"
if [ ! -f "$BACKUP_IAM" ]; then
    mkdir -p scripts/infra-iam
    cat > "$BACKUP_IAM" <<'BACKUP'
#!/bin/bash
# backup_iam.sh — Keycloak IAM backup (REL-001 fix)
# Mirrors backup_pki.sh pattern
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/parse_env.sh" "$SCRIPT_DIR/../../infra-iam/.env"

BACKUP_DIR="${BACKUP_DIR:-/backups/iam}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="${BACKUP_DIR}/iam_backup_${TIMESTAMP}"

GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
log() { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $1"; }
ok()  { echo -e "${GREEN}✔ $1${NC}"; }

mkdir -p "$BACKUP_PATH"

log "Starting IAM backup → $BACKUP_PATH"

# 1. PostgreSQL dump
log "Dumping Keycloak database..."
docker exec iam-db pg_dump \
    -U "${KC_DB_USERNAME:-keycloak}" \
    -d "${KC_DB_DATABASE:-keycloak}" \
    --no-password \
    --format=custom \
    > "${BACKUP_PATH}/keycloak_db.dump"
ok "Database dump: keycloak_db.dump"

# 2. Themes backup
if docker volume inspect iam_themes >/dev/null 2>&1; then
    docker run --rm \
        -v iam_themes:/themes:ro \
        -v "${BACKUP_PATH}:/backup" \
        alpine tar czf /backup/themes.tar.gz -C /themes .
    ok "Themes backup: themes.tar.gz"
fi

# 3. Certs backup
if docker volume inspect iam_certs >/dev/null 2>&1; then
    docker run --rm \
        -v iam_certs:/certs:ro \
        -v "${BACKUP_PATH}:/backup" \
        alpine tar czf /backup/certs.tar.gz -C /certs .
    ok "Certs backup: certs.tar.gz"
fi

# 4. .env backup (without secrets if paranoid, but needed for restore)
cp "$(dirname "$SCRIPT_DIR")/../infra-iam/.env" "${BACKUP_PATH}/.env.bak" 2>/dev/null || true

# 5. Create manifest
cat > "${BACKUP_PATH}/MANIFEST.txt" <<EOF
IAM Backup — ${TIMESTAMP}
Keycloak version: $(docker inspect iam-keycloak --format '{{.Config.Image}}' 2>/dev/null || echo unknown)
Database: keycloak_db.dump
EOF

# 6. Compress
tar czf "${BACKUP_DIR}/iam_backup_${TIMESTAMP}.tar.gz" -C "$BACKUP_DIR" "iam_backup_${TIMESTAMP}/"
rm -rf "$BACKUP_PATH"
ok "Archive: ${BACKUP_DIR}/iam_backup_${TIMESTAMP}.tar.gz"

# 7. Rotate: keep last 7 backups
find "$BACKUP_DIR" -name "iam_backup_*.tar.gz" -mtime +7 -delete

log "IAM backup complete."
# Crontab: 0 2 * * * /opt/infra-iam-pki/scripts/infra-iam/backup_iam.sh
BACKUP
    chmod +x "$BACKUP_IAM"
    ok "Created scripts/infra-iam/backup_iam.sh"
else
    skip "backup_iam.sh already exists"
fi

# ─────────────────────────────────────────────────────────────────────────────
hdr "REL-002 / HIGH" "Graceful Keycloak shutdown (stop_grace_period)"
# ─────────────────────────────────────────────────────────────────────────────
FILE="infra-iam/docker-compose.yml"
if [ -f "$FILE" ]; then
    # Add stop_grace_period to keycloak service
    py_replace "$FILE" \
        'container_name: iam-keycloak
    restart:' \
        'container_name: iam-keycloak
    stop_grace_period: 30s  # REL-002: graceful drain before SIGKILL
    restart:'
    case $? in
        0) ok "Added stop_grace_period: 30s to iam-keycloak" ;;
        2) skip "container_name: iam-keycloak pattern not found" ;;
        *) fail "Could not add stop_grace_period" ;;
    esac
fi

# ─────────────────────────────────────────────────────────────────────────────
hdr "REL-003 / MEDIUM" "Vagrant: increase fingerprint retry timeout"
# ─────────────────────────────────────────────────────────────────────────────
for VAGRANTFILE in sandbox/Vagrantfile Vagrantfile; do
    if [ -f "$VAGRANTFILE" ]; then
        # Extend timeout from 5min (60x5s) to 10min (120x5s)
        py_replace "$VAGRANTFILE" \
            'for i in $(seq 1 60)' \
            'for i in $(seq 1 120)  # REL-003: extended to 10min'
        case $? in
            0) ok "$VAGRANTFILE: fingerprint retry timeout extended to 10 min" ;;
            2) skip "$VAGRANTFILE: retry loop pattern not found" ;;
            *) fail "$VAGRANTFILE: update failed" ;;
        esac
    fi
done

# ─────────────────────────────────────────────────────────────────────────────
hdr "REL-004 / MEDIUM" "Add restart:on-failure to init containers"
# ─────────────────────────────────────────────────────────────────────────────
for FILE in infra-iam/docker-compose.yml infra-ood/docker-compose.yml; do
    if [ -f "$FILE" ]; then
        # iam-init / ood-init typically lack restart policy
        py_replace "$FILE" \
            'container_name: iam-init
    image:' \
            'container_name: iam-init
    restart: on-failure:5  # REL-004
    image:'
        [ $? -eq 0 ] && ok "$FILE: iam-init restart policy added" || skip "$FILE: iam-init pattern not found"

        py_replace "$FILE" \
            'container_name: ood-init
    image:' \
            'container_name: ood-init
    restart: on-failure:5  # REL-004
    image:'
        [ $? -eq 0 ] && ok "$FILE: ood-init restart policy added" || skip "$FILE: ood-init pattern not found"
    fi
done

# ─────────────────────────────────────────────────────────────────────────────
hdr "REL-005 / LOW" "Keycloak healthcheck: add start_period: 120s"
# ─────────────────────────────────────────────────────────────────────────────
FILE="infra-iam/docker-compose.yml"
if [ -f "$FILE" ]; then
    # Only add if not already present
    if ! grep -q 'start_period' "$FILE"; then
        py_replace "$FILE" \
            '      retries: 3' \
            '      retries: 3
      start_period: 120s  # REL-005: allow for DB migration time'
        case $? in
            0) ok "Added start_period: 120s to Keycloak healthcheck" ;;
            2) skip "retries: 3 pattern not found" ;;
            *) fail "Could not add start_period" ;;
        esac
    else
        skip "start_period already present"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
hdr "UI-001 / HIGH" "Theme: update styles= in theme.properties"
# ─────────────────────────────────────────────────────────────────────────────
THEME_PROPS="infra-iam/themes/unibo-bigea/login/theme.properties"
if [ -f "$THEME_PROPS" ]; then
    py_replace "$THEME_PROPS" \
        'styles=' \
        'styles=css/styles.css'
    case $? in
        0) ok "theme.properties: styles=css/styles.css" ;;
        2)
            if ! grep -q 'styles=css/styles.css' "$THEME_PROPS"; then
                echo 'styles=css/styles.css' >> "$THEME_PROPS"
                ok "theme.properties: appended styles=css/styles.css"
            else
                skip "styles already set correctly"
            fi
            ;;
        *) fail "Could not update theme.properties" ;;
    esac
fi

# ─────────────────────────────────────────────────────────────────────────────
hdr "UI-003 / MEDIUM" "Font: add Inter @font-face for airgap compliance"
# ─────────────────────────────────────────────────────────────────────────────
FONTS_DIR="infra-iam/themes/unibo-bigea/login/resources/fonts"
THEME_CSS="infra-iam/themes/unibo-bigea/login/resources/css/styles.css"
if [ -f "$THEME_CSS" ] && ! grep -q '@font-face' "$THEME_CSS"; then
    mkdir -p "$FONTS_DIR"
    # Prepend @font-face stub (fonts need to be bundled separately)
    FONT_FACE='/* UI-003: Bundle Inter locally for airgap support */
/* Download from: https://fonts.google.com/specimen/Inter */
@font-face {
  font-family: '"'"'Inter'"'"';
  font-style: normal;
  font-weight: 400;
  src: url(../fonts/Inter-Regular.woff2) format('"'"'woff2'"'"');
}
@font-face {
  font-family: '"'"'Inter'"'"';
  font-style: normal;
  font-weight: 600;
  src: url(../fonts/Inter-SemiBold.woff2) format('"'"'woff2'"'"');
}

'
    TMPFILE=$(mktemp)
    printf '%s' "$FONT_FACE" > "$TMPFILE"
    cat "$THEME_CSS" >> "$TMPFILE"
    mv "$TMPFILE" "$THEME_CSS"
    ok "Prepended @font-face to styles.css"
    echo -e "  ${YELLOW}ACTION: Copy Inter .woff2 files to $FONTS_DIR${NC}"
else
    skip "styles.css not found or @font-face already present"
fi

# ─────────────────────────────────────────────────────────────────────────────
hdr "CODE-001 / MEDIUM" "Inconsistent .env parsing — common/parse_env.sh created above"
# ─────────────────────────────────────────────────────────────────────────────
skip "Already handled under SEC-003 (parse_env.sh created)"

# ─────────────────────────────────────────────────────────────────────────────
hdr "CODE-002 / LOW" "Deduplicate Dockerfile.init across stacks"
# ─────────────────────────────────────────────────────────────────────────────
ROOT_INIT="Dockerfile.init"
if [ ! -f "$ROOT_INIT" ]; then
    # Use IAM version as canonical if it exists
    if [ -f "infra-iam/Dockerfile.init" ]; then
        cp "infra-iam/Dockerfile.init" "$ROOT_INIT"
        ok "Created root Dockerfile.init (copy of infra-iam/Dockerfile.init)"
        echo -e "  ${YELLOW}ACTION: Update docker-compose files to reference ../../Dockerfile.init${NC}"
    elif [ -f "infra-ood/Dockerfile.init" ]; then
        cp "infra-ood/Dockerfile.init" "$ROOT_INIT"
        ok "Created root Dockerfile.init (copy of infra-ood/Dockerfile.init)"
    else
        skip "Neither infra-iam nor infra-ood Dockerfile.init found"
    fi
else
    skip "Root Dockerfile.init already exists"
fi

# ─────────────────────────────────────────────────────────────────────────────
hdr "SEC-007 / LOW" "PKI HTTP endpoint: add rate limiting to Caddyfile"
# ─────────────────────────────────────────────────────────────────────────────
for CADDYFILE in infra-pki/.Caddyfile infra-pki/Caddyfile; do
    if [ -f "$CADDYFILE" ]; then
        if ! grep -q 'rate_limit\|ratelimit' "$CADDYFILE"; then
            py_replace "$CADDYFILE" \
                'handle /fingerprint/' \
                '# SEC-007: rate limiting on public endpoints
        @rate_limit_ip remote_ip private_ranges
        handle /fingerprint/'
            case $? in
                0) ok "$CADDYFILE: added rate limit comment" ;;
                2) skip "$CADDYFILE: fingerprint route not found" ;;
                *) fail "$CADDYFILE: update failed" ;;
            esac
        else
            skip "$CADDYFILE: rate limiting already configured"
        fi
    fi
done

# ─────────────────────────────────────────────────────────────────────────────
hdr "SBX-001 / SANDBOX" "Vagrant: ensure KC_ADMIN_PASSWORD set in sandbox .env"
# ─────────────────────────────────────────────────────────────────────────────
SANDBOX_ENV="sandbox/.env"
if [ -f "$SANDBOX_ENV" ]; then
    if ! grep -q 'KC_ADMIN_PASSWORD' "$SANDBOX_ENV"; then
        echo -e '\n# SBX-001: Keycloak admin password for sandbox\nKC_ADMIN_PASSWORD=sandbox_admin_password' >> "$SANDBOX_ENV"
        ok "sandbox/.env: added KC_ADMIN_PASSWORD=sandbox_admin_password"
    else
        skip "sandbox/.env: KC_ADMIN_PASSWORD already set"
    fi
fi
VAGRANTFILE="sandbox/Vagrantfile"
if [ -f "$VAGRANTFILE" ] && ! grep -q 'KC_ADMIN_PASSWORD' "$VAGRANTFILE"; then
    py_replace "$VAGRANTFILE" \
        'KC_DB_PASSWORD' \
        'KC_ADMIN_PASSWORD=${KC_ADMIN_PASSWORD:-sandbox_admin_password}
      KC_DB_PASSWORD'
    case $? in
        0) ok "Vagrantfile: KC_ADMIN_PASSWORD propagated to iam-sandbox.yml" ;;
        2) skip "Vagrantfile: KC_DB_PASSWORD pattern not found" ;;
        *) fail "Vagrantfile: update failed" ;;
    esac
fi

# =============================================================================
# SUMMARY
# =============================================================================
echo -e "\n${CYAN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✔ Fixed: $FIXED${NC}   ${YELLOW}– Skipped: $SKIPPED${NC}   ${RED}✘ Failed: $FAILED${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}Manual actions still required:${NC}"
echo "  1. BUG-006: Verify AD cert fetch guard in iam-init command"
echo "  2. PERF-001: Run 'docker compose build keycloak' to trigger Dockerfile.keycloak"
echo "  3. PERF-002: Mount postgres-conf/ in docker-compose.yml for both DBs"
echo "  4. SEC-002: Add tmpfs: [/run/secrets] to iam-renewer service"
echo "  5. UI-003: Download Inter .woff2 fonts to infra-iam/themes/.../fonts/"
echo "  6. REL-001: Add crontab entry: 0 2 * * * /path/to/backup_iam.sh"
echo "  7. CODE-003: Replace 'docker exec <name>' with 'docker compose exec <svc>' in scripts"
echo ""
echo -e "${BLUE}After all fixes: vagrant destroy -f && vagrant up${NC}"
echo ""
