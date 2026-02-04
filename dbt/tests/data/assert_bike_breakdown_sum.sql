-- dbt/tests/data/assert_bikes_breakdown_sum.sql
{{ config(
    severity='error',
    store_failures=true,
    tags=['data_quality']
) }}

/*
check if mechanical_available + ebikes_available = num_bikes_available
*/

SELECT 
    id,
    station_id,
    num_bikes_available,
    mechanical_available,
    ebikes_available,
    (COALESCE(mechanical_available, 0) + COALESCE(ebikes_available, 0)) AS calculated_total,
    ABS(num_bikes_available - (COALESCE(mechanical_available, 0) + COALESCE(ebikes_available, 0))) AS delta,
    last_reported_at,
    'Station ' || station_id || ': ' ||
    'mechanical(' || COALESCE(mechanical_available, 0) || ') + ' ||
    'ebikes(' || COALESCE(ebikes_available, 0) || ') = ' ||
    (COALESCE(mechanical_available, 0) + COALESCE(ebikes_available, 0)) || 
    ' but num_bikes_available=' || num_bikes_available AS error_message
FROM {{ source('velib', 'station_status') }}
WHERE 
    mechanical_available IS NOT NULL
    AND ebikes_available IS NOT NULL
    AND num_bikes_available != (mechanical_available + ebikes_available)
    AND extracted_at >= CURRENT_DATE - INTERVAL '1 day'