# airflow/dags/velib_ingestion_dag.py
from airflow.sdk import dag
from airflow.sdk import task
from datetime import datetime, timedelta
from datetime import timedelta
import pandas as pd

# Extraction 
from extract_Velib_API.velib_client import current_ts,fetch_stations, fetch_station_status
from extract_Velib_API.velib_parser import parse_stations, parse_station_status
# Insertion
from ingest_Velib_API.ingest_station_SCD2 import upsert_stations


@dag(
    dag_id="velib_extract_ingestion_dag",
    start_date=datetime(2026, 1, 1, 1, 00),
    schedule="*/5 * * * *",
    catchup=False,
    is_paused_upon_creation=False,
    default_args={"retries": 2, "retry_delay": timedelta(minutes=2)},
    tags=["velib", "ingestion", "gis"],
)

def velib_extract_ingestion_dag():

    @task
    def extract_station_status():
        #### Extraction and parsing of Velib API data ####
        payload = fetch_station_status()
        payload_ts=current_ts()
        stations = fetch_stations()
        stations_ts=current_ts()
        parsed_stations=parse_stations(stations,stations_ts)
        df_stations = pd.DataFrame(parsed_stations)
        parsed_stations_status=parse_station_status(payload,payload_ts)
        df_stations_status = pd.DataFrame(parsed_stations_status)
        print(df_stations_status)

    extract_station_status()


    @task
    def load_stations(parsed_data: dict):
        #### Insertion into DB staging ####
        stations = parsed_data["stations"]
        upsert_stations(stations)
        print(f"Upserted {len(stations)} stations into DB")

    # @task
    # def load_status(parsed_data: dict):
    #     """Insert les status (append-only) dans la base"""
    #     status = parsed_data["status"]
    #     upsert_station_status(status)
    #     print(f"Inserted {len(status)} station status records into DB")

    # Orchestration TaskFlow
    parsed = extract_station_status()
    load_stations(parsed)
    # load_status(parsed)

# nommer le DAG explicitement pour Airflow
velib_ingestion_dag_instance = velib_extract_ingestion_dag()
