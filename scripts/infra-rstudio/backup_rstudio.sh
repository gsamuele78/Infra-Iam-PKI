#!/bin/bash
set -euo pipefail

# backup_rstudio.sh
# Backs up infra-rstudio infrastructure artifacts:
#   - SSL/PKI certificates
#   - .env file (with password fields redacted)
#   - Ollama model list (not the models themselves — too large)
#   - Nginx configuration
#   - Timestamp-tagged backup directory
#
# User data (R sessions, projects) is on NFS mounts and is out of scope.
# Mirrors: scripts/infra-pki/backup_pki.sh
#
# Usage: backup_rstudio.sh [BACKUP_ROOT]
#   BACKUP_ROOT defaults to /backup/infra-rstudio

# =====================================================================
# CONFIGURATION
# =====================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RSTUDIO_DIR="$(cd "${SCRIPT_DIR}/../../infra-rstudio" && pwd)"
BACKUP_ROOT="${1:-/backup/infra-rstudio}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="${BACKUP_ROOT}/${TIMESTAMP}"
RETENTION_DAYS=7

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}[BACKUP]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; }

# =====================================================================
# CLEANUP TRAP
# =====================================================================

cleanup() {
    local exit_code=$?
    if [ "${exit_code}" -ne 0 ]; then
        err "backup_rstudio.sh failed with exit code ${exit_code}"
        err "Partial backup may exist at: ${BACKUP_DIR}"
    fi
}
trap cleanup EXIT ERR

# =====================================================================
# FUNCTIONS
# =====================================================================

redact_env() {
    local src_env="$1"
    local dst_env="$2"
    # Redact lines containing password/secret/key fields
    # Keeps the key name visible but replaces the value with [REDACTED]
    sed -E \
        's/^(.*(?:PASSWORD|SECRET|KEY|TOKEN|FINGERPRINT|CLIENT_SECRET)[^=]*)=(.+)$/\1=[REDACTED]/' \
        "${src_env}" > "${dst_env}"
    warn "Sensitive fields redacted in backup copy of .env"
}

backup_certs() {
    log "Backing up SSL/PKI certificates..."
    local cert_dir="${BACKUP_DIR}/certs"
    mkdir -p "${cert_dir}"

    # Load SSL paths from .env if available
    local env_file="${RSTUDIO_DIR}/.env"
    local ssl_cert=""
    local ssl_key=""

    if [ -f "${env_file}" ]; then
        ssl_cert=$(grep '^SSL_CERT_PATH=' "${env_file}" | cut -d= -f2- | tr -d '"' || true)
        ssl_key=$(grep '^SSL_KEY_PATH=' "${env_file}" | cut -d= -f2- | tr -d '"' || true)
    fi

    # Back up SSL cert (not key — private key should NOT be in backups
    # unless this is a secure backup store; operator should confirm)
    if [ -n "${ssl_cert}" ] && [ -f "${ssl_cert}" ]; then
        cp "${ssl_cert}" "${cert_dir}/ssl_cert.pem"
        ok "SSL certificate backed up from ${ssl_cert}"
    else
        warn "SSL_CERT_PATH not set or file not found — skipping cert backup."
    fi

    # Back up Root CA from shared certs volume (if accessible on host)
    local root_ca_candidates=(
        "${RSTUDIO_DIR}/certs/root_ca.crt"
        "/usr/local/share/ca-certificates/internal-infra-root-ca.crt"
    )
    for ca_path in "${root_ca_candidates[@]}"; do
        if [ -f "${ca_path}" ]; then
            cp "${ca_path}" "${cert_dir}/root_ca.crt"
            ok "Root CA backed up from ${ca_path}"
            break
        fi
    done
}

backup_env() {
    log "Backing up .env (passwords redacted)..."
    local env_file="${RSTUDIO_DIR}/.env"

    if [ -f "${env_file}" ]; then
        redact_env "${env_file}" "${BACKUP_DIR}/env.redacted"
        ok ".env backed up (redacted) to ${BACKUP_DIR}/env.redacted"
    else
        warn ".env not found at ${env_file} — skipping."
    fi
}

backup_ollama_models() {
    log "Recording Ollama model list (not copying model data)..."

    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q 'rstudio_ollama'; then
        docker exec rstudio_ollama ollama list > "${BACKUP_DIR}/ollama_models.txt" 2>/dev/null \
            && ok "Ollama model list saved to ${BACKUP_DIR}/ollama_models.txt" \
            || warn "Failed to get Ollama model list — container may be unhealthy."
    else
        warn "Ollama container (rstudio_ollama) is not running. Skipping model list."
    fi
}

backup_nginx_config() {
    log "Backing up Nginx configuration..."
    local nginx_conf_dir="${RSTUDIO_DIR}/config"

    if [ -d "${nginx_conf_dir}" ]; then
        cp -a "${nginx_conf_dir}" "${BACKUP_DIR}/config"
        ok "Nginx/config directory backed up."
    else
        warn "Config directory not found at ${nginx_conf_dir}."
    fi
}

cleanup_old_backups() {
    log "Cleaning up backups older than ${RETENTION_DAYS} days..."
    find "${BACKUP_ROOT}" \
        -maxdepth 1 \
        -type d \
        -mtime +"${RETENTION_DAYS}" \
        -name "20*" \
        -exec rm -rf {} + 2>/dev/null || true
    ok "Old backup cleanup done."
}

# =====================================================================
# MAIN
# =====================================================================

log "=== Infra-RStudio Backup ==="
log "Target: ${BACKUP_DIR}"
log "Retention: ${RETENTION_DAYS} days"
echo ""

# Ensure backup directory exists
mkdir -p "${BACKUP_DIR}"

# Run backup steps
backup_env
backup_certs
backup_ollama_models
backup_nginx_config

# Cleanup old backups
cleanup_old_backups

echo ""
ok "Backup completed successfully."
log "Backup location: ${BACKUP_DIR}"
log "Contents:"
ls -lh "${BACKUP_DIR}" | sed 's/^/  /'
