# airflow/ingestion/velib_loader.py
import psycopg2
import os
from psycopg2.extras import execute_values

PG_CONN = os.getenv("AIRFLOW__DATABASE__SQL_ALCHEMY_CONN")


def get_conn():
    return psycopg2.connect(PG_CONN)


def insert_snapshot(conn, snapshot: dict):
    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO velib_snapshot (snapshot_id, snapshot_ts, raw_payload)
            VALUES (%s, %s, %s)
            """,
            (snapshot["snapshot_id"], snapshot["snapshot_ts"], snapshot["raw_payload"]),
        )


def insert_station_status(conn, rows):
    with conn.cursor() as cur:
        execute_values(
            cur,
            """
            INSERT INTO velib_station_status (
                snapshot_id,
                station_id,
                bikes_available,
                ebikes_available,
                mechanical_available,
                docks_available,
                is_installed,
                is_renting,
                is_returning,
                station_last_reported_ts
            ) VALUES %s
            """,
            rows,
        )