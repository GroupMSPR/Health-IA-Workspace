@echo off
setlocal enabledelayedexpansion

REM ========================================================
REM   restore.bat - Restauration PostgreSQL | HealthAI Coach
REM   Usage : restore.bat                  (menu interactif)
REM           restore.bat --latest         (dernier backup auto)
REM           restore.bat mon_fichier.sql  (fichier precis)
REM ========================================================

if "%DB_PASSWORD%"=="" set "DB_PASSWORD=password"
set "DB_USER=sail"
set "DB_NAME=laravel"
set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "BACKUP_DIR=%SCRIPT_DIR%\backups"

echo ========================================================
echo       Restauration PostgreSQL - HealthAI Coach
echo ========================================================

REM --- Conteneur PostgreSQL ---------------------------------------------------
set "CONTAINER="
for /f "delims=" %%C in ('docker ps --format "{{.Names}}" 2^>nul ^| findstr "healthai_pgsql"') do (
    if not defined CONTAINER set "CONTAINER=%%C"
)
if not defined CONTAINER (
    echo [X] Aucun conteneur healthai_pgsql trouve.
    echo     Lancez d'abord le projet avec : start.bat
    endlocal
    exit /b 1
)

set "RESTORE_FILE="

if /i "%~1"=="--latest" (
    for /f "delims=" %%F in ('dir /b /o-d "%BACKUP_DIR%\healthai_backup_*.sql" 2^>nul') do (
        if not defined RESTORE_FILE set "RESTORE_FILE=%BACKUP_DIR%\%%F"
    )
    if not defined RESTORE_FILE (
        echo [X] Aucune sauvegarde trouvee dans %BACKUP_DIR%
        endlocal
        exit /b 1
    )
    echo [-^>] Restauration automatique depuis : !RESTORE_FILE!

) else if not "%~1"=="" (
    if exist "%~1" (
        set "RESTORE_FILE=%~1"
    ) else if exist "%BACKUP_DIR%\%~1" (
        set "RESTORE_FILE=%BACKUP_DIR%\%~1"
    ) else (
        echo [X] Fichier introuvable : %~1
        endlocal
        exit /b 1
    )

) else (
    REM --- Menu interactif ----------------------------------------------------
    set "COUNT=0"
    for /f "delims=" %%F in ('dir /b /o-d "%BACKUP_DIR%\healthai_backup_*.sql" 2^>nul') do (
        set /a COUNT+=1
        set "BK[!COUNT!]=%BACKUP_DIR%\%%F"
        set "BKNAME[!COUNT!]=%%F"
    )
    if "!COUNT!"=="0" (
        echo [X] Aucun fichier de sauvegarde trouve dans %BACKUP_DIR%
        echo     Creez d'abord une sauvegarde avec : backup.bat
        endlocal
        exit /b 1
    )

    echo.
    echo Sauvegardes disponibles :
    echo.
    for /l %%I in (1,1,!COUNT!) do (
        echo   [%%I] !BKNAME[%%I]!
    )
    echo.
    set /p "CHOICE=Choisissez le numero de la sauvegarde [1] : "
    if "!CHOICE!"=="" set "CHOICE=1"

    REM Validation numerique
    set "VALID=1"
    for /f "delims=0123456789" %%X in ("!CHOICE!") do set "VALID=0"
    if "!VALID!"=="0" (
        echo [X] Choix invalide.
        endlocal
        exit /b 1
    )
    if !CHOICE! lss 1 (
        echo [X] Choix invalide.
        endlocal
        exit /b 1
    )
    if !CHOICE! gtr !COUNT! (
        echo [X] Choix invalide.
        endlocal
        exit /b 1
    )

    for %%N in (!CHOICE!) do set "RESTORE_FILE=!BK[%%N]!"
)

echo.
echo  ATTENTION : La base '%DB_NAME%' va etre ecrasee par :
echo    !RESTORE_FILE!
echo.
set /p "CONFIRM=Confirmer ? [o/N] : "
if /i not "!CONFIRM!"=="o" (
    echo Restauration annulee.
    endlocal
    exit /b 0
)

echo [-^>] Restauration en cours...

docker exec -i "%CONTAINER%" sh -c "PGPASSWORD=%DB_PASSWORD% psql -U %DB_USER% -d %DB_NAME% -v ON_ERROR_STOP=1" < "!RESTORE_FILE!" >nul 2>&1
if errorlevel 1 (
    echo [X] Echec de la restauration. Verifiez les logs.
    endlocal
    exit /b 1
)

echo [OK] Restauration reussie.
echo.
endlocal
exit /b 0
