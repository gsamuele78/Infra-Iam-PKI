#!/bin/bash
set -e

# Docker Maintenance Script
# Usage: ./maintenance_docker.sh [prune|monitor|nuke]

MODE=${1:-prune}

if [ "$MODE" == "monitor" ]; then
    echo "=== Docker Disk Usage ==="
    docker system df
    echo
    echo "=== Running Containers ==="
    docker stats --no-stream
    exit 0
fi

if [ "$MODE" == "nuke" ]; then
    echo "☢️  NUCLEAR OPTION INITIATED ☢️"
    echo "This will STOP ALL containers and DELETE ALL images, volumes, and networks."
    echo "This operation is IRREVERSIBLE."
    read -p "Are you absolutely sure? (Type 'NUKE' to confirm): " -r
    if [ "$REPLY" != "NUKE" ]; then
        echo "Aborted."
        exit 1
    fi
    echo "Stopping all containers..."
    docker stop $(docker ps -aq) 2>/dev/null || true
    echo "Pruning entire system..."
    docker system prune -a --volumes --force
    echo "System is clean."
    exit 0
fi

if [ "$MODE" == "prune" ]; then
    echo "WARNING: This will remove:"
    echo "  - all stopped containers"
    echo "  - all networks not used by at least one container"
    echo "  - all unused images"
    echo "  - all build cache"

    read -p "Are you sure you want to proceed? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 1
    fi

    echo "Pruning system..."
    docker system prune -a --volumes --force
    echo "Done."
    exit 0
fi

echo "Usage: $0 [prune|monitor|nuke]"
exit 1
