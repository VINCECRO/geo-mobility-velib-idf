#!/bin/bash
set -e

echo "================================================"
echo "Initialisation de la base de données Velib"
echo "================================================"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    -- Extensions PostGIS
    CREATE EXTENSION IF NOT EXISTS postgis;
    CREATE EXTENSION IF NOT EXISTS postgis_topology;


    -- Schéma raw
    CREATE SCHEMA IF NOT EXISTS raw;
    
    -- Table SCD2 des stations
    CREATE TABLE IF NOT EXISTS raw.stations_scd (
        id SERIAL PRIMARY KEY,                    -- ← Clé primaire auto-incrémentée
        station_id BIGINT NOT NULL,                  -- ← Pas PRIMARY KEY, peut se répéter
        station_code TEXT,
        name TEXT,
        capacity INT,
        geom GEOMETRY(Point, 4326),               -- ← Mieux que lat/lon séparés pour PostGIS
        rental_methods JSONB,
        station_opening_hours TEXT,
        hash_diff VARCHAR(32) NOT NULL,
        valid_from TIMESTAMP DEFAULT now(),
        valid_to TIMESTAMP,                       -- ← NULL = enregistrement actuel
        current_validity BOOLEAN DEFAULT TRUE,
        last_updated_at TIMESTAMP,
        extracted_at TIMESTAMP
    );
    
    -- Index unique partiel : garantit un seul enregistrement current par station
    CREATE UNIQUE INDEX IF NOT EXISTS unique_current_station_idx 
    ON raw.stations_scd(station_id) 
    WHERE current_validity = TRUE;
    
    -- Autres index pour performance
    CREATE INDEX IF NOT EXISTS idx_stations_scd_station_id 
    ON raw.stations_scd(station_id);
    
    CREATE INDEX IF NOT EXISTS idx_stations_scd_geom 
    ON raw.stations_scd USING GIST(geom);
    
    CREATE INDEX IF NOT EXISTS idx_stations_scd_valid_from 
    ON raw.stations_scd(valid_from DESC);
    
    -- Table des statuts de stations
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
        last_reported_at TIMESTAMP,
        last_updated_at TIMESTAMP,
        extracted_at TIMESTAMP
    );
    
    CREATE INDEX IF NOT EXISTS idx_station_status_station_id 
    ON raw.station_status(station_id);
    
    CREATE INDEX IF NOT EXISTS idx_station_status_extracted_at 
    ON raw.station_status(extracted_at DESC);
EOSQL

echo "✓ Initialisation terminée avec succès!"