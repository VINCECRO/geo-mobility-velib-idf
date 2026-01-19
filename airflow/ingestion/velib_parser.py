# airflow/ingestion/velib_parser.py
from datetime import datetime, timezone
from zoneinfo import ZoneInfo 
from typing import List, Dict
import uuid


def ts_from_unix(ts: int) -> datetime:
    # Convert Unix Timestamp to Paris zone time stamp
    return datetime.fromtimestamp(ts, tz=ZoneInfo("Europe/Paris"))

def parse_stations(stations: dict,retrieved_timestamp:datetime) -> List[Dict]:
    last_updated_timestamp=ts_from_unix(stations["lastUpdatedOther"])
    parsed_table = []
    for s in stations["data"]["stations"]:
        parsed_table.append(
            {
                "station_id": s.get("station_id"),
                "station_code": s.get("stationCode"),
                "name": s.get("name"),
                "lat": s.get("lat"),
                "lon": s.get("lon"),
                "capacity": s.get("capacity"),
                "rental_methods": s.get("rental_methods", []),
                "station_opening_hours": s.get("station_opening_hours"),
                "last_updated_at":last_updated_timestamp,
                "retrieved_at":retrieved_timestamp
            }
        )
    return parsed_table


def parse_station_status(station_status: dict, retrieved_timestamp:datetime) -> List[Dict]:
    last_updated_timestamp=ts_from_unix(station_status["lastUpdatedOther"])
    parsed_table = []
    for s in station_status["data"]["stations"]:
        if list(s["num_bikes_available_types"][0].keys())[0]=='mechanical':
            mechanical_available=s["num_bikes_available_types"][0]['mechanical']
        else :
            mechanical_available=s["num_bikes_available_types"][1]['mechanical']
        if list(s["num_bikes_available_types"][0].keys())[0]=='ebike':
            ebike_available=s["num_bikes_available_types"][0]['ebike']
        else :
            ebike_available=s["num_bikes_available_types"][1]['ebike']    
        parsed_table.append(
            {
                "station_id": int(s["station_id"]),
                "sation_code":s.get("stationCode"),
                "num_bikes_available": s.get("num_bikes_available"),
                "last_reported_at": datetime.fromtimestamp(s.get("last_reported"), tz=ZoneInfo("Europe/Paris")),
                "numBikesAvailable": s.get("numBikesAvailable"),
                "rental_methods": s.get("rental_methods", []),
                "ebikes_available": ebike_available,
                "mechanical_available": mechanical_available,
                "num_docks_available": s.get("num_docks_available"),
                "numDocksAvailable": s.get("numDocksAvailable"),
                "is_installed": s.get("is_installed") == 1,
                "is_renting": s.get("is_renting") == 1,
                "is_returning": s.get("is_returning") == 1,
                "last_updated_at":last_updated_timestamp,
                "retrieved_at":retrieved_timestamp
            }
        )
    return parsed_table
