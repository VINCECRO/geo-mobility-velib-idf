# modules/mod_overview.R
# Dashboard vue globale : KPIs réseau sur le dernier snapshot

mod_overview_ui <- function(id) {
  ns <- NS(id)
  layout_columns(
    col_widths = c(5, 7),

    # --- Colonne gauche : 6 KPI cards en 3x2 ---
    layout_columns(
      col_widths = c(6, 6),
      value_box(
        title    = "Available bikes",
        value    = textOutput(ns("kpi_bikes")),
        showcase = bsicons::bs_icon("bicycle"),
        theme    = "primary"
      ),
      value_box(
        title    = "Electrical bikes",
        value    = textOutput(ns("kpi_ebikes")),
        showcase = bsicons::bs_icon("lightning-charge"),
        theme    = "success"
      ),
      value_box(
        title    = "Mechanical bikes",
        value    = textOutput(ns("kpi_mechanical")),
        showcase = bsicons::bs_icon("gear"),
        theme    = "secondary"
      ),
      value_box(
        title    = "Critical stations",
        value    = textOutput(ns("kpi_critical")),
        showcase = bsicons::bs_icon("exclamation-triangle"),
        theme    = "danger"
      ),
      value_box(
        title    = "Bike availability rate",
        value    = textOutput(ns("kpi_rate")),
        showcase = bsicons::bs_icon("graph-up"),
        theme    = "info"
      ),
      value_box(
        title    = "Dock availability rate",
        value    = textOutput(ns("kpi_dock_rate")),
        showcase = bsicons::bs_icon("sign-stop"),
        theme    = "warning"
      )
    ),

    # --- Colonne droite : carte Paris ---
    card(
      card_header(
        div(
          style = "display: flex; justify-content: space-between; align-items: center;",
          span("Station map"),
          selectInput(
            ns("map_kpi"),
            label = NULL,
            choices = c(
              "Available bikes"  = "num_bikes_available",
              "Electrical bikes" = "ebikes_available",
              "Mechanical bikes" = "mechanical_available",
              "Docks available"="num_docks_available",
              "Critical station" = "is_critical",
              "Critical bike availability"="is_bike_critical",
              "Critical dock availability"="is_dock_critical"
            ),
            width = "180px"
          )
        )
      ),
      leafletOutput(ns("map_stations"), height = "500px")
    )
  )
}

mod_overview_server <- function(id, pool, last_snapshot, stations) {
  moduleServer(id, function(input, output, session) {

    # Données agrégées sur le dernier snapshot
    snapshot_data <- reactive({
      req(last_snapshot())
      query(pool, "
        SELECT
          station_id,
          station_name,
          commune_name,
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
        WHERE extracted_at = (SELECT MAX(extracted_at) FROM marts.fct_station_availability)
      ")
    })

    # --- KPIs ---
    output$kpi_bikes <- renderText({
      scales::comma(sum(snapshot_data()$num_bikes_available, na.rm = TRUE))
    })

    output$kpi_ebikes <- renderText({
      scales::comma(sum(snapshot_data()$ebikes_available, na.rm = TRUE))
    })

    output$kpi_mechanical <- renderText({
      scales::comma(sum(snapshot_data()$mechanical_available, na.rm = TRUE))
    })

    output$kpi_critical <- renderText({
      df  <- snapshot_data()
      n   <- sum(df$is_critical, na.rm = TRUE)
      pct <- round(n / nrow(df) * 100, 1)
      glue("{n} ({pct}%)")
    })

    output$kpi_rate <- renderText({
      paste0(round(mean(snapshot_data()$availability_rate, na.rm = TRUE), 1), "%")
    })

    output$kpi_dock_rate <- renderText({
      paste0(round(mean(snapshot_data()$dock_availability_rate, na.rm = TRUE), 1), "%")
    })

    # --- Carte Paris ---
    output$map_stations <- renderLeaflet({
      df <- snapshot_data()
      req(df)
      leaflet() %>%
        addProviderTiles(providers$CartoDB.Positron) %>%
        fitBounds(
          lng1 = min(df$longitude, na.rm = TRUE),
          lat1 = min(df$latitude,  na.rm = TRUE),
          lng2 = max(df$longitude, na.rm = TRUE),
          lat2 = max(df$latitude,  na.rm = TRUE)
        )
    })

    # Labels des KPIs (valeur → label affiché)
    kpi_labels <- c(
      "num_bikes_available"  = "Available bikes",
      "ebikes_available"     = "Electrical bikes",
      "mechanical_available" = "Mechanical bikes",
      "num_docks_available"  = "Docks available",
      "is_critical"          = "Critical station",
      "is_bike_critical"     = "Critical bike availability",
      "is_dock_critical"     = "Critical dock availability"
    )

    # KPIs binaires vs continus
    kpi_binary     <- c("is_critical","is_bike_critical","is_dock_critical")
    kpi_continuous <- c("num_bikes_available", "ebikes_available", "mechanical_available", "num_docks_available")

    observe({
      df  <- snapshot_data()
      kpi <- input$map_kpi
      req(df, kpi)

      vals      <- df[[kpi]]
      kpi_label <- kpi_labels[[kpi]]
    # Define color scale and legend
      # --- Couleur, rayon et légende selon le type de KPI ---
      if (kpi %in% kpi_binary) {
        colors        <- ifelse(vals, COLORS$binary["critical"], COLORS$binary["ok"])
        radius        <- 4
        legend_colors <- COLORS$binary
        legend_labels <- c("Normal", "Critical")
        legend_title  <- kpi_label

      } else {
        breaks        <- quantile(vals, probs = c(0, .25, .5, .75, 1), na.rm = TRUE)
        pal           <- colorBin(COLORS$quartile, domain = vals, bins = breaks, na.color = "#aaa")
        colors        <- pal(vals)
        radius        <- 4
        legend_colors <- COLORS$quartile
        legend_labels <- c(
          glue("Q1  [{round(breaks[1],1)} – {round(breaks[2],1)}]"),
          glue("Q2  [{round(breaks[2],1)} – {round(breaks[3],1)}]"),
          glue("Q3  [{round(breaks[3],1)} – {round(breaks[4],1)}]"),
          glue("Q4  [{round(breaks[4],1)} – {round(breaks[5],1)}]")
        )
        legend_title  <- kpi_label
      }

      df$marker_color <- colors
      # Tooltip definition
      df$popup_text <- paste0(
        "<b>", df$station_name, "</b><br>",
        "Available bikes : ", round(df$num_bikes_available, 1), "<br>",
        "Electrical bikes : ", round(df$ebikes_available, 1), "<br>",
        "Mechanical bikes : ", round(df$mechanical_available, 1), "<br>",
        "Docks available : ", round(df$num_docks_available, 1), "<br>",
        "Availability rate : ", round(df$availability_rate, 1), "%"
      )
      df$label_text <- paste0(df$station_name, " — ", kpi_label, " : ", vals)

      leafletProxy("map_stations", session) %>%
        clearMarkers() %>%
        clearControls() %>%
        addCircleMarkers(
          data        = df,
          lng         = ~longitude,
          lat         = ~latitude,  
          radius      = radius,
          color       = ~marker_color,
          fillOpacity = 1,
          stroke      = FALSE,
          label       = ~label_text,
          popup       = ~popup_text
        ) %>%
        addLegend(
          position = "bottomright",
          colors   = legend_colors,
          labels   = legend_labels,
          title    = legend_title,
          opacity  = 1
        )
    })
  })
}
