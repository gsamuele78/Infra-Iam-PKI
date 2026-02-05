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
    echo "This option allows you to reset specific project data."
    echo "1) Reset Infra-PKI (Wipe step_data and db_data)"
    echo "2) System Prune (Docker system prune -a --volumes)"
    read -rp "Select option: " subchoice

    if [ "$subchoice" == "1" ]; then
        echo "⚠️  WARNING: This will delete ALL certificates and CA configuration for Infra-PKI! ⚠️"
        read -rp "Are you sure? (type 'yes' to confirm): " confirm
        if [ "$confirm" == "yes" ]; then
            PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../infra-pki" && pwd)"
            if [ -d "$PROJECT_DIR" ]; then
                echo "Stopping containers in $PROJECT_DIR..."
                (cd "$PROJECT_DIR" && docker compose down -v)
                
                echo "Removing persistent data..."
                # Use sudo if necessary, or check permissions
                sudo rm -rf "$PROJECT_DIR/step_data/"* "$PROJECT_DIR/db_data/"* || echo "Failed to remove data. Try running script with sudo."
                
                echo "Reset complete. You can now rebuild with: docker compose up --build"
            else
                echo "Error: Could not find infra-pki directory at $PROJECT_DIR"
                exit 1
            fi
        else
            echo "Aborted."
        fi
        exit 0
    elif [ "$subchoice" == "2" ]; then
        echo "☢️  SYSTEM NUKE INITIATED ☢️"
        # ... existing nuke logic ...
        echo "Stopping all containers..."
        docker stop $(docker ps -aq) 2>/dev/null || true
        echo "Pruning entire system..."
        docker system prune -a --volumes --force
        exit 0
    fi
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
