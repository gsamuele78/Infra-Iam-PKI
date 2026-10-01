#!/bin/bash
set -euo pipefail

# .ai/validate.sh
# ══════════════════════════════════════════════════════════════
# Validates the ACTUAL CODEBASE against the project's hard
# constraints. This is the enforcement layer — run locally
# before committing or in CI on every push.
#
# Usage:
#   .ai/validate.sh              # Full validation
#   .ai/validate.sh --ci         # CI mode (no colors, exit code only)
#   .ai/validate.sh --fix-hint   # Show fix suggestions for failures
#
# Exit codes:
#   0 = All checks passed
#   1 = Hard constraint violations found (MUST fix before merge)
#   2 = Warnings found (should review but not blocking)
# ══════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Verify required core dependencies (Fail Fast)
for cmd in awk sed grep find xargs tr head cut; do
    command -v "$cmd" >/dev/null 2>&1 || { echo -e "[\033[0;31m✗ FAIL\033[0m] Missing required dependency: $cmd"; exit 1; }
done

# Parse flags
CI_MODE=false
SHOW_HINTS=false
for arg in "$@"; do
    case "$arg" in
        --ci) CI_MODE=true ;;
        --fix-hint) SHOW_HINTS=true ;;
    esac
done

# Colors (disabled in CI)
if [ "$CI_MODE" = true ]; then
    RED="" GREEN="" YELLOW="" BLUE="" NC="" BOLD=""
else
    RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m'
    BLUE='\033[0;34m' NC='\033[0m' BOLD='\033[1m'
fi

ERRORS=0
WARNINGS=0
CHECKS=0

pass() { echo -e "  ${GREEN}✓${NC} $1"; }
fail() { echo -e "  ${RED}✗ FAIL:${NC} $1"; ERRORS=$((ERRORS + 1)); }
warn() { echo -e "  ${YELLOW}⚠ WARN:${NC} $1"; WARNINGS=$((WARNINGS + 1)); }
hint() { if [ "$SHOW_HINTS" = true ]; then echo -e "    ${BLUE}→ Fix:${NC} $1"; fi; return 0; }
section() { echo ""; echo -e "${BOLD}[$1]${NC}"; }

COMPOSE_FILES=$(find "$PROJECT_ROOT" -name 'docker-compose.yml' -not -path '*/old/*' -not -path '*/.git/*' -not -path '*/kubernetes-deploy/*' 2>/dev/null || true)
SANDBOX_COMPOSE=$(find "$PROJECT_ROOT/sandbox" -name '*.yml' -not -path '*/.git/*' 2>/dev/null || true)

SCRIPTS=$(find "$PROJECT_ROOT" -name '*.sh' -not -path '*/.git/*' -not -path '*/.vagrant/*' -not -path '*/node_modules/*' -not -path '*/.serena/*' -not -path '*/.omo/*' 2>/dev/null | sort || true)

# Vendored trees (infra-rstudio/UPSTREAM.lock) are byte-identical copies of
# R-studioConf: their scripts are governed by R-studioConf's own gate and their
# integrity by `scripts/infra-rstudio/sync_rstudioconf.sh --check`. Script-level
# checks skip them; compose/Dockerfile checks still apply. Local files listed
# in the lock stay in scope.
VENDOR_LOCK="$PROJECT_ROOT/infra-rstudio/UPSTREAM.lock"
VENDORED_SCRIPTS=""
if [ -f "$VENDOR_LOCK" ] && command -v jq >/dev/null 2>&1; then
    while IFS=$'\t' read -r vdir vlocal vfiles; do
        while IFS= read -r s; do
            rel="${s#"$PROJECT_ROOT/$vdir/"}"
            if [ "$vfiles" != null ]; then
                jq -e --arg r "$rel" 'index($r) != null' <<<"$vfiles" >/dev/null || continue
            else
                jq -e --arg r "$rel" 'index($r) != null' <<<"$vlocal" >/dev/null && continue
            fi
            VENDORED_SCRIPTS="${VENDORED_SCRIPTS}${s}"$'\n'
        done < <(printf '%s\n' "$SCRIPTS" | grep -F "$PROJECT_ROOT/$vdir/" || true)
    done < <(jq -r '.mappings[] | [.to, (.local // [] | tojson), (.files // null | tojson)] | @tsv' "$VENDOR_LOCK")
    if [ -n "$VENDORED_SCRIPTS" ]; then
        SCRIPTS=$(comm -23 <(printf '%s\n' "$SCRIPTS" | sort) <(printf '%s' "$VENDORED_SCRIPTS" | sort))
    fi
fi
DOCKERFILES=$(find "$PROJECT_ROOT" -name 'Dockerfile*' -not -path '*/.git/*' -not -path '*/kubernetes-deploy/*' 2>/dev/null || true)

echo -e "${BOLD}═══════════════════════════════════════${NC}"
echo -e "${BOLD}  Infra-IAM-PKI Constraint Validator${NC}"
echo -e "${BOLD}═══════════════════════════════════════${NC}"
echo "  Project root: $PROJECT_ROOT"
echo "  Mode: $([ "$CI_MODE" = true ] && echo 'CI' || echo 'Interactive')"

# ──────────────────────────────────────────────────────────────
# HC-01: Every container MUST have deploy.resources.limits
# ──────────────────────────────────────────────────────────────
section "HC-01: Resource limits on all containers"
for f in $COMPOSE_FILES; do
    CHECKS=$((CHECKS + 1))
    rel_path="${f#$PROJECT_ROOT/}"
    # Extract service names
    services=$(awk '/^services:/ {in_src=1; next} /^[^ ]/ {in_src=0} in_src && /^  [a-zA-Z0-9_-]+:/ {print $1}' "$f" | sed 's/://' || true)
    for svc in $services; do
        # Check if this service has deploy.resources.limits
        # Use an awk block to extract just that service
        if ! awk -v svc="$svc" 'BEGIN{p=0} /^  [a-zA-Z0-9_-]+:/{if($1==svc":"){p=1}else{p=0}} p{print}' "$f" | grep -q 'limits:'; then
            # Exempt one-shot containers that have restart: "no" or no restart policy
            if awk -v svc="$svc" 'BEGIN{p=0} /^  [a-zA-Z0-9_-]+:/{if($1==svc":"){p=1}else{p=0}} p{print}' "$f" | grep -qE 'restart:\s*"?no"?'; then
                warn "$rel_path → service '$svc' has no resource limits (one-shot, non-critical)"
            else
                fail "$rel_path → service '$svc' missing deploy.resources.limits"
                hint "Add deploy.resources.limits.memory and deploy.resources.limits.cpus"
            fi
        fi
    done
done
[ "$ERRORS" -eq 0 ] && pass "All production compose services have resource limits"

# ──────────────────────────────────────────────────────────────
# HC-01b: Every long-running service has a healthcheck
# One-shot services (restart: "no" or on-failure:N) are exempt: they are gated with
# condition: service_completed_successfully instead.
# ──────────────────────────────────────────────────────────────
section "HC-01b: Healthcheck on every long-running service"
HC01B_ERRORS_BEFORE=$ERRORS
for f in $COMPOSE_FILES; do
    rel_path="${f#$PROJECT_ROOT/}"
    services=$(awk '/^services:/ {in_src=1; next} /^[^ #]/ {in_src=0} in_src && /^  [a-zA-Z0-9_-]+:/ {print $1}' "$f" | sed 's/://' || true)
    for svc in $services; do
        CHECKS=$((CHECKS + 1))
        block=$(awk -v svc="$svc" 'BEGIN{p=0} /^[^ #]/{p=0} /^  [a-zA-Z0-9_-]+:/{if($1==svc":"){p=1}else{p=0}} p{print}' "$f")
        # One-shot jobs: restart "no", or a bounded retry (on-failure:N)
        echo "$block" | grep -qE '^\s+restart:\s*"?(no|on-failure:[0-9]+)"?\s*(#.*)?$' && continue
        if ! echo "$block" | grep -qE '^\s+healthcheck:'; then
            fail "$rel_path → long-running service '$svc' has no healthcheck"
            hint "Add a healthcheck (or restart: \"no\" if it is a one-shot job)"
        fi
    done
done
[ "$ERRORS" -eq "$HC01B_ERRORS_BEFORE" ] && pass "Every long-running service has a healthcheck"

# ──────────────────────────────────────────────────────────────
# HC-02: No named Docker volumes
# ──────────────────────────────────────────────────────────────
section "HC-02: No named Docker volumes (bind mounts only)"
HC02_ERRORS_BEFORE=$ERRORS
for f in $COMPOSE_FILES; do
    CHECKS=$((CHECKS + 1))
    rel_path="${f#$PROJECT_ROOT/}"
    # Check for top-level 'volumes:' section (named volume definitions)
    if grep -qE '^volumes:' "$f"; then
        fail "$rel_path → has top-level 'volumes:' section (named volumes)"
        hint "Replace named volumes with bind mounts (e.g., ./data:/path)"
    fi
done
[ "$ERRORS" -eq "$HC02_ERRORS_BEFORE" ] && pass "No named volumes in production compose files"

# Note: sandbox compose files ARE allowed named volumes (documented exception)
for f in $SANDBOX_COMPOSE; do
    rel_path="${f#$PROJECT_ROOT/}"
    if grep -qE '^volumes:' "$f"; then
        warn "$rel_path → has named volumes (acceptable in sandbox only)"
    fi
done

# ──────────────────────────────────────────────────────────────
# HC-03: Scripts MUST begin with set -euo pipefail
# ──────────────────────────────────────────────────────────────
section "HC-03: Scripts have strict error handling"
HC03_ERRORS_BEFORE=$ERRORS
for f in $SCRIPTS; do
    CHECKS=$((CHECKS + 1))
    rel_path="${f#$PROJECT_ROOT/}"
    # The first CODE line (after the shebang and any comment header) must be
    # the set line; a commented-out '#set -e' does not count.
    head_content=$(awk 'NR==1 && /^#!/ {next} /^[[:space:]]*(#|$)/ {next} {print; exit}' "$f")
    if ! echo "$head_content" | grep -qE '^set -e'; then
        fail "$rel_path → missing 'set -euo pipefail' (or at minimum 'set -e')"
        hint "Add 'set -euo pipefail' as the second line after shebang"
    elif ! echo "$head_content" | grep -qE '^set -euo pipefail'; then
        warn "$rel_path → has 'set -e' but not full 'set -euo pipefail'"
    fi
done
[ "$ERRORS" -eq "$HC03_ERRORS_BEFORE" ] && pass "All scripts have strict error handling"

# ──────────────────────────────────────────────────────────────
# HC-05: PostgreSQL ports NEVER exposed
# ──────────────────────────────────────────────────────────────
section "HC-05: No PostgreSQL ports exposed to host"
HC05_ERRORS_BEFORE=$ERRORS
for f in $COMPOSE_FILES; do
    CHECKS=$((CHECKS + 1))
    rel_path="${f#$PROJECT_ROOT/}"
    # Look for postgres services that have 'ports:' section
    if awk '/postgres/,/^  [^ ]/' "$f" | grep -qE '^\s+ports:'; then
        fail "$rel_path → PostgreSQL service has exposed ports"
        hint "Remove the ports: section from the PostgreSQL service"
    fi
done
[ "$ERRORS" -eq "$HC05_ERRORS_BEFORE" ] && pass "No PostgreSQL ports exposed"

# ──────────────────────────────────────────────────────────────
# HC-06: No runtime package installs in entrypoints
# ──────────────────────────────────────────────────────────────
section "HC-06: No runtime package installs in compose entrypoints"
HC06_ERRORS_BEFORE=$ERRORS
for f in $COMPOSE_FILES $SANDBOX_COMPOSE; do
    CHECKS=$((CHECKS + 1))
    rel_path="${f#$PROJECT_ROOT/}"
    # Check entrypoint/command blocks for apk add or apt-get install
    if grep -nE '(apk add|apt-get install|apt install)' "$f" | grep -vE '^\s*#' > /dev/null 2>&1; then
        fail "$rel_path → contains runtime package installation in compose"
        hint "Move package installs to Dockerfile (RUN apk add --no-cache ...)"
    fi
done
[ "$ERRORS" -eq "$HC06_ERRORS_BEFORE" ] && pass "No runtime package installs in compose files"

# ──────────────────────────────────────────────────────────────
# HC-07: No :latest tags on upstream images
# ──────────────────────────────────────────────────────────────
section "HC-07: All images pinned to specific versions"
HC07_ERRORS_BEFORE=$ERRORS
for f in $COMPOSE_FILES; do
    CHECKS=$((CHECKS + 1))
    rel_path="${f#$PROJECT_ROOT/}"
    # Find image: lines with :latest or without any tag (implicit latest)
    while IFS= read -r line; do
        # Skip comments and build contexts
        [[ "$line" =~ ^\s*# ]] && continue
        image_val=$(echo "$line" | sed 's/.*image:\s*//' | tr -d '"' | tr -d "'" | xargs)
        # Skip local builds (no / in name, has : with local tag)
        [[ "$image_val" == *":latest"* ]] && {
            fail "$rel_path → image '$image_val' uses :latest tag"
            hint "Pin to specific version (e.g., postgres:15-alpine)"
        }
        # Check for images without ANY tag (implicit :latest)
        # Only for known upstream images (contain / or are well-known names)
        if [[ "$image_val" == *"/"* ]] && [[ "$image_val" != *":"* ]]; then
            fail "$rel_path → image '$image_val' has no version tag (implicit :latest)"
            hint "Add explicit version tag"
        fi
    done < <(grep -E '^\s+image:' "$f" 2>/dev/null || true)
done
for f in $DOCKERFILES; do
    CHECKS=$((CHECKS + 1))
    rel_path="${f#$PROJECT_ROOT/}"
    # Stage aliases defined in this file may be reused in later FROM lines.
    stages=$(grep -iE '^\s*FROM\s' "$f" | grep -ioE '\sAS\s+[A-Za-z0-9_.-]+' | awk '{print tolower($2)}' || true)
    while IFS= read -r ref; do
        [ -z "$ref" ] && continue
        echo "$stages" | grep -qxF "$(echo "$ref" | tr '[:upper:]' '[:lower:]')" && continue
        [[ "$ref" == *@sha256:* ]] && continue
        tag="${ref##*:}"
        # ${ARG} references are resolved from the ARG default in the same file
        if [[ "$ref" == *'${'* ]]; then
            arg=$(echo "$ref" | grep -oE '\$\{[A-Za-z_][A-Za-z0-9_]*' | head -1 | tr -d '${')
            grep -qE "^ARG ${arg}=[^[:space:]]+" "$f" || { fail "$rel_path → FROM '$ref': ARG $arg has no default"; hint "Give ARG $arg a pinned default"; }
            continue
        fi
        if [[ "$ref" != *:* ]] || [[ "$tag" == "latest" ]] || [[ "$tag" == "builder" ]] || [[ "$tag" == */* ]]; then
            fail "$rel_path → FROM '$ref' is not pinned to a version"
            hint "Use an explicit version tag, e.g. caddy:2.9.1-builder-alpine"
        fi
    done < <(grep -iE '^\s*FROM\s' "$f" | awk '{for(i=2;i<=NF;i++) if($i !~ /^--/){print $i; break}}')
done
[ "$ERRORS" -eq "$HC07_ERRORS_BEFORE" ] && pass "All upstream images and Dockerfile FROM lines have pinned versions"

# ──────────────────────────────────────────────────────────────
# HC-08: .env not tracked in git
# ──────────────────────────────────────────────────────────────
section "HC-08: .env files excluded from git"
CHECKS=$((CHECKS + 1))
if [ -f "$PROJECT_ROOT/.gitignore" ]; then
    if grep -qE '^\*?\.env$|^\.env$' "$PROJECT_ROOT/.gitignore"; then
        pass ".gitignore excludes .env files"
    else
        fail ".gitignore does not exclude .env files"
        hint "Add '.env' and '*.env' to .gitignore (keep !.env.example and !*.env.sandbox)"
    fi
else
    fail "No .gitignore found at project root"
fi

# Check if any .env (non-sandbox, non-example) is tracked
CHECKS=$((CHECKS + 1))
if command -v git &>/dev/null && [ -d "$PROJECT_ROOT/.git" ]; then
    # Any .env variant (.env, x.env, .env.prod, ".env copy") except the
    # committed templates .env.example / .env.sandbox / .env.sandbox.example / *.env.template.
    tracked_envs=$(git -C "$PROJECT_ROOT" ls-files 2>/dev/null \
        | grep -E '(^|/)[^/]*\.env([ .][^/]*)?$|(^|/)\.env[^/]*$' \
        | grep -vE '\.env\.(example|sandbox|sandbox\.example)$|\.env\.template$' || true)
    if [ -n "$tracked_envs" ]; then
        fail "Production .env files tracked in git: $(echo "$tracked_envs" | tr '\n' ' ')"
        hint "git rm --cached <file> && add to .gitignore"
    else
        pass "No production .env files tracked in git"
    fi

    CHECKS=$((CHECKS + 1))
    tracked_keys=$(git -C "$PROJECT_ROOT" ls-files 2>/dev/null \
        | grep -E '(^|/)\.vagrant/|(^|/)private_key$|\.(key|pem|p12)$|(^|/)oauth2-proxy\.cfg$' || true)
    if [ -n "$tracked_keys" ]; then
        fail "Key material or live secret config tracked in git: $(echo "$tracked_keys" | tr '\n' ' ')"
        hint "git rm --cached <file>, add it to .gitignore, rotate the secret"
    else
        pass "No key material or live secret config tracked in git"
    fi
fi

# ──────────────────────────────────────────────────────────────
# HC-09: No direct docker.sock mounts (except socket-proxy)
# ──────────────────────────────────────────────────────────────
section "HC-09: No direct docker.sock mounts (use socket-proxy)"
HC09_ERRORS_BEFORE=$ERRORS
for f in $COMPOSE_FILES; do
    CHECKS=$((CHECKS + 1))
    rel_path="${f#$PROJECT_ROOT/}"
    # Find services mounting docker.sock that are NOT the socket-proxy or watchtower
    while IFS= read -r line; do
        # Get the service name that owns this volume mount
        svc_name=$(awk -v line_num="$line" 'BEGIN{in_svc=0; svc=""} /^services:/{in_svc=1; next} /^[a-zA-Z0-9_-]/{in_svc=0} in_svc && /^  [a-zA-Z0-9_-]+:/{if(NR<=line_num) svc=$1} END{print svc}' "$f" | sed 's/://')
        case "$svc_name" in
            *socket-proxy*|*watchtower*) ;; # Acceptable
            *)
                fail "$rel_path → service '$svc_name' mounts docker.sock directly"
                hint "Use docker-socket-proxy (tecnativa) instead of direct mount"
                ;;
        esac
    done < <(grep -n 'docker\.sock' "$f" 2>/dev/null | grep -vE '^[0-9]+:\s*#' | cut -d: -f1 || true)
done
[ "$ERRORS" -eq "$HC09_ERRORS_BEFORE" ] && pass "No unauthorized docker.sock mounts"

# ──────────────────────────────────────────────────────────────
# HC-11: No external CDN calls in themes
# ──────────────────────────────────────────────────────────────
section "HC-11: No external CDN calls in UI themes"
HC11_ERRORS_BEFORE=$ERRORS
THEME_FILES=$(find "$PROJECT_ROOT" \( -name '*.css' -o -name '*.ftl' -o -name '*.html' \) -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null || true)
for f in $THEME_FILES; do
    CHECKS=$((CHECKS + 1))
    rel_path="${f#$PROJECT_ROOT/}"
    # Check for external URLs (CDN, Google Fonts, etc.)
    if grep -nE '(fonts\.googleapis|cdn\.|cdnjs\.|unpkg\.com|jsdelivr)' "$f" 2>/dev/null | grep -v '^\s*//' | grep -v '^\s*\*' > /dev/null; then
        fail "$rel_path → contains external CDN reference"
        hint "Bundle assets locally or use system-ui font stack"
    fi
done
[ "$ERRORS" -eq "$HC11_ERRORS_BEFORE" ] && pass "No external CDN calls in theme files"

# ──────────────────────────────────────────────────────────────
# EXTRA: Version consistency check
# Verify same image is pinned to same version across all compose files
# ──────────────────────────────────────────────────────────────
section "EXTRA: Image version consistency across compose files"
declare -A IMAGE_VERSIONS
for f in $COMPOSE_FILES; do
    while IFS= read -r line; do
        img=$(echo "$line" | sed 's/.*image:\s*//' | tr -d '"' | tr -d "'" | xargs)
        [ -z "$img" ] && continue
        base=$(echo "$img" | cut -d: -f1)
        ver=$(echo "$img" | grep -o ':.*' | sed 's/://' || echo "none")
        key="${base}"
        if [ -n "${IMAGE_VERSIONS[$key]+x}" ]; then
            existing="${IMAGE_VERSIONS[$key]}"
            if [ "$existing" != "$ver" ]; then
                warn "Image '$base' has inconsistent versions: '$existing' vs '$ver'"
            fi
        else
            IMAGE_VERSIONS[$key]="$ver"
        fi
    done < <(grep -E '^\s+image:' "$f" 2>/dev/null || true)
done

# ──────────────────────────────────────────────────────────────
# EXTRA: Container-internal scripts must not use interactive input
# ──────────────────────────────────────────────────────────────
section "EXTRA: Container-internal scripts have no interactive input"
CONTAINER_SCRIPTS=(
    "scripts/infra-pki/init_step_ca.sh"
    "scripts/infra-pki/patch_ca_config.sh"
    "scripts/infra-iam/fetch_pki_root.sh"
    "scripts/infra-iam/fetch_ad_cert.sh"
    "scripts/infra-iam/renew_certificate.sh"
)
for rel in "${CONTAINER_SCRIPTS[@]}"; do
    f="$PROJECT_ROOT/$rel"
    [ ! -f "$f" ] && continue
    CHECKS=$((CHECKS + 1))
    if grep -nE 'read -[rp]|read -s' "$f" | grep -v '^\s*#' > /dev/null 2>&1; then
        fail "$rel → container-internal script uses interactive input (read -p)"
        hint "This script runs inside a container without TTY. Remove all read commands."
    fi
done

# ──────────────────────────────────────────────────────────────
# EXTRA: Compose files have no version: key
# ──────────────────────────────────────────────────────────────
section "EXTRA: No deprecated version: key in compose files"
for f in $COMPOSE_FILES $SANDBOX_COMPOSE; do
    CHECKS=$((CHECKS + 1))
    rel_path="${f#$PROJECT_ROOT/}"
    if head -5 "$f" | grep -qE '^version:'; then
        warn "$rel_path → has deprecated 'version:' key (Compose v2 doesn't need it)"
    fi
done

# ──────────────────────────────────────────────────────────────
# EXTRA: Agent context files are in sync (if they exist)
# ──────────────────────────────────────────────────────────────
section "EXTRA: Agent context file presence"
for agentfile in "CLAUDE.md" ".cursorrules" ".github/copilot-instructions.md" ".clinerules"; do
    CHECKS=$((CHECKS + 1))
    if [ -f "$PROJECT_ROOT/$agentfile" ]; then
        pass "$agentfile exists"
    else
        warn "$agentfile not found — run .ai/generate.sh to create"
    fi
done

# ══════════════════════════════════════════════════════════════
# SUMMARY
# ══════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}═══════════════════════════════════════${NC}"
echo -e "  Checks run: ${BOLD}$CHECKS${NC}"
echo -e "  Errors:     ${RED}$ERRORS${NC}"
echo -e "  Warnings:   ${YELLOW}$WARNINGS${NC}"
echo -e "${BOLD}═══════════════════════════════════════${NC}"

if [ "$ERRORS" -gt 0 ]; then
    echo -e "${RED}  ✗ VALIDATION FAILED — $ERRORS hard constraint violations${NC}"
    echo ""
    [ "$SHOW_HINTS" = false ] && echo "  Run with --fix-hint to see fix suggestions"
    exit 1
elif [ "$WARNINGS" -gt 0 ]; then
    echo -e "${YELLOW}  ⚠ PASSED WITH WARNINGS — review recommended${NC}"
    exit 0
else
    echo -e "${GREEN}  ✓ ALL CHECKS PASSED${NC}"
    exit 0
fi
