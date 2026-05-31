@echo off
setlocal enabledelayedexpansion

echo ========================================================
echo      Demarrage du projet HealthAI Coach (MSPR)
echo ========================================================

set WWWUSER=1000
set WWWGROUP=1000
set DB_PASSWORD=password
set AUTO_MODE=0
set FRESH_MODE=0
set ERROR_MESSAGE=

cd /d "%~dp0"

for %%A in (%*) do (
	if "%%A"=="--auto" set AUTO_MODE=1
	if "%%A"=="--fresh" set FRESH_MODE=1
)

echo ========================================================
echo [BOOTSTRAP] Verification et recuperation des sous-projets
echo ========================================================

echo [1/10] Clonage API IA (FastAPI)
if exist "API-Ollama\" (
    echo [OK] Dossier API-Ollama deja present.
) else (
    echo [CLONAGE] Recuperation de API-Ollama...
    git clone https://github.com/GroupMSPR/Health-IA-FastAPI.git API-Ollama
)

echo [2/10] Clonage ETL
if exist "ETL\" (
    echo [OK] Dossier ETL deja present.
) else (
    echo [CLONAGE] Recuperation de l'ETL...
    git clone https://github.com/GroupMSPR/Health-IA-ETL.git ETL
)

echo [3/10] Clonage Grafana
if exist "Grafana\" (
    echo [OK] Dossier Grafana deja present.
) else (
    echo [CLONAGE] Recuperation de Grafana...
    git clone https://github.com/GroupMSPR/Health-IA-Grafana.git Grafana
)

echo [4/10] Clonage Backend (Laravel)
if exist "Backend\" (
    echo [OK] Dossier Backend deja present.
) else (
    echo [CLONAGE] Recuperation du Backend Laravel...
    git clone https://github.com/GroupMSPR/Health-IA-Backend.git Backend
)

echo [5/10] Clonage Frontend (React SPA)
if exist "Frontend\" (
    echo [OK] Dossier Frontend deja present.
) else (
    echo [CLONAGE] Recuperation du Frontend React...
    git clone https://github.com/GroupMSPR/Health-IA-Frontend.git Frontend
)
echo.

echo [PRECHECKS] Verification de l'environnement...
docker --version >nul 2>&1
if errorlevel 1 (
	set ERROR_MESSAGE=Docker n'est pas installe ou non accessible. Installez Docker Desktop.
	goto error_handler
)

docker compose version >nul 2>&1
if errorlevel 1 (
	set ERROR_MESSAGE=docker compose n'est pas disponible. Installez une version recente de Docker Desktop.
	goto error_handler
)

docker info >nul 2>&1
if errorlevel 1 (
	set ERROR_MESSAGE=Le daemon Docker ne repond pas. Demarrez Docker Desktop.
	goto error_handler
)
echo [OK] Docker et docker compose detectes.
echo.

echo [6/10] Lancement de l'API Laravel et de PostgreSQL...
pushd "Backend"

if exist ".env" goto skip_laravel_env
echo [INIT] Creation automatique du fichier .env Laravel...
copy .env.example .env >nul
echo [INIT] Decommentation automatique des variables de base de donnees...
powershell -Command "(Get-Content .env) -replace '^# DB_', 'DB_' -replace '^# FORWARD_DB_PORT', 'FORWARD_DB_PORT' | Set-Content .env"
:skip_laravel_env

if exist "vendor\autoload.php" goto skip_composer
echo [INIT] Telechargement des dependances PHP (Composer)...
echo Cela peut prendre quelques minutes la premiere fois.
docker run --rm -v "%cd%:/app" composer install --ignore-platform-reqs
:skip_composer

docker compose up -d --wait
if errorlevel 1 (
	set ERROR_MESSAGE=Lancement du conteneur Laravel/PostgreSQL a echoue.
	popd
	goto error_handler
)
echo [OK] Conteneurs demarres et healthchecks passes.
echo.
echo Attente du demarrage complet de PostgreSQL...
set RETRY_COUNT=0
set MAX_RETRIES=30
:wait_postgres
set /a RETRY_COUNT+=1
docker compose exec -T healthai_pgsql pg_isready -U sail >nul 2>&1
if errorlevel 1 (
	if !RETRY_COUNT! geq !MAX_RETRIES! (
		set ERROR_MESSAGE=PostgreSQL n'a pas demarre apres 30 tentatives.
		popd
		goto error_handler
	)
	timeout /t 4 /nobreak >nul
	goto wait_postgres
)
echo [OK] PostgreSQL est pret.

echo.
echo Verification que Laravel repond...
set RETRY_COUNT=0
set MAX_RETRIES=15
:wait_laravel
set /a RETRY_COUNT+=1
docker compose exec -T healthai_laravel php -r "echo 'ok';" >nul 2>&1
if errorlevel 1 (
	if !RETRY_COUNT! geq !MAX_RETRIES! (
		set ERROR_MESSAGE=Le conteneur Laravel n'a pas demarre apres 15 tentatives.
		popd
		goto error_handler
	)
	timeout /t 4 /nobreak >nul
	goto wait_laravel
)
echo [OK] Laravel est pret.

echo.
echo Verification des identifiants PostgreSQL Sail...
docker compose exec -T healthai_pgsql sh -lc "PGPASSWORD=%DB_PASSWORD% psql -U sail -d laravel -tAc 'select 1' > /dev/null 2>&1"
if not errorlevel 1 goto migrate_db

echo Le cluster PostgreSQL a ete initialise avec d'anciens identifiants.
echo Reparation du role sail et de la base laravel...
docker compose exec -T healthai_pgsql sh -lc "PGPASSWORD=%DB_PASSWORD% psql -U postgres -d postgres -f -" < docker\repair-postgres.sql
if errorlevel 1 (
	set ERROR_MESSAGE=Reparation du cluster PostgreSQL a echoue.
	popd
	goto error_handler
)
echo [OK] Cluster PostgreSQL repare.
:migrate_db

echo.
echo Migration de la base de donnees (creation des tables)...

if !FRESH_MODE! equ 1 (
	echo [FRESH] Reset complet de la base de donnees...
	docker compose exec -T healthai_laravel php artisan migrate:fresh --force --seed
	if errorlevel 1 (
		set ERROR_MESSAGE=migrate:fresh --seed a echoue.
		popd
		goto error_handler
	)
	echo [OK] Base de donnees recree et ensemencee.
	goto after_seed
)

docker compose exec -T healthai_laravel php artisan migrate --force
if errorlevel 1 (
	set ERROR_MESSAGE=Les migrations Laravel ont echoue.
	popd
	goto error_handler
)
docker compose exec -T healthai_laravel php artisan db:seed --force >nul 2>&1
echo [OK] Migrations et verifications terminees.
:after_seed

echo.
echo Generation Key / Optimisation du cache Laravel...
for /f "tokens=*" %%a in ('findstr "^APP_KEY=" .env') do set CURRENT_APP_KEY=%%a
if "!CURRENT_APP_KEY!"=="APP_KEY=" (
    echo [INIT] Generation de la cle Laravel manquante...
    docker compose exec -T healthai_laravel php artisan key:generate >nul 2>&1
)
docker compose exec -T healthai_laravel php artisan optimize >nul 2>&1
docker compose exec -T healthai_laravel php artisan filament:optimize >nul 2>&1
echo [OK] Cache Laravel et Filament optimises.
popd

echo.
echo [7/10] Lancement du Frontend (React SPA)...
pushd "Frontend"
if exist ".env" goto skip_frontend_env
if exist ".env.example" (
    echo [INIT] Creation automatique du fichier .env Frontend...
    copy .env.example .env >nul
)
:skip_frontend_env
docker compose up -d --build
if errorlevel 1 (
	set ERROR_MESSAGE=Lancement du conteneur Frontend React a echoue.
	popd
	goto error_handler
)
echo [OK] Frontend React lance avec succes.
popd

echo.
echo [8/10] Lancement de l'ETL (Python) et de Grafana...
pushd "ETL"
if exist ".env" goto skip_etl_env
if exist ".env.example" (
    echo [INIT] Creation automatique du fichier .env ETL...
    copy .env.example .env >nul
)
:skip_etl_env
docker compose up -d --build
if errorlevel 1 (
	set ERROR_MESSAGE=Lancement des conteneurs ETL/Grafana a echoue.
	popd
	goto error_handler
)
echo [OK] ETL et Grafana demarres.
popd

echo.
echo [9/10] Lancement de l'API IA (FastAPI)...
pushd "API-Ollama"
if exist ".env" goto skip_ia_env
if exist ".env.example" (
    echo [INIT] Creation automatique du fichier .env API IA...
    copy .env.example .env >nul
)
:skip_ia_env
docker compose up -d --build
if errorlevel 1 (
	set ERROR_MESSAGE=Lancement du conteneur API IA a echoue.
	popd
	goto error_handler
)
echo [OK] API IA (FastAPI) et Ollama demarree.
popd

echo.
echo ========================================================
echo [10/10] [IA SETUP] Verification du modele LLaVA
echo ========================================================
timeout /t 5 /nobreak >nul
docker exec healthai_ollama ollama list | findstr "llava" >nul 2>&1
if errorlevel 1 (
    echo [INIT] Le modele LLaVA n'est pas installe sur cette machine.
    echo [INIT] Telechargement en cours... 
    echo [ATTENTION] C'est un fichier de ~4.7 Go, patience !
    docker exec healthai_ollama ollama pull llava
    if errorlevel 1 (
        echo [WARN] Le telechargement a echoue. Vous devrez le faire manuellement.
    ) else (
        echo [OK] Modele LLaVA telecharge avec succes !
    )
) else (
    echo [OK] Le modele LLaVA est deja present et operationnel.
)

echo.
echo ========================================================
echo        TOUT EST DEMARRE AVEC SUCCES ! 
echo ========================================================
echo.
echo Maintenez la touche CTRL appuyee et cliquez sur les liens :
echo.
echo - API Laravel      : http://localhost
echo - BackOffice Admin : http://localhost/admin
echo - Frontend React   : http://localhost:5001
echo - API Doc Swagger  : http://localhost/api/documentation
echo - Grafana          : http://localhost:3000
echo - API IA (FastAPI) : http://localhost:4000/docs
echo - Ollama HC        : http://localhost:11434
echo.
echo Identifiants Grafana : admin / admin
echo ========================================================
echo.
echo [INFOS] Mode d'execution : !AUTO_MODE! (0=interactif, 1=automatique)
echo [INFOS] Mode fresh       : !FRESH_MODE! (0=incremental, 1=reset complet)
echo.
if !AUTO_MODE! equ 0 (
	pause
	goto end
)
echo [AUTO MODE] Demarrage automatique termine.
goto end

:error_handler
echo.
echo ========================================================
echo ERREUR : !ERROR_MESSAGE!
echo ========================================================
echo.
echo Appuyez sur Entree pour fermer ce terminal.
pause >nul
goto end_fail

:end
endlocal
exit /b 0

:end_fail
endlocal
exit /b 1