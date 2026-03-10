#!/bin/bash
# Sandbox testing launcher
# Simulates cross-host network communication using a shared Docker bridge network.

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Create a shared external network to simulate routing between the "3 different hosts"
if ! docker network ls | grep -q "sandbox-net"; then
    echo "Creating shared simulated network 'sandbox-net'..."
    docker network create sandbox-net
fi

case "$1" in
    start)
        echo "Starting IAM Sandbox (Keycloak + Proxy)..."
        docker compose -f "$DIR/iam-sandbox.yml" up -d
        
        echo "Starting OOD Sandbox (UI Layout)..."
        docker compose -f "$DIR/ood-sandbox.yml" up -d
        
        echo ""
        echo "====================================="
        echo " Sandbox environment is running."
        echo "====================================="
        echo " The containers are communicating via 'sandbox-net' to simulate cross-host routing."
        echo ""
        echo " Test URLs:"
        echo " 1. IAM/Keycloak Login UI (Port 8080): http://localhost:8080/"
        echo " 2. OOD Portal UI Landing (Port 8081): http://localhost:8081/"
        echo "====================================="
        ;;
    stop)
        echo "Stopping Sandbox environments..."
        docker compose -f "$DIR/ood-sandbox.yml" down || true
        docker compose -f "$DIR/iam-sandbox.yml" down || true
        # Keep network as it is persistent per test, or remove it:
        # docker network rm sandbox-net
        ;;
    *)
        echo "Usage: $0 {start|stop}"
        exit 1
esac
