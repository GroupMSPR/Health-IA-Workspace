#!/bin/bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

LOG_FILE="$(pwd)/healthai_install.log"
> "$LOG_FILE"

export WWWUSER=1000
export WWWGROUP=1000
export DB_PASSWORD="password"
export DB_USERNAME="sail"
export DB_DATABASE="laravel"
export MONGO_ROOT_USER="root"
export MONGO_ROOT_PASSWORD="example"
export BUILDKIT_PROGRESS=plain
export DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/1521067317923025046/KlSUxUppbi6AqX_HmZ8GOP5a3pPPIrxZyJqi1HekWWDrXcOA6HTurChC6Uu3mkjetjQX"

AUTO_MODE=0
FRESH_MODE=0
ERROR_MESSAGE=""
SPIN_PID=""

# =============================================================================
#  Helpers
# =============================================================================
cleanup() {
    if [ -n "$SPIN_PID" ]; then
        kill $SPIN_PID >/dev/null 2>&1
        wait $SPIN_PID 2>/dev/null
    fi
    tput cnorm
}
trap cleanup EXIT INT TERM

start_task() {
    local msg=$1
    tput civis
    while true; do
        for spinstr in '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏'; do
            printf "\r\033[2K${CYAN}[%s]${NC} %s" "$spinstr" "$msg"
            sleep 0.1
        done
    done &
    SPIN_PID=$!
}

end_task() {
    local msg=$1
    local status=$2
    if [ -n "$SPIN_PID" ]; then
        kill $SPIN_PID >/dev/null 2>&1
        wait $SPIN_PID 2>/dev/null
        SPIN_PID=""
    fi
    if [ "$status" -eq 0 ]; then
        printf "\r\033[2K${GREEN}[✓]${NC} %s\n" "$msg"
    else
        printf "\r\033[2K${RED}[✗]${NC} %s\n" "$msg"
    fi
}

error_handler() {
    cleanup
    echo -e "\n${RED}========================================================${NC}"
    echo -e "${RED}ERREUR : $ERROR_MESSAGE${NC}"
    echo -e "${RED}-> Consultez le fichier ${YELLOW}$LOG_FILE${RED} pour voir les details.${NC}"
    echo -e "${RED}========================================================${NC}\n"
    if [ "$AUTO_MODE" -eq 0 ]; then
        read -p "Appuyez sur Entree pour fermer ce terminal..."
    fi
    exit 1
}

# =============================================================================
#  Init
# =============================================================================
cd "$(dirname "$0")" || exit 1
WORKSPACE_DIR="$(pwd)"

for arg in "$@"; do
    if [ "$arg" == "--auto" ]; then AUTO_MODE=1; fi
    if [ "$arg" == "--fresh" ]; then FRESH_MODE=1; fi
done

clear
echo -e "${CYAN}========================================================${NC}"
echo -e "${CYAN}      Demarrage du projet HealthAI Coach (MSPR)${NC}"
echo -e "${CYAN}========================================================${NC}\n"
echo -e "${CYAN}ℹ️  Mode silencieux activé. Les logs sont ecrits dans :${NC}"
echo -e "${CYAN}   -> ${YELLOW}$LOG_FILE${NC}\n"

# =============================================================================
#  [0/13] Vérification Docker
# =============================================================================
start_task "[0/13] Verification de l'environnement Docker"
if ! docker --version >> "$LOG_FILE" 2>&1; then
    ERROR_MESSAGE="Docker n'est pas installe ou non accessible."
    end_task "[0/13] Verification de l'environnement Docker" 1
    error_handler
fi
if ! docker compose version >> "$LOG_FILE" 2>&1; then
    ERROR_MESSAGE="docker compose n'est pas disponible."
    end_task "[0/13] Verification de l'environnement Docker" 1
    error_handler
fi
end_task "[0/13] Verification de l'environnement Docker" 0

# =============================================================================
#  [1/13] Vérification DISCORD_WEBHOOK_URL
# =============================================================================
start_task "[1/13] Verification de la configuration Discord (alertes monitoring)"
if [ -z "${DISCORD_WEBHOOK_URL}" ]; then
    if [ ! -f ".env" ]; then
        cp .env.example .env
    fi
    sed -i "s|^DISCORD_WEBHOOK_URL=.*|DISCORD_WEBHOOK_URL=$DISCORD_WEBHOOK_URL|" .env
    if [ -f ".env" ] && grep -q "DISCORD_WEBHOOK_URL" .env; then
        export DISCORD_WEBHOOK_URL=$(grep "DISCORD_WEBHOOK_URL" .env | cut -d'=' -f2-)
        end_task "[1/13] DISCORD_WEBHOOK_URL charge depuis .env" 0
    else
        end_task "[1/13] DISCORD_WEBHOOK_URL non configuree (alertes Discord desactivees)" 0
        echo -e "${YELLOW}  -> Pour activer les alertes Discord :${NC}"
        echo -e "${YELLOW}     Ajoutez DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/... dans .env${NC}"
    fi
else
    end_task "[1/13] DISCORD_WEBHOOK_URL configuree" 0
fi

# =============================================================================
#  [2/13] Clonage des repos
# =============================================================================
start_task "[2/13] Clonage des repos"

clone_or_fix() {
    local dir=$1 url=$2 check=$3
    if [ ! -d "$dir" ]; then
        git clone "$url" "$dir" >> "$LOG_FILE" 2>&1
    elif [ ! -f "$dir/$check" ]; then
        echo "[WARN] $dir incomplet, re-clonage..." >> "$LOG_FILE" 2>&1
        rm -rf "$dir"
        git clone "$url" "$dir" >> "$LOG_FILE" 2>&1
    fi
}

clone_or_fix "API-Ollama" "https://github.com/GroupMSPR/Health-IA-FastAPI.git"  "Dockerfile"
clone_or_fix "ETL"        "https://github.com/GroupMSPR/Health-IA-ETL.git"       "Dockerfile"
clone_or_fix "Grafana"    "https://github.com/GroupMSPR/Health-IA-Grafana.git"   "README.md"
clone_or_fix "Backend"    "https://github.com/GroupMSPR/Health-IA-Backend.git"   "composer.json"
clone_or_fix "Frontend"   "https://github.com/GroupMSPR/Health-IA-Frontend.git"  "Dockerfile"
clone_or_fix "Mobile"     "https://github.com/GroupMSPR/Health-IA-Mobile.git"    "package.json"

end_task "[2/13] Clonage des repos" 0

# =============================================================================
#  [3/13] Préparation Backend Laravel
# =============================================================================
start_task "[3/13] Preparation du Backend Laravel (env, composer, permissions)"

if [ ! -f "Backend/.env" ]; then
    cp Backend/.env.example Backend/.env
    sed -i 's/^# DB_/DB_/g' Backend/.env
    sed -i 's/^# FORWARD_DB_PORT/FORWARD_DB_PORT/g' Backend/.env
fi

for SERVICE in Frontend Mobile API-Ollama ETL; do
    if [ ! -f "$SERVICE/.env" ] && [ -f "$SERVICE/.env.example" ]; then
        cp "$SERVICE/.env.example" "$SERVICE/.env"
    fi
done

if [ ! -f "Backend/vendor/autoload.php" ]; then
    docker run --rm -u "$(id -u):$(id -g)" \
        -v "$(pwd)/Backend":/app \
        composer install --ignore-platform-reqs >> "$LOG_FILE" 2>&1
fi

docker run --rm -v "$(pwd)/Backend:/app" alpine sh -c "
    mkdir -p /app/storage/framework/sessions \
             /app/storage/framework/views \
             /app/storage/framework/cache \
             /app/bootstrap/cache && \
    chmod -R 777 /app/storage /app/bootstrap/cache
" >> "$LOG_FILE" 2>&1

end_task "[3/13] Preparation du Backend Laravel" 0

# =============================================================================
#  [4/13] Arrêt des conteneurs existants + nettoyage réseau conflictuel
# =============================================================================
start_task "[4/13] Arret des conteneurs existants"
if [ "$FRESH_MODE" -eq 1 ]; then
    docker compose --profile backend --profile ia --profile monitoring \
        down -v --remove-orphans >> "$LOG_FILE" 2>&1
else
    docker compose --profile backend --profile ia --profile monitoring \
        down --remove-orphans >> "$LOG_FILE" 2>&1
fi

# Supprime le réseau healthai_backend_sail s'il a été créé par un autre projet
# (label com.docker.compose.network=sail au lieu de healthai_network)
NETWORK_LABEL=$(docker network inspect healthai_backend_sail \
    --format '{{index .Labels "com.docker.compose.network"}}' 2>/dev/null || true)
if [ "$NETWORK_LABEL" = "sail" ]; then
    echo "[INFO] Suppression du reseau orphelin healthai_backend_sail (label=sail)" >> "$LOG_FILE" 2>&1
    docker network rm healthai_backend_sail >> "$LOG_FILE" 2>&1 || true
fi

end_task "[4/13] Arret des conteneurs existants" 0

# =============================================================================
#  [5/13] Profil BACKEND (Laravel + PostgreSQL + MailCatcher)
# =============================================================================
start_task "[5/13] Lancement Profil BACKEND (Laravel / PostgreSQL / MailCatcher)"

if ! docker compose --profile backend up -d >> "$LOG_FILE" 2>&1; then
    ERROR_MESSAGE="Lancement du profil backend a echoue."
    end_task "[5/13] Lancement Profil BACKEND" 1
    error_handler
fi

# Attente PostgreSQL
RETRY_COUNT=0; MAX_RETRIES=30
while ! docker compose exec -T healthai_pgsql pg_isready -U sail >> "$LOG_FILE" 2>&1; do
    ((RETRY_COUNT++))
    [ $RETRY_COUNT -ge $MAX_RETRIES ] && {
        ERROR_MESSAGE="PostgreSQL n'a pas demarre apres 30 tentatives."
        end_task "[5/13] Lancement Profil BACKEND" 1
        error_handler
    }
    sleep 4
done

# Attente Laravel
RETRY_COUNT=0; MAX_RETRIES=15
while ! docker compose exec -T healthai_laravel php -r "echo 'ok';" >> "$LOG_FILE" 2>&1; do
    ((RETRY_COUNT++))
    [ $RETRY_COUNT -ge $MAX_RETRIES ] && {
        ERROR_MESSAGE="Le conteneur Laravel n'a pas demarre."
        end_task "[5/13] Lancement Profil BACKEND" 1
        error_handler
    }
    sleep 4
done

# Réparation PostgreSQL si nécessaire
if ! docker compose exec -T healthai_pgsql sh -lc \
    "PGPASSWORD=$DB_PASSWORD psql -U sail -d laravel -tAc 'select 1'" >> "$LOG_FILE" 2>&1; then
    docker compose exec -T healthai_pgsql sh -lc \
        "PGPASSWORD=$DB_PASSWORD psql -U postgres -d postgres -f -" \
        < Backend/docker/repair-postgres.sql >> "$LOG_FILE" 2>&1 || {
        ERROR_MESSAGE="Reparation du cluster PostgreSQL a echoue."
        end_task "[5/13] Lancement Profil BACKEND" 1
        error_handler
    }
fi

# Migrations
if [ "$FRESH_MODE" -eq 1 ]; then
    docker compose exec -T healthai_laravel php artisan migrate:fresh --force --seed >> "$LOG_FILE" 2>&1 || {
        ERROR_MESSAGE="migrate:fresh --seed a echoue."
        end_task "[5/13] Lancement Profil BACKEND" 1
        error_handler
    }
    if [ -f "Backend/docker/healthia_dump_pg.sql" ]; then
        docker compose exec -T healthai_pgsql sh -c \
            "PGPASSWORD=$DB_PASSWORD psql -U sail -d laravel" \
            < Backend/docker/healthia_dump_pg.sql >> "$LOG_FILE" 2>&1
    fi
else
    docker compose exec -T healthai_laravel php artisan migrate --force >> "$LOG_FILE" 2>&1 || {
        ERROR_MESSAGE="Les migrations Laravel ont echoue."
        end_task "[5/13] Lancement Profil BACKEND" 1
        error_handler
    }
    docker compose exec -T healthai_laravel php artisan db:seed --force >> "$LOG_FILE" 2>&1
    if [ -f "Backend/docker/healthia_dump_pg.sql" ]; then
        docker compose exec -T healthai_pgsql sh -c \
            "PGPASSWORD=$DB_PASSWORD psql -U sail -d laravel" \
            < Backend/docker/healthia_dump_pg.sql >> "$LOG_FILE" 2>&1
    fi
fi

grep -q "^APP_KEY=$" Backend/.env && \
    docker compose exec -T healthai_laravel php artisan key:generate >> "$LOG_FILE" 2>&1
docker compose exec -T healthai_laravel php artisan optimize >> "$LOG_FILE" 2>&1
docker compose exec -T healthai_laravel php artisan filament:optimize >> "$LOG_FILE" 2>&1

end_task "[5/13] Lancement Profil BACKEND (Laravel / PostgreSQL / MailCatcher)" 0

# =============================================================================
#  [6/13] Frontend (pas de profil)
# =============================================================================
start_task "[6/13] Lancement Frontend React"
if ! docker compose up -d healthai_frontend >> "$LOG_FILE" 2>&1; then
    ERROR_MESSAGE="Lancement du Frontend React a echoue."
    end_task "[6/13] Lancement Frontend React" 1
    error_handler
fi
end_task "[6/13] Lancement Frontend React" 0

# =============================================================================
#  [7/13] Mobile (pas de profil)
# =============================================================================
start_task "[7/13] Lancement Mobile React Native"
if ! docker compose up -d healthai_mobile >> "$LOG_FILE" 2>&1; then
    ERROR_MESSAGE="Lancement du Mobile React Native a echoue."
    end_task "[7/13] Lancement Mobile React Native" 1
    error_handler
fi
end_task "[7/13] Lancement Mobile React Native" 0

# =============================================================================
#  [8/13] Profil IA (FastAPI + Ollama + MongoDB)
# =============================================================================
start_task "[8/13] Lancement Profil IA (FastAPI / Ollama / MongoDB)"
if ! docker compose --profile ia up -d >> "$LOG_FILE" 2>&1; then
    ERROR_MESSAGE="Lancement du profil IA (FastAPI/Ollama/MongoDB) a echoue."
    end_task "[8/13] Lancement Profil IA" 1
    error_handler
fi
end_task "[8/13] Lancement Profil IA (FastAPI / Ollama / MongoDB)" 0

# =============================================================================
#  [9/13] Vérification LLaVA
# =============================================================================
start_task "[9/13] Verification du modele LLaVA"
sleep 2
if ! docker exec healthai_ollama ollama list | grep -q "llava"; then
    end_task "[9/13] Verification du modele LLaVA (Installation requise)" 0
    echo -e "${YELLOW}  -> Telechargement du modele LLaVA (4.7 Go)... Patientez.${NC}"
    if ! docker exec healthai_ollama ollama pull llava; then
        echo -e "${RED}  -> [WARN] Telechargement echoue. Relancez manuellement :${NC}"
        echo -e "${RED}     docker exec healthai_ollama ollama pull llava${NC}"
    else
        echo -e "${GREEN}  -> [✓] Modele LLaVA telecharge !${NC}"
    fi
else
    end_task "[9/13] Verification du modele LLaVA (Deja present)" 0
fi

# =============================================================================
#  [10/13] Profil MONITORING
#  ETL + Grafana + Prometheus + Alertmanager + Discord Bridge
#  + Node Exporter + cAdvisor + Postgres Exporter
#  + MongoDB Exporter + Blackbox Exporter
# =============================================================================
start_task "[10/13] Lancement Profil MONITORING (Grafana / Prometheus / Alertes Discord)"
if ! docker compose --profile monitoring up -d >> "$LOG_FILE" 2>&1; then
    ERROR_MESSAGE="Lancement du profil monitoring a echoue."
    end_task "[10/13] Lancement Profil MONITORING" 1
    error_handler
fi
end_task "[10/13] Lancement Profil MONITORING (10 conteneurs)" 0

# =============================================================================
#  [11/13] Sauvegarde automatique (cron)
# =============================================================================
start_task "[11/13] Mise en place de la sauvegarde automatique (cron)"
SCRIPT_ABS="$WORKSPACE_DIR/backup.sh"
chmod +x "$SCRIPT_ABS"
chmod +x "$WORKSPACE_DIR/restore.sh"

CRON_JOB="0 2 * * * $SCRIPT_ABS --silent >> $WORKSPACE_DIR/backups/backup_cron.log 2>&1"
if crontab -l 2>/dev/null | grep -qF "$SCRIPT_ABS"; then
    end_task "[11/13] Sauvegarde automatique deja configuree" 0
else
    (crontab -l 2>/dev/null; echo "# HealthAI Coach - backup quotidien 2h00"; echo "$CRON_JOB") | crontab -
    end_task "[11/13] Sauvegarde automatique configuree (tous les jours a 2h00)" 0
fi

# =============================================================================
#  [12/13] Vérification finale des conteneurs
# =============================================================================
start_task "[12/13] Verification finale de tous les conteneurs"
sleep 5
FAILED=$(docker compose --profile backend --profile ia --profile monitoring \
    ps --filter "status=exited" --format "{{.Name}}" 2>/dev/null)
if [ -n "$FAILED" ]; then
    echo -e "\n${YELLOW}  -> [WARN] Conteneurs arretes : $FAILED${NC}"
    end_task "[12/13] Verification finale (avec avertissements)" 0
else
    end_task "[12/13] Tous les conteneurs sont actifs" 0
fi

# =============================================================================
#  [13/13] Demo monitoring — conseil pour la soutenance
# =============================================================================
cleanup
echo -e "\n${CYAN}  Conseil demo monitoring :${NC}"
echo -e "  ${YELLOW}docker stop healthai_fastapi${NC}   → alerte Discord en ~15 secondes"
echo -e "  ${YELLOW}docker start healthai_fastapi${NC}  → résolution Discord en ~15 secondes"

# =============================================================================
#  Fin
# =============================================================================
echo -e "\n${GREEN}========================================================${NC}"
echo -e "${GREEN}        TOUT EST DEMARRE AVEC SUCCES !${NC}"
echo -e "${GREEN}========================================================${NC}"
echo ""
echo "Profils Docker Compose actifs :"
echo -e "  ${CYAN}backend${NC}    → Laravel + PostgreSQL + MailCatcher"
echo -e "  ${CYAN}ia${NC}         → FastAPI + Ollama + MongoDB"
echo -e "  ${CYAN}monitoring${NC} → ETL + Grafana + Prometheus + Alertmanager"
echo -e "             → Discord Bridge + Node/cAdvisor/PG/Mongo/Blackbox Exporters"
echo -e "  ${CYAN}(defaut)${NC}   → Frontend + Mobile"
echo ""
echo "Maintenez CTRL et cliquez sur les liens :"
echo ""
echo " - API Laravel         -> http://localhost"
echo " - Back-office Admin   -> http://localhost/admin"
echo " - Frontend React      -> http://localhost:5001"
echo " - Mobile React Native -> http://localhost:6000"
echo " - API Doc Swagger     -> http://localhost/api/documentation"
echo " - Grafana             -> http://localhost:3000"
echo " - API IA (FastAPI)    -> http://localhost:4000/docs"
echo " - Ollama              -> http://localhost:11434"
echo " - Prometheus          -> http://localhost:9090"
echo " - Alertmanager        -> http://localhost:9093"
echo ""
echo "Identifiants Back-office Admin : admin@healthai-coach.mspr / password123"
echo "Identifiants Frontend + Mobile : john.doe@example.com / password123"
echo "Identifiants Grafana           : admin / admin"
echo ""
echo -e "${GREEN}Commandes utiles :${NC}"
echo "  Arreter tout     : docker compose --profile backend --profile ia --profile monitoring down"
echo "  Reset complet    : ./start.sh --fresh"
echo "  Logs monitoring  : docker compose --profile monitoring logs -f"
echo "  Restaurer backup : ./restore.sh"
echo -e "${GREEN}========================================================${NC}\n"

echo "[INFOS] Mode : $AUTO_MODE (0=interactif, 1=automatique)"
echo "[INFOS] Fresh : $FRESH_MODE (0=incremental, 1=reset)"
echo ""

if [ "$AUTO_MODE" -eq 0 ]; then
    read -p "Appuyez sur Entree pour terminer..."
else
    echo "[AUTO MODE] Demarrage automatique termine."
fi

exit 0