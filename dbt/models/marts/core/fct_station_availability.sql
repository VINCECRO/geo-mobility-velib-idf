-- dbt/models/marts/core/fct_station_availability.sql

{{
  config(
    materialized='incremental',
    unique_key=['station_id', 'extracted_at'],
    on_schema_change='sync_all_columns',
    indexes=[
      {'columns': ['station_id', 'extracted_at'], 'unique': true},
      {'columns': ['extracted_at']},
      {'columns': ['station_id']},
      {'columns': ['day_date']}
    ],
    partition_by={
      'field': 'extracted_at',
      'data_type': 'timestamp',
      'granularity': 'day'
    }
  )
}}

WITH source_data AS (
    SELECT
        station_id,
        station_code,
        extracted_at,
        last_reported_at,
        DATE(extracted_at)              AS day_date,
        EXTRACT(HOUR FROM extracted_at) AS hour_of_day,
        num_bikes_available,
        mechanical_available,
        ebikes_available,
        num_docks_available,
        is_installed,
        is_renting,
        is_returning,
        rental_methods
    FROM {{ ref('stg_velib_station_status') }}

    {% if is_incremental() %}
        WHERE extracted_at > (SELECT MAX(extracted_at) FROM {{ this }})
    {% endif %}
),

-- Enrichissement statique depuis dim_station (version SCD2 courante)
dim_enriched AS (
    SELECT
        sd.*,
        ds.capacity,
        ds.station_name,
        ds.commune_name,
        ds.commune_code,
        ds.department_number,
        ds.commune_population,
        ds.population_500m,
        ds.population_density_500m,
        ds.station_size_category,
        ds.geometry
    FROM source_data sd
    LEFT JOIN {{ ref('dim_station') }} ds
        ON  sd.station_id       = ds.station_id
        AND ds.current_validity = true
),

enriched_data AS (
    SELECT
        de.*,

        -- Disponibilité des voisines au même snapshot (depuis int_station_status_within_500m)
        COALESCE(nb.neighbor_bikes_available_500m, 0)       AS neighbor_bikes_available_500m,
        COALESCE(nb.neighbor_mechanical_available_500m, 0)  AS neighbor_mechanical_available_500m,
        COALESCE(nb.neighbor_ebikes_available_500m, 0)      AS neighbor_ebikes_available_500m,
        COALESCE(nb.neighbor_docks_available_500m, 0)       AS neighbor_docks_available_500m,
        COALESCE(nb.neighbor_station_count_500m, 0)         AS neighbor_station_count_500m,

        -- Totaux accessibles (station propre + voisines)
        de.num_bikes_available + COALESCE(nb.neighbor_bikes_available_500m, 0) AS total_bikes_accessible_500m,
        de.num_docks_available + COALESCE(nb.neighbor_docks_available_500m, 0) AS total_docks_accessible_500m,

        -- KPIs station propre
        CASE
            WHEN de.capacity > 0
            THEN de.num_bikes_available::NUMERIC / de.capacity * 100
            ELSE 0
        END AS availability_rate,

        CASE
            WHEN de.capacity > 0
            THEN de.num_docks_available::NUMERIC / de.capacity * 100
            ELSE 0
        END AS dock_availability_rate,

        -- Flags état critique
        CASE WHEN de.num_bikes_available < de.capacity * 0.1 THEN true ELSE false END AS is_bike_critical,
        CASE WHEN de.num_docks_available < de.capacity * 0.1 THEN true ELSE false END AS is_dock_critical,
        CASE
            WHEN de.num_bikes_available < de.capacity * 0.1
              OR de.num_docks_available < de.capacity * 0.1
            THEN true ELSE false
        END AS is_critical,

        -- Enrichissement temporel
        EXTRACT(DOW FROM de.extracted_at) AS day_of_week,
        TO_CHAR(de.extracted_at, 'Day')   AS day_name,
        CASE
            WHEN EXTRACT(DOW FROM de.extracted_at) IN (0, 6) THEN 'Weekend'
            ELSE 'Weekday'
        END AS day_type,
        CASE
            WHEN EXTRACT(HOUR FROM de.extracted_at) BETWEEN 7  AND 9  THEN 'Morning Rush'
            WHEN EXTRACT(HOUR FROM de.extracted_at) BETWEEN 17 AND 19 THEN 'Evening Rush'
            WHEN EXTRACT(HOUR FROM de.extracted_at) BETWEEN 22 AND 6  THEN 'Night'
            ELSE 'Off-Peak'
        END AS time_period,

        -- Flag opérationnel
        CASE
            WHEN de.is_installed = 1
             AND de.is_renting   = 1
             AND de.is_returning = 1
            THEN true ELSE false
        END AS is_fully_operational

    FROM dim_enriched de
    LEFT JOIN {{ ref('int_station_status_within_500m') }} nb
        ON  nb.station_id   = de.station_id
        AND nb.extracted_at = de.extracted_at
)

SELECT
    -- Clés
    station_id,
    extracted_at,
    day_date,

    -- Identifiants
    station_code,
    station_name,

    -- Timestamps
    last_reported_at,
    hour_of_day,

    -- Disponibilité station propre
    num_bikes_available,
    mechanical_available,
    ebikes_available,
    num_docks_available,
    capacity,

    -- Disponibilité voisines 500m (même snapshot)
    neighbor_bikes_available_500m,
    neighbor_mechanical_available_500m,
    neighbor_ebikes_available_500m,
    neighbor_docks_available_500m,
    neighbor_station_count_500m,

    -- Totaux accessibles (station + voisines)
    total_bikes_accessible_500m,
    total_docks_accessible_500m,

    -- KPIs calculés
    ROUND(availability_rate, 2)      AS availability_rate,
    ROUND(dock_availability_rate, 2) AS dock_availability_rate,

    -- Flags état
    is_bike_critical,
    is_dock_critical,
    is_critical,
    is_fully_operational,

    -- États opérationnels
    is_installed,
    is_renting,
    is_returning,

    -- Enrichissement temporel
    day_of_week,
    day_name,
    day_type,
    time_period,

    -- Enrichissement géographique (statique)
    commune_name,
    commune_code,
    commune_population,
    department_number,
    population_500m,
    population_density_500m,
    station_size_category,
    geometry,

    -- Métadonnées
    rental_methods,

    -- Audit
    CURRENT_TIMESTAMP AS dbt_updated_at

FROM enriched_data