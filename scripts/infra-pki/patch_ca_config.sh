#!/bin/bash
set -e

CA_CONFIG="/home/step/config/ca.json"
TEMP_CONFIG="/home/step/config/ca.json.tmp"

# Check if file exists
if [ ! -f "$CA_CONFIG" ]; then
    echo "ca.json not found, skipping patch."
    exit 0
fi

# Always patch to ensure environment variables are up to date
if [ -f "$CA_CONFIG" ]; then
    echo "Patching ca.json to enforce PostgreSQL usage..."
    
    # Verify jq is available
    if ! command -v jq &> /dev/null; then
        echo "Error: jq is required but not found in container."
        exit 1
    fi

    # DEBUG: Print variables to logs
    echo "DEBUG: PGUSER='${PGUSER}'"
    echo "DEBUG: PGDATABASE='${PGDATABASE}'"
    echo "DEBUG: PGPASSWORD is set? (len=${#PGPASSWORD})"

    # Update configuration using jq
    # DSN format: postgresql://user:password@host:port/dbname?sslmode=disable
    # Using PG* variables as defined in docker-compose environment

    # URL Encode credentials using jq
    PGUSER_ENC=$(jq -nr --arg v "$PGUSER" '$v|@uri')
    PGPASSWORD_ENC=$(jq -nr --arg v "$PGPASSWORD" '$v|@uri')

    DSN="postgresql://${PGUSER_ENC}:${PGPASSWORD_ENC}@postgres:5432/${PGDATABASE}?sslmode=disable"
    
    # Apply jq filter
    jq --arg dsn "$DSN" \
       --arg db "$PGDATABASE" \
       '.db = {
         "type": "postgresql",
         "dataSource": $dsn,
         "database": $db
       }' "$CA_CONFIG" > "$TEMP_CONFIG"

    echo "DEBUG: Generated DSN: $DSN"

    # Verify and replace
    if [ -s "$TEMP_CONFIG" ]; then
        mv "$TEMP_CONFIG" "$CA_CONFIG"
        echo "Patch applied successfully. New DB config:"
        jq '.db' "$CA_CONFIG"
    else
        echo "Error: Failed to patch ca.json (empty output)."
        rm -f "$TEMP_CONFIG"
        exit 1
    fi
fi
