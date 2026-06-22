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
export BUILDKIT_PROGRESS=plain

AUTO_MODE=0
FRESH_MODE=0
ERROR_MESSAGE=""
SPIN_PID=""

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
    echo -e "${RED}-> Consultez le fichier ${YELLOW}$LOG_FILE${RED} pour voir les details du plantage.${NC}"
    echo -e "${RED}========================================================${NC}\n"
    if [ "$AUTO_MODE" -eq 0 ]; then
        read -p "Appuyez sur Entree pour fermer ce terminal..."
    fi
    exit 1
}

cd "$(dirname "$0")" || exit 1

for arg in "$@"; do
    if [ "$arg" == "--auto" ]; then AUTO_MODE=1; fi
    if [ "$arg" == "--fresh" ]; then FRESH_MODE=1; fi
done

clear
echo -e "${CYAN}========================================================${NC}"
echo -e "${CYAN}      Demarrage du projet HealthAI Coach (MSPR)${NC}"
echo -e "${CYAN}========================================================${NC}\n"
echo -e "${CYAN}ℹ️  Mode silencieux activé. Les logs d'installation sont ecrits dans :${NC}"
echo -e "${CYAN}   -> ${YELLOW}$LOG_FILE${NC}\n"

# ---------------------------------------------------------
start_task "[0/12] Verification de l'environnement Docker"
if ! docker --version >> "$LOG_FILE" 2>&1; then
    ERROR_MESSAGE="Docker n'est pas installe ou non accessible."
    end_task "[0/12] Verification de l'environnement Docker" 1
    error_handler
fi
if ! docker compose version >> "$LOG_FILE" 2>&1; then
    ERROR_MESSAGE="docker compose n'est pas disponible."
    end_task "[0/12] Verification de l'environnement Docker" 1
    error_handler
fi
end_task "[0/12] Verification de l'environnement Docker" 0

# ---------------------------------------------------------
start_task "[1/12] Clonage API IA (FastAPI)"
if [ ! -d "API-Ollama" ]; then
    git clone https://github.com/GroupMSPR/Health-IA-FastAPI.git API-Ollama >> "$LOG_FILE" 2>&1
fi
end_task "[1/12] Clonage API IA (FastAPI)" 0

# ---------------------------------------------------------
start_task "[2/12] Clonage ETL"
if [ ! -d "ETL" ]; then
    git clone https://github.com/GroupMSPR/Health-IA-ETL.git ETL >> "$LOG_FILE" 2>&1
fi
end_task "[2/12] Clonage ETL" 0

# ---------------------------------------------------------
start_task "[3/12] Clonage Grafana"
if [ ! -d "Grafana" ]; then
    git clone https://github.com/GroupMSPR/Health-IA-Grafana.git Grafana >> "$LOG_FILE" 2>&1
fi
end_task "[3/12] Clonage Grafana" 0

# ---------------------------------------------------------
start_task "[4/12] Clonage Backend (Laravel)"
if [ ! -d "Backend" ]; then
    git clone https://github.com/GroupMSPR/Health-IA-Backend.git Backend >> "$LOG_FILE" 2>&1
fi
end_task "[4/12] Clonage Backend (Laravel)" 0

# ---------------------------------------------------------
start_task "[5/12] Clonage Frontend (React Web)"
if [ ! -d "Frontend" ]; then
    git clone https://github.com/GroupMSPR/Health-IA-Frontend.git Frontend >> "$LOG_FILE" 2>&1
fi
end_task "[5/12] Clonage Frontend (React Web)" 0

# ---------------------------------------------------------
start_task "[6/12] Clonage Mobile (React Native)"
if [ ! -d "Mobile" ]; then
    git clone https://github.com/GroupMSPR/Health-IA-Mobile.git Mobile >> "$LOG_FILE" 2>&1
fi
end_task "[6/12] Clonage Mobile (React Native)" 0

# ---------------------------------------------------------
start_task "[7/12] Configuration et Lancement du Backend (Laravel/PostgreSQL/MailCatcher)"
pushd "Backend" > /dev/null || exit

if [ ! -f ".env" ]; then
    cp .env.example .env
    sed -i 's/^# DB_/DB_/g' .env
    sed -i 's/^# FORWARD_DB_PORT/FORWARD_DB_PORT/g' .env
fi

if [ ! -f "vendor/autoload.php" ]; then
    docker run --rm -u "$(id -u):$(id -g)" -v $(pwd):/app composer install --ignore-platform-reqs >> "$LOG_FILE" 2>&1
fi

docker run --rm -v "$(pwd):/app" alpine sh -c "
    mkdir -p /app/storage/framework/sessions \
             /app/storage/framework/views \
             /app/storage/framework/cache \
             /app/bootstrap/cache && \
    chmod -R 777 /app/storage /app/bootstrap/cache
" >> "$LOG_FILE" 2>&1

if [ "$FRESH_MODE" -eq 1 ]; then
    docker compose down -v --remove-orphans >> "$LOG_FILE" 2>&1
else
    docker compose down --remove-orphans >> "$LOG_FILE" 2>&1
fi

if ! docker compose up -d >> "$LOG_FILE" 2>&1; then
    ERROR_MESSAGE="Lancement du conteneur Backend (Laravel/PostgreSQL/MailCatcher) a echoue."
    end_task "[7/12] Configuration et Lancement du Backend (Laravel/PostgreSQL/MailCatcher)" 1
    error_handler
fi

RETRY_COUNT=0
MAX_RETRIES=30
while ! docker compose exec -T healthai_pgsql pg_isready -U sail >> "$LOG_FILE" 2>&1; do
    ((RETRY_COUNT++))
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        ERROR_MESSAGE="PostgreSQL n'a pas demarre apres 30 tentatives."
        end_task "[7/12] Configuration et Lancement du Backend (Laravel/PostgreSQL/MailCatcher)" 1
        error_handler
    fi
    sleep 4
done

RETRY_COUNT=0
MAX_RETRIES=15
while ! docker compose exec -T healthai_laravel php -r "echo 'ok';" >> "$LOG_FILE" 2>&1; do
    ((RETRY_COUNT++))
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        ERROR_MESSAGE="Le conteneur Backend (Laravel/PostgreSQL/MailCatcher) n'a pas demarre."
        end_task "[7/12] Configuration et Lancement du Backend (Laravel/PostgreSQL/MailCatcher)" 1
        error_handler
    fi
    sleep 4
done

if ! docker compose exec -T healthai_pgsql sh -lc "PGPASSWORD=$DB_PASSWORD psql -U sail -d laravel -tAc 'select 1'" >> "$LOG_FILE" 2>&1; then
    if ! docker compose exec -T healthai_pgsql sh -lc "PGPASSWORD=$DB_PASSWORD psql -U postgres -d postgres -f -" < docker/repair-postgres.sql >> "$LOG_FILE" 2>&1; then
        ERROR_MESSAGE="Reparation du cluster PostgreSQL a echoue."
        end_task "[7/12] Configuration et Lancement du Backend (Laravel/PostgreSQL/MailCatcher)" 1
        error_handler
    fi
fi

if [ "$FRESH_MODE" -eq 1 ]; then
    if ! docker compose exec -T healthai_laravel php artisan migrate:fresh --force --seed >> "$LOG_FILE" 2>&1; then
        ERROR_MESSAGE="migrate:fresh --seed a echoue."
        end_task "[7/12] Configuration et Lancement du Backend (Laravel/PostgreSQL/MailCatcher)" 1
        error_handler
    fi
    if [ -f "docker/healthia_dump_pg.sql" ]; then
        if ! docker compose exec -T healthai_pgsql sh -c "PGPASSWORD=$DB_PASSWORD psql -U sail -d laravel" < docker/healthia_dump_pg.sql >> "$LOG_FILE" 2>&1; then
            ERROR_MESSAGE="Dump PostgreSQL a echoue."
            end_task "[7/12] Configuration et Lancement du Backend (Laravel/PostgreSQL/MailCatcher)" 1
            error_handler
        fi
    fi
else
    if ! docker compose exec -T healthai_laravel php artisan migrate --force >> "$LOG_FILE" 2>&1; then
        ERROR_MESSAGE="Les migrations Laravel ont echoue."
        end_task "[7/12] Configuration et Lancement du Backend (Laravel/PostgreSQL/MailCatcher)" 1
        error_handler
    fi
    docker compose exec -T healthai_laravel php artisan db:seed --force >> "$LOG_FILE" 2>&1
    if [ -f "docker/healthia_dump_pg.sql" ]; then
        if ! docker compose exec -T healthai_pgsql sh -c "PGPASSWORD=$DB_PASSWORD psql -U sail -d laravel" < docker/healthia_dump_pg.sql >> "$LOG_FILE" 2>&1; then
            ERROR_MESSAGE="Dump PostgreSQL a echoue."
            end_task "[7/12] Configuration et Lancement du Backend (Laravel/PostgreSQL/MailCatcher)" 1
            error_handler
        fi
    fi
fi

if grep -q "^APP_KEY=$" .env; then
    docker compose exec -T healthai_laravel php artisan key:generate >> "$LOG_FILE" 2>&1
fi
docker compose exec -T healthai_laravel php artisan optimize >> "$LOG_FILE" 2>&1
docker compose exec -T healthai_laravel php artisan filament:optimize >> "$LOG_FILE" 2>&1

popd > /dev/null || exit
end_task "[7/12] Configuration et Lancement du Backend (Laravel/PostgreSQL/MailCatcher)" 0

# ---------------------------------------------------------
start_task "[8/12] Lancement du Frontend (React Web)"
pushd "Frontend" > /dev/null || exit
if [ ! -f ".env" ] && [ -f ".env.example" ]; then
    cp .env.example .env
fi
if [ "$FRESH_MODE" -eq 1 ]; then
    docker compose down -v --remove-orphans >> "$LOG_FILE" 2>&1
else
    docker compose down --remove-orphans >> "$LOG_FILE" 2>&1
fi

if ! docker compose up -d >> "$LOG_FILE" 2>&1; then
    ERROR_MESSAGE="Lancement du conteneur Frontend React a echoue."
    end_task "[8/12] Lancement du Frontend (React Web)" 1
    error_handler
fi
popd > /dev/null || exit
end_task "[8/12] Lancement du Frontend (React Web)" 0

# ---------------------------------------------------------
start_task "[9/12] Lancement du Mobile (React Native)"
pushd "Mobile" > /dev/null || exit
if [ ! -f ".env" ] && [ -f ".env.example" ]; then
    cp .env.example .env
fi
if [ "$FRESH_MODE" -eq 1 ]; then
    docker compose down -v --remove-orphans >> "$LOG_FILE" 2>&1
else
    docker compose down --remove-orphans >> "$LOG_FILE" 2>&1
fi

if ! docker compose up -d >> "$LOG_FILE" 2>&1; then
    ERROR_MESSAGE="Lancement du conteneur Mobile (React Native) a echoue."
    end_task "[9/12] Lancement du Mobile (React Native)" 1
    error_handler
fi
popd > /dev/null || exit
end_task "[9/12] Lancement du Mobile (React Native)" 0

# ---------------------------------------------------------
start_task "[10/12] Lancement de l'ETL et de Grafana"
pushd "ETL" > /dev/null || exit
if [ ! -f ".env" ] && [ -f ".env.example" ]; then
    cp .env.example .env
fi
if [ "$FRESH_MODE" -eq 1 ]; then
    docker compose down -v --remove-orphans >> "$LOG_FILE" 2>&1
else
    docker compose down --remove-orphans >> "$LOG_FILE" 2>&1
fi

if ! docker compose up -d >> "$LOG_FILE" 2>&1; then
    ERROR_MESSAGE="Lancement des conteneurs ETL/Grafana a echoue."
    end_task "[10/12] Lancement de l'ETL et de Grafana" 1
    error_handler
fi
popd > /dev/null || exit
end_task "[10/12] Lancement de l'ETL et de Grafana" 0

# ---------------------------------------------------------
start_task "[11/12] Lancement de l'API IA (FastAPI, Ollama & MongoDB)"
pushd "API-Ollama" > /dev/null || exit
if [ ! -f ".env" ] && [ -f ".env.example" ]; then
    cp .env.example .env
fi
if [ "$FRESH_MODE" -eq 1 ]; then
    docker compose down -v --remove-orphans >> "$LOG_FILE" 2>&1
else
    docker compose down --remove-orphans >> "$LOG_FILE" 2>&1
fi

if ! docker compose up -d >> "$LOG_FILE" 2>&1; then
    ERROR_MESSAGE="Lancement du conteneur API IA (FastAPI, Ollama & MongoDB) a echoue."
    end_task "[11/12] Lancement de l'API IA (FastAPI, Ollama & MongoDB)" 1
    error_handler
fi
popd > /dev/null || exit
end_task "[11/12] Lancement de l'API IA (FastAPI, Ollama & MongoDB)" 0

# ---------------------------------------------------------
start_task "[12/12] Verification du modele LLaVA"
sleep 2
if ! docker exec healthai_ollama ollama list | grep -q "llava"; then
    end_task "[12/12] Verification du modele LLaVA (Installation requise)" 0
    echo -e "${YELLOW}  -> Telechargement du modele LLaVA (4.7 Go)... Patientez.${NC}"
    if ! docker exec healthai_ollama ollama pull llava; then
        echo -e "${RED}  -> [WARN] Le telechargement a echoue. A faire manuellement.${NC}"
    else
        echo -e "${GREEN}  -> [✓] Modele LLaVA telecharge avec succes !${NC}"
    fi
else
    end_task "[12/12] Verification du modele LLaVA (Deja present)" 0
fi

# ========================================================
cleanup
# ========================================================

echo -e "\n${GREEN}========================================================${NC}"
echo -e "${GREEN}        TOUT EST DEMARRE AVEC SUCCES ! ${NC}"
echo -e "${GREEN}========================================================${NC}"

echo "Maintenez la touche CTRL appuyee et cliquez sur les liens :"
echo ""
echo " - API Laravel         -> http://localhost"
echo " - Back-office Admin   -> http://localhost/admin"
echo " - Frontend React      -> http://localhost:5001"
echo " - Mobile React Native -> http://localhost:6000"
echo " - API Doc Swagger     -> http://localhost/api/documentation"
echo " - Grafana             -> http://localhost:3000"
echo " - API IA (FastAPI)    -> http://localhost:4000/docs"
echo " - Ollama HC           -> http://localhost:11434"
echo ""
echo "Identifiants Back-office Admin (test) : admin@healthai-coach.mspr / password123"
echo "Identifiants Frontend React (test) : john.doe@example.com / password123"
echo "Identifiants Mobile React Native (test) : john.doe@example.com / password123"
echo "Identifiants Grafana (peut être modifiés) : admin / admin"
echo -e "${GREEN}========================================================${NC}\n"

echo "[INFOS] Mode d'execution : $AUTO_MODE (0=interactif, 1=automatique)"
echo "[INFOS] Mode fresh       : $FRESH_MODE (0=incremental, 1=reset complet)"
echo ""

if [ "$AUTO_MODE" -eq 0 ]; then
    read -p "Appuyez sur Entree pour terminer..."
else
    echo "[AUTO MODE] Demarrage automatique termine."
fi

exit 0