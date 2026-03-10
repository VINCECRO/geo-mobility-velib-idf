# global.R — Chargé une seule fois au démarrage du serveur Shiny

Sys.setenv(TZ = "Europe/Paris")

library(shiny)
library(bslib)
library(bsicons)
library(shinyWidgets)
library(DBI)
library(RPostgres)
library(pool)
library(dplyr)
library(lubridate)
library(plotly)
library(leaflet)
library(sf)
library(DT)
library(glue)
library(scales)

# --- Source des modules AVANT que ui.R et server.R soient chargés ---
source("modules/mod_overview.R")
# source("modules/mod_station.R")
# source("modules/mod_temporal.R")
source("modules/mod_geo.R")
source("modules/mod_sql_explorer.R")

# --- Principal Velib database ---
pool_velib <- dbPool(
  drv      = Postgres(),
  host     = Sys.getenv("POSTGIS_VELIB_HOST"),
  port     = as.integer(Sys.getenv("POSTGIS_VELIB_PORT")),
  dbname   = Sys.getenv("POSTGIS_VELIB_DB"),
  user     = Sys.getenv("POSTGIS_VELIB_USER"),
  password = Sys.getenv("POSTGIS_VELIB_PASSWORD"),
  minSize  = 2,
  maxSize  = 10
)

# --- Dag database ---
pool_dag <- dbPool(
  drv      = Postgres(),
  host     = Sys.getenv("POSTGRES_DAG_HOST"),
  port     = as.integer(Sys.getenv("POSTGRES_DAG_PORT")),
  dbname   = Sys.getenv("POSTGRES_DAG_DB"),
  user     = Sys.getenv("POSTGRES_DAG_USER"),
  password = Sys.getenv("POSTGRES_DAG_PASSWORD"),
  minSize  = 2,
  maxSize  = 10
)

onStop(function() {
  poolClose(pool_velib)
  poolClose(pool_dag)
})

# --- SQL request function ---
# Define function to ease query
query <- function(pool, sql, params = NULL) {
  df           <- dbGetQuery(pool, sql, params = params)
  posixct_cols <- vapply(df, inherits, logical(1), what = "POSIXct")
  df[posixct_cols] <- lapply(df[posixct_cols], lubridate::with_tz, tzone = "Europe/Paris")
  df
}

# --- Palettes de couleurs (miroir des variables CSS) ---
COLORS <- list(
  # Binaire
  binary  = c(ok = "#2ecc71", critical = "#e74c3c"),

  # Quartiles Q1 (bon) → Q4 (mauvais)
  quartile = c("#e74c3c","#e67e22", "#f1c40f" , "#2ecc71"),

  # Linéaire bas → haut
  linear  = c(low = "#e74c3c", mid = "#f39c12", high = "#2ecc71")
)