# 🛠️ Justification des Choix Techniques

Ce document détaille les raisons architecturales et techniques qui ont mené au choix des différentes technologies de la plateforme HealthAI Coach.

## Architecture Microservices & Conteneurisation
* **Docker & Docker Compose** : Choisi pour garantir la portabilité et la reproductibilité parfaite de l'environnement de développement, qu'il soit exécuté sur Windows (via WSL2) ou sur d'autres systèmes. L'isolation des services permet de faire coexister une stack PHP, deux stacks Python et une stack Node.js sans conflit de dépendances locales.

## Couche Applicative & API
* **Backend : Laravel 12** : Framework robuste offrant une gestion native des migrations de base de données, de l'authentification par jeton (Sanctum), et une configuration d'administration clé en main (via Filament). L'architecture respecte une séparation stricte de la logique de routage et de la logique métier.
* **Frontend : React 19 & Vite** : Utilisé pour concevoir une application de type Single Page Application (SPA) rapide et dynamique. Vite fournit un serveur de développement extrêmement performant grâce au Hot Module Replacement (HMR).
* **API IA : FastAPI & Ollama (LLaVA)** : FastAPI a été privilégié pour sa rapidité d'exécution en Python et sa génération automatique de documentation de test (Swagger UI). Ollama permet de faire tourner le modèle multimodal LLaVA en local, garantissant la confidentialité des données de santé des utilisateurs (aucune image ne transite sur des API tierces payantes).

## Couche Données & Ingestion
* **Base de données : PostgreSQL** : Système de gestion de base de données relationnelle choisi pour sa robustesse, sa gestion stricte des contraintes d'intégrité (clés étrangères, types de données) et ses excellentes performances sur les requêtes d'agrégation complexes utilisées pour le monitoring.
* **ETL : Python & Pandas** : Python est la référence pour la manipulation de données. La bibliothèque Pandas est exploitée pour charger, nettoyer, formater et valider les fichiers de métriques (CSV, JSON, XLSX) avant leur insertion en base de données.
* **Monitoring : Grafana** : Choisi pour sa capacité à se brancher nativement sur PostgreSQL afin de concevoir des tableaux de bord analytiques en temps réel (suivi des utilisateurs, évolution des métriques de santé globales).