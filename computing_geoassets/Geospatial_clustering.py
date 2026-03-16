import geopandas as gpd
import pandas as pd
from sklearn.preprocessing import StandardScaler
from sklearn.cluster import KMeans
import numpy as np

import matplotlib
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
import matplotlib.cm as cm

import re
import gc



def Load_bat_file(folder_name)-> gpd.GeoDataFrame :
    gdf=gpd.read_file(f"./input_data/{folder_name}/gpkg/bdnb.gpkg",layer="batiment_groupe_compile")
    return gdf

def gdf_select(gdf) -> gpd.GeoDataFrame:
    gdf=gdf[["bdtopo_bat_l_usage_1","geometry"]]
    return gdf

def select_and_concat(gdf1,gdf2,gdf3,gdf4)-> gpd.GeoDataFrame :
    gdf1=gdf_select(gdf1)
    gdf2=gdf_select(gdf2)
    gdf3=gdf_select(gdf3)
    gdf4=gdf_select(gdf4)
    gdf = pd.concat([gdf1, gdf2, gdf3, gdf4], ignore_index=True)
    gdf = gpd.GeoDataFrame(gdf, geometry='geometry', crs=gdf1.crs)
    return gdf

def extract_main_usage(texte):
    usages = re.sub(r'^\(\d+:', '', str(texte))
    usages = usages.rstrip(')')
    return [u.strip() for u in usages.split(',')]

def Bat_usage_encoding(gdf) -> gpd.GeoDataFrame:
    # Extract different usage
    tous_usages = set()
    for val in gdf['bdtopo_bat_l_usage_1']:
        usages = extract_main_usage(val)
        tous_usages.update(usages)
    # Create one hot encoding with usage category
    for usage in tous_usages:
        gdf[f'usage_{usage}'] = gdf['bdtopo_bat_l_usage_1'].apply(
            lambda x: usage in extract_main_usage(x)
        )
    # one hot encoding cols
    usage_cols = [col for col in gdf.columns if col.startswith('usage_')]
    # Multiply by surface area
    gdf[usage_cols] = gdf[usage_cols].multiply(gdf['area_in_m2'], axis=0)
    return gdf    

def aggregate_on_grid_batch(gdf_grid, gdf_population, bat_complet, buffer_distance=500, batch_size=1000):
    # Changing CRS if needed
    gdf_population = gdf_population.to_crs(gdf_grid.crs)
    bat_complet = bat_complet.to_crs(gdf_grid.crs)
    usage_cols = [col for col in bat_complet.columns if col.startswith("usage_")]
    results = []
    n = len(gdf_grid)
    for start in range(0, n, batch_size):
        print(f"Processing batch {start//batch_size + 1} / {n//batch_size + 1}")
        batch = gdf_grid.iloc[start:start + batch_size].copy()
        # Centroids and buffers
        centroids = batch.geometry.centroid
        buffers = centroids.buffer(buffer_distance)
        gdf_buffers = gpd.GeoDataFrame(
            batch['id'],
            geometry=buffers,
            crs=gdf_grid.crs
        )
        # initial filtering to limit joins
        batch_union = gdf_buffers.geometry.union_all()
        pop_local = gdf_population[gdf_population.geometry.intersects(batch_union)].copy()
        bat_local = bat_complet[bat_complet.geometry.intersects(batch_union)].copy()
        # Population aggregation
        pop_agg = None
        if not pop_local.empty:
            joined_pop = gpd.sjoin(
                pop_local[["population", "geometry"]],
                gdf_buffers[["id", "geometry"]],
                how="inner",
                predicate="within"
            )
            pop_agg = joined_pop.groupby("id")["population"].sum().reset_index()
            pop_agg.columns = ["id", "population_totale"]
        # Buildings aggregation
        bat_agg = None
        if not bat_local.empty:
            joined_bat = gpd.sjoin(
                bat_local[usage_cols + ["geometry"]],
                gdf_buffers[["id", "geometry"]],
                how="inner",
                predicate="intersects"
            )
            bat_agg = joined_bat.groupby("id")[usage_cols].sum().reset_index()
        # --- Assemble batch via left join ---
        batch = batch.merge(pop_agg, on="id", how="left") if pop_agg is not None else batch.assign(population_totale=0.0)
        batch = batch.merge(bat_agg, on="id", how="left") if bat_agg is not None else batch.assign(**{col: 0.0 for col in usage_cols})
        batch[["population_totale"] + usage_cols] = batch[["population_totale"] + usage_cols].fillna(0.0)
        results.append(batch)
    return gpd.GeoDataFrame(pd.concat(results, ignore_index=False), crs=gdf_grid.crs)

#---------------------------
# Clustering functions
#---------------------------
def prepare_features(gdf):
    df = gdf.copy()
    # Total built surface (excluding nan and annex which are noise)
    usage_cols = ["usage_Résidentiel", "usage_Commercial et services", 
                  "usage_Industriel", "usage_Sportif", "usage_Religieux",
                  "usage_Indifférencié", "usage_Agricole"]
    df["surface_totale"] = df[usage_cols].sum(axis=1)
    # Ratios d'usage (entre 0 et 1, robuste à la densité)
    for col in usage_cols:
        df[f"ratio_{col}"] = df[col] / df["surface_totale"].replace(0, np.nan)
    df = df.fillna(0)
    df['population_totale']=gdf['population_totale']
    return df

def clustering(gdf,n_clusters=4):
    gdf=gdf.set_index('id')
    df=prepare_features(gdf)
    feature_cols = ["usage_Résidentiel","usage_Commercial et services"] + ["population_totale"]
    X = df[feature_cols].values
    # StandardScaler for all the features
    scaler = StandardScaler()
    X_scaled = scaler.fit_transform(X)
    # KMeans
    kmeans = KMeans(n_clusters=n_clusters, random_state=42, n_init=10)
    df["cluster"] = kmeans.fit_predict(X_scaled)
    # Interpretation helper: average profile per cluster
    profil = df.groupby("cluster")[feature_cols].mean().round(3)
    print(profil)
    return df, profil

if __name__ == "__main__":
    # Loading grouped building DB downloaded from https://bdnb.io/download/ (CSTB 2025)
    bat_75=Load_bat_file("open_data_millesime_2025-07-a_dep75_gpkg")
    bat_92=Load_bat_file("open_data_millesime_2025-07-a_dep92_gpkg")
    bat_93=Load_bat_file("open_data_millesime_2025-07-a_dep93_gpkg")
    bat_94=Load_bat_file("open_data_millesime_2025-07-a_dep94_gpkg")
    # Dataset reduction and Concat
    bat_complet=select_and_concat(bat_75,bat_92,bat_93,bat_94)
    del bat_75,bat_92,bat_93,bat_94
    gc.collect()
    bat_complet['area_in_m2'] = bat_complet.geometry.area
    # One hot encoding for Builing main usage 
    bat_complet=Bat_usage_encoding(bat_complet)
    # Loading population from https://data.humdata.org/dataset/france-high-resolution-population-density-maps-demographic-estimates (Juil 2019)
    Population = gpd.read_file("./derived_data/Population_IDF.gpkg")
    # Loarding grind data 
    gdf_50m=gpd.read_file('./input_data/grille_50m_SCR_2154.gpkg')
    gdf_50m=gdf_50m[["id","geometry"]]
    # Aggregation with centroid buffer
    gdf_50m_enrichi = aggregate_on_grid_batch(gdf_grid=gdf_50m,gdf_population=Population,bat_complet=bat_complet,buffer_distance=500)
    vmin, vmax = gdf_50m_enrichi["population_totale"].min(), gdf_50m_enrichi["population_totale"].max()  #
    norm = mcolors.Normalize(vmin=0, vmax=5000)
    cmap = "viridis"
    fig, ax = plt.subplots(figsize=(15, 15))
    gdf_50m_enrichi.plot(ax=ax, cmap=cmap, norm=norm,column='population_totale',alpha=0.7,edgecolor=None)
    sm = cm.ScalarMappable(cmap=cmap, norm=norm)
    sm.set_array([])  # Required to avoid an error
    cbar = fig.colorbar(sm, ax=ax)
    cbar.set_label("Population")
    ax.set_xlabel("Longitude")
    ax.set_ylabel("Latitude")
    plt.show()
    gdf_clustering,profil = clustering(gdf_50m_enrichi,4)
    gdf_clustering.to_file("./derived_data/clustered_population_data.gpkg")




