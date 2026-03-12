# modules/mod_geo.R
# Dashboard with commune selection

mod_geo_ui <- function(id) {
  ns <- NS(id)

  layout_sidebar(
    sidebar = sidebar(
      width = 300,
      open  = TRUE,

      # --- Location selection ---
      tags$div(
        class = "mb-3",
        tags$small(class = "text-muted text-uppercase fw-bold", "Location")
      ),

      pickerInput(
        ns("dept"),
        label   = tags$span(bsicons::bs_icon("map"), " Department"),
        choices = NULL,
        multiple = TRUE,
        options = pickerOptions(
          liveSearch            = TRUE,
          actionsBox            = TRUE,
          liveSearchPlaceholder = "Search...",
          deselectAllText       = "Remove selection",
          selectAllText         = "Select all",
          noneSelectedText      = "— choose location —",
          style                 = "btn-outline-primary"
        ),
        width = "100%"
      ),

      uiOutput(ns("commune_ui")),

      hr(),

      # --- Snapshot ---
      tags$div(
        class = "mb-2",
        tags$small(class = "text-muted text-uppercase fw-bold", "Snapshot")
      ),

      switchInput(
        ns("use_custom_ts"),
        label    = "See other timestamp",
        value    = FALSE,
        onLabel  = "Custom",
        offLabel = "Latest",
        size     = "small",
        width    = "100%"
      ),

      uiOutput(ns("ts_date_ui")),
      uiOutput(ns("ts_slider_ui")),
      uiOutput(ns("snapshot_info"))
    ),

    uiOutput(ns("content"))
  )
}

sql_in <- function(vals) {
  paste0("'", gsub("'", "''", vals), "'", collapse = ", ")
}

filter_by_ampm <- function(ts_list, ampm) {
  hours <- as.integer(format(ts_list, "%H", tz = "Europe/Paris"))
  if (ampm == "AM") ts_list[hours < 12] else ts_list[hours >= 12]
}

mod_geo_server <- function(id, pool) {
  moduleServer(id, function(input, output, session) {

    # --- Departments query ---
    depts <- query(pool, "
      SELECT DISTINCT department_number
      FROM marts.dim_station
      WHERE current_validity = TRUE
      ORDER BY department_number
    ") %>% pull(department_number)

    # --- Update commune selection based on Department
    updatePickerInput(session, "dept",
      choices  = setNames(depts, paste0("Dép. ", depts)),
      selected = character(0)
    )

    # --- Commune picker ---
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
            actionsBox            = TRUE,
            liveSearch            = TRUE,
            liveSearchPlaceholder = "Search...",
            deselectAllText       = "Remove selection",
            selectAllText         = "Select all",
            noneSelectedText      = "— choose location —",
            style                 = "btn-outline-primary"
          ),
          width = "100%"
        )
      )
    })

    # --- Date picker (shown when use_custom_ts = TRUE) ---
    output$ts_date_ui <- renderUI({
      req(isTRUE(input$use_custom_ts))

      date_range <- query(pool, "
        SELECT
          DATE(MIN(extracted_at) AT TIME ZONE 'Europe/Paris') AS min_date,
          DATE(MAX(extracted_at) AT TIME ZONE 'Europe/Paris') AS max_date
        FROM marts.fct_station_availability
      ")

      tagList(
        tags$div(class = "mt-2"),
        dateInput(
          session$ns("ts_date"),
          label  = tags$span(bsicons::bs_icon("calendar3"), " Select date"),
          value  = as.character(date_range$max_date),
          min    = as.character(date_range$min_date),
          max    = as.character(date_range$max_date),
          format = "dd/mm/yyyy",
          width  = "100%"
        )
      )
    })

    # --- Available timestamps for selected date ---
    available_timestamps <- reactive({
      req(isTRUE(input$use_custom_ts), input$ts_date)
      query(pool, glue("
        SELECT DISTINCT extracted_at
        FROM marts.fct_station_availability
        WHERE DATE(extracted_at AT TIME ZONE 'Europe/Paris') = '{input$ts_date}'
        ORDER BY extracted_at
      ")) %>% pull(extracted_at)
    })

    # --- Timestamp slider (shown after date selection) ---
    output$ts_slider_ui <- renderUI({
      req(isTRUE(input$use_custom_ts), input$ts_date)
      ts_list <- available_timestamps()
      req(length(ts_list) > 0)

      hours   <- as.integer(format(ts_list, "%H", tz = "Europe/Paris"))
      has_am  <- any(hours < 12)
      has_pm  <- any(hours >= 12)

      ampm_choices <- c()
      if (has_am) ampm_choices <- c(ampm_choices, "AM (00h–11h)" = "AM")
      if (has_pm) ampm_choices <- c(ampm_choices, "PM (12h–23h)" = "PM")
      default_ampm <- if (has_pm) "PM" else "AM"

      tagList(
        tags$div(class = "mt-2"),
        radioGroupButtons(
          session$ns("ts_ampm"),
          label    = NULL,
          choices  = ampm_choices,
          selected = default_ampm,
          justified = TRUE,
          size     = "sm"
        ),
        tags$div(class = "mt-2"),
        uiOutput(session$ns("ts_index_ui")),
        div(
          style = "display: flex; justify-content: space-between; align-items: center; margin-top: 6px;",
          actionButton(
            session$ns("ts_prev"),
            label = bsicons::bs_icon("chevron-left"),
            class = "btn-sm btn-outline-secondary"
          ),
          tags$span(
            style = "font-size: 1rem; font-weight: bold;",
            textOutput(session$ns("ts_current_label"), inline = TRUE)
          ),
          actionButton(
            session$ns("ts_next"),
            label = bsicons::bs_icon("chevron-right"),
            class = "btn-sm btn-outline-secondary"
          )
        )
      )
    })

    # --- Index slider (rebuilt when AM/PM changes) ---
    output$ts_index_ui <- renderUI({
      req(isTRUE(input$use_custom_ts), input$ts_date, input$ts_ampm)
      ts_list  <- available_timestamps()
      filtered <- filter_by_ampm(ts_list, input$ts_ampm)
      req(length(filtered) > 0)

      labels <- format(filtered, "%H:%M", tz = "Europe/Paris")

      sliderTextInput(
        session$ns("ts_index"),
        label    = NULL,
        choices  = labels,
        selected = labels[length(labels)],
        force_edges = TRUE,
        width    = "100%"
      )
    })

    # --- Current time label (repete le slider, utile entre les fleches) ---
    output$ts_current_label <- renderText({
      req(input$ts_index)
      input$ts_index
    })

    # --- Arrow navigation ---
    observeEvent(input$ts_prev, {
      req(input$ts_ampm, input$ts_index)
      ts_list  <- available_timestamps()
      filtered <- filter_by_ampm(ts_list, input$ts_ampm)
      labels   <- format(filtered, "%H:%M", tz = "Europe/Paris")
      idx      <- which(labels == input$ts_index)
      req(length(idx) > 0, idx[1] > 1)
      updateSliderTextInput(session, "ts_index", selected = labels[idx[1] - 1])
    })

    observeEvent(input$ts_next, {
      req(input$ts_ampm, input$ts_index)
      ts_list  <- available_timestamps()
      filtered <- filter_by_ampm(ts_list, input$ts_ampm)
      labels   <- format(filtered, "%H:%M", tz = "Europe/Paris")
      idx      <- which(labels == input$ts_index)
      req(length(idx) > 0, idx[1] < length(labels))
      updateSliderTextInput(session, "ts_index", selected = labels[idx[1] + 1])
    })

    # --- Snapshot info banner ---
    output$snapshot_info <- renderUI({
      if (!isTRUE(input$use_custom_ts)) {
        tags$div(
          class = "text-muted mt-2",
          style = "font-size: 0.78rem;",
          bsicons::bs_icon("info-circle"),
          " Data from latest snapshot."
        )
      } else {
        ts <- selected_ts()
        if (!is.null(ts)) {
          tags$div(
            class = "text-info mt-2",
            style = "font-size: 0.78rem;",
            bsicons::bs_icon("clock-history"),
            tags$b(format(ts, "%d/%m/%Y %H:%M"))
          )
        }
      }
    })

    # --- Resolved timestamp (NULL = latest) ---
    selected_ts <- reactive({
      if (!isTRUE(input$use_custom_ts)) return(NULL)
      req(input$ts_date, input$ts_ampm, input$ts_index)
      ts_list  <- available_timestamps()
      filtered <- filter_by_ampm(ts_list, input$ts_ampm)
      req(length(filtered) > 0)
      labels <- format(filtered, "%H:%M", tz = "Europe/Paris")
      idx    <- which(labels == input$ts_index)
      req(length(idx) > 0)
      filtered[[idx[1]]]
    })

    # --- WHERE clause for timestamp ---
    ts_filter <- reactive({
      ts <- selected_ts()
      if (is.null(ts)) {
        "extracted_at = (SELECT MAX(extracted_at) FROM marts.fct_station_availability)"
      } else {
        ts_str <- format(lubridate::with_tz(ts, "UTC"), "%Y-%m-%d %H:%M:%S")
        glue("extracted_at = '{ts_str} UTC'::timestamptz")
      }
    })

    # --- Data for selected commune + snapshot ---
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
        WHERE {ts_filter()}
          AND commune_name IN ({sql_in(input$commune)})
      "))
    })

    # --- KPI labels & types (mirror mod_overview) ---
    kpi_choices <- c(
      "Available bikes"            = "num_bikes_available",
      "Electrical bikes"           = "ebikes_available",
      "Mechanical bikes"           = "mechanical_available",
      "Docks available"            = "num_docks_available",
      "Bike availability rate"     = "availability_rate",
      "Dock availability rate"     = "dock_availability_rate",
      "Critical station"           = "is_critical",
      "Critical bike availability" = "is_bike_critical",
      "Critical dock availability" = "is_dock_critical"
    )

    kpi_labels <- setNames(names(kpi_choices), kpi_choices)

    kpi_binary     <- c("is_critical", "is_bike_critical", "is_dock_critical")
    kpi_rate       <- c("availability_rate", "dock_availability_rate")
    kpi_continuous <- c("num_bikes_available", "ebikes_available",
                        "mechanical_available", "num_docks_available")

    # --- Main content ---
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
              title    = "Avg bike availability",
              value    = textOutput(session$ns("kpi_rate")),
              showcase = bsicons::bs_icon("graph-up-arrow"),
              theme    = "warning"
            )
          ),
          layout_columns(
            col_widths = c(6, 6),
            value_box(
              title    = "Avg dock availability",
              value    = textOutput(session$ns("kpi_dock_rate")),
              showcase = bsicons::bs_icon("sign-stop"),
              theme    = "light"
            ),
            value_box(
              title    = "Fully operational",
              value    = textOutput(session$ns("kpi_fully_op")),
              showcase = bsicons::bs_icon("check-circle-fill"),
              theme    = "success"
            )
          ),
          card(
            card_header(
              div(
                style = "display: flex; align-items: center; width: 100%;",
                div(
                  style = "display: flex; align-items: center; gap: 0.5rem;",
                  bsicons::bs_icon("map"),
                  tags$span("Stations — ", tags$b(commune_label))
                ),
                div(
                  style = "margin-left: auto;",
                  selectInput(
                    session$ns("map_kpi"),
                    label   = NULL,
                    choices = kpi_choices,
                    width   = "200px"
                  )
                )
              )
            ),
            leafletOutput(session$ns("map"), height = "460px")
          )
        )
      }
    })

    # --- KPIs ---
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

    # --- Map (base + markers in one render to avoid proxy timing issues) ---
    output$map <- renderLeaflet({
      df  <- commune_data()
      kpi <- input$map_kpi
      req(nrow(df) > 0)

      # Fallback to first KPI if input not yet initialised
      if (is.null(kpi) || !kpi %in% names(df)) kpi <- "num_bikes_available"

      vals      <- df[[kpi]]
      kpi_label <- kpi_labels[[kpi]]

      if (kpi %in% kpi_binary) {
        colors        <- ifelse(vals, COLORS$binary["critical"], COLORS$binary["ok"])
        legend_colors <- unname(COLORS$binary)
        legend_labels <- c("Normal", "Critical")

      } else if (kpi %in% kpi_rate) {
        pal           <- colorNumeric(c(COLORS$linear["low"], COLORS$linear["mid"], COLORS$linear["high"]),
                                      domain = c(0, 100))
        colors        <- pal(vals)
        breaks        <- c(0, 25, 50, 75, 100)
        legend_pal    <- colorNumeric(c(COLORS$linear["low"], COLORS$linear["mid"], COLORS$linear["high"]),
                                      domain = c(0, 100))
        legend_colors <- sapply(breaks[-length(breaks)], legend_pal)
        legend_labels <- c("0–25%", "25–50%", "50–75%", "75–100%")

      } else {
        breaks        <- quantile(vals, probs = c(0, .25, .5, .75, 1), na.rm = TRUE)
        pal           <- colorBin(COLORS$quartile, domain = vals, bins = breaks, na.color = "#aaa")
        colors        <- pal(vals)
        legend_colors <- COLORS$quartile
        legend_labels <- c(
          glue("Q1 [{round(breaks[1],1)} – {round(breaks[2],1)}]"),
          glue("Q2 [{round(breaks[2],1)} – {round(breaks[3],1)}]"),
          glue("Q3 [{round(breaks[3],1)} – {round(breaks[4],1)}]"),
          glue("Q4 [{round(breaks[4],1)} – {round(breaks[5],1)}]")
        )
      }

      df$marker_color <- colors
      df$popup_text <- paste0(
        "<b>", df$station_name, "</b><br>",
        "Available bikes: ",   df$num_bikes_available, "<br>",
        "Electrical bikes: ",  df$ebikes_available, "<br>",
        "Mechanical bikes: ",  df$mechanical_available, "<br>",
        "Docks available: ",   df$num_docks_available, "<br>",
        "Bike rate: ",         round(df$availability_rate, 1), "%<br>",
        "Dock rate: ",         round(df$dock_availability_rate, 1), "%"
      )
      df$label_text <- paste0(df$station_name, " — ", kpi_label, ": ", vals)

      leaflet(df) %>%
        addProviderTiles(providers$CartoDB.Positron) %>%
        fitBounds(
          lng1 = min(df$longitude, na.rm = TRUE),
          lat1 = min(df$latitude,  na.rm = TRUE),
          lng2 = max(df$longitude, na.rm = TRUE),
          lat2 = max(df$latitude,  na.rm = TRUE)
        ) %>%
        addCircleMarkers(
          lng         = ~longitude,
          lat         = ~latitude,
          radius      = 5,
          color       = ~marker_color,
          fillOpacity = 0.9,
          stroke      = TRUE,
          weight      = 1,
          opacity     = 0.5,
          label       = ~label_text,
          popup       = ~popup_text
        ) %>%
        addLegend(
          position = "bottomright",
          colors   = legend_colors,
          labels   = legend_labels,
          title    = kpi_label,
          opacity  = 1
        )
    })
  })
}
