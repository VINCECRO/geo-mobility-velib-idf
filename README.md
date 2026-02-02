# 🚲 Geo-Mobility Analytics Platform – Vélib’ Île-de-France
> **Status: 🚧 Work in Progress (Portfolio Project)**

An end-to-end **geo-data analytics platform** focused on Vélib’ bike-sharing usage in Île-de-France.  
This project combines **real-time data ingestion**, **geospatial modeling**, **analytical transformations**, and **cartographic visualization**.

It is developed as a **technical demonstrator and freelance portfolio project**.

---

## 🎯 Project Objective

The goal of this project is to design a **realistic data engineering pipeline** that enables:

- continuous ingestion of Vélib’ open API data (stations & availability)
- centralized storage using PostgreSQL and PostGIS
- enrichment with territorial and socio-demographic data
- spatial and temporal analysis of usage patterns
- visualization of key mobility indicators

---

## 🏗️ Global Architecture

```text
Vélib’ API
    │
    ▼
Airflow (ingestion)
    │
    ▼
PostgreSQL + PostGIS  ◀── Geographical datasets
    │                     (communes, population)
    ▼
DBT (staging & marts)
    │
    ▼
Superset (maps & KPIs)
```
---

## 🧱 Tech stack

| Domain | Tools |
|------|------|
| Data ingestion | Apache Airflow |
| Database | PostgreSQL 15 |
| Geospatial | PostGIS |
| Transformations | DBT |
| Visualization | to be defined (superset, ...) |
| Infra | Docker / Docker Compose |

---
## ⚙️ Development & Configuration

### Local development environment

Local Python development is managed using **UV**, providing:
- fast dependency resolution
- reproducible environments
- isolation between local tooling and Dockerized services

This allows smooth iteration on ingestion logic and data models while keeping
the runtime environment consistent with the containerized stack.

---

### Secrets & configuration management

Sensitive configuration values (database credentials, API tokens, Airflow secrets)
are managed through environment variables.

- A `.env.example` file is provided as a template
- Actual secrets are stored in a local `.env` file (not committed)
- Docker Compose loads configuration directly from the `.env` file

This approach keeps the repository secure while remaining easy to configure locally.

---

### Airflow authentication note (Docker Compose)

When running Airflow with Docker Compose, a **static JWT secret key** is explicitly
defined via environment variables.

This is required to avoid authentication issues related to dynamic secret generation
when containers are recreated, as documented in the following Airflow issue:

https://github.com/apache/airflow/issues/49646

Defining a single, consistent JWT secret ensures stable authentication behavior
across Airflow components in a local Docker-based setup.

## 📊 Target Analytical Use Cases

- Real-time bike availability monitoring
- Detection of high-demand / low-supply areas
- Territorial analysis by commune
- Correlation between population density and bike usage
- Time-series analysis by station or geographic zone

---

## 🚧 Project Status

### ✅ Implemented

- Vélib’ data ingestion pipelines with Airflow
- Centralized PostgreSQL + PostGIS database
- Raw and staging data models
- DBT project structure
- Docker-based local environment

### 🔜 In Progress / Planned

- DBT analytical models (facts & aggregates)
- Spatial enrichment with population and administrative boundaries
- Geospatial dashboards in Superset
- DBT tests and lightweight CI


> ⚠️ This project is **intentionally iterative** and reflects a realistic professional data development workflow.
---

## 📁 Repository structure
```text
.
├── airflow/              # Vélib’ ingestion DAGs
├── dbt/                  # DBT analytical models
├── postgres/             # PostGIS initialization & geospatial assets
│   ├── init/
│   └── data/
├── docker-compose.yml
└── README.md
```

---

## 🚧 To do
- fixing dbt dag bug

## 👤 Auteur

**Vincent Crozet**  
Data Analyst / Scientist, expert SIG  
📍 Cotonou, Benin  


🔗 LinkedIn : www.linkedin.com/in/vincent-crozet

---

## 📝 Note

This repository is a **technical portfolio project**.
It is not intended to be deployed as-is in production, but to demonstrate:
a realistic data architecture
geospatial data modeling skills
modern data engineering tooling
an analytics-driven approach to mobility data
