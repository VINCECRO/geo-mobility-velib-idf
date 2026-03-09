import psycopg2
from psycopg2.extensions import connection
from psycopg2.extras import RealDictCursor
import os

def get_connection()-> connection:
    return psycopg2.connect(
        dbname=os.environ["POSTGIS_VELIB_DB"],
        user=os.environ["POSTGIS_VELIB_USER"],
        password=os.environ["POSTGIS_VELIB_PASSWORD"],
        host=os.environ["POSTGIS_VELIB_HOST"],
        port=os.environ["POSTGIS_VELIB_PORT"]
    )