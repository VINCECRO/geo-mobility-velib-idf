# airflow/dags/velib_ingestion_dag.py
from airflow.sdk import dag
from airflow.sdk import task
from datetime import datetime, timedelta
import os, sys
import logging
from datetime import timedelta

from ingestion.velib_client import fetch_stations, fetch_station_status
from ingestion.velib_parser import parse_snapshot_metadata, parse_station_status
from ingestion.velib_loader import get_conn, insert_snapshot, insert_station_status



@dag(
    dag_id="velib_ingestion",
    start_date=datetime(2026, 1, 1, 1, 00),
    schedule="*/5 * * * *",
    catchup=False,
    # is_paused_upon_creation=False,
    default_args={"retries": 2, "retry_delay": timedelta(minutes=2)},
    tags=["velib", "ingestion", "gis"],
)
def velib_ingestion_dag():

    @task
    def ingest_station_status():
        # payload = fetch_station_status()
        # snapshot = parse_snapshot_metadata(payload)
        # rows = parse_station_status(payload, snapshot["snapshot_id"])
        # conn = get_conn()
        # try:
        #     insert_snapshot(conn, snapshot)
        #     insert_station_status(conn, rows)
        #     conn.commit()
        # finally:
        #     conn.close()

    ingest_station_status()


# nommer le DAG explicitement pour Airflow
velib_ingestion_dag_instance = velib_ingestion_dag()
