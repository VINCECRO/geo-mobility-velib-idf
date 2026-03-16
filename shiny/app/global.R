# global.R — Loaded once at Shiny server startup

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
library(httr2)
library(shinyjs)

# --- Source modules BEFORE ui.R and server.R are loaded ---
# geo/: sub-files (_*.R) sourced before the orchestrator (alphabetical order guaranteed)
source("modules/geo/_snapshot.R")
source("modules/geo/_kpis.R")
source("modules/geo/_map.R")
source("modules/geo/_chart.R")
source("modules/geo/mod_geo.R")

source("modules/overview/mod_overview.R")
source("modules/sql_explorer/mod_sql_explorer.R")

source("modules/dag/_snapshot.R")
source("modules/dag/_kpis.R")
source("modules/dag/_waffle.R")
source("modules/dag/mod_dag.R")
source("modules/agent/mod_agent.R")
# source("modules/mod_station.R")
# source("modules/mod_temporal.R")

# --- Main Velib database ---
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

# --- DAG database ---
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

# --- SQL request helper ---
# Wraps dbGetQuery and converts POSIXct columns to Europe/Paris timezone
query <- function(pool, sql, params = NULL) {
  df           <- dbGetQuery(pool, sql, params = params)
  posixct_cols <- vapply(df, inherits, logical(1), what = "POSIXct")
  df[posixct_cols] <- lapply(df[posixct_cols], lubridate::with_tz, tzone = "Europe/Paris")
  df
}

# --- Color palettes (mirrors CSS variables) ---
COLORS <- list(
  # Binary
  binary  = c(ok = "#2ecc71", critical = "#e74c3c"),

  # Quartiles Q1 (good) → Q4 (bad)
  quartile = c("#e74c3c","#e67e22", "#f1c40f" , "#2ecc71"),

  # Linear low → high
  linear  = c(low = "#e74c3c", mid = "#f39c12", high = "#2ecc71")
)
