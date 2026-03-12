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
