

with source as (
    select *
    from "velib_DB"."raw"."stations_scd"
)

select
    station_id::int,
    name,
    capacity::int,
    ST_SetSRID(
        ST_MakePoint(lon::float, lat::float),
        4326
    ) as geom,
    last_updated_at::timestamp
from source