#!/bin/bash
# backup_pki.sh - Backup PKI Data and Configuration

set -e

# Configuration
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../infra-pki" && pwd)"
BACKUP_ROOT="/backup/infra-pki"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$BACKUP_ROOT/$TIMESTAMP"
RETENTION_DAYS=7

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

echo "Starting PKI Backup to $BACKUP_DIR..."

# 1. Backup step_data (Certificates, Secrets, Config)
if [ -d "$PROJECT_DIR/step_data" ]; then
    echo "Backing up step_data..."
    cp -a "$PROJECT_DIR/step_data" "$BACKUP_DIR/"
else
    echo "Warning: step_data directory not found."
fi

# Source .env to get DB credentials
if [ -f "$PROJECT_DIR/.env" ]; then
    source "$PROJECT_DIR/.env"
fi

# 2. Backup Database (Postgres)
if docker ps | grep -q step-ca-db; then
    echo "Backing up Postgres database..."
    
    # Use env vars if available, else fallback
    DB_USER="${POSTGRES_USER:-step_ca_user}"
    
    # Dump using pg_dumpall for completeness (includes globals)
    if docker exec step-ca-db pg_dumpall -U "$DB_USER" -f "/tmp/db_dump.sql"; then
        echo "Database dump successful."
    else
        echo "Dump failed with user '$DB_USER'. Trying 'postgres'..."
        docker exec step-ca-db pg_dumpall -U postgres -f "/tmp/db_dump.sql" || {
            echo "Error: Database backup failed."
            exit 1
        }
    fi
    
    # Copy from container to host backup dir
    docker cp step-ca-db:/tmp/db_dump.sql "$BACKUP_DIR/db_dump.sql"
    docker exec step-ca-db rm /tmp/db_dump.sql
else
    echo "Warning: step-ca-db container is not running. Skipping DB backup."
fi

# 3. Backup Configuration (.env)
if [ -f "$PROJECT_DIR/.env" ]; then
    echo "Backing up .env..."
    cp "$PROJECT_DIR/.env" "$BACKUP_DIR/"
fi

# 4. Cleanup old backups
echo "Cleaning up backups older than $RETENTION_DAYS days..."
find "$BACKUP_ROOT" -maxdepth 1 -type d -mtime +$RETENTION_DAYS -name "20*" -exec rm -rf {} +

echo "Backup completed successfully."
ls -lh "$BACKUP_DIR"
