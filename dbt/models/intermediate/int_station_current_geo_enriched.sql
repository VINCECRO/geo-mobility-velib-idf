-- dbt/models/intermediate/int_station_geo_enriched.sql

/*
Geographical enrichment for current stations.
Joins station geometry with commune boundaries and commune-level population.
*/

SELECT
    s.station_id,
    s.name,
    s.capacity,
    s.geometry,
    c.nomcom AS nomcom,
    c.insee   AS insee,
    c.numdep AS department_number,
    p.population
FROM {{ ref('stg_velib_station_current') }} s
LEFT JOIN {{ ref('stg_geo_communes_idf') }} c
    ON ST_Within(s.geometry, c.geometry)
LEFT JOIN {{ ref('stg_geo_pop_communes') }} p
    ON c.nomcom = p.nomcom
