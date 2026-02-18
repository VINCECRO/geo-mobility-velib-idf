-- dbt/models/marts/core/dim_station.sql

{{
  config(
    materialized='table',
    unique_key=['station_id', 'valid_from'],
    indexes=[
      {'columns': ['station_id']},
      {'columns': ['station_id', 'valid_from'], 'unique': True},
      {'columns': ['current_validity']},
      {'columns': ['commune_code']},
      {'columns': ['valid_from', 'valid_to']}
    ]
  )
}}

/*
Granularity    : historical data of stations
Natural key    : station_id + valid_from + valid_to (historique complet)

Enrichissements :
- geographical (Zip code + commune) + commune population: int_station_historical_geo_enriched (SCD2-aware, grain station_id + valid_from
- Population 500m                   : int_station_pop_500m     (SCD2-aware, grain station_id + valid_from)
- Operationnal                      : caracterization with quartile population and capacity
*/

-- Quartile cut of capacity (NTILE applied only on current)
WITH capacity_thresholds AS (
    SELECT
        MAX(CASE WHEN capacity_quartile = 1 THEN capacity END) AS q1_capacity,
        MAX(CASE WHEN capacity_quartile = 2 THEN capacity END) AS q2_capacity,
        MAX(CASE WHEN capacity_quartile = 3 THEN capacity END) AS q3_capacity
    FROM (
        SELECT
            capacity,
            NTILE(4) OVER (ORDER BY capacity) AS capacity_quartile
        FROM {{ ref('stg_velib_station_current') }}
    ) t
),

-- Quartile cut of population within 500m (applied only to current)
population_thresholds AS (
    SELECT
        MAX(CASE WHEN pop_quartile = 1 THEN population_500m END) AS q1_population,
        MAX(CASE WHEN pop_quartile = 2 THEN population_500m END) AS q2_population,
        MAX(CASE WHEN pop_quartile = 3 THEN population_500m END) AS q3_population
    FROM (
        SELECT
            population_500m,
            NTILE(4) OVER (ORDER BY population_500m) AS pop_quartile
        FROM {{ ref('int_station_pop_500m') }}
        WHERE current_validity = TRUE
    ) t
),

geo_enriched AS (
    SELECT
        g.*,
        pop.population_500m,
        pop.pop_point_count_500m,

        -- Ratio population locale 500m / capacité
        CASE
            WHEN pop.population_500m > 0 AND g.capacity > 0
            THEN pop.population_500m::NUMERIC / g.capacity
            ELSE NULL
        END AS local_population_per_bike,

        -- Catégorie de taille : comparaison de la capacité aux seuils actuels
        CASE
            WHEN g.capacity <= ct.q1_capacity THEN 'Q1-Small'
            WHEN g.capacity <= ct.q2_capacity THEN 'Q2-Medium'
            WHEN g.capacity <= ct.q3_capacity THEN 'Q3-Large'
            ELSE 'Q4-XLarge'
        END AS station_size_category,

        -- Densité de population : comparaison de population_500m aux seuils actuels
        CASE
            WHEN pop.population_500m <= pt.q1_population THEN 'Peripheral'
            WHEN pop.population_500m <= pt.q2_population THEN 'Suburban'
            WHEN pop.population_500m <= pt.q3_population THEN 'Urban'
            ELSE 'Urban Core'
        END AS population_density_500m

    FROM {{ ref('int_station_historical_geo_enriched') }} g
    LEFT JOIN {{ ref('int_station_pop_500m') }} pop
        ON  pop.station_id = g.station_id
        AND pop.valid_from  = g.valid_from
    CROSS JOIN capacity_thresholds ct
    CROSS JOIN population_thresholds pt
)

SELECT
    -- Clés
    station_id,
    station_code,
    -- Attributs descriptifs
    name AS station_name,
    capacity,
    station_size_category,
    geometry,
    -- Enrichissement géographique commune
    commune_name,
    commune_code,
    commune_population,
    department_number,
    -- Population locale 500m (statique, haute résolution, SCD2-aware)
    population_500m,
    ROUND(local_population_per_bike, 0)   AS local_population_per_bike,
    population_density_500m,
    -- Métadonnées opérationnelles
    rental_methods,
    -- SCD Type 2
    valid_from,
    valid_to,
    current_validity,
    -- Flags qualité
    CASE WHEN commune_name       IS NOT NULL THEN true ELSE false END AS has_geo_enrichment,
    CASE WHEN commune_population IS NOT NULL THEN true ELSE false END AS has_commune_population,
    CASE WHEN population_500m    > 0         THEN true ELSE false END AS has_local_population_500m

FROM geo_enriched
ORDER BY current_validity DESC, station_id

