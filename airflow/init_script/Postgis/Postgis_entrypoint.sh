#!/bin/bash
set -e

echo "================================================"
echo "Initialisation de la base de données Velib"
echo "================================================"

# PostgreSQL est DÉJÀ démarré par Docker, on se connecte directement
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    -- Extensions PostGIS
    CREATE EXTENSION IF NOT EXISTS postgis;
    CREATE EXTENSION IF NOT EXISTS postgis_topology;
    
    -- Schéma staging
    CREATE SCHEMA IF NOT EXISTS staging;
    
    -- Table des stations
    CREATE TABLE IF NOT EXISTS staging.stations (
        station_id INT PRIMARY KEY,
        station_code TEXT,
        name TEXT,
        lat DOUBLE PRECISION,
        lon DOUBLE PRECISION,
        capacity INT,
        rental_methods JSONB,
        last_updated_at TIMESTAMP,
        retrieved_at TIMESTAMP,
        valid_from TIMESTAMP DEFAULT now()
    );
    
    -- Table des statuts de stations
    CREATE TABLE IF NOT EXISTS staging.station_status (
        id SERIAL PRIMARY KEY,
        station_id INT,
        num_bikes_available INT,
        mechanical_available INT,
        ebikes_available INT,
        num_docks_available INT,
        is_installed BOOLEAN,
        is_renting BOOLEAN,
        is_returning BOOLEAN,
        last_updated_at TIMESTAMP,
        retrieved_at TIMESTAMP,
        FOREIGN KEY (station_id) REFERENCES staging.stations(station_id)
    );
    
    -- Index pour améliorer les performances
    CREATE INDEX IF NOT EXISTS idx_station_status_station_id 
    ON staging.station_status(station_id);
    
    CREATE INDEX IF NOT EXISTS idx_station_status_retrieved_at 
    ON staging.station_status(retrieved_at DESC);
EOSQL

echo "✓ Schéma staging créé"
echo "✓ Tables stations et station_status créées"
echo "✓ Extensions PostGIS activées"
echo "================================================"
echo "Initialisation terminée avec succès!"
echo "================================================"