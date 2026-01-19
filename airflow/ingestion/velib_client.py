# airflow/ingestion/velib_client.py
import os
import requests
from datetime import datetime
from zoneinfo import ZoneInfo 

BASE_URL = "https://prim.iledefrance-mobilites.fr/marketplace/velib"

API_KEY = os.getenv("VELIB_API_KEY")
if not API_KEY:
    raise RuntimeError("VELIB_API_KEY is not set")

HEADERS = {
    "apikey": API_KEY
}

def current_ts() -> datetime:
    return datetime.now(tz=ZoneInfo("Europe/Paris"))

def fetch_stations():
    url = f"{BASE_URL}/station_information.json"
    response = requests.get(url, headers=HEADERS, timeout=30)
    response.raise_for_status()
    return response.json()

def fetch_station_status():
    url = f"{BASE_URL}/station_status.json"
    response = requests.get(url, headers=HEADERS, timeout=30)
    response.raise_for_status()
    return response.json()