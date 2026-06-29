@echo off
setlocal enabledelayedexpansion

REM =============================================================================
REM  HealthAI Coach (MSPR) - Lancement du projet sous Windows (sans WSL)
REM  Equivalent de start.sh
REM =============================================================================

REM --- Variables d'environnement ----------------------------------------------
set "WWWUSER=1000"
set "WWWGROUP=1000"
set "DB_PASSWORD=password"
set "DB_USERNAME=sail"
set "DB_DATABASE=laravel"
set "MONGO_ROOT_USER=root"
set "MONGO_ROOT_PASSWORD=example"
set "BUILDKIT_PROGRESS=plain"
set "DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/1521067317923025046/KlSUxUppbi6AqX_HmZ8GOP5a3pPPIrxZyJqi1HekWWDrXcOA6HTurChC6Uu3mkjetjQX"

set "AUTO_MODE=0"
set "FRESH_MODE=0"

REM --- Init -------------------------------------------------------------------
cd /d "%~dp0"
set "WORKSPACE_DIR=%CD%"
set "LOG_FILE=%WORKSPACE_DIR%\healthai_install.log"
break > "%LOG_FILE%"

REM --- Parsing des arguments --------------------------------------------------
:parse_args
if "%~1"=="" goto end_parse
if /i "%~1"=="--auto"  set "AUTO_MODE=1"
if /i "%~1"=="--fresh" set "FRESH_MODE=1"
shift
goto parse_args
:end_parse

cls
echo ========================================================
echo       Demarrage du projet HealthAI Coach (MSPR)
echo ========================================================
echo.
echo  i  Mode silencieux active. Les logs sont ecrits dans :
echo     -^> %LOG_FILE%
echo.

REM =============================================================================
REM  [0/13] Verification Docker
REM =============================================================================
echo [*] [0/13] Verification de l'environnement Docker
docker --version >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    call :error_handler "Docker n'est pas installe ou non accessible."
    goto :eof
)
docker compose version >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    call :error_handler "docker compose n'est pas disponible."
    goto :eof
)
echo [OK] [0/13] Verification de l'environnement Docker

REM =============================================================================
REM  [1/13] Configuration Discord (alertes monitoring)
REM =============================================================================
echo [*] [1/13] Verification de la configuration Discord (alertes monitoring)
if not exist ".env" (
    if exist ".env.example" copy /Y ".env.example" ".env" >nul
)
if exist ".env" (
    powershell -NoProfile -Command "(Get-Content '.env') -replace '^DISCORD_WEBHOOK_URL=.*', 'DISCORD_WEBHOOK_URL=%DISCORD_WEBHOOK_URL%' | Set-Content '.env'"
)
echo [OK] [1/13] DISCORD_WEBHOOK_URL configuree

REM =============================================================================
REM  [2/13] Clonage des repos
REM =============================================================================
echo [*] [2/13] Clonage des repos
if not exist "API-Ollama" git clone https://github.com/GroupMSPR/Health-IA-FastAPI.git API-Ollama >> "%LOG_FILE%" 2>&1
if not exist "ETL"        git clone https://github.com/GroupMSPR/Health-IA-ETL.git ETL >> "%LOG_FILE%" 2>&1
if not exist "Grafana"    git clone https://github.com/GroupMSPR/Health-IA-Grafana.git Grafana >> "%LOG_FILE%" 2>&1
if not exist "Backend"    git clone https://github.com/GroupMSPR/Health-IA-Backend.git Backend >> "%LOG_FILE%" 2>&1
if not exist "Frontend"   git clone https://github.com/GroupMSPR/Health-IA-Frontend.git Frontend >> "%LOG_FILE%" 2>&1
if not exist "Mobile"     git clone https://github.com/GroupMSPR/Health-IA-Mobile.git Mobile >> "%LOG_FILE%" 2>&1
echo [OK] [2/13] Clonage des repos

REM =============================================================================
REM  [3/13] Preparation Backend Laravel
REM =============================================================================
echo [*] [3/13] Preparation du Backend Laravel (env, composer, permissions)

if not exist "Backend\.env" (
    copy /Y "Backend\.env.example" "Backend\.env" >nul
    powershell -NoProfile -Command "(Get-Content 'Backend\.env') -replace '^# DB_', 'DB_' -replace '^# FORWARD_DB_PORT', 'FORWARD_DB_PORT' | Set-Content 'Backend\.env'"
)

for %%S in (Frontend Mobile API-Ollama ETL) do (
    if not exist "%%S\.env" if exist "%%S\.env.example" copy /Y "%%S\.env.example" "%%S\.env" >nul
)

if not exist "Backend\vendor\autoload.php" (
    docker run --rm -v "%CD%/Backend":/app composer install --ignore-platform-reqs >> "%LOG_FILE%" 2>&1
)

docker run --rm -v "%CD%/Backend":/app alpine sh -c "mkdir -p /app/storage/framework/sessions /app/storage/framework/views /app/storage/framework/cache /app/bootstrap/cache && chmod -R 777 /app/storage /app/bootstrap/cache" >> "%LOG_FILE%" 2>&1

echo [OK] [3/13] Preparation du Backend Laravel

REM =============================================================================
REM  [4/13] Arret des conteneurs existants
REM =============================================================================
echo [*] [4/13] Arret des conteneurs existants
if "%FRESH_MODE%"=="1" (
    docker compose --profile backend --profile ia --profile monitoring down -v --remove-orphans >> "%LOG_FILE%" 2>&1
) else (
    docker compose --profile backend --profile ia --profile monitoring down --remove-orphans >> "%LOG_FILE%" 2>&1
)
echo [OK] [4/13] Arret des conteneurs existants

REM =============================================================================
REM  [5/13] Profil BACKEND (Laravel + PostgreSQL + MailCatcher)
REM =============================================================================
echo [*] [5/13] Lancement Profil BACKEND (Laravel / PostgreSQL / MailCatcher)
docker compose --profile backend up -d >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    call :error_handler "Lancement du profil backend a echoue."
    goto :eof
)

REM Attente PostgreSQL
set "RETRY_COUNT=0"
:wait_pg
docker compose exec -T healthai_pgsql pg_isready -U sail >> "%LOG_FILE%" 2>&1
if not errorlevel 1 goto pg_ready
set /a RETRY_COUNT+=1
if %RETRY_COUNT% geq 30 (
    call :error_handler "PostgreSQL n'a pas demarre apres 30 tentatives."
    goto :eof
)
timeout /t 4 /nobreak >nul
goto wait_pg
:pg_ready

REM Attente Laravel
set "RETRY_COUNT=0"
:wait_laravel
docker compose exec -T healthai_laravel php -r "echo 'ok';" >> "%LOG_FILE%" 2>&1
if not errorlevel 1 goto laravel_ready
set /a RETRY_COUNT+=1
if %RETRY_COUNT% geq 15 (
    call :error_handler "Le conteneur Laravel n'a pas demarre."
    goto :eof
)
timeout /t 4 /nobreak >nul
goto wait_laravel
:laravel_ready

REM Reparation PostgreSQL si necessaire
docker compose exec -T healthai_pgsql sh -lc "PGPASSWORD=%DB_PASSWORD% psql -U sail -d laravel -tAc 'select 1'" >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    docker compose exec -T healthai_pgsql sh -lc "PGPASSWORD=%DB_PASSWORD% psql -U postgres -d postgres -f -" < "Backend\docker\repair-postgres.sql" >> "%LOG_FILE%" 2>&1
    if errorlevel 1 (
        call :error_handler "Reparation du cluster PostgreSQL a echoue."
        goto :eof
    )
)

REM Migrations
if "%FRESH_MODE%"=="1" (
    docker compose exec -T healthai_laravel php artisan migrate:fresh --force --seed >> "%LOG_FILE%" 2>&1
    if errorlevel 1 (
        call :error_handler "migrate:fresh --seed a echoue."
        goto :eof
    )
    if exist "Backend\docker\healthia_dump_pg.sql" (
        docker compose exec -T healthai_pgsql sh -c "PGPASSWORD=%DB_PASSWORD% psql -U sail -d laravel" < "Backend\docker\healthia_dump_pg.sql" >> "%LOG_FILE%" 2>&1
    )
) else (
    docker compose exec -T healthai_laravel php artisan migrate --force >> "%LOG_FILE%" 2>&1
    if errorlevel 1 (
        call :error_handler "Les migrations Laravel ont echoue."
        goto :eof
    )
    docker compose exec -T healthai_laravel php artisan db:seed --force >> "%LOG_FILE%" 2>&1
    if exist "Backend\docker\healthia_dump_pg.sql" (
        docker compose exec -T healthai_pgsql sh -c "PGPASSWORD=%DB_PASSWORD% psql -U sail -d laravel" < "Backend\docker\healthia_dump_pg.sql" >> "%LOG_FILE%" 2>&1
    )
)

findstr /R /C:"^APP_KEY=$" "Backend\.env" >nul 2>&1
if not errorlevel 1 docker compose exec -T healthai_laravel php artisan key:generate >> "%LOG_FILE%" 2>&1
docker compose exec -T healthai_laravel php artisan optimize >> "%LOG_FILE%" 2>&1
docker compose exec -T healthai_laravel php artisan filament:optimize >> "%LOG_FILE%" 2>&1

echo [OK] [5/13] Lancement Profil BACKEND (Laravel / PostgreSQL / MailCatcher)

REM =============================================================================
REM  [6/13] Frontend (pas de profil)
REM =============================================================================
echo [*] [6/13] Lancement Frontend React
docker compose up -d healthai_frontend >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    call :error_handler "Lancement du Frontend React a echoue."
    goto :eof
)
echo [OK] [6/13] Lancement Frontend React

REM =============================================================================
REM  [7/13] Mobile (pas de profil)
REM =============================================================================
echo [*] [7/13] Lancement Mobile React Native
docker compose up -d healthai_mobile >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    call :error_handler "Lancement du Mobile React Native a echoue."
    goto :eof
)
echo [OK] [7/13] Lancement Mobile React Native

REM =============================================================================
REM  [8/13] Profil IA (FastAPI + Ollama + MongoDB)
REM =============================================================================
echo [*] [8/13] Lancement Profil IA (FastAPI / Ollama / MongoDB)
docker compose --profile ia up -d >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    call :error_handler "Lancement du profil IA (FastAPI/Ollama/MongoDB) a echoue."
    goto :eof
)
echo [OK] [8/13] Lancement Profil IA (FastAPI / Ollama / MongoDB)

REM =============================================================================
REM  [9/13] Verification LLaVA
REM =============================================================================
echo [*] [9/13] Verification du modele LLaVA
timeout /t 2 /nobreak >nul
docker exec healthai_ollama ollama list | findstr "llava" >nul 2>&1
if errorlevel 1 (
    echo   -^> Telechargement du modele LLaVA (4.7 Go)... Patientez.
    docker exec healthai_ollama ollama pull llava
    if errorlevel 1 (
        echo   -^> [WARN] Telechargement echoue. Relancez manuellement :
        echo      docker exec healthai_ollama ollama pull llava
    ) else (
        echo   -^> [OK] Modele LLaVA telecharge !
    )
) else (
    echo [OK] [9/13] Verification du modele LLaVA (Deja present)
)

REM =============================================================================
REM  [10/13] Profil MONITORING
REM =============================================================================
echo [*] [10/13] Lancement Profil MONITORING (Grafana / Prometheus / Alertes Discord)
docker compose --profile monitoring up -d >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    call :error_handler "Lancement du profil monitoring a echoue."
    goto :eof
)
echo [OK] [10/13] Lancement Profil MONITORING (10 conteneurs)

REM =============================================================================
REM  [11/13] Sauvegarde automatique (tache planifiee Windows)
REM =============================================================================
echo [*] [11/13] Mise en place de la sauvegarde automatique (schtasks)
if exist "%WORKSPACE_DIR%\backup.bat" (
    schtasks /Query /TN "HealthAI_Coach_Backup" >nul 2>&1
    if errorlevel 1 (
        schtasks /Create /SC DAILY /ST 02:00 /TN "HealthAI_Coach_Backup" /TR "\"%WORKSPACE_DIR%\backup.bat\" --silent" /F >> "%LOG_FILE%" 2>&1
        echo [OK] [11/13] Sauvegarde automatique configuree (tous les jours a 2h00)
    ) else (
        echo [OK] [11/13] Sauvegarde automatique deja configuree
    )
) else (
    echo [OK] [11/13] Sauvegarde automatique ignoree (backup.bat introuvable)
    echo   -^> backup.sh n'est pas executable sous Windows sans WSL.
    echo      Creez un backup.bat pour activer la tache planifiee.
)

REM =============================================================================
REM  [12/13] Verification finale des conteneurs
REM =============================================================================
echo [*] [12/13] Verification finale de tous les conteneurs
timeout /t 5 /nobreak >nul
set "FAILED="
for /f "delims=" %%F in ('docker compose --profile backend --profile ia --profile monitoring ps --filter "status=exited" --format "{{.Name}}" 2^>nul') do set "FAILED=!FAILED! %%F"
if defined FAILED (
    echo.
    echo   -^> [WARN] Conteneurs arretes :!FAILED!
    echo [OK] [12/13] Verification finale (avec avertissements)
) else (
    echo [OK] [12/13] Tous les conteneurs sont actifs
)

REM =============================================================================
REM  [13/13] Demo monitoring
REM =============================================================================
echo.
echo   Conseil demo monitoring :
echo   docker stop healthai_fastapi    -^> alerte Discord en ~15 secondes
echo   docker start healthai_fastapi   -^> resolution Discord en ~15 secondes

REM =============================================================================
REM  Fin
REM =============================================================================
echo.
echo ========================================================
echo         TOUT EST DEMARRE AVEC SUCCES !
echo ========================================================
echo.
echo Profils Docker Compose actifs :
echo   backend    -^> Laravel + PostgreSQL + MailCatcher
echo   ia         -^> FastAPI + Ollama + MongoDB
echo   monitoring -^> ETL + Grafana + Prometheus + Alertmanager
echo              -^> Discord Bridge + Node/cAdvisor/PG/Mongo/Blackbox Exporters
echo   (defaut)   -^> Frontend + Mobile
echo.
echo Liens (Ctrl + clic) :
echo.
echo  - API Laravel         -^> http://localhost
echo  - Back-office Admin   -^> http://localhost/admin
echo  - Frontend React      -^> http://localhost:5001
echo  - Mobile React Native -^> http://localhost:6000
echo  - API Doc Swagger     -^> http://localhost/api/documentation
echo  - Grafana             -^> http://localhost:3000
echo  - API IA (FastAPI)    -^> http://localhost:4000/docs
echo  - Ollama              -^> http://localhost:11434
echo  - Prometheus          -^> http://localhost:9090
echo  - Alertmanager        -^> http://localhost:9093
echo.
echo Identifiants Back-office Admin : admin@healthai-coach.mspr / password123
echo Identifiants Frontend + Mobile : john.doe@example.com / password123
echo Identifiants Grafana           : admin / admin
echo.
echo Commandes utiles :
echo   Arreter tout     : docker compose --profile backend --profile ia --profile monitoring down
echo   Reset complet    : start.bat --fresh
echo   Logs monitoring  : docker compose --profile monitoring logs -f
echo ========================================================
echo.
echo [INFOS] Mode : %AUTO_MODE% (0=interactif, 1=automatique)
echo [INFOS] Fresh : %FRESH_MODE% (0=incremental, 1=reset)
echo.

if "%AUTO_MODE%"=="0" (
    pause
) else (
    echo [AUTO MODE] Demarrage automatique termine.
)

endlocal
exit /b 0

REM =============================================================================
REM  Gestionnaire d'erreur
REM =============================================================================
:error_handler
echo.
echo ========================================================
echo ERREUR : %~1
echo -^> Consultez le fichier %LOG_FILE% pour voir les details.
echo ========================================================
echo.
if "%AUTO_MODE%"=="0" pause
endlocal
exit /b 1
