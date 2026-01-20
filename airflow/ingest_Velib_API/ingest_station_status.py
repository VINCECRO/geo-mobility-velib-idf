import hashlib
import json
from datetime import datetime
from typing import List, Dict, Any
import logging

from psycopg2.extensions import connection

logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO)

# Type alias pour une station
StationDict = Dict[str, Any]

def insert_station_status(conn: connection, stations_status: List[StationDict]) -> None:
    cur = conn.cursor()
    with conn.cursor() as cur:
        for stations in stations_status:
            cur.execute("""
                INSERT INTO staging.station_status (
                    station_id,
                    station_code,
                    num_bikes_available,
                    numBikesAvailable,
                    mechanical_available,
                    ebikes_available,
                    rental_methods,
                    num_docks_available,
                    numDocksAvailable,
                    is_installed,
                    is_renting,
                    is_returning,
                    last_reported_at,
                    last_updated_at,
                    extracted_at
                )
                VALUES (
                    %s, %s, %s, %s, %s,
                    %s, %s, %s, %s, %s,
                    %s, %s, %s, %s, %s 
                )
            """, (
                stations.get('station_id'),
                stations.get('sation_code'),
                stations.get('num_bikes_available'),
                stations.get('numBikesAvailable'),
                stations.get('ebikes_available'),
                stations.get('mechanical_available'),
                json.dumps(stations.get('rental_methods', [])),
                stations.get('num_docks_available'),
                stations.get('numDocksAvailable'),
                stations.get('is_installed'),
                stations.get('is_renting'),
                stations.get('is_returning'),
                stations.get('last_reported_at'),
                stations.get('last_updated_at'),                
                stations.get('extracted_at')
            ))
        

        # Final Log
        logger.info(
            f"✓ Processed {len(stations)} stations: "
        )
        

