# modules/geo/mod_geo.R
# Geo dashboard — commune-level station analysis
# Sub-modules: _snapshot.R | _kpis.R | _map.R | _chart.R

sql_in <- function(vals) {
  paste0("'", gsub("'", "''", vals), "'", collapse = ", ")
}

mod_geo_ui <- function(id) {
  ns <- NS(id)

  layout_sidebar(
    sidebar = sidebar(
      width = 300,
      open  = TRUE,

      # --- Location ---
      tags$div(class = "mb-3",
        tags$small(class = "text-muted text-uppercase fw-bold", "Location")
      ),
      pickerInput(
        ns("dept"),
        label    = tags$span(bsicons::bs_icon("map"), " Department"),
        choices  = NULL,
        multiple = TRUE,
        options  = pickerOptions(
          liveSearch = TRUE, actionsBox = TRUE,
          liveSearchPlaceholder = "Search...",
          deselectAllText = "Remove selection", selectAllText = "Select all",
          noneSelectedText = "— choose location —", style = "btn-outline-primary"
        ),
        width = "100%"
      ),
      uiOutput(ns("commune_ui")),

      hr(),

      # --- Snapshot ---
      tags$div(class = "mb-2",
        tags$small(class = "text-muted text-uppercase fw-bold", "Snapshot")
      ),
      switchInput(
        ns("use_custom_ts"), label = "See other timestamp",
        value = FALSE, onLabel = "Custom", offLabel = "Latest",
        size = "small", width = "100%"
      ),
      uiOutput(ns("ts_date_ui")),
      uiOutput(ns("ts_slider_ui")),
      uiOutput(ns("snapshot_info"))
    ),

    uiOutput(ns("content"))
  )
}

mod_geo_server <- function(id, pool) {
  moduleServer(id, function(input, output, session) {

    # --- Location pickers ---
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
          label    = tags$span(bsicons::bs_icon("building"), " Commune"),
          choices  = communes,
          multiple = TRUE,
          options  = pickerOptions(
            actionsBox = TRUE, liveSearch = TRUE,
            liveSearchPlaceholder = "Search...",
            deselectAllText = "Remove selection", selectAllText = "Select all",
            noneSelectedText = "— choose location —", style = "btn-outline-primary"
          ),
          width = "100%"
        )
      )
    })

    # --- Snapshot sub-module → returns ts_filter reactive ---
    snap <- geo_snapshot_server(input, output, session, pool)

    # --- Snapshot data (single timestamp) ---
    commune_data <- reactive({
      req(input$commune)
      query(pool, glue("
        SELECT
          station_name,
          ST_Y(geometry) AS latitude,
          ST_X(geometry) AS longitude,
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
        WHERE {snap$ts_filter()}
          AND commune_name IN ({sql_in(input$commune)})
      "))
    })

    # --- Time series data (all history, per station) ---
    timeseries_data <- reactive({
      req(input$commune)
      query(pool, glue("
        SELECT
          extracted_at AT TIME ZONE 'Europe/Paris' AS ts,
          station_name,
          num_bikes_available,
          ebikes_available,
          mechanical_available
        FROM marts.fct_station_availability
        WHERE commune_name IN ({sql_in(input$commune)})
        ORDER BY station_name, extracted_at
      "))
    })

    # --- Selected date for "journée" mode in chart ---
    selected_date <- reactive({
      if (isTRUE(input$use_custom_ts) && !is.null(input$ts_date)) {
        as.Date(input$ts_date)
      } else {
        as.Date(max(timeseries_data()$ts, na.rm = TRUE))
      }
    })

    # --- Selected station (shared between map and chart) ---
    selected_station <- reactiveVal(NULL)

    # Reset station selection when commune changes
    observeEvent(input$commune, { selected_station(NULL) })

    # --- Main content layout ---
    output$content <- renderUI({
      if (length(input$commune) == 0) {
        div(
          class = "d-flex flex-column align-items-center justify-content-center text-muted",
          style = "min-height: 500px; gap: 1rem;",
          bsicons::bs_icon("arrow-left-circle", size = "3em"),
          tags$h5("Select a department and a commune", class = "mb-0")
        )
      } else {
        commune_label <- paste(input$commune, collapse = ", ")
        tagList(
          # --- Top row: 6 KPI cards ---
          layout_columns(
            col_widths = c(2, 2, 2, 2, 2, 2),
            value_box("Stations",          textOutput(session$ns("kpi_stations")),  showcase = bsicons::bs_icon("pin-map-fill"),            theme = "primary"),
            value_box("Available bikes",   textOutput(session$ns("kpi_bikes")),     showcase = bsicons::bs_icon("bicycle"),                 theme = "success"),
            value_box("Electrical",        textOutput(session$ns("kpi_ebikes")),    showcase = bsicons::bs_icon("lightning-charge-fill"),    theme = "info"),
            value_box("Mechanical",        textOutput(session$ns("kpi_mech")),      showcase = bsicons::bs_icon("gear-fill"),                theme = "secondary"),
            value_box("Critical stations", textOutput(session$ns("kpi_critical")),  showcase = bsicons::bs_icon("exclamation-triangle-fill"), theme = "danger"),
            value_box("Avg bike avail.",   textOutput(session$ns("kpi_rate")),      showcase = bsicons::bs_icon("graph-up-arrow"),           theme = "warning")
          ),
          # --- Bottom row: left panel | map ---
          layout_columns(
            col_widths = c(5, 7),

            # LEFT: dock/fully-op cards + time series chart
            tagList(
              layout_columns(
                col_widths = c(6, 6),
                value_box("Avg dock avail.",   textOutput(session$ns("kpi_dock_rate")), showcase = bsicons::bs_icon("sign-stop"),         theme = "light"),
                value_box("Fully operational", textOutput(session$ns("kpi_fully_op")),  showcase = bsicons::bs_icon("check-circle-fill"), theme = "success")
              ),
              card(
                card_header(
                  div(
                    style = "display: flex; align-items: center; width: 100%;",
                    div(
                      style = "display: flex; align-items: center; gap: 0.5rem;",
                      bsicons::bs_icon("graph-up"),
                      textOutput(session$ns("chart_title"), inline = TRUE)
                    ),
                    div(style = "margin-left: auto;", uiOutput(session$ns("chart_view_ui")))
                  )
                ),
                plotlyOutput(session$ns("timeseries_chart"), height = "340px")
              )
            ),

            # RIGHT: map
            card(
              card_header(
                div(
                  style = "display: flex; align-items: center; width: 100%;",
                  div(
                    style = "display: flex; align-items: center; gap: 0.5rem;",
                    bsicons::bs_icon("map"),
                    tags$span("Stations — ", tags$b(commune_label))
                  ),
                  div(style = "margin-left: auto;",
                      selectInput(session$ns("map_kpi"), label = NULL,
                                  choices = GEO_KPI_CHOICES, width = "200px"))
                )
              ),
              leafletOutput(session$ns("map"), height = "480px")
            )
          )
        )
      }
    })

    # --- Sub-modules ---
    geo_kpis_server(input, output, session, commune_data)
    geo_map_server(input, output, session, commune_data, selected_station)
    geo_chart_server(input, output, session, timeseries_data, selected_station, selected_date)
  })
}
