#!/bin/bash
set -euo pipefail

# configure_iam.sh
# Interactive configuration manager for Infra-IAM
# Location: /opt/docker/Infra-Iam-PKI/scripts/infra-iam/configure_iam.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="$(cd "$SCRIPT_DIR/../../infra-iam" && pwd)"
ENV_FILE="$WORKDIR/.env"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

header() {
    clear
    echo -e "${BLUE}========================================"
    echo -e "   Infra-IAM Configuration Manager"
    echo -e "========================================${NC}"
    echo "Working Config: $WORKDIR"
    echo ""
}

check_dependencies() {
    if ! command -v docker >/dev/null; then
        echo "Error: docker is not installed."
        exit 1
    fi
}

# --- VIEW CONFIGURATION ---
view_config() {
    header
    echo -e "${GREEN}Current IAM Configuration (.env):${NC}"
    echo "----------------------------------------"
    if [ -f "$ENV_FILE" ]; then
        grep -v '^#' "$ENV_FILE" | grep -v '^$' || echo "No active variables found."
    else
        echo -e "${RED}Error: .env file not found at $ENV_FILE${NC}"
    fi
    echo ""
    read -p "Press Enter to return..."
}

# --- HELPER: EDIT ENV VAR ---
edit_env_var() {
    local var_name=$1
    local current_val
    current_val=$(grep "^$var_name=" "$ENV_FILE" | cut -d= -f2- | tr -d '"' || echo "")
    
    echo "Current $var_name: $current_val"
    read -p "Enter new value (leave empty to keep current): " new_val
    
    if [ -n "$new_val" ]; then
        if grep -q "^$var_name=" "$ENV_FILE"; then
            sed -i "s|^$var_name=.*|$var_name=\"$new_val\"|" "$ENV_FILE"
        else
            echo "$var_name=\"$new_val\"" >> "$ENV_FILE"
        fi
        echo "Updated $var_name to \"$new_val\"."
    else
        echo "No change made."
    fi
    sleep 1
}

# --- MODIFY CONFIGURATION ---
modify_config() {
    header
    echo "Select variable to modify:"
    echo "1. Domain SSO (DOMAIN_SSO)"
    echo "2. CA URL (CA_URL)"
    echo "3. Active Directory Host (AD_HOST)"
    echo "4. Database Password (DB_PASSWORD)"
    echo "5. Keycloak Admin Password (KC_ADMIN_PASSWORD)"
    echo "6. PUID / PGID"
    echo "7. Return"
    echo ""
    read -p "Choice [1-7]: " choice
    
    case $choice in
        1) edit_env_var "DOMAIN_SSO" ;;
        2) edit_env_var "CA_URL" ;;
        3) edit_env_var "AD_HOST" ;;
        4) edit_env_var "DB_PASSWORD" ;;
        5) edit_env_var "KC_ADMIN_PASSWORD" ;;
        6) edit_env_var "PUID"; edit_env_var "PGID" ;;
        7) return ;;
        *) echo "Invalid choice." ;;
    esac
}

# --- VIEW LOGS ---
view_logs() {
    header
    echo "Select IAM service logs to view:"
    echo "1. Keycloak"
    echo "2. Database (Postgres)"
    echo "3. Caddy Proxy"
    echo "4. Watchtower"
    echo "5. Return"
    echo ""
    read -p "Choice [1-5]: " choice
    
    local service=""
    case $choice in
        1) service="keycloak" ;;
        2) service="db" ;;
        3) service="caddy" ;;
        4) service="watchtower" ;;
        5) return ;;
        *) echo "Invalid choice." ; sleep 1 ; return ;;
    esac
    
    echo "Fetching logs for $service (last 50 lines)..."
    cd "$WORKDIR" || return
    docker compose logs --tail=50 "$service"
    echo ""
    read -p "Press Enter to return..."
}

# --- RUN TOOLBOX ---
run_toolbox() {
    header
    echo "IAM Utility Tools:"
    echo "1. Force Certificate Refresh (Fetch Roots)"
    echo "2. View Docker Health Status"
    echo "3. Run post-deployment validation"
    echo "4. Return"
    echo ""
    read -p "Choice [1-4]: " choice
    
    case $choice in
        1) 
            echo "Restarting iam-init service to fetch certificates..."
            cd "$WORKDIR" && docker compose up iam-init
            ;;
        2)
            cd "$WORKDIR" && docker compose ps
            ;;
        3)
            "$SCRIPT_DIR/validate_iam_config.sh" --post-deploy
            ;;
        4) return ;;
        *) echo "Invalid choice." ;;
    esac
    read -p "Press Enter to return..."
}

# --- APPLY & DEPLOY ---
apply_deploy() {
    header
    echo -e "${RED}WARNING: This will deploy/restart the Infra-IAM stack.${NC}"
    read -p "Are you sure? (y/N) " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        cd "$SCRIPT_DIR" && sudo ./deploy_iam.sh
    else
        echo "Cancelled."
    fi
    read -p "Press Enter to return..."
}

# --- MAIN MENU ---
main_menu() {
    while true; do
        header
        echo "1. View Current Configuration"
        echo "2. Modify Configuration (.env)"
        echo "3. View Service Logs"
        echo "4. Utility Toolbox"
        echo "5. DEPLOY / RESTART STACK"
        echo "6. RESET Data (DANGER)"
        echo "7. Exit"
        echo "----------------------------------------"
        read -p "Select action [1-7]: " choice
        
        case $choice in
            1) view_config ;;
            2) modify_config ;;
            3) view_logs ;;
            4) run_toolbox ;;
            5) apply_deploy ;;
            6) cd "$SCRIPT_DIR" && sudo ./reset_iam.sh ;;
            7) exit 0 ;;
            *) echo "Invalid option." ; sleep 1 ;;
        esac
    done
}

check_dependencies
chmod +x "$0" 2>/dev/null || true
main_menu
