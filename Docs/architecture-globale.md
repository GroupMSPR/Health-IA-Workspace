# 🗺️ Architecture Globale - HealthAI Coach

Ce document présente l'architecture macro de la plateforme et la manière dont les différents microservices interagissent entre eux pour assurer le fonctionnement du système.

## Diagramme d'architecture (Flux Applicatifs & Data)

Le système est découpé en deux couches principales : une couche applicative (qui gère l'interface utilisateur et la logique métier de l'IA) et une couche de données (centrée autour de la base de données relationnelle, de l'ingestion ETL et du monitoring).

```mermaid
graph TD
    %% Couche Applicative
    Front("💻 Frontend Web (React)")
    Back("⚙️ Backend API (Laravel)")
    IA("🧠 API IA (FastAPI + LLaVA)")

    %% Couche Data
    ETL("📥 Pipeline ETL (Python)")
    DB("🗄️ PostgreSQL Database")
    Grafana("📊 Dashboards (Grafana)")

    %% Flux Applicatifs
    Front <-->|"Requêtes et Réponses (REST)"| Back
    Back <-->|"Envoi d'image et Retour de l'IA"| IA
    
    %% Flux de Données
    Back <-->|"Lecture et Écriture SQL"| DB
    ETL -- "Ingestion de données" --> DB
    Grafana <-->|"Requêtes et Métriques en temps réel"| DB
```