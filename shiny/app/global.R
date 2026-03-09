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

# --- Pool de connexions PostGIS ---
pool <- dbPool(
  drv      = Postgres(),
  host     = Sys.getenv("POSTGRES_HOST",    "postgres-velib"),
  port     = as.integer(Sys.getenv("POSTGRES_PORT", "5432")),
  dbname   = Sys.getenv("POSTGRES_DB",      "velib_DB"),
  user     = Sys.getenv("POSTGRES_USER",    "velib"),
  password = Sys.getenv("POSTGRES_PASSWORD","velib_password"),
  minSize  = 2,
  maxSize  = 10
)

onStop(function() poolClose(pool))

# --- Helper requête ---
query <- function(sql) {
  dbGetQuery(pool, sql)
}