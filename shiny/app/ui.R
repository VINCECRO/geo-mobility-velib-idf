library(bslib)

ui <- page_navbar(
  title    = "Vélib Dashboard",
  theme    = bs_theme(bootswatch = "flatly"),
  fillable = TRUE,

  nav_panel("🗺️ Global view",     mod_overview_ui("overview")),
  # nav_panel("📍 Par Station",     mod_station_ui("station")),
  # nav_panel("⏱️ Historical station status",mod_temporal_ui("temporal")),
  # nav_panel("🗾 Carte",           mod_geo_ui("geo")),
  nav_panel("🔍 Explorateur SQL", mod_sql_explorer_ui("sql")),
  
  nav_spacer(),
  nav_item(
    tags$span(
      class = "text-muted small",
      textOutput("last_update", inline = TRUE)
    )
  )
)