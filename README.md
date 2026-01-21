
# 🚲 Geo-Mobility Analytics Platform – Vélib’ Île-de-France
> **Status : 🚧 Work in Progress (Portfolio Project)**

Plateforme d’analyse **data & géospatiale** des usages Vélib’ en Île-de-France,  
combinant **ingestion temps réel**, **modélisation analytique**, **PostGIS** et **visualisation cartographique**.

Ce projet est développé comme **démonstrateur technique** et **portfolio freelance**.

---

## 🎯 Objectif du projet

L’objectif est de concevoir une **chaîne data complète** permettant :

- l’ingestion continue des données Vélib’ (stations, disponibilité)
- le stockage géospatial structuré (PostgreSQL + PostGIS)
- l’enrichissement avec des données territoriales (communes, population)
- l’analyse des tensions d’usage par zone
- la visualisation cartographique et temporelle des indicateurs clés

---

## 🏗️ Architecture globale

```text
API Vélib’
    │
    ▼
Airflow (ingestion)
    │
    ▼
PostgreSQL + PostGIS  ◀── Données géographiques
    │                     (communes, population)
    ▼
DBT (staging & marts)
    │
    ▼
Superset (cartes & KPI)
```
---

## 🧱 Stack technique

| Domaine | Outils |
|------|------|
| Ingestion | Apache Airflow |
| Base de données | PostgreSQL 15 |
| SIG | PostGIS |
| Transformation | DBT |
| Visualisation | Apache Superset |
| Infra | Docker / Docker Compose |

---

## 📊 Cas d’usage analytiques visés

- Disponibilité des vélos en temps réel
- Détection des zones de tension (offre vs demande)
- Analyse territoriale par commune
- Corrélation entre population et usage Vélib’
- Séries temporelles par station / zone

---

## 🚧 Avancement du projet

### ✅ Déjà implémenté

- Ingestion des données Vélib’ via Airflow
- Stockage centralisé PostgreSQL + PostGIS
- Modèle de données brut et staging
- Structure DBT définie
- Architecture Docker opérationnelle

### 🔜 En cours / à venir

- Modèles analytiques DBT (facts & agrégats)
- Enrichissement spatial (communes, population)
- Dashboards cartographiques Superset
- Tests DBT & CI légère

> ⚠️ Ce projet est **volontairement itératif** :  
> il illustre une approche réaliste de développement data en environnement professionnel.

---

## 📁 Organisation du repository
```text
.
├── airflow/ # DAGs d’ingestion Vélib’
├── dbt/ # Modèles analytiques
├── postgres/ # Initialisation PostGIS & données géographiques
├── docker-compose.yml
└── README.md
```

---

## 👤 Auteur

**Vincent Crozet**  
Data Analyst / Scientist, expert SIG  
📍 Île-de-France  
💼 Disponible pour missions freelance

🔗 LinkedIn : www.linkedin.com/in/vincent-crozet

---

## 📝 Note

Ce repository est un **projet de démonstration technique**.  
Il n’a pas vocation à être déployé en production tel quel, mais à illustrer :

- une architecture data réaliste
- une maîtrise des outils modernes
- une approche analytique orientée métier
