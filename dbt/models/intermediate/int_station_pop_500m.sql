-- dbt/models/marts/core/int_station_pop_500m.sql
{{
  config(
    materialized='incremental',
    unique_key=['station_id', 'valid_from'],
    on_schema_change='sync_all_columns',
    indexes=[
      {'columns': ['station_id', 'valid_from'], 'unique': true}
    ]
  )
}}

WITH stations_lambert AS (
    SELECT
        station_id,
        valid_from,
        current_validity,
        ST_Transform(geometry, 2154) AS geometry_2154
    FROM {{ ref('stg_velib_station_historical') }}

    {% if is_incremental() %}
        -- Only new SCD2 versions not yet computed
        WHERE valid_from > (SELECT MAX(valid_from) FROM {{ this }})
    {% endif %}
),

pop_points AS (
    SELECT
        population,
        geometry
    FROM {{ ref('stg_geo_pop_idf') }}
)

SELECT
    s.station_id,
    s.valid_from,
    s.current_validity,
    COALESCE(SUM(p.population), 0) AS population_500m,
    COUNT(p.population)            AS pop_point_count_500m
FROM stations_lambert s
LEFT JOIN pop_points p
    ON ST_DWithin(s.geometry_2154, p.geometry, 500)
GROUP BY s.station_id, s.valid_from, s.current_validity