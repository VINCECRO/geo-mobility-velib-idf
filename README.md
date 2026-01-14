# Geo_mobilité IDF – Monitoring spatio-temporel Vélib’

## 🚀 Objectif du projet

Ce projet a pour but de construire une **chaîne de données complète et réaliste** pour le suivi des stations Vélib’ en Île-de-France, avec un focus sur :

- Ingestion continue des données via l’API officielle Vélib’
- Stockage géospatial avec PostgreSQL + PostGIS
- Modélisation analytique avec DBT (staging, marts, tests)
- Analyses spatio-temporelles avancées (SIG, clustering, vélos disponibles, etc.)
- Bonnes pratiques d’ingénierie : CI/CD, versioning, tests, gestion des secrets

> ⚠️ Ce projet est conçu comme un **portfolio technique**, pas comme une application en production.

---

## 📦 Structure du repository

```text
velib-monitoring/
├── docker-compose.yml       # Orchestration des containers
├── .env.velib.example       # Template secrets / API key
├── README.md
├── ingestion/               # Scripts Python pour ingestion API
├── dbt/                     # Modélisation et transformations DBT
├── airflow/                 # DAGs Airflow (optionnel pour orchestration)
└── superset/                # Dashboards (optionnel)