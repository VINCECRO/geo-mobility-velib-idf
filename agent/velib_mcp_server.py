"""
MCP Server — Vélib PostGIS database (read-only).

Exposes two MCP primitives:
  - tool    : query_velib(sql)  → executes a SELECT on the PostGIS database
  - resource: schema://velib    → annotated schema of the marts tables

Usage (stdio, launched by the agent):
    python velib_mcp_server.py

Required environment variables:
    POSTGIS_VELIB_HOST
    POSTGIS_VELIB_PORT
    POSTGIS_VELIB_DB
    POSTGIS_VELIB_USER
    POSTGIS_VELIB_PASSWORD
"""

import json
import os
import re

import psycopg2
import psycopg2.extras
from fastmcp import FastMCP

mcp = FastMCP("velib-db")

# ---------------------------------------------------------------------------
# Connection
# ---------------------------------------------------------------------------

def _get_conn() -> psycopg2.extensions.connection:
    return psycopg2.connect(
        host=os.environ["POSTGIS_VELIB_HOST"],
        port=int(os.environ["POSTGIS_VELIB_PORT"]),
        dbname=os.environ["POSTGIS_VELIB_DB"],
        user=os.environ["POSTGIS_VELIB_USER"],
        password=os.environ["POSTGIS_VELIB_PASSWORD"],
        connect_timeout=10,
    )


# ---------------------------------------------------------------------------
# SQL guard: SELECT only, LIMIT required
# ---------------------------------------------------------------------------

_FORBIDDEN = re.compile(
    r"\b(DROP|INSERT|UPDATE|DELETE|TRUNCATE|CREATE|ALTER|GRANT|REVOKE|COPY|VACUUM)\b",
    re.IGNORECASE,
)
_SENSITIVE_TABLES = re.compile(r"\b(ab_user|ab_role|ab_permission)\b", re.IGNORECASE)


def _validate(sql: str) -> str | None:
    """Returns an error message if the query is invalid, None otherwise."""
    if m := _FORBIDDEN.search(sql):
        return f"Forbidden keyword '{m.group()}' — SELECT only."
    if _SENSITIVE_TABLES.search(sql):
        return "Access denied to this table."
    if "LIMIT" not in sql.upper():
        return "Query must include a LIMIT clause (recommended max: 100)."
    return None


# ---------------------------------------------------------------------------
# Tool: query_velib
# ---------------------------------------------------------------------------

@mcp.tool()
def query_velib(sql: str) -> str:
    """
    Execute a read-only SQL SELECT query on the Vélib PostGIS database.

    Rules:
    - SELECT only — no DML or DDL.
    - Must include a LIMIT clause.
    - Geometries are in EPSG:4326.
    - Database timezone: Europe/Paris.
    - Main schema: marts  (dim_station, fct_station_availability)

    Before writing a query, read the 'schema://velib' resource to
    understand the grain, SCD2 joins, and business rules.

    Returns: JSON array (list of dicts) or error message.
    """
    if err := _validate(sql):
        return f"SQL validation error: {err}"

    try:
        conn = _get_conn()
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute("SET TIME ZONE 'Europe/Paris'")
            cur.execute(sql)
            rows = cur.fetchall()
        conn.close()
    except psycopg2.OperationalError as e:
        return f"Connection error: {e}"
    except psycopg2.Error as e:
        return f"Database error: {e.pgerror or str(e)}"

    if not rows:
        return "Query returned 0 rows."

    return json.dumps([dict(r) for r in rows], default=str, ensure_ascii=False, indent=2)


# ---------------------------------------------------------------------------
# Resource: schema://velib
# ---------------------------------------------------------------------------

@mcp.resource("schema://velib")
def velib_schema() -> str:
    """
    Full Vélib database schema with business annotations.
    Read this BEFORE writing any SQL query.
    """
    return """
# Vélib Schema — marts layer

## marts.dim_station  —  station metadata (SCD Type 2)

Grain: one row per (station_id, valid_from) — full history of changes.

⚠️  SCD2 JOINS
    Current state only:
        WHERE current_validity = TRUE
    Temporal join with fct_station_availability:
        ON  f.station_id = d.station_id
        AND f.extracted_at BETWEEN d.valid_from AND COALESCE(d.valid_to, NOW())

Key columns:
    station_id                TEXT         Natural key (Vélib API)
    station_code              TEXT         Short code
    station_name              TEXT         Human-readable name
    capacity                  INT          Total number of docks
    station_size_category     TEXT         'Q1-Small' | 'Q2-Medium' | 'Q3-Large' | 'Q4-XLarge'
    geometry                  GEOMETRY     Point EPSG:4326 (lon, lat)
    commune_name              TEXT         Municipality (IDF)
    commune_code              TEXT         INSEE code
    commune_population        INT          Municipality population
    department_number         TEXT         e.g. '75', '92', '93'
    population_500m           FLOAT        Estimated population within 500m radius (Meta 30m grid)
    local_population_per_bike FLOAT        population_500m / capacity
    population_density_500m   TEXT         'Peripheral' | 'Suburban' | 'Urban' | 'Urban Core'
    rental_methods            TEXT[]       Array of accepted payment methods
    valid_from                TIMESTAMPTZ  SCD2 validity start
    valid_to                  TIMESTAMPTZ  SCD2 validity end (NULL if current version)
    current_validity          BOOLEAN      TRUE = active version


## marts.fct_station_availability  —  availability snapshots

Grain: one row per (station_id, extracted_at) — snapshot every ~5 minutes.
Volume: ~1,400 stations × 288 snapshots/day ≈ 400,000 rows/day.

⚠️  AGGREGATION
    Never COUNT(*) without GROUP BY over a time range.
    For hourly stats: AVG(availability_rate) GROUP BY station_id, hour_of_day.

Key columns:
    station_id                      TEXT
    extracted_at                    TIMESTAMPTZ  Snapshot timestamp (Europe/Paris)
    day_date                        DATE
    hour_of_day                     INT          0–23
    station_name                    TEXT
    last_reported_at                TIMESTAMPTZ

    -- Station availability
    num_bikes_available             INT
    mechanical_available            INT
    ebikes_available                INT
    num_docks_available             INT
    capacity                        INT

    -- Neighbors within 500m radius (same snapshot)
    neighbor_bikes_available_500m   INT
    neighbor_docks_available_500m   INT
    neighbor_station_count_500m     INT
    total_bikes_accessible_500m     INT          station + neighbors
    total_docks_accessible_500m     INT

    -- KPIs (0 to 100)
    availability_rate               NUMERIC      num_bikes / capacity × 100
    dock_availability_rate          NUMERIC      num_docks / capacity × 100

    -- Critical flags (threshold: < 10% of capacity)
    is_bike_critical                BOOLEAN
    is_dock_critical                BOOLEAN
    is_critical                     BOOLEAN      bike OR dock critical

    -- Operational state
    is_fully_operational            BOOLEAN      installed AND renting AND returning
    is_installed                    INT          1 / 0
    is_renting                      INT          1 / 0
    is_returning                    INT          1 / 0

    -- Temporal enrichment
    day_of_week                     INT          0 = Sunday … 6 = Saturday
    day_name                        TEXT         'Monday' etc.
    day_type                        TEXT         'Weekday' | 'Weekend'
    time_period                     TEXT         'Morning Rush'(7-9h) | 'Evening Rush'(17-19h) | 'Night' | 'Off-Peak'

    -- Geography (denormalized from current dim_station version)
    commune_name                    TEXT
    commune_code                    TEXT
    department_number               TEXT
    population_500m                 FLOAT
    population_density_500m         TEXT
    station_size_category           TEXT
    geometry                        GEOMETRY     EPSG:4326


## Common query patterns

-- Latest available snapshot
SELECT MAX(extracted_at) FROM marts.fct_station_availability;

-- Critical stations at the latest snapshot
SELECT station_name, commune_name, availability_rate
FROM marts.fct_station_availability
WHERE extracted_at = (SELECT MAX(extracted_at) FROM marts.fct_station_availability)
  AND is_critical = TRUE
ORDER BY availability_rate ASC
LIMIT 20;

-- Average availability by hour over 7 days
SELECT day_date, hour_of_day, ROUND(AVG(availability_rate), 1) AS avg_avail
FROM marts.fct_station_availability
WHERE extracted_at >= NOW() - INTERVAL '7 days'
GROUP BY day_date, hour_of_day
ORDER BY day_date, hour_of_day
LIMIT 200;

-- Municipality ranking by availability (current snapshot)
SELECT commune_name,
       COUNT(*)                          AS nb_stations,
       ROUND(AVG(availability_rate), 1)  AS avg_avail,
       SUM(CASE WHEN is_critical THEN 1 ELSE 0 END) AS nb_critical
FROM marts.fct_station_availability
WHERE extracted_at = (SELECT MAX(extracted_at) FROM marts.fct_station_availability)
GROUP BY commune_name
ORDER BY avg_avail ASC
LIMIT 20;
"""


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    mcp.run()
