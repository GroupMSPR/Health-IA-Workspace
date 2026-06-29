# HealthAI Coach – Stack Monitoring

> Prometheus · Alertmanager · Grafana · Discord

---

## Vue d'ensemble

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

> **Pourquoi `host.docker.internal` pour le Frontend ?**
> Le conteneur Frontend est sur le réseau `frontend_default` (réseau isolé créé par son propre compose).
> Les autres services sont sur `healthai_backend_sail`. Le blackbox exporter ne peut pas
> joindre `healthai_frontend` par nom. On passe par le port exposé sur le host (:5001).

---

## Architecture réseau — pourquoi certaines sondes passent par le host

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

---

## Séquence complète d'une alerte Discord

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

---

## Structure complète des fichiers

```mermaid
graph TD
    subgraph REPO["📁 Health-IA-Workspace"]

        subgraph MON["📁 Monitoring/"]
            DC2[docker-compose.yml\n8 conteneurs monitoring]
            ENV[.env\nDISCORD_WEBHOOK_URL + credentials BDD]

            subgraph PROM["📁 prometheus/"]
                PC[prometheus.yml\nconfig scrape — quoi collecter et où]
                subgraph RULES["📁 rules/"]
                    RA[healthai_alerts.yml\n14 règles d'alerte définies]
                end
            end

            subgraph ALT["📁 alertmanager/"]
                AC[alertmanager.yml\nroutage critique vs warning vers Discord]
            end

            subgraph BRIDGE["📁 discord-bridge/"]
                BP[bridge.py\nserveur HTTP Python — reçoit Alertmanager\net envoie des embeds Discord formatés]
                BDF[Dockerfile\npython:3.12-alpine]
            end
        end

        subgraph GRF["📁 Grafana/"]
            subgraph PROV["📁 provisioning/"]
                subgraph DS["📁 datasources/"]
                    DSP[prometheus.yml\nauto-connecte Grafana à Prometheus\nUID: prometheus-healthai]
                    DSQ[postgresql.yml\nauto-connecte Grafana à PostgreSQL\nUID: fficjnp24r8jka]
                end
                subgraph DBP["📁 dashboards/"]
                    DBF[dashboards.yml\ndéclare 2 dossiers Grafana:\nHealthAI Monitoring + HealthAI Data]
                end
                subgraph ALP["📁 alerting/"]
                    CP[contactpoints.yml\ncontact Discord natif Grafana]
                    PL[policies.yml\nrègle de routage des alertes Grafana]
                end
            end
            subgraph MDASH["📁 monitoring-dashboards/"]
                MJ[healthai_monitoring.json\ndashboard infra — 7 panneaux services\n+ conteneurs + BDD + système hôte]
            end
            subgraph DDASH["Dashboards data existants"]
                U[usersGrafana.json]
                F2[foodsGrafana.json]
                E[exercisesGrafana.json]
                H[healthMetricsGrafana.json]
            end
        end

    end
```

---

## Les 8 conteneurs du stack Monitoring

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

---

## Pourquoi un bridge Python maison ?

```mermaid
flowchart LR
    AM3[Alertmanager] -->|POST JSON format v4| ROGERRUM["❌ rogerrum/alertmanager-discord\nBug : embeds mal formatés\nErreur Discord 403 code 1010"]
    AM3 -->|POST JSON format v4| BRIDGE["✅ discord-bridge/bridge.py\nReçoit le JSON Alertmanager\nConstruit les embeds correctement\nAjoute le User-Agent requis par Discord\nRetourne 200 OK"]
    BRIDGE -->|POST embeds + User-Agent| DC3[💬 Discord\nRépond 204 No Content]

    style ROGERRUM fill:#ff4444,color:#fff
    style BRIDGE fill:#44bb44,color:#fff
    style DC3 fill:#5865F2,color:#fff
```

> L'image `rogerrum/alertmanager-discord` envoyait des embeds mal formés → Discord répondait 403.
> Notre bridge Python génère le bon format et ajoute le header `User-Agent` requis par Cloudflare.

---

## Les 14 alertes configurées

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

### Timing des alertes pour la démo

```mermaid
sequenceDiagram
    Note over PR3: docker stop healthai_fastapi
    PR3->>PR3: Scrape interval 15s → détecte probe_success=0
    Note over PR3: for=0s → FIRING immédiat
    PR3->>AM4: Alerte critique
    Note over AM4: group_wait=0s pour critical
    AM4->>DC4: Message Discord
    Note over DC4: ⏱️ Total : ~15-20 secondes
```

---

## Dashboard Grafana — ce qui est affiché

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

## Démo pour la présentation

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

---

## Modifications apportées aux fichiers existants

| Fichier | Ce qui a changé | Pourquoi |
|---|---|---|
| [ETL/docker-compose.yml](../ETL/docker-compose.yml) | Grafana : volumes provisioning, env alerting, réseau sail, `MIN_REFRESH_INTERVAL=5s` | Auto-charger datasources + dashboards, permettre refresh 5s |
| [start.sh](../start.sh) | Étape 13/14 : lance `Monitoring/docker-compose.yml` | Démarrage automatique du stack monitoring |
| [Grafana/provisioning/datasources/postgresql.yml](../Grafana/provisioning/datasources/postgresql.yml) | Datasource PostgreSQL avec UID `fficjnp24r8jka` | Correspond à l'UID codé dans les 4 dashboards data existants |
| [Monitoring/prometheus/prometheus.yml](prometheus/prometheus.yml) | Frontend sondé via `host.docker.internal:5001` au lieu de `healthai_frontend:5173` | Frontend sur réseau `frontend_default` inaccessible depuis le réseau `sail` |
| [Monitoring/prometheus/rules/healthai_alerts.yml](prometheus/rules/healthai_alerts.yml) | `ServiceDown` : `for: 0s` (au lieu de 2m) | Alerte immédiate pour la démo |
| [Monitoring/alertmanager/alertmanager.yml](alertmanager/alertmanager.yml) | `group_wait: 0s` pour critical | Envoi Discord sans délai |
| [Grafana/monitoring-dashboards/healthai_monitoring.json](../Grafana/monitoring-dashboards/healthai_monitoring.json) | Ajout panneau Frontend, w=3 pour 7 panneaux, refresh=5s, fix queries WSL2 | Frontend visible, rafraîchissement rapide |
