# 🗄️ Dictionnaire de Données (PostgreSQL) -- A CONTINUER

Ce document décrit la structure des principales tables de la base de données PostgreSQL de l'application.

## Table : `users`
Contient les informations de profil et d'authentification des utilisateurs de la plateforme.

| Champ | Type | Contraintes | Description |
|-------|------|-------------|-------------|
| `id` | BigInt | Primary Key, Auto-increment | Identifiant unique de l'utilisateur |
| `name` | VARCHAR(255) | Not Null | Nom complet ou pseudonyme |
| `email` | VARCHAR(255) | Unique, Not Null | Adresse email de connexion |
| `password` | VARCHAR(255) | Not Null | Empreinte de hachage du mot de passe |
| `created_at` | Timestamp | Nullable | Date et heure de création du compte |

## Table : `foods`
Répertoire des aliments et des informations nutritionnelles associées issues de l'analyse IA ou de l'ETL.

| Champ | Type | Contraintes | Description |
|-------|------|-------------|-------------|
| `id` | BigInt | Primary Key, Auto-increment | Identifiant unique de l'aliment |
| `name` | VARCHAR(255) | Not Null | Nom de l'aliment ou du plat |
| `calories` | Integer | Not Null | Nombre de calories pour 100g |
| `proteins` | Float | Nullable | Quantité de protéines (g) |
| `carbohydrates`| Float | Nullable | Quantité de glucides (g) |
| `lipids` | Float | Nullable | Quantité de lipides (g) |

## Table : `exercises`
Catalogue des activités physiques disponibles dans le système.

| Champ | Type | Contraintes | Description |
|-------|------|-------------|-------------|
| `id` | BigInt | Primary Key, Auto-increment | Identifiant unique de l'exercice |
| `name` | VARCHAR(255) | Not Null | Nom de l'activité (ex: Course, Musculation) |
| `calories_per_minute` | Float | Not Null | Ratio de dépenses énergétiques estimé |

## Tables d'Associations & Métriques
* `consume` : Table pivot reliant `users` et `foods` pour historiser les repas pris (avec quantité et date).
* `practice` : Table pivot reliant `users` et `exercises` pour suivre les entraînements (durée et date).
* `health_metrics` : Table stockant les relevés physiologiques (poids, hydratation, sommeil, rythme cardiaque) liés à un utilisateur.
