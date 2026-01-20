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
from ingest_Velib_API.db_connect import get_connection
from ingest_Velib_API.ingest_station_SCD2 import upsert_stations
from ingest_Velib_API.ingest_station_status import insert_station_status

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
    def extract_station():
        #### Extract & Parse Velib station information ####
        stations = fetch_stations()
        stations_ts=current_ts()
        parsed_stations=parse_stations(stations,stations_ts)
        return parsed_stations

    @task
    def extract_station_status():
        #### Extract & Parse Velib station status ####
        payload = fetch_station_status()
        payload_ts=current_ts()
        parsed_stations_status=parse_station_status(payload,payload_ts)
        return parsed_stations_status

    @task
    def load_stations(parsed_station: list):
        #### Insertion into DB at staging level ####
        print("Starting load_stations task...")
        conn = get_connection()
        print("connection to DB done")
        try:
            upsert_stations(conn,parsed_station)
            conn.commit()   # ✅ OBLIGATOIRE
            print(f"✓ Upserted {len(parsed_station)} stations")
        except Exception as e:
            conn.rollback() # rollback transactionnel
            raise           # ❗ Airflow doit voir l’erreur
        finally:
            conn.close()
            
    @task
    def load_stations_status(parsed_station_status: list):
        #### Insertion into DB at staging level ####
        print("Starting load_stations status task...")
        conn = get_connection()
        print("connection to DB done")
        try:
            insert_station_status(conn,parsed_station_status)
            conn.commit()   # ✅ OBLIGATOIRE
            print(f"✓ Inserted station status")
        except Exception as e:
            conn.rollback() # rollback transactionnel
            raise           # ❗ Airflow doit voir l’erreur
        finally:
            conn.close()        


    # Orchestration TaskFlow
    parsed_station = extract_station()
    parsed_station_status = extract_station_status()
    load_stations(parsed_station)
    load_stations_status(parsed_station_status)

# nommer le DAG explicitement pour Airflow
velib_ingestion_dag_instance = velib_extract_ingestion_dag()
