"""
MCP Server — Vélib PostGIS database (read-only).

Expose deux primitives MCP :
  - tool    : query_velib(sql)  → exécute un SELECT sur la base PostGIS
  - resource: schema://velib    → schéma annoté des tables marts

Usage (stdio, lancé par l'agent) :
    python velib_mcp_server.py

Variables d'environnement requises :
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
# Connexion
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
# Guard SQL : SELECT only, LIMIT obligatoire
# ---------------------------------------------------------------------------

_FORBIDDEN = re.compile(
    r"\b(DROP|INSERT|UPDATE|DELETE|TRUNCATE|CREATE|ALTER|GRANT|REVOKE|COPY|VACUUM)\b",
    re.IGNORECASE,
)
_SENSITIVE_TABLES = re.compile(r"\b(ab_user|ab_role|ab_permission)\b", re.IGNORECASE)


def _validate(sql: str) -> str | None:
    """Retourne un message d'erreur si la requête est invalide, None sinon."""
    if m := _FORBIDDEN.search(sql):
        return f"Mot-clé interdit '{m.group()}' — uniquement SELECT."
    if _SENSITIVE_TABLES.search(sql):
        return "Accès refusé à cette table."
    if "LIMIT" not in sql.upper():
        return "La requête doit inclure une clause LIMIT (max conseillé : 100)."
    return None


# ---------------------------------------------------------------------------
# Tool : query_velib
# ---------------------------------------------------------------------------

@mcp.tool()
def query_velib(sql: str) -> str:
    """
    Exécute une requête SQL SELECT en lecture seule sur la base Vélib PostGIS.

    Règles :
    - SELECT uniquement — pas de DML ni DDL.
    - Doit inclure une clause LIMIT.
    - Les géométries sont en EPSG:4326.
    - Fuseau horaire de la base : Europe/Paris.
    - Schéma principal : marts  (dim_station, fct_station_availability)

    Avant d'écrire une requête, lire la ressource 'schema://velib' pour
    comprendre le grain, les jointures SCD2, et les règles métier.

    Retourne : tableau JSON (liste de dicts) ou message d'erreur.
    """
    if err := _validate(sql):
        return f"Erreur de validation SQL : {err}"

    try:
        conn = _get_conn()
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute("SET TIME ZONE 'Europe/Paris'")
            cur.execute(sql)
            rows = cur.fetchall()
        conn.close()
    except psycopg2.OperationalError as e:
        return f"Erreur de connexion : {e}"
    except psycopg2.Error as e:
        return f"Erreur base de données : {e.pgerror or str(e)}"

    if not rows:
        return "La requête a retourné 0 lignes."

    return json.dumps([dict(r) for r in rows], default=str, ensure_ascii=False, indent=2)


# ---------------------------------------------------------------------------
# Resource : schema://velib
# ---------------------------------------------------------------------------

@mcp.resource("schema://velib")
def velib_schema() -> str:
    """
    Schéma complet de la base Vélib avec annotations métier.
    À lire AVANT d'écrire toute requête SQL.
    """
    return """
# Schéma Vélib — couche marts

## marts.dim_station  —  métadonnées des stations (SCD Type 2)

Grain : une ligne par (station_id, valid_from) — historique complet des changements.

⚠️  JOINTURES SCD2
    État courant uniquement :
        WHERE current_validity = TRUE
    Jointure temporelle avec fct_station_availability :
        ON  f.station_id = d.station_id
        AND f.extracted_at BETWEEN d.valid_from AND COALESCE(d.valid_to, NOW())

Colonnes clés :
    station_id                TEXT         Clé naturelle (API Vélib)
    station_code              TEXT         Code court
    station_name              TEXT         Nom lisible
    capacity                  INT          Nombre total de places
    station_size_category     TEXT         'Q1-Small' | 'Q2-Medium' | 'Q3-Large' | 'Q4-XLarge'
    geometry                  GEOMETRY     Point EPSG:4326 (lon, lat)
    commune_name              TEXT         Commune (IDF)
    commune_code              TEXT         Code INSEE
    commune_population        INT          Population de la commune
    department_number         TEXT         ex. '75', '92', '93'
    population_500m           FLOAT        Population estimée dans un rayon 500m (grille Meta 30m)
    local_population_per_bike FLOAT        population_500m / capacity
    population_density_500m   TEXT         'Peripheral' | 'Suburban' | 'Urban' | 'Urban Core'
    rental_methods            TEXT[]       Tableau de méthodes de paiement acceptées
    valid_from                TIMESTAMPTZ  Début de validité SCD2
    valid_to                  TIMESTAMPTZ  Fin de validité SCD2 (NULL si version courante)
    current_validity          BOOLEAN      TRUE = version active


## marts.fct_station_availability  —  snapshots de disponibilité

Grain : une ligne par (station_id, extracted_at) — snapshot toutes les ~5 minutes.
Volume : ~1 400 stations × 288 snapshots/jour ≈ 400 000 lignes/jour.

⚠️  AGRÉGATION
    Ne jamais faire COUNT(*) sans GROUP BY sur une plage temporelle.
    Pour une heure : AVG(availability_rate) GROUP BY station_id, hour_of_day.

Colonnes clés :
    station_id                      TEXT
    extracted_at                    TIMESTAMPTZ  Timestamp du snapshot (Europe/Paris)
    day_date                        DATE
    hour_of_day                     INT          0–23
    station_name                    TEXT
    last_reported_at                TIMESTAMPTZ

    -- Disponibilité station
    num_bikes_available             INT
    mechanical_available            INT
    ebikes_available                INT
    num_docks_available             INT
    capacity                        INT

    -- Voisines dans un rayon 500m (même snapshot)
    neighbor_bikes_available_500m   INT
    neighbor_docks_available_500m   INT
    neighbor_station_count_500m     INT
    total_bikes_accessible_500m     INT          station + voisines
    total_docks_accessible_500m     INT

    -- KPIs (0 à 100)
    availability_rate               NUMERIC      num_bikes / capacity × 100
    dock_availability_rate          NUMERIC      num_docks / capacity × 100

    -- Flags critique (seuil : < 10% de la capacité)
    is_bike_critical                BOOLEAN
    is_dock_critical                BOOLEAN
    is_critical                     BOOLEAN      bike OU dock critique

    -- État opérationnel
    is_fully_operational            BOOLEAN      installée ET louant ET restituant
    is_installed                    INT          1 / 0
    is_renting                      INT          1 / 0
    is_returning                    INT          1 / 0

    -- Enrichissement temporel
    day_of_week                     INT          0 = Dimanche … 6 = Samedi
    day_name                        TEXT         'Monday' etc.
    day_type                        TEXT         'Weekday' | 'Weekend'
    time_period                     TEXT         'Morning Rush'(7-9h) | 'Evening Rush'(17-19h) | 'Night' | 'Off-Peak'

    -- Géographie (dénormalisé depuis dim_station version courante)
    commune_name                    TEXT
    commune_code                    TEXT
    department_number               TEXT
    population_500m                 FLOAT
    population_density_500m         TEXT
    station_size_category           TEXT
    geometry                        GEOMETRY     EPSG:4326


## Patterns de requêtes courants

-- Dernier snapshot disponible
SELECT MAX(extracted_at) FROM marts.fct_station_availability;

-- Stations critiques au dernier snapshot
SELECT station_name, commune_name, availability_rate
FROM marts.fct_station_availability
WHERE extracted_at = (SELECT MAX(extracted_at) FROM marts.fct_station_availability)
  AND is_critical = TRUE
ORDER BY availability_rate ASC
LIMIT 20;

-- Disponibilité moyenne par heure sur 7 jours
SELECT day_date, hour_of_day, ROUND(AVG(availability_rate), 1) AS avg_avail
FROM marts.fct_station_availability
WHERE extracted_at >= NOW() - INTERVAL '7 days'
GROUP BY day_date, hour_of_day
ORDER BY day_date, hour_of_day
LIMIT 200;

-- Classement des communes par disponibilité (snapshot courant)
SELECT commune_name,
       COUNT(*)                          AS nb_stations,
       ROUND(AVG(availability_rate), 1)  AS avg_avail,
       SUM(CASE WHEN is_critical THEN 1 ELSE 0 END) AS nb_critiques
FROM marts.fct_station_availability
WHERE extracted_at = (SELECT MAX(extracted_at) FROM marts.fct_station_availability)
GROUP BY commune_name
ORDER BY avg_avail ASC
LIMIT 20;
"""


# ---------------------------------------------------------------------------
# Entrée
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    mcp.run()
