library(bslib)

ui <- page_navbar(
  title    = "Vélib Dashboard",
  theme    = bs_theme(bootswatch = "flatly"),
  fillable = "🗺️ Global view",
  tags$head(tags$link(rel = "stylesheet", href = "styles.css")),

  nav_panel("🗺️ Global view",     mod_overview_ui("overview")),
  # nav_panel("📍 Par Station",     mod_station_ui("station")),
  # nav_panel("⏱️ Historical station status",mod_temporal_ui("temporal")),
  nav_panel("🗾  Situation per commune",  mod_geo_ui("geo")),
  nav_panel("🔍 Explorateur SQL", mod_sql_explorer_ui("sql")),
  
  nav_spacer(),
  # Def
  nav_item(
    tags$span(
      class = "text-white small",
      textOutput("last_update", inline = TRUE)
    )
  )
)