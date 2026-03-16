#!/bin/bash
set -e

echo "================================================"
echo "Initializing Velib Database"
echo "================================================"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL

    -- activate PostGIS extension
    CREATE EXTENSION IF NOT EXISTS postgis;
    CREATE EXTENSION IF NOT EXISTS postgis_topology;

    -- Raw schema
    CREATE SCHEMA IF NOT EXISTS raw;
    
    -- SCD2 stations table
    CREATE TABLE IF NOT EXISTS raw.stations_scd (
        id SERIAL PRIMARY KEY,                    -- ← Auto-incremented primary key
        station_id BIGINT NOT NULL,                  -- ← Not PRIMARY KEY, can repeat
        station_code TEXT,
        name TEXT,
        capacity INT,
        lon FLOAT,
        lat FLOAT,
        rental_methods JSONB,
        station_opening_hours TEXT,
        hash_diff VARCHAR(32) NOT NULL,
        valid_from TIMESTAMPTZ DEFAULT now(),
        valid_to TIMESTAMPTZ,                       -- ← NULL = current record
        current_validity BOOLEAN DEFAULT TRUE,
        last_updated_at TIMESTAMPTZ,
        extracted_at TIMESTAMPTZ,
        last_extracted_at TIMESTAMPTZ 
    );
    
    -- Partial unique index: ensures a single current record per station
    CREATE UNIQUE INDEX IF NOT EXISTS unique_current_station_idx 
    ON raw.stations_scd(station_id) 
    WHERE current_validity = TRUE;
    
    -- Additional indexes for performance
    CREATE INDEX IF NOT EXISTS idx_stations_scd_station_id 
    ON raw.stations_scd(station_id);
    
    CREATE INDEX IF NOT EXISTS idx_stations_scd_valid_from 
    ON raw.stations_scd(valid_from DESC);
    
    -- Station status table
    CREATE TABLE IF NOT EXISTS raw.station_status (
        id SERIAL PRIMARY KEY,
        station_id BIGINT NOT NULL,
        station_code TEXT,
        num_bikes_available INT,
        numBikesAvailable INT,
        mechanical_available INT,
        ebikes_available INT,
        num_docks_available INT,
        numDocksAvailable INT,
        is_installed INT,
        is_renting INT,
        is_returning INT,
        rental_methods JSONB,
        last_reported_at TIMESTAMPTZ,
        last_updated_at TIMESTAMPTZ,
        extracted_at TIMESTAMPTZ
    );
    
    CREATE INDEX IF NOT EXISTS idx_station_status_station_id 
    ON raw.station_status(station_id);
    
    CREATE INDEX IF NOT EXISTS idx_station_status_extracted_at 
    ON raw.station_status(extracted_at DESC);

    -- Defining database session Timezone
    SET timezone = 'Europe/Paris';
EOSQL


psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "postgres" <<-EOSQL
    -- Default timezone for the database should be set outside the DB
    ALTER DATABASE ${POSTGRES_DB} SET timezone TO 'Europe/Paris';
EOSQL

echo "✓ Initialization completed successfully!"
