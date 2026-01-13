# Geo_mobilite_IDF_project

## 📍 Objectif

Ce projet open source vise à analyser l’évolution temporelle de l’offre de transport public
en Île-de-France à partir des données **GTFS publiées par Île-de-France Mobilités**.

Il met en œuvre une chaîne de données complète incluant :
- ingestion automatisée de fichiers GTFS,
- historisation des données (SCD Type 2),
- modélisation bi-temporelle,
- analyse géospatiale,
- visualisation et interrogation analytique.

---

## 📊 Source de données

Les données proviennent du jeu de données officiel :

**Offre horaires transport public – GTFS IDFM**  
https://data.iledefrance-mobilites.fr

L’ingestion s’appuie sur l’API **Opendatasoft Explore v2.1** pour :
- lister les publications disponibles,
- détecter les mises à jour,
- télécharger automatiquement les fichiers GTFS.

---

## 🧠 Concepts clés

- **Double temporalité**
  - `publication_date` : date de publication du GTFS
  - `service_date` : date réelle de circulation du service

- **Dimensions historisées (SCD Type 2)**
  - arrêts (`stops`)
  - lignes (`routes`)
  - agences (`agencies`)

- **Faits bitemporels**
  - passages par arrêt
  - fréquences
  - offre de service

---

## ⚙️ Architecture

```text
API Opendatasoft (GTFS)
        ↓
Ingestion Airflow (Python)
        ↓
PostgreSQL + PostGIS (raw + analytics)
        ↓
DBT (snapshots & models)
        ↓
Apache Superset (cartes & dashboards)
