# global.R — Chargé une seule fois au démarrage du serveur Shiny

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
# source("modules/mod_geo.R")
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

# --- Helper requête ---
query <- function(pool,sql) {
  dbGetQuery(pool, sql)
}