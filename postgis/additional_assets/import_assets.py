import os
import time
import json
import geopandas as gpd
import pandas as pd
import psycopg2
import glob
from shapely.geometry import MultiPolygon
from sqlalchemy import create_engine,text
from psycopg2.extras import execute_values
from shapely.geometry import mapping 


# 🔧 PostgreSQL connexion (Verify availability + connexion)
def wait_for_db(DB_CONN,max_retries=10):
    for i in range(max_retries):
        try:
            engine = create_engine(DB_CONN)
            with engine.connect() as conn:
                print("✅ Connected to database.")
                return
        except Exception as e:
            print(f"⏳ Waiting for DB... ({i+1}/{max_retries})")
            time.sleep(3)
    raise Exception("❌ Could not connect to the database.")

# 🔧 Ensure schema exists
def ensure_schema_exists(engine, schema_name: str):
    with engine.begin() as conn:
        conn.execute(
            text(f"CREATE SCHEMA IF NOT EXISTS {schema_name};")
        )
        print(f"✅ Schema '{schema_name}' ready.")
############### GEODATA ##########################
def insert_geodata(file):
    gdf = gpd.read_file(file)
    print(f"📦 Loaded {len(gdf)} features from gpkg.")
    gdf=gdf.to_crs(epsg=4326)
    gdf.columns = gdf.columns.str.lower()
    return gdf

def create_table_with_geometry(engine, gdf, table_name: str, schema: str):
    gdf.to_postgis(table_name, engine, schema=schema, if_exists="replace", index=True)
    print(f"✅ Table '{schema}.{table_name}' created (with geometry).")

############# TABLE DATA ##########################
def insert_data(file):
    df = pd.read_csv(file)
    df.columns = df.columns.str.lower()
    print(f"📦 Loaded {len(df)} features from GeoJSON.")
    return df

def create_table_without_geometry(engine, df, table_name: str, schema: str):
    df.to_sql(table_name, engine, schema=schema, if_exists="replace", index=True)
    print(f"✅ Table '{schema}.{table_name}' created (without geometry).")
####################################################


if __name__ == "__main__":
    POSTGRES_DB=os.environ["POSTGRES_DB"]
    POSTGRES_USER=os.environ["POSTGRES_USER"]
    POSTGRES_PASSWORD=os.environ["POSTGRES_PASSWORD"]
    POSTGRES_HOST=os.environ["POSTGRES_HOST"]
    POSTGRES_PORT=os.environ["POSTGRES_PORT"]
    ##
    ADD_ASSETS_SCHEMA = "add_assets"
    ##
    DB_CONN = f"postgresql://{POSTGRES_USER}:{POSTGRES_PASSWORD}@{POSTGRES_HOST}:{POSTGRES_PORT}/{POSTGRES_DB}"
    wait_for_db(DB_CONN)
    engine = create_engine(DB_CONN)
    ensure_schema_exists(engine, ADD_ASSETS_SCHEMA)
    # enable_postgis_extension()
    liste_gpkg = glob.glob(f"*.gpkg")
    liste_csv = glob.glob(f"*.csv")
    print(f"Files to insert : {liste_gpkg}")
    print(f"Files to insert : {liste_csv}") 
    for file in liste_gpkg:
        print(f"File currently uploaded : {file}")
        table_name = os.path.splitext(os.path.basename(file))[0].lower()
        print(f"insertion successfull Table name: {ADD_ASSETS_SCHEMA}.{table_name}")
        gdf = insert_geodata(file)
        create_table_with_geometry(engine, gdf, table_name, ADD_ASSETS_SCHEMA)
    for file in liste_csv:
        print(f"le fichier a ouvrir est : {file}")
        table_name = os.path.splitext(os.path.basename(file))[0].lower()
        df = insert_data(file)
        print(f"insertion successfull Table name: {ADD_ASSETS_SCHEMA}.{table_name}")
        create_table_without_geometry(engine, df, table_name, ADD_ASSETS_SCHEMA)

