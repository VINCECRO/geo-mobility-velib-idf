import hashlib
import json
from datetime import datetime
from typing import List, Dict
import logging
from loader.db import get_connection

logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO)

# Exemple de structure d'une station après parsing
type StationDict = Dict[str, any]


def compute_hash(station: StationDict) -> str:
    """Compute a hash of station fields relevant for change detection"""
    # On inclut les champs qui définissent l'état 'métier', pas les timestamps
    relevant = f"{station['station_id']}|{station.get('station_code')}|{station.get('name')}|{station.get('capacity')}|{station.get('lat')}|{station.get('lon')}"
    return hashlib.md5(relevant.encode('utf-8')).hexdigest()


def upsert_stations(stations: List[StationDict]):
    """Insert or update stations into current-only SCD table with valid_from"""
    conn = get_connection()
    cur = conn.cursor()
    for station in stations:
        station_hash = compute_hash(station)
        station_id = station['station_id']

        # Check if record exists
        cur.execute("""
            SELECT id, hash_diff
            FROM stations_scd
            WHERE station_id = %s
        """, (station_id,))
        result = cur.fetchone()
        if result:
            current_id, current_hash = result
            if current_hash != station_hash:
                # Update existing record with new values + refresh valid_from
                cur.execute("""
                    UPDATE stations_scd
                    SET station_code = %s,
                        name = %s,
                        capacity = %s,
                        geom = ST_SetSRID(ST_Point(%s, %s), 4326),
                        rental_methods = %s,
                        station_opening_hours = %s,
                        hash_diff = %s,
                        valid_from = %s,
                        last_updated_at = %s,
                        retrieved_at = %s
                    WHERE id = %s
                """, (
                    station.get('station_code'),
                    station.get('name'),
                    station.get('capacity'),
                    station.get('lon'),
                    station.get('lat'),
                    json.dumps(station.get('rental_methods', [])),
                    station.get('station_opening_hours'),
                    station_hash,
                    station.get('last_updated_at'),
                    station.get('retrieved_at'),
                    current_id
                ))
                logger.info(f"Station {station_id} updated")
            else:
                logger.debug(f"Station {station_id} unchanged")
        else:
            # No record exists, insert new
            cur.execute("""
                INSERT INTO stations_scd (
                    station_id,
                    station_code,
                    name,
                    capacity,
                    geom,
                    rental_methods,
                    station_opening_hours,
                    hash_diff,
                    valid_from,
                    last_updated_at,
                    retrieved_at
                )
                VALUES (%s, %s, %s, %s, ST_SetSRID(ST_Point(%s, %s), 4326), %s, %s, %s, %s, %s, %s)
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
                station.get('last_updated_at'),
                station.get('retrieved_at')
            ))
            logger.info(f"Station {station_id} inserted")

    conn.commit()
    cur.close()
    conn.close()


