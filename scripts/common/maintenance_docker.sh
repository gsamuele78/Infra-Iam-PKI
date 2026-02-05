#!/bin/bash
set -e

# Docker Maintenance Script
# Usage: ./maintenance_docker.sh [prune|monitor|nuke]

# Function to show menu
show_menu() {
    echo "=========================================="
    echo "   Docker Maintenance Menu"
    echo "=========================================="
    echo "1) Monitor (Stats & Usage)"
    echo "2) Prune (Clean unused resources)"
    echo "3) NUKE (Reset System - DESTRUCTIVE)"
    echo "4) Exit"
    echo "=========================================="
    read -rp "Select an option [1-4]: " choice
    case $choice in
        1) MODE="monitor" ;;
        2) MODE="prune" ;;
        3) MODE="nuke" ;;
        4) exit 0 ;;
        *) echo "Invalid option"; exit 1 ;;
    esac
}

# If no argument provided, show menu
if [ -z "$1" ]; then
    show_menu
else
    MODE=$1
fi

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
    echo "This will:"
    echo "  1. STOP ALL containers"
    echo "  2. REMOVE ALL containers, images, volumes, networks"
    echo "  3. CLEAR build cache"
    echo "  NOTE: This does NOT delete bind-mounted data directories on the host filesystem."
    echo "  This operation is IRREVERSIBLE."
    
    read -rp "Are you absolutely sure? (Type 'NUKE' to confirm): " confirmation
    if [ "$confirmation" != "NUKE" ]; then
        echo "Aborted."
        exit 1
    fi
    
    echo "Stopping all containers..."
    docker stop $(docker ps -aq) 2>/dev/null || true
    
    echo "Removing all containers..."
    docker rm $(docker ps -aq) 2>/dev/null || true
    
    echo "Pruning entire system (volumes + images)..."
    docker system prune -a --volumes --force
    
    echo "Cleaning build cache..."
    docker builder prune --all --force
    
    echo "System is clean."
    exit 0
fi

if [ "$MODE" == "prune" ]; then
    echo "WARNING: This will remove:"
    echo "  - all stopped containers"
    echo "  - all networks not used by at least one container"
    echo "  - all unused images"
    echo "  - all build cache"

    read -rp "Are you sure you want to proceed? (y/N) " -n 1 -r
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
