# modules/mod_geo.R
# Dashboard with commune selection

mod_geo_ui <- function(id) {
  ns <- NS(id)

  layout_sidebar(
    sidebar = sidebar(
      width = 300,
      open  = TRUE,

      tags$div(
        class = "mb-3",
        tags$small(class = "text-muted text-uppercase fw-bold", "location")
      ),

      pickerInput(
        ns("dept"),
        label   = tags$span(bsicons::bs_icon("map"), " Department"),
        choices = NULL,
        multiple = TRUE,
        options = pickerOptions(
          liveSearch            = TRUE,
          actionsBox=TRUE,
          liveSearchPlaceholder = "Search...",
          deselectAllText = "Remove selection",
          selectAllText = "Select all",
          noneSelectedText      = "— choose location —",
          style                 = "btn-outline-primary"
        ),
        width = "100%"
      ),

      uiOutput(ns("commune_ui")),

      hr(),

      tags$div(
        class = "text-muted",
        style = "font-size: 0.78rem;",
        bsicons::bs_icon("info-circle"), " Les données correspondent au dernier snapshot disponible."
      )
    ),

    uiOutput(ns("content"))
  )
}

sql_in <- function(vals) {
  paste0("'", gsub("'", "''", vals), "'", collapse = ", ")
}

mod_geo_server <- function(id, pool) {
  moduleServer(id, function(input, output, session) {

    # --- Chargement des départements au démarrage ---
    depts <- query(pool, "
      SELECT DISTINCT department_number
      FROM marts.dim_station
      WHERE current_validity = TRUE
      ORDER BY department_number
    ") %>% pull(department_number)

    updatePickerInput(session, "dept",
      choices  = setNames(depts, paste0("Dép. ", depts)),
      selected = character(0)
    )

    # --- Commune picker : apparaît après sélection du département ---
    output$commune_ui <- renderUI({
      req(input$dept)

      communes <- query(pool, glue("
        SELECT DISTINCT commune_name
        FROM marts.dim_station
        WHERE current_validity = TRUE
          AND department_number IN ({sql_in(input$dept)})
        ORDER BY commune_name
      ")) %>% pull(commune_name)

      tagList(
        tags$div(class = "mt-2"),
        pickerInput(
          session$ns("commune"),
          label   = tags$span(bsicons::bs_icon("building"), " Commune"),
          choices = communes,
          multiple = TRUE,
          options = pickerOptions(
            actionsBox=TRUE,
            liveSearch            = TRUE,
            liveSearchPlaceholder = "Search...",
            deselectAllText = "Remove selection",
            selectAllText = "Select all",
            noneSelectedText      = "— choose location —",
            style                 = "btn-outline-primary"
          ),
          width = "100%"
        )
      )
    })

    # --- Données du dernier snapshot pour la commune sélectionnée ---
    commune_data <- reactive({
      req(input$commune)
      query(pool, glue("
        SELECT
          d.station_name,
          ST_Y(d.geometry::geometry) AS latitude,
          ST_X(d.geometry::geometry) AS longitude,
          f.num_bikes_available,
          f.ebikes_available,
          f.mechanical_available,
          f.num_docks_available,
          f.capacity,
          f.availability_rate,
          f.dock_availability_rate,
          f.is_critical
        FROM marts.fct_station_availability f
        JOIN marts.dim_station d USING (station_id)
        WHERE f.extracted_at = (SELECT MAX(extracted_at) FROM marts.fct_station_availability)
          AND d.commune_name IN ({sql_in(input$commune)})
          AND d.current_validity = TRUE
      "))
    })

    # --- Zone de contenu principale ---
    output$content <- renderUI({
      if (length(input$commune) == 0) {
        div(
          class = "d-flex flex-column align-items-center justify-content-center text-muted",
          style = "min-height: 500px; gap: 1rem;",
          bsicons::bs_icon("arrow-left-circle", size = "3em"),
          tags$h5("Select a department and a commune", class = "mb-0"),
        )
      } else {
        commune_label <- paste(input$commune, collapse = ", ")
        tagList(
          layout_columns(
            col_widths = c(2, 2, 2, 2, 2, 2),
            value_box(
              title    = "Stations",
              value    = textOutput(session$ns("kpi_stations")),
              showcase = bsicons::bs_icon("pin-map-fill"),
              theme    = "primary"
            ),
            value_box(
              title    = "Available bikes",
              value    = textOutput(session$ns("kpi_bikes")),
              showcase = bsicons::bs_icon("bicycle"),
              theme    = "success"
            ),
            value_box(
              title    = "Electrical",
              value    = textOutput(session$ns("kpi_ebikes")),
              showcase = bsicons::bs_icon("lightning-charge-fill"),
              theme    = "info"
            ),
            value_box(
              title    = "Mechanical",
              value    = textOutput(session$ns("kpi_mech")),
              showcase = bsicons::bs_icon("gear-fill"),
              theme    = "secondary"
            ),
            value_box(
              title    = "Critical stations",
              value    = textOutput(session$ns("kpi_critical")),
              showcase = bsicons::bs_icon("exclamation-triangle-fill"),
              theme    = "danger"
            ),
            value_box(
              title    = "Avg availability",
              value    = textOutput(session$ns("kpi_rate")),
              showcase = bsicons::bs_icon("graph-up-arrow"),
              theme    = "warning"
            )
          ),
          card(
            card_header(
              div(
                style = "display: flex; align-items: center; gap: 0.5rem;",
                bsicons::bs_icon("map"),
                tags$span("Stations KPI in commune : ", tags$b(commune_label))
              )
            ),
            leafletOutput(session$ns("map"), height = "460px")
          )
        )
      }
    })

    # --- KPIs ---
    output$kpi_stations <- renderText({
      nrow(commune_data())
    })

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

    # --- Carte ---
    output$map <- renderLeaflet({
      df <- commune_data()
      req(nrow(df) > 0)

      pal <- colorNumeric(
        palette = c("#e74c3c", "#f39c12", "#2ecc71"),
        domain  = c(0, 100)
      )

      leaflet(df) %>%
        addProviderTiles(providers$CartoDB.Positron) %>%
        fitBounds(
          lng1 = min(df$longitude), lat1 = min(df$latitude),
          lng2 = max(df$longitude), lat2 = max(df$latitude)
        ) %>%
        addCircleMarkers(
          lng         = ~longitude,
          lat         = ~latitude,
          radius      = 5,
          fillColor   = ~pal(availability_rate),
          fillOpacity = 0.85,
          stroke      = TRUE,
          weight      = 1,
          color       = "#ffffff",
          label       = ~paste0(station_name, " — ", round(availability_rate, 1), "%"),
          popup       = ~paste0(
            "<b>", station_name, "</b><br>",
            "🚲 Bikes: <b>", num_bikes_available, "</b><br>",
            "⚡ Electric: ", ebikes_available, "<br>",
            "⚙️ Mechanical: ", mechanical_available, "<br>",
            "🅿️ Docks free: ", num_docks_available, "<br>",
            "📊 Rate: ", round(availability_rate, 1), "%"
          )
        ) %>%
        addLegend(
          position  = "bottomright",
          pal       = pal,
          values    = ~availability_rate,
          title     = "Availability (%)",
          opacity   = 0.9
        )
    })
  })
}
