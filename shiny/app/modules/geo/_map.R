# geo/_map.R
# Map rendering + KPI colour logic

GEO_KPI_CHOICES <- c(
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

GEO_KPI_LABELS <- setNames(names(GEO_KPI_CHOICES), GEO_KPI_CHOICES)
GEO_KPI_BINARY <- c("is_critical", "is_bike_critical", "is_dock_critical")
GEO_KPI_RATE   <- c("availability_rate", "dock_availability_rate")

.map_colors <- function(kpi, vals) {
  if (kpi %in% GEO_KPI_BINARY) {
    colors        <- ifelse(vals, COLORS$binary["critical"], COLORS$binary["ok"])
    legend_colors <- unname(COLORS$binary)
    legend_labels <- c("Normal", "Critical")

  } else if (kpi %in% GEO_KPI_RATE) {
    pal           <- colorNumeric(unname(COLORS$linear), domain = c(0, 100))
    colors        <- pal(vals)
    breaks        <- c(0, 25, 50, 75, 100)
    legend_colors <- sapply(breaks[-length(breaks)], pal)
    legend_labels <- c("0\u201325%", "25\u201350%", "50\u201375%", "75\u2013100%")

  } else {
    breaks        <- quantile(vals, probs = c(0, .25, .5, .75, 1), na.rm = TRUE)
    pal           <- colorBin(COLORS$quartile, domain = vals, bins = breaks, na.color = "#aaa")
    colors        <- pal(vals)
    legend_colors <- COLORS$quartile
    legend_labels <- c(
      glue("Q1 [{round(breaks[1],1)} \u2013 {round(breaks[2],1)}]"),
      glue("Q2 [{round(breaks[2],1)} \u2013 {round(breaks[3],1)}]"),
      glue("Q3 [{round(breaks[3],1)} \u2013 {round(breaks[4],1)}]"),
      glue("Q4 [{round(breaks[4],1)} \u2013 {round(breaks[5],1)}]")
    )
  }

  list(colors = unname(colors), legend_colors = legend_colors, legend_labels = legend_labels)
}

geo_map_server <- function(input, output, session, commune_data, selected_station) {

  # Full render — same pattern as original, NO dependency on selected_station (no zoom reset on click)
  output$map <- renderLeaflet({
    df  <- commune_data()
    kpi <- input$map_kpi
    req(nrow(df) > 0)

    if (is.null(kpi) || !kpi %in% names(df)) kpi <- "num_bikes_available"

    vals      <- df[[kpi]]
    kpi_label <- GEO_KPI_LABELS[[kpi]]
    col_info  <- .map_colors(kpi, vals)

    df$marker_color <- col_info$colors
    df$popup_text <- paste0(
      "<b>", df$station_name, "</b><br>",
      "Available bikes: ",  df$num_bikes_available, "<br>",
      "Electrical bikes: ", df$ebikes_available, "<br>",
      "Mechanical bikes: ", df$mechanical_available, "<br>",
      "Docks available: ",  df$num_docks_available, "<br>",
      "Bike rate: ",        round(df$availability_rate, 1), "%<br>",
      "Dock rate: ",        round(df$dock_availability_rate, 1), "%"
    )
    df$label_text <- paste0(df$station_name, " \u2014 ", kpi_label, ": ", vals)

    leaflet(df) %>%
      addProviderTiles(providers$CartoDB.Positron) %>%
      fitBounds(
        lng1 = min(df$longitude, na.rm = TRUE), lat1 = min(df$latitude,  na.rm = TRUE),
        lng2 = max(df$longitude, na.rm = TRUE), lat2 = max(df$latitude,  na.rm = TRUE)
      ) %>%
      addCircleMarkers(
        lng         = ~longitude, lat     = ~latitude,
        layerId     = ~station_name,
        radius      = 5,          color   = ~marker_color,
        fillColor   = ~marker_color,
        fillOpacity = 0.9,        stroke  = TRUE,
        weight      = 1,          opacity = 0.5,
        label       = ~label_text, popup  = ~popup_text
      ) %>%
      addLegend(
        position = "bottomright",
        colors   = col_info$legend_colors,
        labels   = col_info$legend_labels,
        title    = kpi_label,
        opacity  = 1
      )
  })

  # Station click: toggle selection + proxy update (no renderLeaflet re-run → no zoom reset)
  observeEvent(input$map_marker_click, {
    click_id <- input$map_marker_click$id
    df       <- commune_data()
    kpi      <- isolate(input$map_kpi)
    if (is.null(kpi) || !kpi %in% names(df)) kpi <- "num_bikes_available"

    vals            <- df[[kpi]]
    col_info        <- .map_colors(kpi, vals)
    df$marker_color <- col_info$colors
    df$popup_text   <- paste0(
      "<b>", df$station_name, "</b><br>",
      "Available bikes: ",  df$num_bikes_available, "<br>",
      "Electrical bikes: ", df$ebikes_available, "<br>",
      "Mechanical bikes: ", df$mechanical_available, "<br>",
      "Docks available: ",  df$num_docks_available, "<br>",
      "Bike rate: ",        round(df$availability_rate, 1), "%<br>",
      "Dock rate: ",        round(df$dock_availability_rate, 1), "%"
    )
    df$label_text <- paste0(df$station_name, " \u2014 ", GEO_KPI_LABELS[[kpi]], ": ", vals)

    # Toggle
    new_sel <- if (!is.null(selected_station()) && selected_station() == click_id) NULL else click_id
    selected_station(new_sel)

    is_sel     <- if (is.null(new_sel)) rep(FALSE, nrow(df)) else df$station_name == new_sel
    radii      <- ifelse(is_sel, 10, 5)
    weights    <- ifelse(is_sel, 3, 1)
    stroke_col <- ifelse(is_sel, "#ffffff", df$marker_color)

    leafletProxy("map", session = session) %>%
      clearMarkers() %>%
      addCircleMarkers(
        data        = df,
        lng         = ~longitude, lat     = ~latitude,
        layerId     = ~station_name,
        radius      = radii,      color   = stroke_col,
        fillColor   = ~marker_color,
        fillOpacity = 0.9,        stroke  = TRUE,
        weight      = weights,    opacity = 0.9,
        label       = ~label_text, popup  = ~popup_text
      )
  })
}
