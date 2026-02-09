#!/bin/bash
set -euo pipefail
#
# configure_pki.sh: Interactive configuration manager for Infra-PKI
#
WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../infra-pki" && pwd)"
SECRETS_DIR="$WORKDIR/secrets"
ENV_FILE="$WORKDIR/.env"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

header() {
    clear
    echo -e "${BLUE}========================================"
    echo -e "   Infra-PKI Configuration Manager"
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
    echo -e "${GREEN}Current Environment Configuration (.env):${NC}"
    echo "----------------------------------------"
    if [ -f "$ENV_FILE" ]; then
        grep -v '^#' "$ENV_FILE" | grep -v '^$' || echo "No active variables found."
    else
        echo -e "${RED}Error: .env file not found at $ENV_FILE${NC}"
    fi
    echo ""
    echo -e "${GREEN}Secrets Status (infra-pki/secrets/):${NC}"
    echo "----------------------------------------"
    if [ -d "$SECRETS_DIR" ]; then
        for secret in password postgres_password ssh_host_password oidc_client_secret; do
            if [ -f "$SECRETS_DIR/$secret" ]; then
                echo -e "  - $secret: ${GREEN}EXISTS${NC}"
            else
                echo -e "  - $secret: ${RED}MISSING${NC}"
            fi
        done
    else
        echo -e "${RED}Secrets directory missings!${NC}"
    fi
    echo ""
    read -p "Press Enter to return..."
}

# --- HELPER: EDIT ENV VAR ---
edit_env_var() {
    local var_name=$1
    local current_val
    current_val=$(grep "^$var_name=" "$ENV_FILE" | cut -d= -f2 || echo "")
    
    echo "Current $var_name: $current_val"
    read -p "Enter new value (leave empty to keep current): " new_val
    
    if [ -n "$new_val" ]; then
        if grep -q "^$var_name=" "$ENV_FILE"; then
            sed -i "s|^$var_name=.*|$var_name=$new_val|" "$ENV_FILE"
        else
            echo "$var_name=$new_val" >> "$ENV_FILE"
        fi
        echo "Updated $var_name to $new_val."
    else
        echo "No change made."
    fi
    sleep 1
}

toggle_env() {
    local var_name=$1
    local current_val
    current_val=$(grep "^$var_name=" "$ENV_FILE" | cut -d= -f2 || echo "unknown")
    
    echo "Current $var_name: $current_val"
    read -p "Set to true/false? " new_val
    if [[ "$new_val" != "true" && "$new_val" != "false" ]]; then
        echo "Invalid input. Must be 'true' or 'false'."
        sleep 2
        return
    fi
    
    if grep -q "^$var_name=" "$ENV_FILE"; then
        sed -i "s/^$var_name=.*/$var_name=$new_val/" "$ENV_FILE"
    else
        echo "$var_name=$new_val" >> "$ENV_FILE"
    fi
    echo "Updated $var_name to $new_val."
    sleep 1
}

# --- MODIFY CONFIGURATION (.env) ---
modify_config() {
    header
    echo "Select variable to modify:"
    echo "1. Toggle ACME Provisioner (ENABLE_ACME)"
    echo "2. Toggle SSH Provisioner (ENABLE_SSH_PROVISIONER)"
    echo "3. Toggle K8s Provisioner (ENABLE_K8S_PROVISIONER)"
    echo "4. Edit Allowed IPs (ALLOWED_IPS)"
    echo "5. Return"
    echo ""
    read -p "Choice [1-5]: " choice
    
    case $choice in
        1) toggle_env "ENABLE_ACME" ;;
        2) toggle_env "ENABLE_SSH_PROVISIONER" ;;
        3) toggle_env "ENABLE_K8S_PROVISIONER" ;;
        4) edit_env_var "ALLOWED_IPS" ;;
        5) return ;;
        *) echo "Invalid choice." ;;
    esac
}

# --- MANAGE SECRETS ---
manage_secrets() {
    header
    mkdir -p "$SECRETS_DIR"
    echo "Update Secret (Overwrite):"
    echo "1. CA Password (secrets/password)"
    echo "2. DB Password (secrets/postgres_password)"
    echo "3. SSH Host Password (secrets/ssh_host_password)"
    echo "4. OIDC Client Secret (secrets/oidc_client_secret)"
    echo "5. Return"
    echo ""
    read -p "Choice [1-5]: " choice
    
    local secret_file=""
    case $choice in
        1) secret_file="password" ;;
        2) secret_file="postgres_password" ;;
        3) secret_file="ssh_host_password" ;;
        4) secret_file="oidc_client_secret" ;;
        5) return ;;
        *) echo "Invalid choice." ;;
    esac
    
    echo ""
    read -sp "Enter new value for $secret_file: " secret_val
    echo ""
    read -sp "Confirm value: " secret_val_confirm
    echo ""
    
    if [ "$secret_val" != "$secret_val_confirm" ]; then
        echo -e "${RED}Passwords do not match!${NC}"
        sleep 2
        return
    fi
    
    echo -n "$secret_val" > "$SECRETS_DIR/$secret_file"
    echo -e "${GREEN}Secret updated.${NC}"
    sleep 1
}

# --- VIEW LOGS ---
view_logs() {
    header
    echo "Select service logs to view:"
    echo "1. Step-CA Service (step-ca)"
    echo "2. Configurator (step-ca-configurator)"
    echo "3. Caddy Proxy (caddy)"
    echo "4. Return"
    echo ""
    read -p "Choice [1-4]: " choice
    
    local service=""
    case $choice in
        1) service="step-ca" ;;
        2) service="step-ca-configurator" ;;
        3) service="caddy" ;;
        4) return ;;
        *) echo "Invalid choice." ; sleep 1 ; return ;;
    esac
    
    echo "Fetching logs for $service (last 50 lines)..."
    cd "$WORKDIR" || return
    docker compose logs --tail=50 "$service"
    echo ""
    read -p "Press Enter to return..."
}

# --- APPLY CHANGES ---
apply_changes() {
    header
    echo -e "${RED}WARNING: This will restart the Infra-PKI stack.${NC}"
    echo "Any config changes or secret updates will be applied."
    read -p "Are you sure? (y/N) " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo "Restarting stack..."
        cd "$WORKDIR" || return
        docker compose up -d --force-recreate
        echo -e "${GREEN}Stack restarted.${NC}"
    else
        echo "Cancelled."
    fi
    read -p "Press Enter to return..."
}

# --- TEST PROVISIONER ---
test_provisioners() {
    header
    echo "Testing CA Health..."
    if ! docker ps | grep -q "step-ca"; then
        echo -e "${RED}step-ca container is not running.${NC}"
    else
        if docker exec step-ca step ca health >/dev/null 2>&1; then
             echo -e "${GREEN}CA is Healthy.${NC}"
        else
             echo -e "${RED}CA Health Check Failed.${NC}"
             docker exec step-ca step ca health || true
        fi
        
        echo ""
        echo "Current Provisioners:"
        if command -v jq >/dev/null; then
             # Pretty print with jq if available
             docker exec step-ca step ca provisioner list | jq '.' || echo "Failed to parse provisioner list"
        else
             # Fallback to raw output
             docker exec step-ca step ca provisioner list
        fi
    fi
    read -p "Press Enter to return..."
}

# --- MAIN MENU ---
main_menu() {
    while true; do
        header
        echo "1. View Current Configuration"
        echo "2. Modify Environment Variables"
        echo "3. Manage Secrets"
        echo "4. View Service Logs"
        echo "5. Test Provisioners/Health"
        echo "6. APPLY CHANGES (Restart Stack)"
        echo "7. Exit"
        echo "----------------------------------------"
        read -p "Select action [1-7]: " choice
        
        case $choice in
            1) view_config ;;
            2) modify_config ;;
            3) manage_secrets ;;
            4) view_logs ;;
            5) test_provisioners ;;
            6) apply_changes ;;
            7) exit 0 ;;
            *) echo "Invalid option." ; sleep 1 ;;
        esac
    done
}

check_dependencies
# Ensure script executable
chmod +x "$0" 2>/dev/null || true
main_menu
