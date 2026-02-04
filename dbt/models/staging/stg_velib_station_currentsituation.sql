-- dbt/models/staging/stg_velib_station_currentsituation.sql
WITH latest_extraction AS (
    SELECT 
        MAX(extracted_at) AS max_extracted_at
    FROM {{ source('velib', 'stations_scd') }} AS s
)

SELECT s.id,
    s.station_id,
    s.station_code,
    s.name,
    s.capacity,
    ST_SetSRID(ST_MakePoint(s.lon, s.lat), 4326),
    s.rental_methods,
    s.station_opening_hours,
    s.valid_from,
    s.last_updated_at,
    s.extracted_at
FROM {{ source('velib', 'stations_scd') }} AS s
JOIN latest_extraction le
    ON s.extracted_at = le.max_extracted_at