with source as (
    select *
    from {{ source('velib', 'stations_scd') }}
)

select
    station_id::bigint,
    name,
    capacity::int,
    ST_SetSRID(
        ST_MakePoint(lon::float, lat::float),
        4326
    ) as geom,
    last_updated_at::timestamp
from source