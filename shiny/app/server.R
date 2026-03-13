library(shiny)
library(dplyr)
library(lubridate)
library(plotly)
library(leaflet)
library(sf)
library(DT)
library(glue)

server <- function(input, output, session) {

  # ===========================================================================
  # Global Data
  #
  # ===========================================================================

  # Active stations
  stations <- reactive({
    query(pool_velib,"
      SELECT
        station_id,
        station_code,
        station_name,
        capacity,
        station_size_category,
        commune_name,
        department_number,
        population_500m,
        population_density_500m,
        ST_X(geometry::geometry) AS lon,
        ST_Y(geometry::geometry) AS lat
      FROM marts.dim_station
      WHERE current_validity = TRUE
      ORDER BY station_name
    ")
  }) %>% bindCache("stations_dim")  # cache statique

  # Define last snapshot
  last_snapshot <- reactive({
    query(pool_velib,"SELECT MAX(extracted_at) AS ts FROM marts.fct_station_availability") %>%
      pull(ts)
  })

  # Last recorded timestamp print in navbar
  output$last_update <- renderText({
    ts <- last_snapshot()
    paste("Last snapshot :", format(ts, "%d/%m/%Y %H:%M"))
  })

  # Update every 5 minutes
  autoInvalidate <- reactiveTimer(300000)
  observe({
    autoInvalidate()
    stations()
    last_snapshot()
  })

  # ===========================================================================
  # MODULE : Global View
  # KPIs agregate over last snapshot
  # ===========================================================================

  mod_overview_server("overview",
    pool         = pool_velib,
    last_snapshot = last_snapshot,
    stations     = stations
  )

  # ===========================================================================
  # MODULE : PAR STATION
  # Drill-down sur une station + navigation temporelle slider 5 min
  # ===========================================================================

  # mod_station_server("station",
  #   pool         = pool,
  #   stations     = stations,
  #   last_snapshot = last_snapshot
  # )

  # ===========================================================================
  # MODULE : TEMPOREL
  # Vue calendrier → jour → heure → tranche 5 min
  # ===========================================================================

  # mod_temporal_server("temporal",
  #   pool = pool
  # )

  # ===========================================================================
  # MODULE : CARTE COMMUNAL
  # Leaflet avec état en temps réel par station
  # ===========================================================================

  mod_geo_server("geo",
    pool         = pool_velib
  )

  # ===========================================================================
  # MODULE : SQL explorer for Velib Data & Dag data
  # ===========================================================================

  # ===========================================================================
  # MODULE : DAG MONITORING
  # Waffle chart des dag runs (historique ou date spécifique)
  # ===========================================================================

  mod_dag_server("dag", pool = pool_dag)

  mod_sql_explorer_server("sql", pool_velib = pool_velib, pool_dag = pool_dag)
}