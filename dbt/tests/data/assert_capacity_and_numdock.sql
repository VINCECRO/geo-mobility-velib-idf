-- dbt/tests/data/assert_capacity_and_numdocks.sql
{{ config(
    severity='warn',
    store_failures=true,
    tags=['data_quality']
) }}

-- Get latest Station SCD
WITH latest_extraction AS (
    SELECT 
        MAX(extracted_at) AS max_extracted_at
    FROM {{ source('velib', 'stations_scd') }} AS s
    ),

last_station_scd AS (
    SELECT s.station_id,
        s.capacity
    FROM {{ source('velib', 'stations_scd') }} AS s
    JOIN latest_extraction le
        ON s.extracted_at = le.max_extracted_at
    ),

-- Get latest Station Status
latest_status_extraction AS (
    SELECT 
        MAX(extracted_at) AS max_extracted_at
    FROM {{ source('velib', 'station_status') }} AS s
    ),

latest_status_status AS (
    SELECT s.station_id,
        s.num_docks_available
    FROM {{ source('velib', 'station_status') }} AS s
    JOIN latest_status_extraction le
        ON s.extracted_at = le.max_extracted_at
    ),

-- Check equality of num_docks_available with capacity
mismatch_case AS (
    SELECT sstatus.station_id ,
            sstatus.num_docks_available,
            sscd.capacity
    FROM latest_status_status AS sstatus
    JOIN last_station_scd AS sscd
    ON sstatus.station_id=sscd.station_id
    WHERE sstatus.num_docks_available!=sscd.capacity
)


SELECT 
    *,
    CONCAT(
        'Mismatch: ', 'station id', station_id, ','
        'docks_available', num_docks_available, ') ','≠ ',
        'capacity', capacity
    ) AS error_message
FROM mismatch_case

