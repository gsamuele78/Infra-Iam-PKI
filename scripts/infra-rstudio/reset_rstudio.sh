#!/bin/bash
set -euo pipefail

# reset_rstudio.sh
# Reset completo dell'ambiente Infra-RStudio: ferma i container, cancella dati generati.
# Location: scripts/infra-rstudio/reset_rstudio.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../infra-rstudio" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}=== DANGER: RESET INFRA-RSTUDIO ===${NC}"
echo "Target Directory: $PROJECT_DIR"
echo ""
echo "Questa operazione:"
echo "  1. Ferma e rimuove tutti i container Infra-RStudio."
echo "  2. Rimuove le immagini Docker buildatte."
echo "  3. CANCELLA i log generati."
echo ""
echo -e "${YELLOW}I dati utente (/home, /nfs) NON vengono toccati.${NC}"
echo -e "${YELLOW}I certificati host NON vengono toccati.${NC}"
echo ""

read -rp "Sei sicuro? (scrivi 'yes' per confermare): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Annullato."
    exit 1
fi

if [ ! -d "$PROJECT_DIR" ]; then
    echo "Error: directory non trovata: $PROJECT_DIR"
    exit 1
fi

echo ""
echo -e "${GREEN}1. Fermo i container...${NC}"
(cd "$PROJECT_DIR" && docker compose --profile sssd --profile samba --profile portal --profile oidc --profile ai down) 2>/dev/null \
    || echo "docker compose down fallito (forse già fermato)."

echo ""
echo -e "${GREEN}2. Rimuovo le immagini buildatte...${NC}"
for img in rstudio-botanical-sssd rstudio-botanical-samba botanical-portal-nginx botanical-telemetry-api botanical-ai-ollama; do
    if docker images --format '{{.Repository}}' | grep -q "^${img}$"; then
        echo "   Rimuovo $img..."
        docker rmi "$img" 2>/dev/null || echo "   (in uso, skipped)"
    fi
done

echo ""
echo -e "${GREEN}3. Pulizia log Docker...${NC}"
# Container logs are managed by json-file driver; they're cleaned with container removal.
echo "   Log container rimossi con i container."

echo ""
echo -e "${GREEN}>>> RESET COMPLETATO <<<${NC}"
echo "Per riavviare l'ambiente:"
echo "  sudo $SCRIPT_DIR/deploy_rstudio.sh"
echo ""
