# Documentation du Système de Supervision — HealthAI Coach

> **Livrable MSPR TPRE601** — Documentation exhaustive du système de monitoring  
> Stack : Grafana · Prometheus · PostgreSQL · Discord  
> Dernière mise à jour : 2026-06-29

---

## Table des matières

1. [Vue d'ensemble](#1-vue-densemble)
2. [Sources de données](#2-sources-de-données)
3. [Métriques infrastructure collectées (Prometheus)](#3-métriques-infrastructure-collectées-prometheus)
4. [Métriques applicatives collectées (PostgreSQL)](#4-métriques-applicatives-collectées-postgresql)
5. [Dashboards disponibles](#5-dashboards-disponibles)
6. [Système d'alertes](#6-système-dalertes)
7. [Fréquences de collecte](#7-fréquences-de-collecte)
8. [Captures d'écran](#8-captures-décran)

---

## 1. Vue d'ensemble

Le système de supervision HealthAI Coach repose sur deux couches complémentaires :

| Couche | Outil | Rôle |
|---|---|---|
| **Infrastructure** | Prometheus + exporters | Collecte des métriques système (CPU, RAM, réseau, services HTTP, BDD) |
| **Applicative** | Grafana + PostgreSQL | Analyse des données métier (utilisateurs, exercices, aliments, santé) |
| **Alerting** | Grafana natif → Discord | Notification en temps réel des incidents |

```
┌─────────────────────────────────────────────────────────┐
│                    GRAFANA :3000                        │
│  ┌─────────────────┐    ┌──────────────────────────┐   │
│  │ Dashboard Infra  │    │  5 Dashboards Data       │   │
│  │ (Prometheus)     │    │  (PostgreSQL SQL direct) │   │
│  └────────┬─────────┘    └───────────┬──────────────┘   │
│           │                          │                   │
│  ┌────────▼──────────┐   ┌───────────▼──────────────┐   │
│  │  Prometheus :9090  │   │  PostgreSQL :5432        │   │
│  │  6 exporters       │   │  Base : laravel           │   │
│  └───────────────────┘   └──────────────────────────┘   │
│                                                          │
│  ┌──────────────────────────────────────────────────┐   │
│  │  Alerting natif Grafana → Discord (webhook)       │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

---

## 2. Sources de données

### 2.1 Source PostgreSQL — Données applicatives

| Paramètre | Valeur |
|---|---|
| **UID datasource Grafana** | `fficjnp24r8jka` |
| **Nom** | HealthAI PostgreSQL |
| **Hôte** | `healthai_pgsql:5432` |
| **Base de données** | `laravel` |
| **Utilisateur** | `sail` |
| **Réseau Docker** | `healthai_backend_sail` |
| **Type de requêtes** | SQL brut (`rawSql`) |

**Tables exploitées :**

| Table | Nb entrées (démo) | Colonnes clés |
|---|---|---|
| `users` | 2 | id, first_name, last_name, email, gender, weight, height, bmi, physical_activity_level, daily_caloric_intake, favorite_exercise_category, created_at, deleted_at |
| `exercises` | 250 | id, name, category, sub_category, difficulty_level, estimated_calories_per_minutes, target_muscle, created_at, deleted_at |
| `foods` | 250 | id, name, category, calories, protein, carbohydrates, fat, fiber, created_at, deleted_at |
| `health_metrics` | 30 | id, user_id, date, weight, avg_bpm, max_bpm, resting_bpm, steps_count, sleep_time, calories_burned, active_minute, deleted_at |
| `practice` | 40 | practice_id, user_id, exercise_id, deleted_at |
| `consume` | 30 | consume_id, user_id, food_id, deleted_at |
| `subscriptions` | 2 | id, subscription_type (Free, Premium) |
| `user_subscription` | 2 | user_id, subscription_id, started_at, ended_at |
| `roles` | 3 | id, name (admin, coach, user) |
| `model_has_roles` | 2 | role_id, model_id, model_type |
| `goals` | 8 | id, goal |
| `user_goal` | N | user_id, goal_id |

### 2.2 Source Prometheus — Métriques infrastructure

| Paramètre | Valeur |
|---|---|
| **UID datasource Grafana** | `prometheus-healthai` |
| **Nom** | HealthAI Prometheus |
| **URL** | `http://prometheus:9090` |
| **Réseau Docker** | `healthai_backend_sail` |
| **Type de requêtes** | PromQL |

---

## 3. Métriques infrastructure collectées (Prometheus)

### 3.1 Blackbox Exporter — Sondes HTTP (`blackbox-exporter:9115`)

Vérifie la disponibilité HTTP de chaque service toutes les 15 secondes.

| Métrique | Description | Valeurs |
|---|---|---|
| `probe_success` | Service HTTP accessible | 0 = DOWN, 1 = UP |
| `probe_duration_seconds` | Temps de réponse HTTP | En secondes |
| `probe_http_status_code` | Code HTTP retourné | 200, 403, 500… |

**Services sondés :**

| Service | URL sondée | Via |
|---|---|---|
| Laravel API | `http://healthai_laravel:80/up` | Réseau sail direct |
| FastAPI IA | `http://healthai_fastapi:4000/` | Réseau sail direct |
| Ollama LLM | `http://healthai_ollama:11434/` | Réseau sail direct |
| Frontend React | `http://host.docker.internal:5001/` | Port exposé sur le host |

> **Note Frontend** : Le frontend tourne sur le réseau `frontend_default`, inaccessible depuis le réseau `sail`. La sonde passe par le port exposé sur le host WSL2 (`:5001`), ce qui peut retourner HTTP 403 (restriction Vite dev server) — comportement attendu.

### 3.2 Node Exporter — Système hôte (`node-exporter:9100`)

Collecte les métriques du serveur Linux hôte toutes les 15 secondes.

| Métrique | Description |
|---|---|
| `node_cpu_seconds_total` | Utilisation CPU par mode (user, system, idle…) |
| `node_memory_MemAvailable_bytes` | Mémoire RAM disponible |
| `node_memory_MemTotal_bytes` | Mémoire RAM totale |
| `node_filesystem_avail_bytes` | Espace disque disponible |
| `node_filesystem_size_bytes` | Espace disque total |
| `node_load1` / `node_load5` / `node_load15` | Charge système (1min, 5min, 15min) |
| `node_network_receive_bytes_total` | Octets reçus sur le réseau |
| `node_network_transmit_bytes_total` | Octets émis sur le réseau |

### 3.3 cAdvisor — Ressources Docker (`cadvisor:8080`)

Collecte les métriques des conteneurs Docker toutes les 15 secondes.

| Métrique | Description |
|---|---|
| `container_cpu_usage_seconds_total` | CPU consommé par conteneur |
| `container_memory_usage_bytes` | RAM consommée par conteneur |
| `container_network_receive_bytes_total` | Réseau entrant par conteneur |
| `container_network_transmit_bytes_total` | Réseau sortant par conteneur |

> **Limitation WSL2** : cAdvisor sur WSL2 ne peut pas isoler les métriques par conteneur individuel (cgroup driver limité). Les métriques sont globales (`id="/"`) — comportement normal sur WSL2.

### 3.4 PostgreSQL Exporter — Base de données (`postgres-exporter:9187`)

Collecte les métriques PostgreSQL toutes les 15 secondes.

| Métrique | Description |
|---|---|
| `pg_up` | PostgreSQL accessible | 0 = DOWN, 1 = UP |
| `pg_stat_activity_count` | Connexions actives en cours |
| `pg_stat_database_tup_fetched` | Lignes lues par requête SELECT |
| `pg_stat_database_tup_inserted` | Lignes insérées |
| `pg_stat_database_tup_updated` | Lignes mises à jour |
| `pg_stat_database_tup_deleted` | Lignes supprimées |
| `pg_stat_database_xact_commit` | Transactions validées (commits/s) |
| `pg_stat_database_xact_rollback` | Transactions annulées (rollbacks/s) |
| `pg_database_size_bytes` | Taille de la base de données |

### 3.5 MongoDB Exporter — Base NoSQL (`mongodb-exporter:9216`)

Collecte les métriques MongoDB toutes les 15 secondes.

| Métrique | Description |
|---|---|
| `mongodb_up` | MongoDB accessible | 0 = DOWN, 1 = UP |
| `mongodb_connections_current` | Connexions actives |
| `mongodb_connections_available` | Connexions disponibles |
| `mongodb_op_counters_total` | Opérations CRUD par seconde |
| `mongodb_memory_resident` | Mémoire résidente MongoDB |

### 3.6 Prometheus lui-même (`prometheus:9090`)

| Métrique | Description |
|---|---|
| `up` | État de chaque target scrapée (1=OK, 0=KO) |
| `scrape_duration_seconds` | Temps de collecte par target |
| `prometheus_tsdb_head_samples_appended_total` | Métriques ingérées |

---

## 4. Métriques applicatives collectées (PostgreSQL)

### 4.1 Métriques Utilisateurs

Requêtes SQL exécutées par le dashboard **Dashboard – Utilisateurs** :

| Panneau | Requête SQL | Description |
|---|---|---|
| Total inscrits | `SELECT COUNT(*) FROM users WHERE deleted_at IS NULL` | Comptes actifs |
| Comptes supprimés | `SELECT COUNT(*) FROM users WHERE deleted_at IS NOT NULL` | Soft delete |
| Rôles | `COUNT(DISTINCT id) FROM roles` | admin, coach, user |
| Inscriptions/jour | `date_trunc('day', created_at), COUNT(*)` | Évolution temporelle |
| Répartition rôle | `JOIN model_has_roles, roles GROUP BY r.name` | Distribution admin/coach |
| Actifs vs inactifs | `CASE WHEN deleted_at IS NULL THEN 'Actifs'` | Pie chart statut |
| Derniers inscrits | `ORDER BY created_at DESC LIMIT 20` | Table avec rôle et statut |

### 4.2 Métriques Aliments (Foods)

Requêtes SQL exécutées par le dashboard **Dashboard – Foods** :

| Panneau | Requête SQL | Description |
|---|---|---|
| Total aliments | `COUNT(*) FROM foods WHERE deleted_at IS NULL` | 250 aliments |
| Scans IA (proxy) | `COUNT(*) FROM consume WHERE deleted_at IS NULL` | Consommations enregistrées |
| Catégories | `COUNT(DISTINCT category) FROM foods` | 6 catégories |
| Calories moyennes | `AVG(calories) FROM foods` | Kcal/aliment |
| Top 10 consommés | `JOIN consume ON food_id GROUP BY name ORDER BY COUNT DESC` | Classement |
| Par catégorie | `category, COUNT(*) GROUP BY category` | Vegetables, Fruits… |
| Macros moyens | `AVG(protein), AVG(carbohydrates), AVG(fat), AVG(fiber)` | g/aliment |
| Macros/catégorie | `GROUP BY category AVG(protein/carbs/fat)` | Comparaison |
| Ajoutés/jour | `date_trunc('day', created_at), COUNT(*)` | Évolution 2021–2026 |

**Données de référence :**

| Catégorie | Nb aliments | Protéines moy. | Glucides moy. | Lipides moy. |
|---|---|---|---|---|
| Vegetables | 50 | ~2.5g | ~8g | ~0.3g |
| Fruits | 45 | ~0.9g | ~14g | ~0.2g |
| Meat & Fish | 45 | ~22g | ~1g | ~10g |
| Grains | 40 | ~8g | ~45g | ~2g |
| Dairy | 35 | ~6g | ~6g | ~8g |
| Snacks | 35 | ~5g | ~30g | ~15g |

### 4.3 Métriques Exercices

Requêtes SQL exécutées par le dashboard **Dashboard – Exercices** :

| Panneau | Requête SQL | Description |
|---|---|---|
| Total exercices | `COUNT(*) FROM exercises WHERE deleted_at IS NULL` | 250 exercices |
| Séances pratiquées | `COUNT(*) FROM practice WHERE deleted_at IS NULL` | 40 séances |
| Top 10 pratiqués | `JOIN practice GROUP BY e.name ORDER BY COUNT DESC` | Classement |
| Par catégorie | `category, COUNT(*) GROUP BY category` | Distribution |
| Par difficulté | `difficulty_level, COUNT(*) GROUP BY difficulty_level` | Beginner/Inter/Advanced |
| Pratiques/catégorie | `JOIN exercises GROUP BY e.category` | Séances par type |
| Cal/min/catégorie | `AVG(estimated_calories_per_minutes) GROUP BY category` | Intensité |
| Ajoutés/jour | `date_trunc('day', created_at), COUNT(*)` | Évolution 2021–2026 |

**Données de référence :**

| Catégorie | Nb exercices | Pratiques | Cal/min moy. |
|---|---|---|---|
| Strength | 145 | 23 | ~8 |
| Cardio | 30 | 1 | ~10 |
| Flexibility | 25 | 7 | ~4 |
| HIIT | 20 | 5 | ~12 |
| Rehabilitation | 15 | 2 | ~3 |
| Balance | 15 | 2 | ~4 |

| Difficulté | Nb exercices |
|---|---|
| Beginner | 109 |
| Intermediate | 100 |
| Advanced | 41 |

### 4.4 Métriques Santé (Health Metrics)

Requêtes SQL exécutées par le dashboard **Dashboard – Health metrics** :

| Panneau | Requête SQL | Description |
|---|---|---|
| Total métriques | `COUNT(*) FROM health_metrics WHERE deleted_at IS NULL` | 30 entrées |
| Poids moyen | `AVG(weight) FROM health_metrics` | En kg |
| IMC moyen | `AVG(bmi) FROM users` | Index masse corporelle |
| Jours de données | `COUNT(DISTINCT date) FROM health_metrics` | Jours uniques |
| Distribution IMC | `CASE WHEN bmi < 18.5 … GROUP BY tranche` | Catégories OMS |
| Activité physique | `physical_activity_level, COUNT(*) GROUP BY` | Sédentaire/Modéré/Actif |
| Évolution poids | `date AS time, AVG(weight) GROUP BY date` | Time series |
| Métriques/jour | `date AS time, COUNT(*) GROUP BY date` | Fréquence de saisie |
| Calories brûlées | `date AS time, AVG(calories_burned) GROUP BY date` | Time series kcal |
| BPM moyen/repos/max | `AVG(avg_bpm), AVG(resting_bpm), AVG(max_bpm)` | Fréquence cardiaque |

**Données de référence :**

| Métrique | Valeur moyenne (démo) |
|---|---|
| Calories brûlées | 2 418 kcal/jour |
| Pas quotidiens | 8 441 pas |
| BPM moyen | 72.4 bpm |
| BPM repos | ~58 bpm |
| Poids (health_metrics) | 90.1 kg |
| Minutes actives | ~45 min/jour |

> **Note** : Les données de démo ont été générées pour les besoins du projet. Le poids moyen dans `users` (171 kg) est une anomalie des données de seed — les métriques dans `health_metrics` sont plus réalistes.

---

## 5. Dashboards disponibles

### 5.1 Liste complète

| Dashboard | UID Grafana | Dossier | Source | Plage défaut |
|---|---|---|---|---|
| HealthAI Coach – Monitoring | `healthai-monitoring-main` | HealthAI Monitoring | Prometheus | 1 heure |
| Dashboard – Utilisateurs | `adszhtx` | HealthAI Data | PostgreSQL | 1 an |
| Dashboard – Foods | `adx4wcl` | HealthAI Data | PostgreSQL | 5 ans |
| Dashboard – Exercices | `advpcp7` | HealthAI Data | PostgreSQL | 5 ans |
| Dashboard – Health metrics | `ad8srgr` | HealthAI Data | PostgreSQL | 1 an |
| HealthAI Coach – Application | `healthai-app-dashboard` | HealthAI Data | PostgreSQL | 30 jours |

### 5.2 Dashboard Monitoring Infra

**Fichier** : `Grafana/monitoring-dashboards/healthai_monitoring.json`

| Section | Panneaux | Métriques utilisées |
|---|---|---|
| État des services | Laravel, FastAPI, Ollama, PostgreSQL, MongoDB, Frontend (stat UP/DOWN) | `probe_success`, `pg_up`, `mongodb_up` |
| Ressources système | CPU %, RAM %, Réseau (gauge/time series) | `node_cpu_seconds_total`, `node_memory_*` |
| Bases de données | PgSQL connexions, commits/rollbacks, MongoDB connexions/ops | `pg_stat_activity_count`, `pg_stat_database_*`, `mongodb_*` |
| Système hôte | CPU jauge, RAM jauge, Disque jauge, historiques | `node_filesystem_*`, `node_load*` |

### 5.3 Dashboard – Utilisateurs

**Fichier** : `Grafana/data-dashboards/usersGrafana.json`  
**Panneaux** : 8 panneaux

| Panneau | Type | Ce qu'il affiche |
|---|---|---|
| Total utilisateurs inscrits | Stat (bleu) | Nombre total de comptes actifs |
| Utilisateurs actifs | Stat (vert) | Comptes non supprimés |
| Comptes supprimés | Stat (rouge) | Soft delete |
| Rôles disponibles | Stat (violet) | 3 rôles (admin, coach, user) |
| Nouvelles inscriptions par jour | Time series (barres) | Évolution des inscriptions sur 1 an |
| Répartition par rôle | Donut | admin / coach / Sans rôle |
| Actifs vs inactifs | Pie chart | Actifs (vert) vs Supprimés (rouge) |
| Derniers inscrits | Table | Nom, Email, Rôle, Genre, Activité, Statut coloré |

> 📸 *[Capture d'écran à insérer ici]*

### 5.4 Dashboard – Foods

**Fichier** : `Grafana/data-dashboards/foodsGrafana.json`  
**Panneaux** : 9 panneaux

| Panneau | Type | Ce qu'il affiche |
|---|---|---|
| Total aliments en base | Stat (vert) | 250 aliments référencés |
| Consommations / scans IA | Stat (orange) | 30 consommations (proxy LLaVA) |
| Catégories d'aliments | Stat (bleu) | 6 catégories distinctes |
| Calories moyennes / aliment | Stat (rouge) | Kcal moyen |
| Top 10 aliments consommés | Barres horizontales | Classement des aliments les plus mangés |
| Répartition par catégorie | Donut | Vegetables, Fruits, Meat & Fish… |
| Macronutriments moyens | Pie chart | Protéines / Glucides / Lipides / Fibres |
| Macros par catégorie | Barres groupées | Comparaison protéines/glucides/lipides par catégorie |
| Aliments ajoutés par jour | Time series (barres) | Historique 2021–2026 |

> 📸 *[Capture d'écran à insérer ici]*

### 5.5 Dashboard – Exercices

**Fichier** : `Grafana/data-dashboards/exercisesGrafana.json`  
**Panneaux** : 10 panneaux

| Panneau | Type | Ce qu'il affiche |
|---|---|---|
| Total exercices en base | Stat (orange) | 250 exercices disponibles |
| Séances pratiquées | Stat (bleu) | 40 séances enregistrées |
| Recommandations IA (Random Forest) | Stat (violet) | Exercices recommandés par le modèle ML |
| Catégories d'exercices | Stat (vert) | 6 catégories |
| Top 10 exercices pratiqués | Barres horizontales | Classement par nb de séances |
| Répartition par catégorie musculaire | Donut | Strength, Cardio, Flexibility… |
| Exercices par niveau de difficulté | Barres | Beginner (109) / Intermediate (100) / Advanced (41) |
| Pratiques par catégorie | Barres horizontales | Séances réalisées par type |
| Détail catégorie × difficulté + Cal/min | Table | Vue croisée avec colorisation |
| Exercices ajoutés par jour | Time series (barres) | Historique 2021–2026 |

> 📸 *[Capture d'écran à insérer ici]*

### 5.6 Dashboard – Health Metrics

**Fichier** : `Grafana/data-dashboards/healthMetricsGrafana.json`  
**Panneaux** : 10 panneaux

| Panneau | Type | Ce qu'il affiche |
|---|---|---|
| Métriques enregistrées (total) | Stat (bleu) | 30 entrées en base |
| Poids moyen (kg) | Stat (orange) | Depuis `health_metrics.weight` |
| IMC moyen (BMI) | Stat (violet, seuils colorés) | Catégorisé OMS (Normal/Surpoids/Obésité) |
| Jours de données | Stat (vert) | Jours uniques dans `health_metrics` |
| Distribution IMC | Barres (catégories OMS) | < 18.5 / 18.5–25 / 25–30 / 30–35 / > 35 |
| Répartition activité physique | Pie chart | Sédentaire / Modéré / Actif |
| Évolution du poids dans le temps | Time series | Suivi poids jan.–avr. 2026 |
| Métriques enregistrées par jour | Time series (barres) | Fréquence de saisie |
| Calories brûlées par jour | Time series | Évolution kcal |
| Fréquence cardiaque (BPM) | Time series | BPM moyen / BPM repos / BPM max |

> 📸 *[Capture d'écran à insérer ici]*

---

## 6. Système d'alertes

### 6.1 Architecture d'alerting

```
Prometheus scrape métriques (toutes les 15s)
        ↓
Grafana évalue les règles d'alerte (toutes les 30–60s)
        ↓
Condition remplie → alerte FIRING
        ↓
Grafana envoie webhook Discord natif
        ↓
💬 Canal Discord #alertes — message embed avec statut + sévérité
```

**Configuration Grafana** : `alertingSimplifiedRouting=true` — chaque règle définit son contact point directement via `notification_settings`.

### 6.2 Contact point Discord

| Paramètre | Valeur |
|---|---|
| Nom | Discord HealthAI |
| Type | Discord (intégration native Grafana) |
| UID | `discord-healthai-receiver` |
| Message | Embed formaté : alertname, summary, description, statut, sévérité |
| Résolution | Activée (`disableResolveMessage: false`) |

### 6.3 Les 7 règles d'alerte

**Groupe : HealthAI – Services HTTP** (évaluation toutes les 30s)

| Règle | UID | Condition | Délai | Sévérité | Répétition |
|---|---|---|---|---|---|
| Service DOWN | `healthai-service-down` | `probe_success < 1` | for=0s | critical | 1h |
| Service LENT | `healthai-service-slow` | `probe_duration > 2s` | for=2min | warning | 4h |

**Groupe : HealthAI – Bases de données** (évaluation toutes les 30s)

| Règle | UID | Condition | Délai | Sévérité | Répétition |
|---|---|---|---|---|---|
| PostgreSQL DOWN | `healthai-pgsql-down` | `pg_up = 0` | for=30s | critical | 1h |
| MongoDB DOWN | `healthai-mongodb-down` | `mongodb_up = 0` | for=30s | critical | 1h |
| PostgreSQL connexions | `healthai-pgsql-connections` | `pg_stat_activity_count > 80` | for=5min | warning | 4h |

**Groupe : HealthAI – Système hôte** (évaluation toutes les 60s)

| Règle | UID | Condition | Délai | Sévérité | Répétition |
|---|---|---|---|---|---|
| RAM hôte > 90% | `healthai-host-memory` | `node_memory_available < 10%` | for=5min | critical | 1h |
| Disque hôte > 85% | `healthai-host-disk` | `node_filesystem_avail < 15%` | for=5min | warning | 4h |

### 6.4 Exemple de notification Discord

```
🔴 PostgreSQL inaccessible
─────────────────────────
L'exporter PostgreSQL ne peut plus joindre la base de données.
Status: Firing | Sévérité: critical
[FIRING:1] PostgreSQL inaccessible HealthAI Monitoring
Grafana v13.0.2

→ Résolution (8 min plus tard) :

✅ PostgreSQL inaccessible
Status: Resolved | Sévérité: critical
[RESOLVED] PostgreSQL inaccessible HealthAI Monitoring
```

---

## 7. Fréquences de collecte

| Source | Intervalle | Configurable dans |
|---|---|---|
| Prometheus scrape général | 15s | `Monitoring/prometheus/prometheus.yml` → `scrape_interval` |
| Blackbox (sondes HTTP) | 15s | `Monitoring/prometheus/prometheus.yml` → job `blackbox_http` |
| Node Exporter | 15s | Hérité du `scrape_interval` global |
| cAdvisor | 15s | Hérité du `scrape_interval` global |
| PostgreSQL Exporter | 15s | Hérité du `scrape_interval` global |
| MongoDB Exporter | 15s | Hérité du `scrape_interval` global |
| Évaluation alertes Grafana (HTTP) | 30s | `Grafana/provisioning/alerting/rules.yml` → `interval` |
| Évaluation alertes Grafana (Hôte) | 60s | `Grafana/provisioning/alerting/rules.yml` → `interval` |
| Rechargement dashboards data | 3600s | `Grafana/provisioning/dashboards/dashboards.yml` → `updateIntervalSeconds` |
| Rechargement dashboard monitoring | 30s | `Grafana/provisioning/dashboards/dashboards.yml` → `updateIntervalSeconds` |
| Rafraîchissement UI Grafana (min) | 5s | `GF_DASHBOARDS_MIN_REFRESH_INTERVAL=5s` |
| Rétention données Prometheus | 30 jours | `Monitoring/docker-compose.yml` → `--storage.tsdb.retention.time=30d` |

---

## 8. Captures d'écran

> **Instructions** : Prendre les captures depuis `http://localhost:3000` avec la stack démarrée.

### 8.1 Dashboard Monitoring Infra
> 📸 *Insérer capture — aller sur Grafana → dossier "HealthAI Monitoring" → "HealthAI Coach – Monitoring"*

![Dashboard Monitoring](./screenshots/dashboard-monitoring.png)

### 8.2 Dashboard Utilisateurs
> 📸 *Insérer capture — aller sur Grafana → dossier "HealthAI Data" → "Dashboard – Utilisateurs"*  
> ⚠️ Sélectionner la plage **Last 1 year** pour voir les données

![Dashboard Utilisateurs](./screenshots/dashboard-users.png)

### 8.3 Dashboard Foods
> 📸 *Insérer capture — aller sur Grafana → dossier "HealthAI Data" → "Dashboard – Foods"*  
> ⚠️ Sélectionner la plage **Last 5 years** pour voir les time series

![Dashboard Foods](./screenshots/dashboard-foods.png)

### 8.4 Dashboard Exercices
> 📸 *Insérer capture — aller sur Grafana → dossier "HealthAI Data" → "Dashboard – Exercices"*  
> ⚠️ Sélectionner la plage **Last 5 years** pour voir les time series

![Dashboard Exercices](./screenshots/dashboard-exercises.png)

### 8.5 Dashboard Health Metrics
> 📸 *Insérer capture — aller sur Grafana → dossier "HealthAI Data" → "Dashboard – Health metrics"*  
> ⚠️ Sélectionner la plage **Last 1 year** (données : janv.–avr. 2026)

![Dashboard Health Metrics](./screenshots/dashboard-health.png)

### 8.6 Alerte Discord en action
> 📸 *Insérer capture Discord montrant un message FIRING + RESOLVED*

![Alertes Discord](./screenshots/discord-alerts.png)

---

## Fichiers de configuration associés

| Fichier | Rôle |
|---|---|
| `ETL/docker-compose.yml` | Définition du service Grafana + volumes provisioning |
| `Monitoring/docker-compose.yml` | Stack Prometheus + 5 exporters |
| `Monitoring/prometheus/prometheus.yml` | Configuration scrape Prometheus |
| `Grafana/provisioning/datasources/prometheus.yml` | Datasource Prometheus (auto-chargée) |
| `Grafana/provisioning/datasources/postgresql.yml` | Datasource PostgreSQL (auto-chargée) |
| `Grafana/provisioning/dashboards/dashboards.yml` | Providers de dashboards (2 dossiers) |
| `Grafana/provisioning/alerting/rules.yml` | 7 règles d'alerte Grafana |
| `Grafana/provisioning/alerting/contactpoints.yml` | Contact point Discord |
| `Grafana/provisioning/alerting/policies.yml` | Politique de routage global |
| `Grafana/monitoring-dashboards/healthai_monitoring.json` | Dashboard infra Prometheus |
| `Grafana/data-dashboards/usersGrafana.json` | Dashboard données utilisateurs |
| `Grafana/data-dashboards/foodsGrafana.json` | Dashboard données aliments |
| `Grafana/data-dashboards/exercisesGrafana.json` | Dashboard données exercices |
| `Grafana/data-dashboards/healthMetricsGrafana.json` | Dashboard métriques santé |
| `Grafana/data-dashboards/appGrafana.json` | Dashboard synthèse application |
| `Monitoring/.env` | Variables d'environnement (webhook Discord, credentials BDD) |
