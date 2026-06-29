#!/bin/bash

# ========================================================
#   restore.sh – Restauration PostgreSQL | HealthAI Coach
#   Usage : ./restore.sh                    (menu interactif)
#           ./restore.sh --latest           (dernier backup auto)
#           ./restore.sh mon_fichier.sql    (fichier précis)
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

echo -e "${CYAN}========================================================${NC}"
echo -e "${CYAN}      Restauration PostgreSQL – HealthAI Coach${NC}"
echo -e "${CYAN}========================================================${NC}"

if [ -z "$CONTAINER" ]; then
    echo -e "${RED}[✗] Aucun conteneur healthai_pgsql trouvé (healthai_pgsql ou healthai_pgsql-1).${NC}"
    echo -e "${YELLOW}    Lancez d'abord le projet avec : ./start.sh${NC}"
    exit 1
fi

RESTORE_FILE=""

if [ "$1" == "--latest" ]; then
    RESTORE_FILE=$(ls -t "$BACKUP_DIR"/healthai_backup_*.sql 2>/dev/null | head -n 1)
    if [ -z "$RESTORE_FILE" ]; then
        echo -e "${RED}[✗] Aucune sauvegarde trouvée dans $BACKUP_DIR${NC}"
        exit 1
    fi
    echo -e "${YELLOW}[→] Restauration automatique depuis : $(basename "$RESTORE_FILE")${NC}"

elif [ -n "$1" ]; then
    if [ -f "$1" ]; then
        RESTORE_FILE="$1"
    elif [ -f "$BACKUP_DIR/$1" ]; then
        RESTORE_FILE="$BACKUP_DIR/$1"
    else
        echo -e "${RED}[✗] Fichier introuvable : $1${NC}"
        exit 1
    fi

else
    mapfile -t BACKUPS < <(ls -t "$BACKUP_DIR"/healthai_backup_*.sql 2>/dev/null)

    if [ ${#BACKUPS[@]} -eq 0 ]; then
        echo -e "${RED}[✗] Aucun fichier de sauvegarde trouvé dans $BACKUP_DIR${NC}"
        echo -e "${YELLOW}    Créez d'abord une sauvegarde avec : ./backup.sh${NC}"
        exit 1
    fi

    echo -e "${YELLOW}Sauvegardes disponibles :${NC}\n"
    for i in "${!BACKUPS[@]}"; do
        SIZE=$(du -h "${BACKUPS[$i]}" | cut -f1)
        FNAME=$(basename "${BACKUPS[$i]}")

        RAW_DATE=$(echo "$FNAME" | sed 's/healthai_backup_//;s/\.sql//')
        FORMATTED=$(echo "$RAW_DATE" | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)_\([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\3\/\2\/\1 \4:\5:\6/')
        echo -e "  ${CYAN}[$((i+1))]${NC} $FNAME  ${YELLOW}($SIZE)${NC}  –  $FORMATTED"
    done

    echo ""
    read -p "Choisissez le numéro de la sauvegarde [1] : " CHOICE
    CHOICE="${CHOICE:-1}"

    if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt "${#BACKUPS[@]}" ]; then
        echo -e "${RED}[✗] Choix invalide.${NC}"
        exit 1
    fi

    RESTORE_FILE="${BACKUPS[$((CHOICE-1))]}"
fi

echo ""
echo -e "${YELLOW}⚠️  ATTENTION : La base '$DB_NAME' va être écrasée par :${NC}"
echo -e "${YELLOW}   $(basename "$RESTORE_FILE")${NC}"
echo ""
read -p "Confirmer ? [o/N] : " CONFIRM
if [[ ! "$CONFIRM" =~ ^[oO]$ ]]; then
    echo -e "${YELLOW}Restauration annulée.${NC}"
    exit 0
fi

echo -e "${YELLOW}[→] Restauration en cours...${NC}"

if docker exec -i "$CONTAINER" sh -c \
    "PGPASSWORD=$DB_PASSWORD psql -U $DB_USER -d $DB_NAME -v ON_ERROR_STOP=1" \
    < "$RESTORE_FILE" >> /dev/null 2>&1; then

    echo -e "${GREEN}[✓] Restauration réussie depuis : $(basename "$RESTORE_FILE")${NC}"
else
    echo -e "${RED}[✗] Échec de la restauration. Vérifiez les logs.${NC}"
    exit 1
fi

echo ""
exit 0