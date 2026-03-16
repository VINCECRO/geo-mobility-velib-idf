-- dbt/models/intermediate/int_station_status_within_500m.sql

/*
Compute for each snapshot the available bikes and docks within 500m of the station
*/

{{
  config(
    materialized='incremental',
    unique_key=['station_id', 'extracted_at'],
    on_schema_change='sync_all_columns',
    indexes=[
      {'columns': ['station_id', 'extracted_at'], 'unique': true},
      {'columns': ['extracted_at']},
      {'columns': ['station_id']}
    ]
  )
}}
-----------------------------------------------------------------
-- get every stations SCD with correct natural key
WITH stations_lambert AS (
    SELECT
        station_id,
        valid_from,
        valid_to,
        ST_Transform(geometry, 2154) AS geometry_2154
    FROM {{ ref('stg_velib_station_historical') }}
)
-----------------------------------------------------------------

-----------------------------------------------------------------
SELECT
    st.station_id,
    st.extracted_at,

    -- Available bikes within 500m
    COALESCE(SUM(st_n.num_bikes_available), 0)  AS neighbor_bikes_available_500m,
    COALESCE(SUM(st_n.mechanical_available), 0) AS neighbor_mechanical_available_500m,
    COALESCE(SUM(st_n.ebikes_available), 0)     AS neighbor_ebikes_available_500m,

    -- Available docks within 500m
    COALESCE(SUM(st_n.num_docks_available), 0)  AS neighbor_docks_available_500m,

    -- Nb of station within 500m
    COUNT(st_n.station_id)                       AS neighbor_station_count_500m

FROM {{ ref('stg_velib_station_status') }} st

-- Geometry of the target station at snapshot instant (SCD2)
JOIN stations_lambert s
    ON  s.station_id   = st.station_id
    AND st.extracted_at >= s.valid_from
    AND (s.valid_to IS NULL OR st.extracted_at < s.valid_to)

-- neighbouring station within 500m for a similar snapshot (without the targeted station itself)
JOIN stations_lambert n
    ON  ST_DWithin(s.geometry_2154, n.geometry_2154, 500)
    AND n.station_id != st.station_id
    AND st.extracted_at >= n.valid_from
    AND (n.valid_to IS NULL OR st.extracted_at < n.valid_to)

-- Neighbor station status at the same instant
JOIN {{ ref('stg_velib_station_status') }} st_n
    ON  st_n.station_id   = n.station_id
    AND st_n.extracted_at = st.extracted_at

{% if is_incremental() %}
    WHERE st.extracted_at > (SELECT MAX(extracted_at) FROM {{ this }})
{% endif %}

GROUP BY st.station_id, st.extracted_at