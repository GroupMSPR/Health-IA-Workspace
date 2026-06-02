#!/bin/bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}========================================================${NC}"
echo -e "${CYAN}      Demarrage du projet HealthAI Coach (MSPR)${NC}"
echo -e "${CYAN}========================================================${NC}"

WWWUSER=1000
WWWGROUP=1000
DB_PASSWORD="password"
AUTO_MODE=0
FRESH_MODE=0
ERROR_MESSAGE=""

error_handler() {
    echo -e "\n${RED}========================================================${NC}"
    echo -e "${RED}ERREUR : $ERROR_MESSAGE${NC}"
    echo -e "${RED}========================================================${NC}\n"
    if [ "$AUTO_MODE" -eq 0 ]; then
        read -p "Appuyez sur Entree pour fermer ce terminal..."
    fi
    exit 1
}

cd "$(dirname "$0")" || exit 1

for arg in "$@"; do
    if [ "$arg" == "--auto" ]; then
        AUTO_MODE=1
    fi
    if [ "$arg" == "--fresh" ]; then
        FRESH_MODE=1
    fi
done

echo -e "\n${CYAN}========================================================${NC}"
echo -e "${CYAN}[BOOTSTRAP] Verification et recuperation des sous-projets${NC}"
echo -e "${CYAN}========================================================${NC}"

echo -e "${GREEN}[1/10] Clonage API IA (FastAPI)${NC}"
if [ -d "API-Ollama" ]; then
    echo "[OK] Dossier API-Ollama deja present."
else
    echo "[CLONAGE] Recuperation de API-Ollama..."
    git clone https://github.com/GroupMSPR/Health-IA-FastAPI.git API-Ollama
fi

echo -e "${GREEN}[2/10] Clonage ETL${NC}"
if [ -d "ETL" ]; then
    echo "[OK] Dossier ETL deja present."
else
    echo "[CLONAGE] Recuperation de l'ETL..."
    git clone https://github.com/GroupMSPR/Health-IA-ETL.git ETL
fi

echo -e "${GREEN}[3/10] Clonage Grafana${NC}"
if [ -d "Grafana" ]; then
    echo "[OK] Dossier Grafana deja present."
else
    echo "[CLONAGE] Recuperation de Grafana..."
    git clone https://github.com/GroupMSPR/Health-IA-Grafana.git Grafana
fi

echo -e "${GREEN}[4/10] Clonage Backend (Laravel)${NC}"
if [ -d "Backend" ]; then
    echo "[OK] Dossier Backend deja present."
else
    echo "[CLONAGE] Recuperation du Backend Laravel..."
    git clone https://github.com/GroupMSPR/Health-IA-Backend.git Backend
fi

echo -e "${GREEN}[5/10] Clonage Frontend (React SPA)${NC}"
if [ -d "Frontend" ]; then
    echo "[OK] Dossier Frontend deja present."
else
    echo "[CLONAGE] Recuperation du Frontend React..."
    git clone https://github.com/GroupMSPR/Health-IA-Frontend.git Frontend
fi

echo -e "\n${GREEN}[PRECHECKS] Verification de l'environnement...${NC}"
if ! docker --version >/dev/null 2>&1; then
    ERROR_MESSAGE="Docker n'est pas installe ou non accessible. Installez Docker Desktop."
    error_handler
fi

if ! docker compose version >/dev/null 2>&1; then
    ERROR_MESSAGE="docker compose n'est pas disponible. Installez une version recente de Docker Desktop."
    error_handler
fi

if ! docker info >/dev/null 2>&1; then
    ERROR_MESSAGE="Le daemon Docker ne repond pas. Demarrez Docker Desktop."
    error_handler
fi
echo "[OK] Docker et docker compose detectes."

echo -e "\n${GREEN}[6/10] Lancement de l'API Laravel et de PostgreSQL...${NC}"
pushd "Backend" > /dev/null || exit

if [ ! -f ".env" ]; then
    echo "[INIT] Creation automatique du fichier .env Laravel..."
    cp .env.example .env
    echo "[INIT] Decommentation automatique des variables de base de donnees..."
    sed -i 's/^# DB_/DB_/g' .env
    sed -i 's/^# FORWARD_DB_PORT/FORWARD_DB_PORT/g' .env
fi

if [ ! -f "vendor/autoload.php" ]; then
    echo "[INIT] Telechargement des dependances PHP (Composer)..."
    echo "Cela peut prendre quelques minutes la premiere fois."
    docker run --rm -v "$(pwd):/app" composer install --ignore-platform-reqs
fi

if ! docker compose up -d --wait; then
    ERROR_MESSAGE="Lancement du conteneur Laravel/PostgreSQL a echoue."
    error_handler
fi
echo "[OK] Conteneurs demarres et healthchecks passes."

echo "Attente du demarrage complet de PostgreSQL..."
RETRY_COUNT=0
MAX_RETRIES=30
while ! docker compose exec -T healthai_pgsql pg_isready -U sail >/dev/null 2>&1; do
    ((RETRY_COUNT++))
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        ERROR_MESSAGE="PostgreSQL n'a pas demarre apres 30 tentatives."
        error_handler
    fi
    sleep 4
done
echo "[OK] PostgreSQL est pret."

echo "Verification que Laravel repond..."
RETRY_COUNT=0
MAX_RETRIES=15
while ! docker compose exec -T healthai_laravel php -r "echo 'ok';" >/dev/null 2>&1; do
    ((RETRY_COUNT++))
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        ERROR_MESSAGE="Le conteneur Laravel n'a pas demarre apres 15 tentatives."
        error_handler
    fi
    sleep 4
done
echo "[OK] Laravel est pret."

echo "Verification des identifiants PostgreSQL Sail..."
if ! docker compose exec -T healthai_pgsql sh -lc "PGPASSWORD=$DB_PASSWORD psql -U sail -d laravel -tAc 'select 1'" > /dev/null 2>&1; then
    echo "Le cluster PostgreSQL a ete initialise avec d'anciens identifiants."
    echo "Reparation du role sail et de la base laravel..."
    if ! docker compose exec -T healthai_pgsql sh -lc "PGPASSWORD=$DB_PASSWORD psql -U postgres -d postgres -f -" < docker/repair-postgres.sql; then
        ERROR_MESSAGE="Reparation du cluster PostgreSQL a echoue."
        error_handler
    fi
    echo "[OK] Cluster PostgreSQL repare."
fi

echo -e "\nMigration de la base de donnees & Seeding..."
if [ "$FRESH_MODE" -eq 1 ]; then
    echo "[FRESH] Reset complet de la base de donnees..."
    if ! docker compose exec -T healthai_laravel php artisan migrate:fresh --force --seed; then
        ERROR_MESSAGE="migrate:fresh --seed a echoue."
        error_handler
    fi
    echo "[OK] Base de donnees recree et ensemencee."
else
    if ! docker compose exec -T healthai_laravel php artisan migrate --force; then
        ERROR_MESSAGE="Les migrations Laravel ont echoue."
        error_handler
    fi
    docker compose exec -T healthai_laravel php artisan db:seed --force >/dev/null 2>&1
    echo "[OK] Migrations et verifications terminees."
fi

echo -e "\nGeneration Key / Optimisation du cache Laravel..."
if grep -q "^APP_KEY=$" .env; then
    echo "[INIT] Generation de la cle Laravel manquante..."
    docker compose exec -T healthai_laravel php artisan key:generate >/dev/null 2>&1
fi
docker compose exec -T healthai_laravel php artisan optimize >/dev/null 2>&1
docker compose exec -T healthai_laravel php artisan filament:optimize >/dev/null 2>&1
echo "[OK] Cache Laravel et Filament optimises."
popd > /dev/null || exit

echo -e "\n${GREEN}[7/10] Lancement du Frontend (React SPA)...${NC}"
pushd "Frontend" > /dev/null || exit
if [ ! -f ".env" ] && [ -f ".env.example" ]; then
    echo "[INIT] Creation automatique du fichier .env Frontend..."
    cp .env.example .env
fi
if ! docker compose up -d --build; then
    ERROR_MESSAGE="Lancement du conteneur Frontend React a echoue."
    error_handler
fi
echo "[OK] Frontend React lance avec succes."
popd > /dev/null || exit

echo -e "\n${GREEN}[8/10] Lancement de l'ETL (Python) et de Grafana...${NC}"
pushd "ETL" > /dev/null || exit
if [ ! -f ".env" ] && [ -f ".env.example" ]; then
    echo "[INIT] Creation automatique du fichier .env ETL..."
    cp .env.example .env
fi
if ! docker compose up -d --build; then
    ERROR_MESSAGE="Lancement des conteneurs ETL/Grafana a echoue."
    error_handler
fi
echo "[OK] ETL et Grafana demarres."
popd > /dev/null || exit

echo -e "\n${GREEN}[9/10] Lancement de l'API IA (FastAPI)...${NC}"
pushd "API-Ollama" > /dev/null || exit
if [ ! -f ".env" ] && [ -f ".env.example" ]; then
    echo "[INIT] Creation automatique du fichier .env API IA..."
    cp .env.example .env
fi
if ! docker compose up -d --build; then
    ERROR_MESSAGE="Lancement du conteneur API IA a echoue."
    error_handler
fi
echo "[OK] API IA (FastAPI) et Ollama demarree."
popd > /dev/null || exit

echo -e "\n${CYAN}========================================================${NC}"
echo -e "${CYAN}[10/10] [IA SETUP] Verification du modele LLaVA${NC}"
echo -e "${CYAN}========================================================${NC}"
sleep 5
if ! docker exec healthai_ollama ollama list | grep -q "llava"; then
    echo "[INIT] Le modele LLaVA n'est pas installe sur cette machine."
    echo "[INIT] Telechargement en cours... "
    echo "[ATTENTION] C'est un fichier de ~4.7 Go, patience !"
    if ! docker exec healthai_ollama ollama pull llava; then
        echo -e "${YELLOW}[WARN] Le telechargement a echoue. Vous devrez le faire manuellement.${NC}"
    else
        echo "[OK] Modele LLaVA telecharge avec succes !"
    fi
else
    echo "[OK] Le modele LLaVA est deja present et operationnel."
fi

echo -e "\n${GREEN}========================================================${NC}"
echo -e "${GREEN}        TOUT EST DEMARRE AVEC SUCCES ! ${NC}"
echo -e "${GREEN}========================================================${NC}\n"

echo "Maintenez la touche CTRL appuyee et cliquez sur les liens :"
echo ""
echo " - API Laravel      : http://localhost"
echo " - BackOffice Admin : http://localhost/admin"
echo " - Frontend React   : http://localhost:5001"
echo " - API Doc Swagger  : http://localhost/api/documentation"
echo " - Grafana          : http://localhost:3000"
echo " - API IA (FastAPI) : http://localhost:4000/docs"
echo " - Ollama HC        : http://localhost:11434"
echo ""
echo "Identifiants Grafana : admin / admin"
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