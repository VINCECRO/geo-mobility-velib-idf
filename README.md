# Vélib' Geo-Mobility Analytics Platform — Île-de-France

> **End-to-end data engineering pipeline** — real-time ingestion · SCD Type 2 · PostGIS spatial joins · dbt layered modeling · geospatial ML

<br>

## Overview

A **production-grade data platform** for Vélib' bike-sharing analytics across the Île-de-France region. The project covers the full data lifecycle: real-time API ingestion every 5 minutes, historized station metadata with SCD Type 2, a fully layered dbt transformation stack (staging → intermediate → marts), geospatial enrichment with PostGIS spatial joins and high-resolution population data, ML-based territory clustering, and BI visualization with Apache Superset.

Designed as a **technical portfolio demonstrator**, it applies patterns typically found in professional data teams — distributed Airflow orchestration, hash-based change detection, SCD2-aware spatial aggregation, incremental materialization with `delete+insert` strategy, and custom dbt tests for data quality enforcement.

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
│         CeleryExecutor · Redis broker · Python 3.12         │
│                                                             │
│  velib_extract_ingestion_dag  (*/5 * * * *)                 │
│    extract_station ──► load_stations  (SCD2 upsert)         │
│    extract_status  ──► load_status    (append-only)         │
│                                                             │
│  dbt_dag  (:03 and :33 past each hour)                      │
│    ExternalTaskSensor ──► dbt run ──► dbt test              │
│                       ──► dbt docs generate                 │
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
│                                                             │
│  staging/                                                   │
│    stg_velib_station_current     ← SCD2 filter current only │
│    stg_velib_station_historical  ← full SCD2 history        │
│    stg_velib_station_status      ← incremental (del+insert) │
│    stg_geo_communes_idf          ← CRS transform → 4326     │
│    stg_geo_pop_communes          ← commune population       │
│    stg_geo_pop_idf               ← 30m grid + GiST index    │
│                                                             │
│  intermediate/                                              │
│    int_station_current_geo_enriched   ← ST_Within commune   │
│    int_station_historical_geo_enriched← SCD2-aware commune  │
│    int_station_pop_500m               ← ST_DWithin 500m pop │
│    int_station_status_with_capacity   ← SCD2 capacity join  │
│    int_station_status_within_500m     ← real-time neighbor  │
│    int_station_status_hourly          ← hourly aggregation  │
│                                                             │
│  marts/core/                                                │
│    dim_station           ← enriched SCD2 dimension          │
│    fct_station_availability ← fact table w/ 500m context   │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│              Visualization Layer                             │
│   Apache Superset — geospatial dashboards, Redis cache      │
│   R/Shiny        — custom analytics platform (planned)      │
└─────────────────────────────────────────────────────────────┘
```

---

## Technical Highlights

### SCD Type 2 with hash-based change detection

Station metadata (location, capacity, name) is tracked with a full **Slowly Changing Dimension Type 2** strategy, implemented from scratch without any external SCD framework.

Each payload is fingerprinted with an MD5 hash over `(station_id, station_code, name, capacity, lat, lon)`. On each 5-minute cycle, the pipeline:
- **inserts** a new row if the station is new,
- **closes** the active version (`valid_to`, `current_validity = FALSE`) and **opens** a new one when the hash changes,
- **updates only `last_extracted_at`** if the hash is unchanged (heartbeat pattern, preserving lineage without row bloat).

The database enforces this with a **partial unique index** on `(station_id) WHERE current_validity = TRUE`, guaranteeing exactly one active version per station at all times. Every station relocation, capacity change, or rename is preserved with full temporal validity.

### SCD2-aware spatial joins throughout the transformation layer

The dbt intermediate layer is carefully designed to respect the SCD2 grain at every step. When joining station status snapshots to capacity, geometry, or population data, joins always apply the temporal predicate:

```sql
ON  sr.station_id   = scd.station_id
AND sr.extracted_at >= scd.valid_from
AND (scd.valid_to IS NULL OR sr.extracted_at < scd.valid_to)
```

This ensures that if a station was physically relocated, historical status snapshots are joined to the geometry that was valid *at that point in time* — not the current one.

### Real-time neighbor availability at each snapshot (`int_station_status_within_500m`)

One of the most technically involved models: for **each status snapshot**, it computes the total bikes and docks available within 500m of the station across all neighbor stations captured at that **same exact timestamp**.

This requires a three-way join: station status × station geometry (SCD2-resolved) × neighbor station geometry (also SCD2-resolved), filtered by `ST_DWithin(geometry_lambert, neighbor_geometry_lambert, 500)`. The model is materialized **incrementally** with a composite unique index on `(station_id, extracted_at)` and three additional indexes. All coordinates are projected to Lambert-93 (EPSG:2154) to use metric distances accurately.

This feeds directly into `fct_station_availability` where each row exposes both the station's own availability and its neighborhood context — enabling queries like *"was this station critically empty despite abundant supply nearby?"*

### High-resolution population aggregation at 500m (`int_station_pop_500m`)

For each station version (SCD2 grain: `station_id + valid_from`), the model sums all population points from Meta's High Resolution Population Density dataset (30m grid, CSTB 2019) within a 500m buffer. The geometry for each station version is resolved from its SCD2 record, so a relocated station gets a recomputed population score. Incremental materialization ensures only new SCD2 versions trigger a recalculation.

### `dim_station` — a fully enriched SCD2 dimension

The station dimension preserves the full history of station versions while enriching each with:
- **Commune** name, INSEE code, and population via `ST_Within` join,
- **Local population** within 500m from the high-resolution point grid,
- **NTILE-based capacity quartile** (`Q1-Small` to `Q4-XLarge`), computed on current stations and applied consistently to all versions,
- **Population density category** (`Peripheral` / `Suburban` / `Urban` / `Urban Core`), derived from current thresholds via `CROSS JOIN` with quartile CTEs,
- **`local_population_per_bike`** ratio: inhabitants within 500m per dock, a proxy for structural demand pressure.

### `fct_station_availability` — the central analytical fact table

Each row is one status snapshot, enriched with the full station context (capacity, commune, population) from `dim_station` plus 500m neighbor aggregates from `int_station_status_within_500m`. The model computes at grain level:
- `availability_rate` and `dock_availability_rate` (% of capacity),
- `is_bike_critical` / `is_dock_critical` flags (< 10% of capacity),
- `total_bikes_accessible_500m` / `total_docks_accessible_500m` (station + neighbors),
- temporal enrichment: `day_type` (Weekday/Weekend), `time_period` (Morning Rush, Evening Rush, Night, Off-Peak).

Materialized incrementally, partitioned by day on `extracted_at`, with four indexes including a composite unique on `(station_id, extracted_at)`.

### Hourly aggregation with operational KPIs (`int_station_status_hourly`)

Aggregates 5-minute snapshots into hourly slots via `DATE_TRUNC`. Per slot, it computes min/avg/max for bikes, docks, mechanical, and e-bikes, plus:
- `avg_bike_availability_pct`,
- `critical_bike_time_pct` and `critical_dock_time_pct` — the **fraction of the hour** the station spent in critical state (< 10% capacity),
- `is_complete_hour` flag (≥ 10 snapshots),
- temporal annotations: `hour_of_day`, `day_of_week`, `day_type`, `time_period`.

### Custom dbt tests for data quality

Beyond standard `not_null` / `unique` / `accepted_values`, the project includes:

**Generic tests (Jinja macros):**
- `columns_must_match(column_a, column_b, tolerance)` — asserts two columns are equal within a numeric tolerance, with a detailed diff message per failing row.
- `sum_must_match(column_a, column_b, column_c)` — asserts `a + b = c`, detecting API inconsistencies in bike type breakdowns.

**Singular data tests:**
- `assert_bike_breakdown_sum` — validates `mechanical_available + ebikes_available = num_bikes_available` on the last 24h. Configured `severity: error`, `store_failures: true`.
- `assert_capacity_and_numdock` — checks `num_bikes_available + num_docks_available = capacity` on the latest snapshot. `severity: warn`.
- `assert_orphan_station_id_bidirectionnal` — performs a **FULL OUTER JOIN** between the latest `stations_scd` and `station_status` extractions, detecting stations present in one table but absent from the other in both directions (`orphan_in_status` / `orphan_in_stations`).

Source freshness is monitored with `warn_after: 15 minutes` and `error_after: 30 minutes` on `station_status`, using `extracted_at` as the loaded field.

### Orchestration with timing-aware DAG dependency

The ingestion DAG runs every 5 minutes. The dbt DAG runs at `:03` and `:33`, offset to let ingestion complete first. A custom `execution_date_fn` resolves the **most recently completed ingestion cycle** dynamically — not a static delta — avoiding race conditions when the two DAGs don't align exactly. The `ExternalTaskSensor` runs in `reschedule` mode (non-blocking) with a 15s poke interval and 3-minute timeout.

### Database initialization and geo-asset loading

The PostGIS database is initialized via a shell script in `docker-entrypoint-initdb.d`, creating the `raw` schema, both tables, all indexes (including the partial unique index for SCD2), and setting the database timezone to `Europe/Paris`.

A dedicated **`loader` container** starts after PostGIS is healthy and auto-discovers all `.gpkg` and `.csv` files in the mounted volume, loading them into the `add_assets` schema via `geopandas.to_postgis()`. Adding new geo-reference datasets is a simple file-drop operation — no SQL migration required.

### Geospatial feature engineering for ML clustering

A standalone pipeline enriches a **50m hexagonal grid** of the Île-de-France petite couronne (depts. 75, 92, 93, 94) with building usage profiles from the BDNB 2025 national database and Meta HRPD population density. Building usages are one-hot encoded and weighted by built surface area (m²), aggregated by 500m centroid buffer in batches of 1,000 grid cells. The result feeds a **KMeans clustering** with `StandardScaler`, producing territory typologies (residential, commercial, mixed-use, peripheral) exported as GeoPackage for PostGIS ingestion.

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
    │   ├── int_station_current_geo_enriched     (ST_Within commune)
    │   ├── int_station_historical_geo_enriched  (SCD2 × commune × pop)
    │   ├── int_station_pop_500m                 (ST_DWithin 500m, incremental)
    │   ├── int_station_status_with_capacity     (SCD2-resolved capacity join)
    │   ├── int_station_status_within_500m       (real-time neighbor, incremental)
    │   └── int_station_status_hourly            (hourly KPIs + critical flags)
    │
    └── marts/core/ (tables)
        ├── dim_station           (SCD2 + NTILE quartiles + pop density category)
        └── fct_station_availability  (fact table, partitioned by day, incremental)
```

---

## Stack

| Layer | Technology |
|---|---|
| Orchestration | Apache Airflow 3.x · CeleryExecutor · Redis |
| Storage | PostgreSQL 15 · PostGIS 3.4 |
| Transformation | dbt 1.8 · dbt-utils 1.1 |
| Geospatial | PostGIS · GeoPandas · BDNB 2025 · Meta HRPD |
| ML | scikit-learn (KMeans · StandardScaler) |
| Visualization | Apache Superset (Redis cache · Gunicorn) · R/Shiny *(planned)* |
| Infrastructure | Docker · Docker Compose |
| Dev tooling | Python 3.12 · UV |

---

## Repository Structure

```
.
├── airflow/
│   ├── Dockerfile                            # Airflow + dbt-postgres image
│   ├── dags/
│   │   ├── velib_ingestion_dag.py            # Extract & load DAG (*/5 min)
│   │   └── velib_dbt_transform.py            # dbt DAG + ExternalTaskSensor
│   ├── extract_Velib_API/
│   │   ├── velib_client.py                   # HTTP client + Paris timezone
│   │   └── velib_parser.py                   # API payload deserializer
│   └── ingest_Velib_API/
│       ├── db_connect.py                     # psycopg2 connection factory
│       ├── ingest_station_SCD2.py            # SCD2 upsert with hash diff
│       └── ingest_station_status.py          # Append-only status writer
│
├── dbt/
│   ├── dbt_project.yml                       # Schema layout + materialization
│   ├── packages.yml                          # dbt-utils 1.1.1
│   ├── profiles.yml                          # env_var-based connection
│   ├── macros/
│   │   └── generate_schema_name.sql          # Custom schema routing macro
│   ├── models/
│   │   ├── sources/                          # 4 source definitions + column tests
│   │   ├── staging/                          # 6 staging models
│   │   ├── intermediate/                     # 6 intermediate models (views)
│   │   └── marts/core/                       # dim_station + fct_station_availability
│   └── tests/
│       ├── generic/                          # columns_must_match, sum_must_match
│       └── data/                             # assert_bike_breakdown_sum
│                                             # assert_capacity_and_numdock
│                                             # assert_orphan_station_id_bidirectionnal
│
├── postgis/
│   ├── init_script/01_Postgis_init.sh        # Schema + tables + indexes
│   └── additional_assets/
│       ├── Dockerfile                        # Geo-asset loader container
│       ├── import_assets.py                  # Auto-discover & load .gpkg/.csv
│       ├── communes_Idf.gpkg                 # IDF commune boundaries
│       └── pop_commune_Idf.gpkg              # Commune-level population
│
├── computing_geoassets/
│   ├── reducting_pop_to_idf.py              # Clip population to IDF communes
│   ├── generating_pop_data.py               # Population GeoDataFrame builder
│   └── Geospatial_clustering.py             # BDNB + population → KMeans
│   # ⚠️ The derived population files (pop_pointwise_idf) are not committed
│   #    due to file size constraints. The scripts above fully reproduce them
│   #    from the original Meta HRPD source data.
│
├── superset/
│   ├── Dockerfile
│   └── superset_config.py                   # Redis cache, geo flags, SQL Lab
│
├── docker-compose-Airflow.yml               # Full stack (Airflow + PostGIS + loader)
├── docker-compose-Superset.yml              # Superset on shared idfm_network
└── pyproject.toml                           # UV-managed dependencies
```

---

## Getting Started

### Prerequisites

- Docker & Docker Compose
- A Vélib' API key from the [IDFM Marketplace](https://prim.iledefrance-mobilites.fr)

### Environment setup

```bash
cp .env.example .env
# Fill in: VELIB_API_KEY, POSTGRES_*, AIRFLOW_*, AIRFLOW_JWT_SECRET, SUPERSET_*
```

> **Note on Airflow JWT:** A static `AIRFLOW_JWT_SECRET` is required to prevent authentication failures when containers are recreated. See [apache/airflow#49646](https://github.com/apache/airflow/issues/49646).

### Launch

```bash
# Start the pipeline stack (Airflow + PostGIS + geo-asset loader)
docker compose -f docker-compose-Airflow.yml up -d

# Start the visualization layer
docker compose -f docker-compose-Superset.yml up -d
```

| Service | URL |
|---|---|
| Airflow UI | http://localhost:8080 |
| dbt docs | http://localhost:8001 |
| Superset | http://localhost:8088 |

### Geospatial ML assets (optional)

Download BDNB 2025 building data for depts. 75, 92, 93, 94 from [bdnb.io](https://bdnb.io/download/) and Meta HRPD population CSV from [HDX](https://data.humdata.org/dataset/france-high-resolution-population-density-maps-demographic-estimates), then:

```bash
uv run python computing_geoassets/reducting_pop_to_idf.py
uv run python computing_geoassets/Geospatial_clustering.py
```

---

## Project Status

| Component | Status |
|---|---|
| Airflow ingestion DAGs | ✅ Operational |
| SCD Type 2 station tracking | ✅ Operational |
| Station status time series | ✅ Operational |
| PostgreSQL + PostGIS setup | ✅ Operational |
| Geo-asset loader (Docker) | ✅ Operational |
| dbt staging models (×6) | ✅ Operational |
| dbt intermediate models (×6) | ✅ Operational |
| dbt mart models (dim + fct) | ✅ Operational |
| Custom dbt tests (generic + singular) | ✅ Operational |
| Source freshness monitoring | ✅ Operational |
| Geospatial ML clustering pipeline | ✅ Operational |
| Superset geospatial dashboards | 🔄 In progress |
| R/Shiny custom dashboard platform | 📋 Planned |
| CI / automated dbt test pipeline | 📋 Planned |

---

## Analytical Use Cases

The platform is designed to answer questions such as:

- Which stations are structurally undersupplied relative to surrounding population density?
- At which times and locations does critical unavailability occur — and is supply available nearby within 500m?
- How has the Vélib' network evolved over time (station additions, relocations, capacity changes)?
- What is the ratio of local inhabitants to available docks per station, and how does it cluster by territory type?
- Which communes show the highest correlation between rush-hour demand and supply shortage?

---

## Author

**Vincent Crozet** — Data Engineer / Analyst · GIS Expert  
📍 Cotonou, Benin  
🔗 [linkedin.com/in/vincent-crozet](https://www.linkedin.com/in/vincent-crozet)

---

*This repository is a portfolio project demonstrating realistic data engineering patterns, geospatial modeling, and analytics-driven pipeline design. It is not intended for direct production deployment.*