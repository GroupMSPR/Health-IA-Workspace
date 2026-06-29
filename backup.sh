#!/bin/bash

# ========================================================
#   backup.sh – Sauvegarde PostgreSQL | HealthAI Coach
#   Usage : ./backup.sh
#           ./backup.sh --silent   (pas de confirmation)
# ========================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

DB_PASSWORD="${DB_PASSWORD:-password}"
DB_USER="sail"
DB_NAME="laravel"
CONTAINER=$(docker ps --format '{{.Names}}' | grep "healthai_pgsql" | head -n 1)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="$SCRIPT_DIR/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/healthai_backup_$TIMESTAMP.sql"
MAX_BACKUPS=7
SILENT=0

for arg in "$@"; do
    if [ "$arg" == "--silent" ]; then SILENT=1; fi
done

mkdir -p "$BACKUP_DIR"

[ "$SILENT" -eq 0 ] && echo -e "${CYAN}========================================================${NC}"
[ "$SILENT" -eq 0 ] && echo -e "${CYAN}      Sauvegarde PostgreSQL – HealthAI Coach${NC}"
[ "$SILENT" -eq 0 ] && echo -e "${CYAN}========================================================${NC}"

if [ -z "$CONTAINER" ]; then
    echo -e "${RED}[✗] Aucun conteneur healthai_pgsql trouvé (healthai_pgsql ou healthai_pgsql-1).${NC}"
    exit 1
fi

[ "$SILENT" -eq 0 ] && echo -e "${YELLOW}[→] Sauvegarde en cours...${NC}"

if docker exec "$CONTAINER" sh -c \
    "PGPASSWORD=$DB_PASSWORD pg_dump -U $DB_USER -d $DB_NAME \
     --clean --if-exists --no-owner --no-acl" \
    > "$BACKUP_FILE" 2>/dev/null; then

    SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    echo -e "${GREEN}[✓] Sauvegarde créée : $(basename "$BACKUP_FILE") ($SIZE)${NC}"
    [ "$SILENT" -eq 0 ] && echo -e "${GREEN}    Dossier : $BACKUP_DIR${NC}"

    BACKUP_LIST=$(ls -t "$BACKUP_DIR"/healthai_backup_*.sql 2>/dev/null)
    COUNT=$(echo "$BACKUP_LIST" | wc -l)
    if [ "$COUNT" -gt "$MAX_BACKUPS" ]; then
        echo "$BACKUP_LIST" | tail -n +$((MAX_BACKUPS + 1)) | xargs rm -f
        [ "$SILENT" -eq 0 ] && echo -e "${GREEN}[✓] Nettoyage : $MAX_BACKUPS dernières sauvegardes conservées.${NC}"
    fi

else
    echo -e "${RED}[✗] Échec de la sauvegarde.${NC}"
    rm -f "$BACKUP_FILE"
    exit 1
fi

[ "$SILENT" -eq 0 ] && echo ""
exit 0