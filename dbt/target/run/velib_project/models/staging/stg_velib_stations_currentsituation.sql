
  
    

  create  table "velib_DB"."staging"."stg_velib_stations_currentsituation__dbt_tmp"
  
  
    as
  
  (
    

WITH latest_extraction AS (
    SELECT 
        MAX(extracted_at) AS max_extracted_at
    FROM raw.stations_scd
)

SELECT s.*
FROM raw.stations_scd s
JOIN latest_extraction le
    ON s.extracted_at = le.max_extracted_at
  );
  