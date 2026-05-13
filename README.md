# HealthAI Coach - Guide de demarrage complet

Bienvenue dans le projet HealthAI Coach.
Ce README explique comment etre operationnel rapidement sur les 3 briques:

- API Laravel + PostgreSQL
- ETL Python (ingestion des donnees)
- Grafana (visualisation)

Le guide est pense pour Windows + Docker Desktop, en mode simple et reproductible.

## 1) Vue d'ensemble

Le projet est compose de 2 stacks Docker:

- HealthAI-Coach: API Laravel + base PostgreSQL
- ETL: pipeline Python + Grafana

Point d'entree recommande:

- Lancer le script [start.bat](start.bat) a la racine du workspace

Ce script:

1. demarre API + PostgreSQL
2. attend la base
3. repare automatiquement PostgreSQL si ancien cluster detecte
4. lance les migrations + seeders Laravel
5. demarre ETL + Grafana

## 2) Prerequis

- Windows
- Docker Desktop en cours d'execution
- Docker Compose v2 disponible (`docker compose`)

Ports utilises:

- API: 80
- PostgreSQL Docker: 55432
- Grafana: 3000

Note importante:
Le port 55432 est volontaire pour eviter les conflits avec un PostgreSQL local Windows en 5432.

## 3) Demarrage rapide (recommande)

1. Ouvrir le dossier racine du projet
2. Double-cliquer sur [start.bat](start.bat)

Attendre le message de fin puis ouvrir:

- API: http://localhost
- BackOffice: http://localhost/admin
- Swagger: http://localhost/api/documentation
- Grafana: http://localhost:3000

Identifiants Grafana par defaut:

- user: admin
- password: admin

## 4) Configuration de la base PostgreSQL

Configuration cible pour outils externes (DBeaver, PhpStorm):

- Host: localhost
- Port: 55432
- Database: laravel
- Username: sail
- Password: password

Important:

- `pgsql` fonctionne uniquement depuis les conteneurs Docker (pas depuis Windows)
- Si vous utilisiez l'IP WSL avant, vous pouvez maintenant rester sur `localhost:55432`

## 5) Variables d'environnement API

Fichier: [HealthAI-Coach/.env](HealthAI-Coach/.env)

Variables principales:

- DB_HOST=pgsql
- DB_PORT=5432
- DB_DATABASE=laravel
- DB_USERNAME=sail
- DB_PASSWORD=password
- FORWARD_DB_PORT=55432

Pourquoi deux ports differents?

- `DB_PORT=5432` est le port interne entre conteneurs
- `FORWARD_DB_PORT=55432` est le port expose cote Windows

## 6) ETL - ce qu'il faut configurer

L'ETL lit des fichiers depuis Google Drive et charge les donnees dans PostgreSQL.

Fichiers utiles:

- [ETL/.env](ETL/.env)
- [ETL/.env.exemple](ETL/.env.exemple)
- [ETL/main.py](ETL/main.py)
- [ETL/config.py](ETL/config.py)

Variables ETL attendues:

- DATABASE_URL
- GCS_BUCKET
- TO_IMPORT_ID
- ARCHIVE_ID
- ERROR_ID
- LOG_ID
- GOOGLE_TOKEN_PICKLE

Exemple de DATABASE_URL (depuis le conteneur ETL):

`postgresql://sail:password@host.docker.internal:55432/laravel`

Preparation Google Drive:

1. creer les dossiers: ToImport, Archive, Error, Log
2. recuperer les IDs de ces dossiers
3. renseigner les IDs dans [ETL/.env](ETL/.env)
4. configurer les credentials OAuth Google (voir [ETL/README.md](ETL/README.md))

## 7) Demarrage manuel (si besoin)

Depuis la racine:

1. API + DB

`cd HealthAI-Coach`

`docker compose up -d --force-recreate`

2. Migrations Laravel

`docker compose exec -T laravel.test php artisan migrate`

`docker compose exec -T laravel.test php artisan db:seed`

3. ETL + Grafana

`cd ..\ETL`

`docker compose up -d --build`

## 8) Verifications rapides

API + DB:

- [HealthAI-Coach](HealthAI-Coach)
- `docker compose ps`
- `docker compose exec -T laravel.test php artisan migrate:status`

PostgreSQL depuis Windows:

- `Test-NetConnection localhost -Port 55432`

Grafana:

- ouvrir http://localhost:3000

## 9) Resolution des problemes

### A) Je n'arrive pas a me connecter en localhost

Verifier:

1. que vous utilisez `localhost:55432` (pas 5432)
2. que votre datasource IDE est bien mise a jour
3. que Docker est demarre

### B) Ancien cluster PostgreSQL incompatible

Le script [start.bat](start.bat) tente une reparation automatique via:

- [HealthAI-Coach/docker/repair-postgres.sql](HealthAI-Coach/docker/repair-postgres.sql)

Si echec, repartir proprement:

`cd HealthAI-Coach`

`docker compose down -v`

`docker compose up -d --force-recreate`

`docker compose exec -T laravel.test php artisan migrate --seed`

### C) L'ETL ne charge aucun fichier

Verifier:

1. les IDs Google Drive dans [ETL/.env](ETL/.env)
2. le token OAuth Google
3. la variable `DATABASE_URL`
4. les logs ETL dans votre dossier Drive Log

## 10) Arret et redemarrage

Arret:

- `cd HealthAI-Coach && docker compose down`
- `cd ..\ETL && docker compose down`

Redemarrage:

- relancer [start.bat](start.bat)

## 11) Checklist operationnelle

Avant de dire "environnement operationnel":

1. API disponible sur http://localhost
2. Swagger disponible sur http://localhost/api/documentation
3. Connexion PostgreSQL valide en localhost:55432
4. Grafana accessible sur http://localhost:3000
5. `php artisan migrate:status` sans erreur
6. ETL configure avec variables Drive + token OAuth

Si les 6 points sont OK, vous etes operationnel pour l'API, l'ETL et Grafana.
