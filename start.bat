@echo off
setlocal enabledelayedexpansion

echo ========================================================
echo      Demarrage du projet HealthAI Coach (MSPR)
echo ========================================================

:: Definition des variables obligatoires pour Laravel Sail
set WWWUSER=1000
set WWWGROUP=1000
set DB_PASSWORD=password
set AUTO_MODE=0
set FRESH_MODE=0
set ERROR_MESSAGE=

:: Se placer dans le repertoire du script (fonctionne meme si lance depuis ailleurs)
cd /d "%~dp0"

:: Verification des arguments
for %%A in (%*) do (
	if "%%A"=="--auto" set AUTO_MODE=1
	if "%%A"=="--fresh" set FRESH_MODE=1
)

echo ========================================================
echo [BOOTSTRAP] Verification et recuperation des sous-projets
echo ========================================================

echo [1/9] Clonage API IA (FastAPI)
if not exist "API-IA\" (
    echo [CLONAGE] Recuperation de API-IA...
    git clone https://github.com/GroupMSPR/Health-IA-FastAPI.git API-IA
) else (
    echo [OK] Dossier API-IA deja present.
)

echo [2/9] Clonage ETL
if not exist "ETL\" (
    echo [CLONAGE] Recuperation de l'ETL...
    git clone https://github.com/GroupMSPR/Health-IA-ETL.git ETL
) else (
    echo [OK] Dossier ETL deja present.
)

echo [3/9] Clonage Grafana
if not exist "Grafana\" (
    echo [CLONAGE] Recuperation de Grafana...
    git clone https://github.com/GroupMSPR/Health-IA-Grafana.git Grafana
) else (
    echo [OK] Dossier Grafana deja present.
)

echo [4/9] Clonage Backend (HealthAI-Coach)
if not exist "HealthAI-Coach\" (
    echo [CLONAGE] Recuperation du Backend Laravel...
    git clone https://github.com/GroupMSPR/Health-IA-Backend.git HealthAI-Coach
) else (
    echo [OK] Dossier HealthAI-Coach deja present.
)
echo.

:: PRECHECKS - Verifier que Docker et docker compose sont disponibles
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

:: Verifier que Docker daemon tourne
docker info >nul 2>&1
if errorlevel 1 (
	set ERROR_MESSAGE=Le daemon Docker ne repond pas. Demarrez Docker Desktop.
	goto error_handler
)
echo [OK] Docker et docker compose detectes.
echo.

echo [5/9] Lancement de l'API Laravel et de PostgreSQL...
pushd "HealthAI-Coach"
if not exist ".env" (
    echo [INIT] Creation automatique du fichier .env Laravel...
    copy .env.example .env >nul

	echo [INIT] Decommentation automatique des variables de base de donnees...
    powershell -Command "(Get-Content .env) -replace '^# DB_', 'DB_' -replace '^# FORWARD_DB_PORT', 'FORWARD_DB_PORT' | Set-Content .env"
)
powershell -Command "(Get-Content .env) -replace '^# DB_', 'DB_' -replace '^# FORWARD_DB_PORT', 'FORWARD_DB_PORT' | Set-Content .env"
echo [INIT] Telechargement des dependances PHP (Composer)...
echo Cela peut prendre quelques minutes la premiere fois.
docker run --rm -v "%cd%:/app" composer install --ignore-platform-reqs
docker compose up -d --force-recreate --wait
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
echo [!RETRY_COUNT!/!MAX_RETRIES!] Verification du statut PostgreSQL...
docker compose exec -T pgsql pg_isready -U sail >nul 2>&1
if errorlevel 1 (
	if !RETRY_COUNT! geq !MAX_RETRIES! (
		set ERROR_MESSAGE=PostgreSQL n'a pas demarre apres 30 tentatives en 2 minutes.
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
echo [!RETRY_COUNT!/!MAX_RETRIES!] Verification du conteneur Laravel...
docker compose exec -T laravel php -r "echo 'ok';" >nul 2>&1
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
docker compose exec -T pgsql sh -lc "PGPASSWORD=%DB_PASSWORD% psql -U sail -d laravel -tAc 'select 1' > /dev/null 2>&1"
if not errorlevel 1 goto migrate_db

echo.
echo Le cluster PostgreSQL a ete initialise avec d'anciens identifiants.
echo Reparation du role sail et de la base laravel...
docker compose exec -T pgsql sh -lc "PGPASSWORD=%DB_PASSWORD% psql -U postgres -d postgres -f -" < docker\repair-postgres.sql
if errorlevel 1 (
	set ERROR_MESSAGE=Reparation du cluster PostgreSQL a echoue.
	popd
	goto error_handler
)
echo [OK] Cluster PostgreSQL repare.

:migrate_db

echo.
echo [6/9] Migration de la base de donnees (creation des tables)...

if !FRESH_MODE! equ 1 (
	echo [FRESH] Reset complet de la base de donnees...
	docker compose exec -T laravel php artisan migrate:fresh --force --seed
	if errorlevel 1 (
		set ERROR_MESSAGE=migrate:fresh --seed a echoue.
		popd
		goto error_handler
	)
	echo [OK] Base de donnees recree et ensemencee.
	goto after_seed
)

echo Lancement des migrations...
docker compose exec -T laravel php artisan migrate --force
if errorlevel 1 (
	set ERROR_MESSAGE=Les migrations Laravel ont echoue.
	popd
	goto error_handler
)
echo [OK] Migrations completees.

echo Lancement du seeding...
docker compose exec -T laravel php artisan db:seed --force
if errorlevel 1 (
	echo [WARN] Le seeding a echoue, souvent a cause de doublons deja presents.
	echo [WARN] Le script continue pour demarrer ETL et Grafana.
	goto after_seed
)
echo [OK] Base de donnees ensemencee.
:after_seed

echo.
echo Correction des permissions storage/cache...
docker compose exec -T laravel chmod -R 777 /var/www/html/storage /var/www/html/bootstrap/cache >nul 2>&1
docker compose exec -T laravel chown -R sail:sail /var/www/html/storage /var/www/html/bootstrap/cache >nul 2>&1
docker compose exec -T laravel chmod -R 777 /var/www/html >nul 2>&1
echo [OK] Permissions corrigees.

echo.
echo Generation Key / Optimisation du cache Laravel (config, routes, vues)...
docker compose exec -T laravel php artisan key:generate >nul 2>&1
docker compose exec -T laravel php artisan optimize >nul 2>&1
if errorlevel 1 (
	echo [WARN] L'optimisation Laravel a echoue, le backend fonctionnera sans cache.
) else (
	echo [OK] Key generee et cache Laravel optimise.
)

echo.
echo Optimisation Filament (composants, icones)...
docker compose exec -T laravel php artisan filament:optimize >nul 2>&1
docker compose exec -T laravel php artisan icons:cache >nul 2>&1
echo [OK] Cache Filament optimise.
popd

echo.
echo [7/9] Lancement de l'ETL (Python) et de Grafana...
pushd "ETL"
if not exist ".env" (
    if exist ".env.example" (
        echo [INIT] Creation automatique du fichier .env ETL...
        copy .env.example .env >nul
    )
)
docker compose up -d --build
if errorlevel 1 (
	set ERROR_MESSAGE=Lancement des conteneurs ETL/Grafana a echoue.
	popd
	goto error_handler
)
echo [OK] ETL et Grafana demarres.
popd

echo.
echo [8/9] Lancement de l'API IA (FastAPI), Models Ollama et des volumes...
pushd "API-IA"
if not exist ".env" (
    if exist ".env.example" (
        echo [INIT] Creation automatique du fichier .env API IA...
        copy .env.example .env >nul
    )
)
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
echo [9/9] [IA SETUP] Verification du modele LLaVA
echo ========================================================
:: On attend 5 secondes pour s'assurer qu'Ollama a bien fini de demarrer en interne
timeout /t 5 /nobreak >nul

docker compose exec -T ollama ollama list | findstr "llava" >nul 2>&1
if errorlevel 1 (
    echo [INIT] Le modele LLaVA n'est pas installe sur cette machine.
    echo [INIT] Telechargement en cours... 
    echo [ATTENTION] C'est un fichier de ~4.7 Go, cela depend de votre connexion internet, patience !
    docker compose exec -T ollama ollama pull llava
    if errorlevel 1 (
        echo [WARN] Le telechargement de LLaVA a echoue. Vous devrez le faire manuellement plus tard.
    ) else (
        echo [OK] Modele LLaVA telecharge et installe avec succes !
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
echo - API Doc Swagger  : http://localhost/api/documentation
echo - Grafana          : http://localhost:3000
echo - API IA (FastAPI) : http://localhost:4000/docs
echo - Ollama HC        : http://localhost:11434
echo.
echo Identifiants Grafana : admin / admin
echo ========================================================
echo.
echo [INFOS] Mode d'execution : !AUTO_MODE! (0=interactif, 1=automatique CI/CD)
echo [INFOS] Mode fresh       : !FRESH_MODE! (0=incremental, 1=reset complet)
echo.
if !AUTO_MODE! equ 0 (
	pause
	goto end
)
echo [AUTO MODE] Demarrage automatique termine. Pas de pause pour CI/CD.
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