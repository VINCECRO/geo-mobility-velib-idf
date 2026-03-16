# Vélib' Geo-Mobility Analytics Platform — Île-de-France

![Python](https://img.shields.io/badge/Python-3.12-3776AB?logo=python&logoColor=white)
![R](https://img.shields.io/badge/R-Shiny-276DC3?logo=r&logoColor=white)
![dbt](https://img.shields.io/badge/dbt-1.8-FF694B?logo=dbt&logoColor=white)
![Airflow](https://img.shields.io/badge/Airflow-3.x-017CEE?logo=apacheairflow&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-15+PostGIS-4169E1?logo=postgresql&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)

> End-to-end analytics platform on the Vélib' bike-sharing network of Île-de-France — real-time ingestion, SCD Type 2 historization, PostGIS geospatial modeling, dbt layered transformation, R/Shiny dashboards, and a natural-language LLM agent to query the data.

---

## Screenshots

<!-- SCREENSHOT 1 : Global view dashboard (KPI cards + Leaflet map) -->
<!-- Suggested filename : screenshot_overview.png -->
![Global view — network KPIs and station map](https://raw.githubusercontent.com/VINCECRO/geo-mobility-velib-idf/main/img/screenshot_overview.png)

<!-- SCREENSHOT 2 : Commune-level geo module (Leaflet + time series chart) -->
<!-- Suggested filename : screenshot_geo.png -->
![Commune analysis — station map and availability time series](https://raw.githubusercontent.com/VINCECRO/geo-mobility-velib-idf/main/img/screenshot_geo.png)

<!-- SCREENSHOT 3 : DAG monitoring (waffle chart) -->
<!-- Suggested filename : screenshot_dag.png -->
![DAG monitoring — Airflow run history](https://raw.githubusercontent.com/VINCECRO/geo-mobility-velib-idf/main/img/screenshot_dag.png)

<!-- SCREENSHOT 4 : LLM Agent chat (question + SQL block in response) -->
<!-- Suggested filename : screenshot_agent.png -->
![LLM Agent — natural language query with auto-generated SQL](https://raw.githubusercontent.com/VINCECRO/geo-mobility-velib-idf/main/img/screenshot_agent.png)

---

## Overview

This project builds a complete analytics platform on the Vélib' open API, covering the full data lifecycle from raw ingestion to decision-support dashboards.

The primary goal is **analytical**: understanding availability patterns, supply/demand imbalances, and network evolution across the Île-de-France territory. The engineering layer (Airflow, dbt, PostGIS, Docker) is built to production-grade standards, but the value delivered is analytical — answering real operational questions about bike-sharing supply.

**Key capabilities:**
- Real-time station status captured every 5 minutes with full temporal history
- Station metadata tracked with SCD Type 2 — every relocation and capacity change is preserved
- Geospatial enrichment: commune boundaries, population density at 500m resolution (Meta HRPD 30m grid)
- Layered dbt transformation stack from raw to analytical marts
- Interactive R/Shiny dashboards: global network view, commune drill-down, DAG monitoring, SQL explorer
- Natural language agent (LLM + MCP) for ad-hoc querying of the PostGIS database

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Vélib' Open API                          │
│       (IDFM Marketplace — station_information + status)      │
└──────────────────────────┬──────────────────────────────────┘
                           │  every 5 min
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                   Apache Airflow 3.x                         │
│                                                             │
│  velib_ingestion_dag  (*/5 * * * *)                         │
│    extract_station ──► load_stations  (SCD2 upsert)         │
│    extract_status  ──► load_status    (append-only)         │
│                                                             │
│  dbt_dag  (:03 and :33 past each hour)                      │
│    ExternalTaskSensor ──► dbt run ──► dbt test              │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│            PostgreSQL 15 + PostGIS 3.4                       │
│                                                             │
│  Schema: raw                                                │
│    stations_scd      ← SCD2 with MD5 hash diff             │
│    station_status    ← append-only time series (5 min)      │
│                                                             │
│  Schema: add_assets  (loaded at container startup)          │
│    communes_idf      ← IDF commune boundaries (EPSG:4326)   │
│    pop_commune_idf   ← commune-level population             │
│    pop_pointwise_idf ← Meta HRPD 30m grid (EPSG:2154)       │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                        dbt                                   │
│    staging → intermediate → marts/core                      │
│    dim_station (SCD2 + geo enrichment)                      │
│    fct_station_availability (incremental, ~400k rows/day)   │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│              Visualization & Analytics Layer                 │
│   R/Shiny     — dashboards (overview, commune, DAG, agent)  │
│   LLM Agent   — FastAPI + MCP + Groq/Qwen3-32b              │
└─────────────────────────────────────────────────────────────┘
```

---

## Technical Highlights

### SCD Type 2 with hash-based change detection

Station metadata (location, capacity, name) is tracked with a full **Slowly Changing Dimension Type 2** strategy, implemented from scratch without any external SCD framework.

Each payload is fingerprinted with an MD5 hash over `(station_id, station_code, name, capacity, lat, lon)`. On each 5-minute cycle, the pipeline inserts a new row if the station is new, closes the active version and opens a new one when the hash changes, or updates only the heartbeat timestamp if nothing changed.

A **partial unique index** on `(station_id) WHERE current_validity = TRUE` guarantees exactly one active version per station at all times.

### SCD2-aware spatial joins

Every join between station status and station metadata in the dbt intermediate layer applies the temporal predicate:

```sql
ON  sr.station_id   = scd.station_id
AND sr.extracted_at >= scd.valid_from
AND (scd.valid_to IS NULL OR sr.extracted_at < scd.valid_to)
```

This ensures that if a station was physically relocated, historical status snapshots are joined to the geometry that was valid *at that point in time*.

### Real-time neighbor availability (`int_station_status_within_500m`)

For **each status snapshot**, this model computes total bikes and docks available within 500m across all neighbor stations captured at the **same exact timestamp**. This requires a three-way join (status × station geometry SCD2 × neighbor geometry SCD2), filtered with `ST_DWithin` in Lambert-93 (EPSG:2154) for accurate metric distances. This feeds `fct_station_availability` with a neighborhood context column, enabling queries like *"was this station empty despite abundant supply nearby?"*

### High-resolution population at 500m (`int_station_pop_500m`)

For each station version (SCD2 grain), the model sums population points from Meta's High Resolution Population Density dataset (30m grid) within a 500m buffer. A relocated station gets a recomputed population score automatically. This produces the `local_population_per_bike` ratio — a proxy for structural demand pressure per station.

### `dim_station` — enriched SCD2 dimension

The station dimension preserves the full history while enriching each version with commune name and INSEE code, local population within 500m, NTILE-based capacity quartile (`Q1-Small` to `Q4-XLarge`), population density category (`Peripheral` / `Suburban` / `Urban` / `Urban Core`), and the `local_population_per_bike` ratio.

### Custom dbt tests

Beyond standard `not_null` / `unique` / `accepted_values`, the project includes:

- **`columns_must_match`** — asserts two columns are equal within a numeric tolerance, with a diff message per failing row
- **`sum_must_match`** — asserts `a + b = c`, detecting API inconsistencies in bike type breakdowns
- **`assert_bike_breakdown_sum`** — validates `mechanical + ebikes = total` on the last 24h (severity: error, failures stored)
- **`assert_orphan_station_id_bidirectionnal`** — FULL OUTER JOIN between stations and status, detecting IDs present in one table but absent from the other in both directions

Source freshness is monitored with `warn_after: 15 minutes` / `error_after: 30 minutes`.

### Timing-aware DAG orchestration

The ingestion DAG runs every 5 minutes. The dbt DAG runs at `:03` and `:33`, offset to let ingestion complete. A custom `execution_date_fn` resolves the most recently completed ingestion cycle dynamically — not a static delta — avoiding race conditions. The `ExternalTaskSensor` runs in `reschedule` mode (non-blocking) with a 15s poke interval.

### LLM agent for natural language querying

A natural language agent allows ad-hoc querying of the PostGIS database without writing SQL. The architecture is:

```
Shiny (httr2) → FastAPI → Agent (Groq / Qwen3-32b) → MCP Server → PostGIS
```

The MCP server exposes a single read-only `query_velib` tool with SQL validation (SELECT-only, LIMIT required, sensitive table guard) and a `schema://velib` resource injecting the full annotated schema into the system prompt. The Shiny module provides a chat interface with pre-built question suggestions.

---

## dbt Data Model

```
sources (raw + add_assets schemas)
    │
    ├── staging/
    │   ├── stg_velib_station_current       (filter: current_validity = TRUE)
    │   ├── stg_velib_station_historical    (full SCD2 history)
    │   ├── stg_velib_station_status        (incremental, delete+insert)
    │   ├── stg_geo_communes_idf            (ST_Transform → EPSG:4326)
    │   ├── stg_geo_pop_communes            (commune-level population)
    │   └── stg_geo_pop_idf                 (30m grid, GiST index, EPSG:2154)
    │
    ├── intermediate/ (views)
    │   ├── int_station_current_geo_enriched
    │   ├── int_station_historical_geo_enriched
    │   ├── int_station_pop_500m             (incremental)
    │   ├── int_station_status_with_capacity (SCD2-resolved capacity join)
    │   ├── int_station_status_within_500m   (real-time neighbor, incremental)
    │   └── int_station_status_hourly        (hourly KPIs + critical flags)
    │
    └── marts/core/ (tables)
        ├── dim_station           (SCD2 + NTILE quartiles + pop density)
        └── fct_station_availability  (incremental, partitioned by day)
```

---

## Analytical Use Cases

The platform is designed to answer questions such as:

- Which stations are structurally undersupplied relative to local population density?
- At which times and locations does critical unavailability occur — and is there supply nearby within 500m?
- How has the Vélib' network evolved over time (additions, relocations, capacity changes)?
- What is the ratio of local inhabitants to available docks per station, and how does it vary by territory type?
- Which communes show the highest correlation between rush-hour demand and supply shortage?

---

## Stack

| Layer | Technology |
|---|---|
| Orchestration | Apache Airflow 3.x · CeleryExecutor · Redis |
| Storage | PostgreSQL 15 · PostGIS 3.4 |
| Transformation | dbt 1.8 · dbt-utils 1.1 |
| Geospatial | PostGIS · GeoPandas · Meta HRPD 30m grid |
| Visualization | R/Shiny · bslib · Leaflet · Plotly |
| LLM Agent | Groq API (Qwen3-32b) · FastMCP · FastAPI |
| Infrastructure | Docker · Docker Compose |
| Dev tooling | Python 3.12 · UV · R 4.4 |

---

## Repository Structure

```
.
├── airflow/
│   ├── dags/
│   │   ├── velib_ingestion_dag.py        # Extract & load DAG (*/5 min)
│   │   └── velib_dbt_transform.py        # dbt DAG + ExternalTaskSensor
│   ├── extract_Velib_API/
│   │   ├── velib_client.py               # HTTP client + Paris timezone
│   │   └── velib_parser.py               # API payload deserializer
│   └── ingest_Velib_API/
│       ├── ingest_station_SCD2.py        # SCD2 upsert with hash diff
│       └── ingest_station_status.py      # Append-only status writer
│
├── dbt/
│   ├── models/
│   │   ├── sources/                      # Source definitions + freshness
│   │   ├── staging/                      # 6 staging models
│   │   ├── intermediate/                 # 6 intermediate models (views)
│   │   └── marts/core/                   # dim_station + fct_station_availability
│   └── tests/
│       ├── generic/                      # columns_must_match, sum_must_match
│       └── data/                         # assert_bike_breakdown_sum, assert_orphan_*
│
├── agent/
│   ├── velib_mcp_server.py               # MCP server: query_velib tool + schema resource
│   ├── agent.py                          # Agentic loop (Groq + MCP client)
│   └── api.py                            # FastAPI wrapper (POST /ask)
│
├── shiny/app/
│   ├── modules/
│   │   ├── overview/                     # Global KPIs + station map
│   │   ├── geo/                          # Commune drill-down + time series
│   │   ├── dag/                          # Airflow run monitoring (waffle chart)
│   │   ├── sql_explorer/                 # Interactive SQL query tool
│   │   └── agent/                        # LLM chat interface (httr2 → FastAPI)
│   ├── ui.R
│   └── server.R
│
├── postgis/
│   ├── init_script/01_Postgis_init.sh    # Schema + tables + indexes
│   └── additional_assets/
│       ├── import_assets.py              # Auto-discover & load .gpkg/.csv
│       ├── communes_Idf.gpkg
│       └── pop_commune_Idf.gpkg
│
├── computing_geoassets/
│   ├── reducting_pop_to_idf.py          # Clip Meta HRPD population to IDF communes
│   ├── generating_pop_data.py           # Population GeoDataFrame builder
│   └── Geospatial_clustering.py         # BDNB + population → KMeans clustering (roadmap)
│   # Data sources:
│   #   - Meta High Resolution Population Density (HRPD), 30m grid
│   #     https://data.humdata.org/dataset/france-high-resolution-population-density-maps-demographic-estimates
│   # ⚠️ Derived files (pop_pointwise_idf) not committed due to size.
│   #    Scripts above fully reproduce them from the original sources.
│
├── docker-compose-Airflow.yml
├── docker-compose-Shiny.yml
├── docker-compose-Agent.yml
└── pyproject.toml
```

---

## Getting Started

### Prerequisites

- Docker & Docker Compose
- A Vélib' API key from the [IDFM Marketplace](https://prim.iledefrance-mobilites.fr)
- A Groq API key (free tier sufficient) from [console.groq.com](https://console.groq.com)

### Environment setup

```bash
cp .env.example .env
# Fill in: VELIB_API_KEY, POSTGRES_*, AIRFLOW_*, GROQ_API_KEY
```

> **Note on Airflow JWT:** A static `AIRFLOW_JWT_SECRET` is required to prevent authentication failures when containers are recreated. See [apache/airflow#49646](https://github.com/apache/airflow/issues/49646).

### Launch

```bash
# Pipeline stack: Airflow + PostGIS + geo-asset loader
docker compose -f docker-compose-Airflow.yml up -d

# Dashboard
docker compose -f docker-compose-Shiny.yml up -d

# LLM Agent API
docker compose -f docker-compose-Agent.yml up -d
```

| Service | URL |
|---|---|
| Airflow UI | http://localhost:8080 |
| dbt docs | http://localhost:8001 |
| R/Shiny dashboard | http://localhost:3838 |
| Agent API | http://localhost:8002 |

---

## Project Status

| Component | Status |
|---|---|
| Airflow ingestion DAGs | ✅ Operational |
| SCD Type 2 station tracking | ✅ Operational |
| Station status time series | ✅ Operational |
| PostgreSQL + PostGIS setup | ✅ Operational |
| Geo-asset loader (Docker) | ✅ Operational |
| dbt staging + intermediate + marts | ✅ Operational |
| Custom dbt tests | ✅ Operational |
| Source freshness monitoring | ✅ Operational |
| R/Shiny dashboard (4 modules) | ✅ Operational |
| LLM Agent (MCP + FastAPI) | ✅ Operational |
| CI / automated dbt test pipeline | 📋 Roadmap |

---

## Roadmap

**Agent evaluation framework**
Implement a systematic evaluation of the Text-to-SQL agent: a reference question dataset with expected SQL and result schema, automated scoring (query validity, semantic accuracy, hallucination rate), and comparison across LLM backends.

**Decision-support dashboards**
New analytical module focused on network expansion: identification of under-served zones (high `local_population_per_bike`, low station density), territorial clustering by usage profile, and commune-level ranking for new station placement.

**Geospatial ML pipeline**
A feature engineering pipeline over a 50m hexagonal grid of the Île-de-France petite couronne, enriched with building usage data (BDNB 2025) and Meta HRPD population density, feeding a KMeans clustering to produce territory typologies for network planning.

---

## Author

**Vincent Crozet** — Data Analyst / Data Engineer · GIS  
📍 Cotonou, Benin  
🔗 [linkedin.com/in/vincent-crozet](https://www.linkedin.com/in/vincent-crozet)

---

*Portfolio project demonstrating end-to-end analytics platform design, geospatial modeling, and LLM-augmented data tooling. Not intended for direct production deployment.*