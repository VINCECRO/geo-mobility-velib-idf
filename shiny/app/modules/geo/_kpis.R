# geo/_kpis.R
# KPI value box renderers

geo_kpis_server <- function(input, output, session, commune_data) {

  output$kpi_stations <- renderText({ nrow(commune_data()) })

  output$kpi_bikes <- renderText({
    scales::comma(sum(commune_data()$num_bikes_available, na.rm = TRUE))
  })

  output$kpi_ebikes <- renderText({
    scales::comma(sum(commune_data()$ebikes_available, na.rm = TRUE))
  })

  output$kpi_mech <- renderText({
    scales::comma(sum(commune_data()$mechanical_available, na.rm = TRUE))
  })

  output$kpi_critical <- renderText({
    df  <- commune_data()
    n   <- sum(df$is_critical, na.rm = TRUE)
    pct <- round(n / nrow(df) * 100, 1)
    glue("{n} ({pct}%)")
  })

  output$kpi_rate <- renderText({
    paste0(round(mean(commune_data()$availability_rate, na.rm = TRUE), 1), "%")
  })

  output$kpi_dock_rate <- renderText({
    paste0(round(mean(commune_data()$dock_availability_rate, na.rm = TRUE), 1), "%")
  })

  output$kpi_fully_op <- renderText({
    df  <- commune_data()
    n   <- sum(df$is_fully_operational, na.rm = TRUE)
    pct <- round(n / nrow(df) * 100, 1)
    glue("{n} ({pct}%)")
  })
}
