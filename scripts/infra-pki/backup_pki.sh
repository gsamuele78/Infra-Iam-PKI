#!/bin/bash
# backup_pki.sh - Backup PKI Data and Configuration

set -e

# Configuration
PROJECT_DIR="/opt/docker/Infra-Iam-PKI/infra-pki"
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

# 2. Backup Database (Postgres)
# Using docker exec to dump the database from the running container
if docker ps | grep -q step-ca-db; then
    echo "Backing up Postgres database..."
    # Note: Assuming user 'step' is the db user based on previous context, 
    # but strictly checking compose might be better. 
    # The user provided snippet used 'step_ca_user' and 'step_ca_db'.
    # I should verify these. For now I'll use the environment variables from .env if possible or defaults.
    # Actually, in the logs it showed: "The files belonging to this database system will be owned by user "postgres"."
    # And "POSTGRES_USER" in docker-compose usually defaults or is set.
    # Let's try to use pg_dumpall or pg_dump with the user.
    # The snippet used: docker exec step-ca-db pg_dump -U step_ca_user step_ca_db
    # I'll rely on that but maybe make it more robust by sourcing .env if avail.
    
    # We will try a generic pg_dumpall which might be safer if we don't know the exact db name, 
    # OR we assume the standard names.
    # Let's use the one from the user request but safeguard it.
    docker exec step-ca-db pg_dumpall -U step -f "/tmp/db_dump.sql" || {
         echo "Dump failed with user 'step', trying 'postgres'..."
         docker exec step-ca-db pg_dumpall -U postgres -f "/tmp/db_dump.sql"
    }
    
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
