# HealthAI Coach – Stack Monitoring (Grafana + Prometheus)

> **Prometheus · Alertmanager · Grafana · Discord**
> Documentation pédagogique : comprendre **pourquoi** et **comment** fonctionne la supervision du projet.

---

## 📖 Comment lire ce document (sens de lecture)

Ce README se lit **du concept vers le détail**. Si tu débutes en monitoring, suis cet ordre :

1. **[Les 3 idées à comprendre AVANT tout](#1-les-3-idées-à-comprendre-avant-tout)** — le modèle « pull », les exporters, la séparation des rôles. **Ne saute pas cette partie**, tout le reste en découle.
2. **[Vue d'ensemble](#2-vue-densemble)** — le schéma global, qui parle à qui.
3. **[Comment Prometheus récupère les métriques](#3-comment-prometheus-récupère-vraiment-les-métriques)** — la réponse précise à « via Swagger ? via l'output du conteneur ? ».
4. **[Les 8 conteneurs, un par un](#4-les-8-conteneurs-du-stack-un-par-un)** — le rôle de chaque brique.
5. **[Le réseau Docker](#5-architecture-réseau--pourquoi-certaines-sondes-passent-par-le-host)** — pourquoi certaines sondes passent par le host.
6. **[Le voyage d'une métrique](#6-le-voyage-dune-métrique-de-la-source-à-grafana)** — du conteneur jusqu'au graphe Grafana.
7. **[Le voyage d'une alerte](#7-le-voyage-dune-alerte-jusquà-discord)** — de la panne jusqu'au message Discord.
8. **[Grafana en détail](#8-grafana--datasources-dashboards-provisioning)** — datasources, dashboards, provisioning.
9. **[Quel fichier fait quoi](#9-quel-fichier-fait-quoi-le-mapping-complet)** — le mapping fichier → rôle (référence).
10. **[Démo & FAQ](#11-démo-pour-la-présentation)** — pour la soutenance.

> 💡 **Convention des schémas** : une flèche `A --> B` se lit **« A envoie vers B »** ou **« A est lu par B »** selon le libellé porté par la flèche. Lis **toujours le texte sur la flèche**, il précise le sens.

---

## 1. Les 3 idées à comprendre AVANT tout

### Idée n°1 — Prometheus fonctionne en **PULL** (il va chercher), pas en **PUSH** (on lui envoie)

Beaucoup pensent que les applications « envoient » leurs métriques à Prometheus. **C'est l'inverse.**

> **Prometheus va lui-même interroger** chaque cible, à intervalle régulier (ici **toutes les 15 secondes**), via une simple **requête HTTP GET** sur une URL spéciale appelée **`/metrics`**.

Cette opération s'appelle un **scrape** (« raclage »). Prometheus « racle » la page `/metrics` de chaque cible, lit le texte renvoyé, et le range dans sa base de données temporelle (TSDB).

```mermaid
flowchart LR
    PR["🔥 Prometheus :9090"] -->|"GET http://node-exporter:9100/metrics\n(toutes les 15s)"| NE["📡 Node Exporter"]
    NE -->|"renvoie du TEXTE brut :\nnode_cpu_seconds_total 1234.5\nnode_memory_free_bytes 8e9"| PR
    PR -->|range dans la TSDB| DB[("🗄️ Base de données\ntemporelle interne")]
```

### Idée n°2 — Une application « normale » ne sait PAS parler à Prometheus → on utilise des **exporters**

Prometheus ne comprend qu'**un seul langage** : le **format d'exposition Prometheus** (du texte `nom_metric{label="x"} valeur`).

Or PostgreSQL, MongoDB, le système Linux, Docker… **ne parlent pas ce langage nativement**. On intercale donc des **traducteurs** appelés **exporters** :

> Un **exporter** est un petit programme (dans son propre conteneur) qui :
> 1. interroge un système (ex : PostgreSQL) avec **son** protocole natif,
> 2. **traduit** le résultat en format Prometheus,
> 3. l'expose sur une page **`/metrics`** que Prometheus vient scraper.

C'est exactement pour ça qu'on a 5 exporters (postgres, mongodb, node, cadvisor, blackbox) : ce sont les **adaptateurs** entre les services et Prometheus.

### Idée n°3 — Séparation des rôles : chacun fait UNE chose

```mermaid
flowchart LR
    EXP["📡 Exporters\nCOLLECTENT &\nTRADUISENT"] --> PR["🔥 Prometheus\nSTOCKE &\nÉVALUE les règles"]
    PR --> AM["📬 Alertmanager\nROUTE &\nGROUPE les alertes"]
    PR --> GR["📊 Grafana\nAFFICHE\n(ne stocke rien)"]
    AM --> BD["🐍 Bridge\nTRADUIT pour Discord"]
```

Retiens cette chaîne : **Collecter → Stocker → (Afficher | Alerter)**. Aucune brique ne fait le travail d'une autre. C'est ce qui rend le système **modulaire** : on peut remplacer Grafana sans toucher à Prometheus, ajouter un exporter sans toucher aux alertes, etc.

---

## 2. Vue d'ensemble

Le monitoring surveille **tous les services** du projet en temps réel.
Quand quelque chose ne va pas, une alerte part automatiquement sur Discord.

```mermaid
flowchart TD
    subgraph Services["🏗️ Services HealthAI"]
        L[Laravel API\n:80]
        F[FastAPI IA\n:4000]
        O[Ollama LLM\n:11434]
        PG[(PostgreSQL\n:5432)]
        MG[(MongoDB\n:27017)]
        FE[Frontend React\n:5001]
    end

    subgraph Exporters["📡 Exporters — collectent les métriques"]
        BB[Blackbox Exporter\nsondes HTTP up/down]
        PE[Postgres Exporter\nconnexions, transactions]
        ME[MongoDB Exporter\nconnexions, opérations]
        NE[Node Exporter\nCPU, RAM, disque hôte]
        CA[cAdvisor\nressources Docker globales]
    end

    subgraph Core["⚙️ Cœur Monitoring"]
        PR[(Prometheus\n:9090\nstocke les métriques)]
        AM[Alertmanager\n:9093\nroute les alertes]
    end

    subgraph Notification["🔔 Notifications"]
        BD[Bridge Discord\n:9094\nbridge maison Python]
        DC[💬 Discord]
    end

    GR[📊 Grafana\n:3000\ndashboards]

    L & F & O -->|HTTP probe via réseau sail| BB
    FE -->|HTTP probe via host.docker.internal:5001| BB
    PG --> PE
    MG --> ME

    BB & PE & ME & NE & CA -->|expose /metrics| PR
    PR -->|scrape toutes les 15s| NE
    PR -->|scrape toutes les 15s| CA

    PR -->|évalue règles d'alerte| AM
    AM -->|webhook JSON| BD
    BD -->|POST embed Discord| DC

    PR -->|datasource| GR
```

**Comment lire ce schéma (de haut en bas) :**
- **En haut**, les **services** du projet (ce qu'on veut surveiller).
- **Juste en dessous**, les **exporters** : chacun « branché » sur un service, ils exposent une page `/metrics`.
- **Au centre**, **Prometheus** scrape tous les exporters et **stocke** ; il **évalue** en continu les règles d'alerte.
- **À droite**, **Grafana** lit Prometheus pour **dessiner** les graphes (il ne stocke rien).
- **En bas**, la chaîne d'**alerte** : Prometheus → Alertmanager → Bridge → Discord.

> **Pourquoi `host.docker.internal` pour le Frontend ?**
> Le conteneur Frontend est sur le réseau `frontend_default` (réseau isolé créé par son propre compose).
> Les autres services sont sur `healthai_backend_sail`. Le blackbox exporter ne peut pas
> joindre `healthai_frontend` par nom. On passe par le port exposé sur le host (:5001).

---

## 3. Comment Prometheus récupère **vraiment** les métriques

> ❓ **Question fréquente : « Prometheus récupère-t-il les données via le Swagger ? via l'output (les logs) du conteneur ? »**
> **Réponse courte : NI l'un NI l'autre.**

| Idée reçue | Vrai ? | Explication |
|---|---|---|
| Via le **Swagger / OpenAPI** | ❌ **Non** | Le Swagger documente une API REST pour les **humains/devs**. Prometheus ne le lit jamais. |
| Via les **logs / stdout** du conteneur | ❌ **Non** | Prometheus ne lit pas la sortie console des conteneurs (ça, c'est le rôle d'outils comme Loki/ELK). |
| Via une page **HTTP `/metrics`** | ✅ **OUI** | Prometheus fait un `GET …/metrics` et lit un **texte au format Prometheus**. C'est **le seul** mécanisme. |

### Ce que renvoie réellement une page `/metrics`

Quand Prometheus fait `GET http://postgres-exporter:9187/metrics`, il reçoit un **texte brut** comme :

```text
# HELP pg_up Whether the last scrape of metrics from PostgreSQL was successful
# TYPE pg_up gauge
pg_up 1
# HELP pg_stat_database_numbackends Number of backends currently connected
# TYPE pg_stat_database_numbackends gauge
pg_stat_database_numbackends{datname="laravel"} 7
```

Chaque ligne = **un nom de métrique**, des **labels** entre `{}`, et une **valeur** numérique. Prometheus parse ce texte, horodate chaque valeur, et la stocke. **C'est tout.** Pas de magie, pas de Swagger, pas de logs.

### Cas particulier : les applications (Laravel, FastAPI, Ollama) n'ont PAS de `/metrics`

Nos applications **ne sont pas instrumentées** (elles n'exposent pas de page `/metrics` Prometheus). On ne peut donc pas lire leurs métriques internes.

👉 **Solution : le Blackbox Exporter.** Au lieu de demander à l'app « donne-moi tes métriques », on demande au Blackbox : **« va frapper à la porte de cette app et dis-moi si elle répond »**. C'est une sonde **« boîte noire »** (on ne regarde pas l'intérieur, juste si ça répond et en combien de temps).

```mermaid
flowchart LR
    PR["🔥 Prometheus"] -->|"1. GET /probe?target=http://healthai_fastapi:4000/"| BB["🔍 Blackbox Exporter"]
    BB -->|"2. GET http://healthai_fastapi:4000/"| APP["⚙️ FastAPI\n(app non instrumentée)"]
    APP -->|"3. 200 OK (ou timeout)"| BB
    BB -->|"4. renvoie : probe_success=1\nprobe_duration_seconds=0.08"| PR
```

> **À retenir** : pour les bases de données et le système → exporters qui exposent `/metrics`.
> Pour les applications web non instrumentées → blackbox qui les **sonde en HTTP** (up/down + temps de réponse).

### ❓ « Est-ce que Prometheus crée lui-même d'autres conteneurs ? »

**Non, jamais.** Prometheus est un **consommateur passif** : il lit des pages `/metrics`, c'est tout. Il ne lance **aucun** conteneur.

> Ce sont **nous** qui déclarons tous les conteneurs (Prometheus, les exporters, Alertmanager…) dans **`docker-compose.yml`**. C'est **Docker Compose** qui les crée et les démarre. Prometheus, une fois lancé, se contente d'aller scraper les adresses qu'on lui a données dans **`prometheus.yml`**.

```mermaid
flowchart TD
    DCY["📄 docker-compose.yml\n(NOUS l'écrivons)"] -->|"docker compose up -d\nCRÉE les conteneurs"| CONT["🐳 8 conteneurs\n(prometheus + exporters + ...)"]
    PCY["📄 prometheus.yml\n(NOUS l'écrivons)"] -->|"dit À Prometheus\nQUOI scraper et OÙ"| PR["🔥 Prometheus\n(LIT seulement)"]
    PR -.->|"ne crée RIEN,\nva juste lire les /metrics"| CONT
```

---

## 4. Les 8 conteneurs du stack, un par un

```mermaid
graph TD
    subgraph STACK["docker compose up -d  (depuis Monitoring/)"]
        PR2["🔥 Prometheus :9090\nCollecte + stocke toutes les métriques\nRétention 30 jours\nÉvalue les règles d'alerte"]
        AM2["📬 Alertmanager :9093\nReçoit les alertes de Prometheus\nGroupe, filtre les doublons\nRoute vers Discord"]
        BD2["🐍 Bridge Discord :9094\nServeur HTTP Python maison\nReçoit les webhooks Alertmanager\nFormate en embed Discord + User-Agent"]
        NE2["🖥️ Node Exporter :9100\nCPU, RAM, Disque, Load du serveur\nMétriques kernel Linux"]
        CA2["🐳 cAdvisor :8080\nRessources globales Docker\nLimité en WSL2 — pas de vue par conteneur"]
        PE2["🐘 Postgres Exporter :9187\nConnexions actives, transactions\nTaille des bases, slow queries"]
        ME2["🍃 MongoDB Exporter :9216\nConnexions, opérations CRUD/s\nÉtat replica set"]
        BB2["🔍 Blackbox Exporter :9115\nSonde HTTP GET sur chaque service\nMesure up/down + temps de réponse"]
    end
```

| # | Conteneur | Port | Rôle pédagogique | Type |
|---|---|---|---|---|
| 1 | **Prometheus** | 9090 | Le **cerveau** : scrape, stocke (30j), évalue les alertes | Cœur |
| 2 | **Alertmanager** | 9093 | Le **standardiste** : reçoit les alertes, dédoublonne, route | Cœur |
| 3 | **Bridge Discord** | 9094 | Le **traducteur** : transforme l'alerte en message Discord | Notif |
| 4 | **Node Exporter** | 9100 | Métriques **de la machine hôte** (CPU, RAM, disque) | Exporter |
| 5 | **cAdvisor** | 8080 | Métriques **des conteneurs Docker** (CPU/RAM par conteneur) | Exporter |
| 6 | **Postgres Exporter** | 9187 | Métriques **PostgreSQL** (connexions, transactions) | Exporter |
| 7 | **MongoDB Exporter** | 9216 | Métriques **MongoDB** (connexions, opérations) | Exporter |
| 8 | **Blackbox Exporter** | 9115 | **Sonde HTTP** up/down des applis non instrumentées | Exporter |

> ⚠️ **Grafana ne fait PAS partie de ces 8 conteneurs.** Grafana est lancé ailleurs (avec le reste de la stack applicative). Le stack `Monitoring/` fournit la **donnée** ; Grafana ne fait que **l'afficher**. C'est volontaire : on sépare « produire la métrique » de « la visualiser ».

---

## 5. Architecture réseau — pourquoi certaines sondes passent par le host

```mermaid
graph LR
    subgraph SAIL["Réseau : healthai_backend_sail"]
        BB[Blackbox\nExporter]
        LA[healthai_laravel\n:80]
        FA[healthai_fastapi\n:4000]
        OL[healthai_ollama\n:11434]
        PG[(healthai_pgsql\n:5432)]
        MG[(healthai_mongodb\n:27017)]
    end

    subgraph FRONT["Réseau : frontend_default"]
        FE[healthai_frontend\n:5173 interne]
    end

    HOST[🖥️ Host WSL2\n:5001 exposé]

    BB -->|direct| LA
    BB -->|direct| FA
    BB -->|direct| OL
    BB -->|host.docker.internal:5001| HOST
    HOST --> FE

    style FRONT fill:#ff9999,stroke:#cc0000
    style SAIL fill:#99ccff,stroke:#0066cc
```

**Pourquoi ce schéma ?** Dans Docker, **deux conteneurs ne se voient par leur nom QUE s'ils sont sur le même réseau**. Le Blackbox vit sur le réseau **`healthai_backend_sail`** (en bleu) ; il atteint donc Laravel/FastAPI/Ollama/PostgreSQL/MongoDB **directement par leur nom de service**.

Mais le **Frontend** (en rouge) a été démarré par **son propre `docker-compose`**, qui l'a mis sur un **autre réseau** (`frontend_default`). Le Blackbox **ne peut pas** l'atteindre par `healthai_frontend`. On contourne en passant par **le port publié sur la machine hôte** (`host.docker.internal:5001`), qui ressort sur le réseau Docker pour retomber sur le Frontend.

> 🎓 **Leçon DevOps** : un service injoignable « par son nom » est presque toujours un **problème de réseau Docker**, pas un bug applicatif. C'est exactement le piège classique « ça marche sur ma machine ».

Le stack monitoring se **rattache** à ce réseau existant grâce à cette déclaration dans `docker-compose.yml` :

```yaml
networks:
  sail:
    external: true            # le réseau existe déjà (créé par le Backend)
    name: healthai_backend_sail
```

`external: true` signifie : **« ne crée pas un nouveau réseau, branche-toi sur celui qui existe déjà »**. C'est ce qui permet aux exporters de parler aux conteneurs applicatifs.

---

## 6. Le voyage d'une métrique (de la source à Grafana)

Suis le chemin **de gauche à droite** : c'est l'ordre chronologique d'une donnée.

```mermaid
flowchart LR
    SRC["🐘 PostgreSQL\nla source"] -->|"1. protocole SQL natif"| PE["🐘 Postgres Exporter\nle traducteur"]
    PE -->|"2. expose /metrics\n(format Prometheus)"| PR["🔥 Prometheus\nscrape toutes les 15s"]
    PR -->|"3. stocke avec horodatage"| TSDB[("🗄️ TSDB\n30 jours")]
    GR["📊 Grafana"] -->|"4. requête PromQL\n(ex: pg_stat_database_numbackends)"| PR
    PR -->|"5. renvoie la série temporelle"| GR
    GR -->|"6. dessine le graphe"| USER["👀 Apprenant"]
```

1. **La source** (PostgreSQL) ne connaît pas Prometheus, elle parle SQL.
2. **L'exporter** interroge PostgreSQL en SQL, traduit, et publie une page `/metrics`.
3. **Prometheus** scrape cette page toutes les 15s et **stocke** chaque valeur avec son horodatage.
4. **Grafana** interroge Prometheus avec le langage **PromQL** (le langage de requête de Prometheus).
5. Prometheus renvoie la **série temporelle** (la suite des valeurs dans le temps).
6. Grafana **dessine** la courbe. Grafana **ne stocke rien** : à chaque rafraîchissement, il redemande à Prometheus.

> 🎯 **Point clé** : Grafana est juste une **fenêtre** sur les données de Prometheus. Si Prometheus est vide, Grafana affiche « No data ».

---

## 7. Le voyage d'une alerte (jusqu'à Discord)

```mermaid
sequenceDiagram
    participant S as Service (ex: FastAPI)
    participant BB as Blackbox Exporter
    participant PR as Prometheus
    participant AM as Alertmanager
    participant BD as Bridge Discord (Python)
    participant DC as 💬 Discord

    loop Toutes les 15 secondes
        PR->>BB: "Sonde http://healthai_fastapi:4000/"
        BB->>S: GET /
        S-->>BB: timeout ou connexion refusée
        BB-->>PR: probe_success=0
    end

    PR->>PR: Règle ServiceDown : for=0s → FIRE immédiat
    PR->>AM: ALERT{alertname=ServiceDown, severity=critical}

    AM->>AM: group_wait=0s pour critical
    AM->>BD: POST / {alerts: [...], status: firing}

    BD->>BD: Formate en Discord embed\n(title, color rouge, fields)
    BD->>DC: POST webhook\nUser-Agent: HealthAI-Monitoring/1.0

    Note over DC: 🔴 Service DOWN affiché dans #alertes

    Note over S: docker start healthai_fastapi
    PR->>AM: RESOLVED{alertname=ServiceDown}
    AM->>BD: POST / {status: resolved}
    BD->>DC: POST webhook (couleur verte)
    Note over DC: ✅ Résolu affiché dans #alertes
```

**Qui fait quoi dans cette chaîne (et pourquoi cette séparation) :**

| Étape | Brique | Rôle | Pourquoi pas ailleurs ? |
|---|---|---|---|
| Détecter | **Prometheus** | Évalue les règles (`probe_success == 0`) | C'est lui qui a les données |
| Décider d'alerter | **Prometheus** | `for: 0s` → déclenche immédiatement | La règle vit près de la donnée |
| Router / dédoublonner | **Alertmanager** | Groupe, applique les délais, évite le spam | Séparé pour ne pas alourdir Prometheus |
| Formater pour Discord | **Bridge Python** | Transforme le JSON en embed lisible | Discord a un format précis (voir ci-dessous) |
| Afficher | **Discord** | Notifie l'équipe | Là où l'équipe regarde |

### Pourquoi un bridge Python maison ?

```mermaid
flowchart LR
    AM3[Alertmanager] -->|POST JSON format v4| ROGERRUM["❌ rogerrum/alertmanager-discord\nBug : embeds mal formatés\nErreur Discord 403 code 1010"]
    AM3 -->|POST JSON format v4| BRIDGE["✅ discord-bridge/bridge.py\nReçoit le JSON Alertmanager\nConstruit les embeds correctement\nAjoute le User-Agent requis par Discord\nRetourne 200 OK"]
    BRIDGE -->|POST embeds + User-Agent| DC3[💬 Discord\nRépond 204 No Content]

    style ROGERRUM fill:#ff4444,color:#fff
    style BRIDGE fill:#44bb44,color:#fff
    style DC3 fill:#5865F2,color:#fff
```

> L'image toute faite `rogerrum/alertmanager-discord` envoyait des embeds mal formés → Discord répondait **403**.
> Notre bridge (`discord-bridge/bridge.py`, **~40 lignes de Python standard, sans dépendance**) génère le bon format **et** ajoute le header **`User-Agent`** exigé par Cloudflare (sinon Discord refuse). C'est un bon exemple de **« quand l'outil tout fait ne marche pas, on écrit 40 lignes maîtrisées »**.

---

## 8. Grafana : datasources, dashboards, provisioning

Grafana est **auto-configuré au démarrage** (« provisioning »), pour ne rien avoir à cliquer à la main. Deux notions :

```mermaid
flowchart TD
    subgraph PROV["📁 Grafana/provisioning/ (lu au démarrage)"]
        DS["datasources/\nOÙ aller chercher les données"]
        DASH["dashboards/\nQUELS dashboards charger"]
        ALERT["alerting/\n(alertes natives Grafana, optionnel)"]
    end

    DS -->|"prometheus.yml → http://healthai_prometheus:9090"| PR[("🔥 Prometheus")]
    DS -->|"postgresql.yml → healthai_pgsql:5432"| PG[("🐘 PostgreSQL")]
    DASH -->|"charge les .json"| BOARDS["📊 Dashboards"]

    PR --> BOARDS
    PG --> BOARDS
```

**Deux sources de données, deux usages :**
- **Datasource Prometheus** → dashboards **d'infrastructure** (services up/down, CPU, RAM, conteneurs). C'est le **monitoring technique**.
- **Datasource PostgreSQL** → dashboards **métier** (utilisateurs, aliments, exercices, santé). Grafana fait alors du **SQL directement** sur la base applicative pour des **statistiques métier**.

> 🎓 **Point important** : Grafana peut lire **plusieurs sources**. Ici il combine du **technique** (via Prometheus) et du **métier** (via SQL Postgres). Les deux mondes cohabitent dans la même interface.

**Le piège de l'UID** : chaque dashboard `.json` référence sa datasource par un **UID** (identifiant unique). Si l'UID du provisioning ne correspond pas à celui codé dans le `.json`, le dashboard affiche « datasource not found ». C'est pour ça que `postgresql.yml` fixe l'UID `fficjnp24r8jka` : il doit **matcher** l'UID déjà inscrit dans les 4 dashboards data existants.

### Ce que montre le dashboard d'infrastructure

```mermaid
graph TD
    subgraph ROW1["🌐 Section 1 — État des services (7 panneaux stat)"]
        P1[Laravel API\nprobe_success HTTP /up]
        P2[FastAPI IA\nprobe_success HTTP /]
        P3[Ollama LLM\nprobe_success HTTP /]
        P4[PostgreSQL\npg_up]
        P5[MongoDB\nmongodb_up]
        P6[Frontend React\nprobe_success host:5001]
        P7[Targets UP / 9\ncount of up==1\n= 4 sondes + 5 exporters]
    end

    subgraph ROW2["🐳 Section 2 — Ressources système"]
        P8[CPU global\ncAdvisor id=/]
        P9[RAM globale\ncAdvisor id=/]
        P10[Réseau global\ncAdvisor id=/]
        note1["⚠️ WSL2 : cAdvisor ne voit pas\nles conteneurs individuellement\n— métriques globales uniquement"]
    end

    subgraph ROW3["🗄️ Section 3 — Bases de données"]
        P11[PgSQL connexions stat]
        P12[PgSQL commits/rollbacks/s]
        P13[MongoDB connexions stat]
        P14[MongoDB ops/s]
    end

    subgraph ROW4["💻 Section 4 — Système hôte"]
        P15[CPU % jauge]
        P16[RAM % jauge]
        P17[Disque % jauge]
        P18[CPU historique]
        P19[RAM historique]
    end
```

> **Limitation WSL2** : cAdvisor tourne sur WSL2 où le cgroup driver ne permet pas d'isoler les métriques
> par conteneur. On voit les métriques de la machine entière (`id="/"`) — c'est normal, pas un bug.

---

## 9. Quel fichier fait quoi (le mapping complet)

### Fichiers du stack Monitoring (ce dossier)

```mermaid
graph TD
    subgraph MON["📁 Monitoring/"]
        DC2["docker-compose.yml\n→ CRÉE les 8 conteneurs monitoring"]
        ENV[".env\n→ secrets : webhook Discord + creds BDD"]
        subgraph PROM["📁 prometheus/"]
            PC["prometheus.yml\n→ QUOI scraper, OÙ, et règles d'alerte à charger"]
            RA["rules/healthai_alerts.yml\n→ les 14 règles (quand déclencher une alerte)"]
        end
        subgraph ALT["📁 alertmanager/"]
            AC["alertmanager.yml\n→ COMMENT router (critique vs warning) vers Discord"]
        end
        subgraph BR["📁 discord-bridge/"]
            BP["bridge.py\n→ TRADUIT l'alerte en embed Discord"]
            BDF["Dockerfile\n→ image python:3.12-alpine du bridge"]
        end
    end
```

| Fichier | Ce qu'il **permet de faire** | Détail clé |
|---|---|---|
| **`Monitoring/docker-compose.yml`** | **Crée et démarre les 8 conteneurs** (Prometheus, Alertmanager, bridge, 5 exporters) | Se branche sur le réseau existant `healthai_backend_sail` (`external: true`) |
| **`Monitoring/prometheus/prometheus.yml`** | **Dit à Prometheus quoi surveiller** | `scrape_configs` = la liste des cibles + adresses ; `rule_files` = où sont les alertes ; `alerting` = où est Alertmanager |
| **`Monitoring/prometheus/rules/healthai_alerts.yml`** | **Définit les 14 alertes** | Chaque règle = une condition PromQL (ex `probe_success == 0`) + une `severity` + un message |
| **`Monitoring/alertmanager/alertmanager.yml`** | **Route et tempère les alertes** | `group_wait: 0s` pour critique (immédiat), `repeat_interval` (anti-spam), `inhibit_rules` (si DOWN, on tait les warnings du même service) |
| **`Monitoring/discord-bridge/bridge.py`** | **Transforme l'alerte JSON en message Discord** | Serveur HTTP Python (~40 lignes), construit les `embeds`, ajoute le `User-Agent` requis |
| **`Monitoring/discord-bridge/Dockerfile`** | **Empaquette le bridge** en image | `python:3.12-alpine`, aucune dépendance externe |
| **`Monitoring/.env`** | **Fournit les secrets** | `DISCORD_WEBHOOK_URL`, identifiants PostgreSQL/MongoDB (jamais commités) |

### Fichiers Grafana (dans le repo `Grafana/`)

| Fichier | Ce qu'il **permet de faire** |
|---|---|
| **`Grafana/provisioning/datasources/prometheus.yml`** | Connecte **automatiquement** Grafana à Prometheus (`http://healthai_prometheus:9090`, UID `prometheus-healthai`) |
| **`Grafana/provisioning/datasources/postgresql.yml`** | Connecte Grafana à PostgreSQL pour les dashboards **métier** (UID `fficjnp24r8jka`) |
| **`Grafana/provisioning/dashboards/dashboards.yml`** | Déclare les **dossiers** Grafana et charge les `.json` au démarrage |
| **`Grafana/monitoring-dashboards/healthai_monitoring.json`** | Le **dashboard d'infrastructure** (services up/down, CPU, RAM, BDD, hôte) |
| **`Grafana/usersGrafana.json` …** | Les 4 dashboards **métier** (utilisateurs, aliments, exercices, santé) |

### Modifications apportées aux fichiers existants (intégration)

| Fichier | Ce qui a changé | Pourquoi |
|---|---|---|
| [ETL/docker-compose.yml](../ETL/docker-compose.yml) | Grafana : volumes provisioning, env alerting, réseau sail, `MIN_REFRESH_INTERVAL=5s` | Auto-charger datasources + dashboards, permettre refresh 5s |
| [start.sh](../start.sh) | Étape 13/14 : lance `Monitoring/docker-compose.yml` | Démarrage automatique du stack monitoring |
| [Grafana/provisioning/datasources/postgresql.yml](../Grafana/provisioning/datasources/postgresql.yml) | Datasource PostgreSQL avec UID `fficjnp24r8jka` | Correspond à l'UID codé dans les 4 dashboards data existants |
| [Monitoring/prometheus/prometheus.yml](prometheus/prometheus.yml) | Frontend sondé via `host.docker.internal:5001` au lieu de `healthai_frontend:5173` | Frontend sur réseau `frontend_default` inaccessible depuis `sail` |
| [Monitoring/prometheus/rules/healthai_alerts.yml](prometheus/rules/healthai_alerts.yml) | `ServiceDown` : `for: 0s` (au lieu de 2m) | Alerte immédiate pour la démo |
| [Monitoring/alertmanager/alertmanager.yml](alertmanager/alertmanager.yml) | `group_wait: 0s` pour critical | Envoi Discord sans délai |
| [Grafana/monitoring-dashboards/healthai_monitoring.json](../Grafana/monitoring-dashboards/healthai_monitoring.json) | Ajout panneau Frontend, w=3 pour 7 panneaux, refresh=5s, fix queries WSL2 | Frontend visible, rafraîchissement rapide |

---

## 10. Les 14 alertes configurées

```mermaid
graph LR
    subgraph CRIT["🔴 Critique — notification immédiate, répète toutes les heures"]
        A1[ServiceDown\nService HTTP mort — for=0s]
        A2[ContainerDown\nConteneur disparu depuis 2min]
        A3[PostgreSQLDown\nExporter ne joint plus la BDD]
        A4[MongoDBDown\nExporter ne joint plus la BDD]
        A5[HostHighMemory\nRAM hôte > 90%]
        A6[HostDiskFull\nDisque > 95%]
    end

    subgraph WARN["⚠️ Warning — répète toutes les 4h"]
        B1[ServiceSlowResponse\nRéponse HTTP > 5s pendant 5min]
        B2[ContainerHighCPU\nCPU conteneur > 80% — 5min]
        B3[ContainerHighMemory\nRAM conteneur > 85% de la limite]
        B4[ContainerRestarting\nPlus de 2 redémarrages en 15min]
        B5[PostgreSQLTooManyConnections\nConnexions > 80]
        B6[MongoDBTooManyConnections\nConnexions > 200]
        B7[HostHighCPU\nCPU > 85% pendant 10min]
        B8[HostDiskAlmostFull\nDisque > 85%]
    end
```

**Comprendre les 2 mots-clés d'une règle :**
- **`severity`** (`critical` / `warning`) → décide de l'urgence et du routage dans Alertmanager.
- **`for`** → durée pendant laquelle la condition doit rester vraie avant de déclencher. `for: 0s` = immédiat (pour la démo) ; `for: 5m` = il faut 5 min de problème continu (évite les fausses alertes sur un pic passager).

---

## 11. Démo pour la présentation

### Timing complet

| T+ | Événement |
|---|---|
| 0s | `docker stop healthai_fastapi` |
| ~15s | Prometheus détecte `probe_success=0` |
| ~15s | Alerte FIRING (for=0s) |
| ~15s | Message Discord 🔴 |
| +60s | `docker start healthai_fastapi` |
| ~75s | Alerte RESOLVED |
| ~75s | Message Discord ✅ |

### Commandes prêtes

```bash
# Déclenche l'alerte (~15s avant Discord)
docker stop healthai_fastapi

# Surveille Prometheus en live (terminal séparé)
watch -n 2 'curl -s http://localhost:9090/api/v1/alerts | python3 -c "
import sys,json
d=json.load(sys.stdin)
alerts=d[\"data\"][\"alerts\"]
print(\"Alertes actives:\", len(alerts))
for a in alerts: print(\" \", a[\"state\"].upper(), a[\"labels\"][\"alertname\"], a[\"labels\"].get(\"instance\",\"\"))
"'

# Résoud l'alerte (~15s avant Discord ✅)
docker start healthai_fastapi
```

### Les URLs à connaître pour la démo

| Interface | URL | À montrer |
|---|---|---|
| **Prometheus** | http://localhost:9090 | Onglet *Status → Targets* (tout est UP), onglet *Alerts* |
| **Alertmanager** | http://localhost:9093 | Les alertes en cours de routage |
| **Grafana** | http://localhost:3000 | Le dashboard *HealthAI Monitoring* |
| **cAdvisor** | http://localhost:8080 | Les métriques Docker brutes |

---

## 12. FAQ pédagogique (questions de jury)

**« Prometheus lit le Swagger ? »**
→ Non. Prometheus fait `GET /metrics` et lit un texte au format Prometheus. Le Swagger est une doc d'API pour les humains, sans rapport.

**« Prometheus lit les logs du conteneur ? »**
→ Non. Lire les logs, c'est le rôle de Loki/ELK. Prometheus ne fait que scraper des pages `/metrics`.

**« Prometheus crée des conteneurs ? »**
→ Non. C'est **Docker Compose** qui crée tous les conteneurs (`docker-compose.yml`). Prometheus ne fait que **lire** les `/metrics` aux adresses listées dans `prometheus.yml`.

**« Pourquoi des exporters et pas directement l'app ? »**
→ Parce que PostgreSQL, MongoDB, le système… ne parlent pas le format Prometheus. L'exporter traduit. Et nos applis web ne sont pas instrumentées → on les sonde de l'extérieur avec Blackbox (up/down + temps de réponse).

**« Que se passe-t-il si la base n'est pas prête au démarrage ? »**
→ Le postgres-exporter renvoie `pg_up=0`, l'alerte `PostgreSQLDown` se déclenche, et un message Discord part. Le monitoring **observe** la panne ; il ne la corrige pas (ce serait le rôle des health checks Docker + `restart: unless-stopped`).

**« Où sont stockées les métriques et combien de temps ? »**
→ Dans la TSDB interne de Prometheus (volume `prometheus_data`), **30 jours** (`--storage.tsdb.retention.time=30d`).

---

### En une phrase
> **Les exporters traduisent, Prometheus collecte et stocke, Grafana affiche, Alertmanager + le bridge préviennent sur Discord — et tout est créé par Docker Compose, pas par Prometheus.**
