@echo off
setlocal enabledelayedexpansion

REM ========================================================
REM   backup.bat - Sauvegarde PostgreSQL | HealthAI Coach
REM   Usage : backup.bat
REM           backup.bat --silent   (pas de messages)
REM ========================================================

if "%DB_PASSWORD%"=="" set "DB_PASSWORD=password"
set "DB_USER=sail"
set "DB_NAME=laravel"
set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "BACKUP_DIR=%SCRIPT_DIR%\backups"
set "MAX_BACKUPS=7"
set "SILENT=0"

REM --- Parsing des arguments --------------------------------------------------
for %%A in (%*) do (
    if /i "%%~A"=="--silent" set "SILENT=1"
)

REM --- Timestamp YYYYMMDD_HHMMSS (independant de la locale) --------------------
for /f "usebackq tokens=*" %%T in (`powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"`) do set "TIMESTAMP=%%T"
set "BACKUP_FILE=%BACKUP_DIR%\healthai_backup_%TIMESTAMP%.sql"

REM --- Conteneur PostgreSQL ---------------------------------------------------
set "CONTAINER="
for /f "delims=" %%C in ('docker ps --format "{{.Names}}" 2^>nul ^| findstr "healthai_pgsql"') do (
    if not defined CONTAINER set "CONTAINER=%%C"
)

if not exist "%BACKUP_DIR%" mkdir "%BACKUP_DIR%"

if "%SILENT%"=="0" (
    echo ========================================================
    echo       Sauvegarde PostgreSQL - HealthAI Coach
    echo ========================================================
)

if not defined CONTAINER (
    echo [X] Aucun conteneur healthai_pgsql trouve.
    endlocal
    exit /b 1
)

if "%SILENT%"=="0" echo [-^>] Sauvegarde en cours...

docker exec "%CONTAINER%" sh -c "PGPASSWORD=%DB_PASSWORD% pg_dump -U %DB_USER% -d %DB_NAME% --clean --if-exists --no-owner --no-acl" > "%BACKUP_FILE%" 2>nul
if errorlevel 1 (
    echo [X] Echec de la sauvegarde.
    del /q "%BACKUP_FILE%" >nul 2>&1
    endlocal
    exit /b 1
)

REM --- Verifie que le fichier n'est pas vide ----------------------------------
for %%F in ("%BACKUP_FILE%") do set "FSIZE=%%~zF"
if "%FSIZE%"=="0" (
    echo [X] Echec de la sauvegarde (fichier vide).
    del /q "%BACKUP_FILE%" >nul 2>&1
    endlocal
    exit /b 1
)

echo [OK] Sauvegarde creee : healthai_backup_%TIMESTAMP%.sql
if "%SILENT%"=="0" echo      Dossier : %BACKUP_DIR%

REM --- Rotation : conserve les MAX_BACKUPS plus recents -----------------------
set "INDEX=0"
for /f "delims=" %%B in ('dir /b /o-d "%BACKUP_DIR%\healthai_backup_*.sql" 2^>nul') do (
    set /a INDEX+=1
    if !INDEX! gtr %MAX_BACKUPS% del /q "%BACKUP_DIR%\%%B" >nul 2>&1
)
if %INDEX% gtr %MAX_BACKUPS% (
    if "%SILENT%"=="0" echo [OK] Nettoyage : %MAX_BACKUPS% dernieres sauvegardes conservees.
)

if "%SILENT%"=="0" echo.
endlocal
exit /b 0
