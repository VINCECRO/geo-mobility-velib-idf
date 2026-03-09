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
  # DONNÉES RÉACTIVES GLOBALES
  # Chargées une fois au démarrage, rafraîchissables
  # ===========================================================================

  # Toutes les stations actives (dim_station current_validity = TRUE)
  stations <- reactive({
    query("
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
  }) %>% bindCache("stations_dim")  # cache statique, peu changeant

  # Dernier snapshot disponible dans fct_station_availability
  last_snapshot <- reactive({
    query("SELECT MAX(extracted_at) AS ts FROM marts.fct_station_availability") %>%
      pull(ts)
  })

  # Mise à jour du timestamp affiché dans la navbar
  output$last_update <- renderText({
    ts <- last_snapshot()
    paste("Dernier snapshot :", format(ts, "%d/%m/%Y %H:%M"))
  })

  # Invalider les données réactives toutes les 5 minutes
  autoInvalidate <- reactiveTimer(300000)
  observe({
    autoInvalidate()
    stations()
    last_snapshot()
  })

  # ===========================================================================
  # MODULE : VUE GLOBALE
  # KPIs agrégés sur le dernier snapshot
  # ===========================================================================

  mod_overview_server("overview",
    pool         = pool,
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
  # MODULE : CARTE
  # Leaflet avec état en temps réel par station
  # ===========================================================================

  # mod_geo_server("geo",
  #   pool         = pool,
  #   stations     = stations,
  #   last_snapshot = last_snapshot
  # )

  # ===========================================================================
  # MODULE : EXPLORATEUR SQL
  # ===========================================================================

  mod_sql_explorer_server("sql")
}