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


def compute_hash(station: StationDict) -> str:
    # Compute a hash to discrimitate evolution between records
    relevant = (
        f"{station['station_id']}|"
        f"{station.get('station_code')}|"
        f"{station.get('name')}|"
        f"{station.get('capacity')}|"
        f"{station.get('lat')}|"
        f"{station.get('lon')}"
    )
    return hashlib.md5(relevant.encode('utf-8')).hexdigest()


def upsert_stations(conn: connection, stations: List[StationDict]) -> None:
    cur = conn.cursor()
    stats = {
        'inserted': 0,
        'updated': 0,
        'unchanged': 0
    }
    with conn.cursor() as cur:
        for station in stations:
            station_hash = compute_hash(station)
            station_id = station['station_id']
            now = datetime.now()
            # fetch current valid station_id (current_validity=True)
            cur.execute("""
                SELECT id, hash_diff
                FROM staging.stations_scd
                WHERE station_id = %s 
                  AND current_validity = TRUE
            """, (station_id,))
            result = cur.fetchone()
            if result:
                current_id, current_hash = result
                if current_hash != station_hash:
                    #-------------------------------------------------------------
                    #   Record evolution detected (station_id already in DB)
                    #-------------------------------------------------------------
                    # Step 1 : closing previous version
                    cur.execute("""
                        UPDATE staging.stations_scd
                        SET current_validity = FALSE,
                            valid_to = %s
                        WHERE id = %s
                    """, (now, current_id))
                    logger.info(f"Closed old version for station {station_id} (id={current_id})")
                    
                    # Step 2 : Inserting new version
                    cur.execute("""
                        INSERT INTO staging.stations_scd (
                            station_id,
                            station_code,
                            name,
                            capacity,
                            geom,
                            rental_methods,
                            station_opening_hours,
                            hash_diff,
                            valid_from,
                            valid_to,
                            current_validity,
                            last_updated_at,
                            extracted_at
                        )
                        VALUES (
                            %s, %s, %s, %s, 
                            ST_SetSRID(ST_Point(%s, %s), 4326), 
                            %s, %s, %s, %s, NULL, TRUE, %s, %s
                        )
                    """, (
                        station_id,
                        station.get('station_code'),
                        station.get('name'),
                        station.get('capacity'),
                        station.get('lon'),
                        station.get('lat'),
                        json.dumps(station.get('rental_methods', [])),
                        station.get('station_opening_hours'),
                        station_hash,
                        now,  # valid_from
                        station.get('last_updated_at'),
                        station.get('extracted_at')
                    ))
                    stats['updated'] += 1
                    logger.info(f"✓ Station {station_id} changed: new version created (hash: {current_hash[:8]} → {station_hash[:8]})")
                    
                else:
                    #-------------------------------------------------------------
                    #   No record evolution detected (Nothing to change) 
                    #-------------------------------------------------------------
                    stats['unchanged'] += 1
                    logger.debug(f"Station {station_id} unchanged (hash: {station_hash[:8]})")
                    
            else:
                    #-------------------------------------------------------------
                    #   New record detected (station_id not in DB)
                    #-------------------------------------------------------------
                    cur.execute("""
                        INSERT INTO staging.stations_scd (
                            station_id,
                            station_code,
                            name,
                            capacity,
                            geom,
                            rental_methods,
                            station_opening_hours,
                            hash_diff,
                            valid_from,
                            valid_to,
                            current_validity,
                            last_updated_at,
                            extracted_at
                        )
                        VALUES (
                            %s, %s, %s, %s, 
                            ST_SetSRID(ST_Point(%s, %s), 4326), 
                            %s, %s, %s, %s, NULL, TRUE, %s, %s
                        )
                    """, (
                        station_id,
                        station.get('station_code'),
                        station.get('name'),
                        station.get('capacity'),
                        station.get('lon'),
                        station.get('lat'),
                        json.dumps(station.get('rental_methods', [])),
                        station.get('station_opening_hours'),
                        station_hash,
                        now,  # valid_from
                        station.get('last_updated_at'),
                        station.get('extracted_at')
                    ))
                    
                    stats['inserted'] += 1
                    logger.info(f"✓ Station {station_id} inserted (new station)")

        
        # Final Log
        logger.info(
            f"✓ Processed {len(stations)} stations: "
            f"{stats['inserted']} inserted, "
            f"{stats['updated']} updated, "
            f"{stats['unchanged']} unchanged"
        )
        

