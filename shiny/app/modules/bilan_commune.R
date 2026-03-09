# modules/mod_overview.R
# Dashboard vue globale : KPIs réseau sur le dernier snapshot

mod_commune_select_ui <- function(id) {
  ns <- NS(id)
  tagList(
    # Ligne KPIs
    layout_columns(
      col_widths = c(3, 3),
      value_box(
        title    = "Vélos disponibles",
        value    = textOutput(ns("kpi_bikes")),
        showcase = bsicons::bs_icon("bicycle"),
        theme    = "primary"
      ),
      value_box(
        title    = "Vélos électriques",
        value    = textOutput(ns("kpi_ebikes")),
        showcase = bsicons::bs_icon("lightning-charge"),
        theme    = "success"
      ),
      value_box(
        title    = "Stations critiques",
        value    = textOutput(ns("kpi_critical")),
        showcase = bsicons::bs_icon("exclamation-triangle"),
        theme    = "danger"
      ),
      value_box(
        title    = "Taux dispo. moyen",
        value    = textOutput(ns("kpi_rate")),
        showcase = bsicons::bs_icon("graph-up"),
        theme    = "info"
      )
    ),

    # Ligne graphiques
    layout_columns(
      col_widths = c(6, 6),
      card(
        card_header("Disponibilité par commune (Top 20)"),
        plotlyOutput(ns("plot_commune"), height = "350px")
      ),
      card(
        card_header("Distribution taux de disponibilité"),
        plotlyOutput(ns("plot_distrib"), height = "350px")
      )
    ),

    # Tableau résumé par commune
    card(
      card_header("Résumé par commune"),
      DTOutput(ns("table_commune"))
    )
  )
}

mod_overview_server <- function(id, pool, last_snapshot, stations) {
  moduleServer(id, function(input, output, session) {

    # Données agrégées sur le dernier snapshot
    snapshot_data <- reactive({
      ts <- last_snapshot()
      req(ts)
      query(glue("
        SELECT
          station_id,
          station_name,
          commune_name,
          num_bikes_available,
          ebikes_available,
          mechanical_available,
          num_docks_available,
          capacity,
          availability_rate,
          dock_availability_rate,
          is_critical,
          is_bike_critical,
          is_dock_critical,
          is_fully_operational
        FROM marts.fct_station_availability
        WHERE extracted_at = '{ts}'
      "))
    })

    # --- KPIs ---
    output$kpi_bikes <- renderText({
      df <- snapshot_data()
      scales::comma(sum(df$num_bikes_available, na.rm = TRUE))
    })

    output$kpi_ebikes <- renderText({
      df <- snapshot_data()
      scales::comma(sum(df$ebikes_available, na.rm = TRUE))
    })

    output$kpi_critical <- renderText({
      df <- snapshot_data()
      n  <- sum(df$is_critical, na.rm = TRUE)
      pct <- round(n / nrow(df) * 100, 1)
      glue("{n} ({pct}%)")
    })

    output$kpi_rate <- renderText({
      df <- snapshot_data()
      paste0(round(mean(df$availability_rate, na.rm = TRUE), 1), "%")
    })

    # --- Plot par commune ---
    output$plot_commune <- renderPlotly({
      df <- snapshot_data() %>%
        group_by(commune_name) %>%
        summarise(
          avg_rate  = round(mean(availability_rate, na.rm = TRUE), 1),
          n_critical = sum(is_critical, na.rm = TRUE),
          n_stations = n(),
          .groups = "drop"
        ) %>%
        arrange(desc(avg_rate)) %>%
        slice_head(n = 20)

      plot_ly(df,
        x    = ~avg_rate,
        y    = ~reorder(commune_name, avg_rate),
        type = "bar",
        orientation = "h",
        marker = list(
          color     = ~avg_rate,
          colorscale = list(c(0, "red"), c(0.5, "orange"), c(1, "green")),
          showscale = FALSE
        ),
        hovertemplate = "<b>%{y}</b><br>Taux dispo : %{x:.1f}%<extra></extra>"
      ) %>%
        layout(
          xaxis = list(title = "Taux de disponibilité moyen (%)"),
          yaxis = list(title = ""),
          margin = list(l = 120)
        )
    })

    # --- Distribution ---
    output$plot_distrib <- renderPlotly({
      df <- snapshot_data()
      plot_ly(df,
        x    = ~availability_rate,
        type = "histogram",
        nbinsx = 20,
        marker = list(color = "#3498db", line = list(color = "white", width = 0.5)),
        hovertemplate = "%{x:.0f}%–%{x:.0f}% : %{y} stations<extra></extra>"
      ) %>%
        layout(
          xaxis = list(title = "Taux de disponibilité (%)"),
          yaxis = list(title = "Nombre de stations")
        )
    })

    # --- Tableau commune ---
    output$table_commune <- renderDT({
      df <- snapshot_data() %>%
        group_by(commune_name) %>%
        summarise(
          `Stations`          = n(),
          `Vélos dispo`       = sum(num_bikes_available, na.rm = TRUE),
          `dont électriques`  = sum(ebikes_available, na.rm = TRUE),
          `Places libres`     = sum(num_docks_available, na.rm = TRUE),
          `Taux dispo moy.`   = paste0(round(mean(availability_rate, na.rm = TRUE), 1), "%"),
          `Stations critiques` = sum(is_critical, na.rm = TRUE),
          .groups = "drop"
        ) %>%
        arrange(desc(`Stations critiques`), `Taux dispo moy.`)

      datatable(df,
        options = list(pageLength = 15, scrollX = TRUE),
        rownames = FALSE
      )
    })
  })
}