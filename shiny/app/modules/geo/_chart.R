# geo/_chart.R
# Time series chart: bikes, ebikes, mechanical

CHART_COLORS <- c(
  num_bikes_available  = "#198754",  # success green
  ebikes_available     = "#0dcaf0",  # info cyan
  mechanical_available = "#6c757d"   # secondary grey
)

CHART_LABELS <- c(
  num_bikes_available  = "Available bikes",
  ebikes_available     = "Electrical",
  mechanical_available = "Mechanical"
)

geo_chart_server <- function(input, output, session, timeseries_data, selected_station, selected_date) {

  output$chart_view_ui <- renderUI({
    radioGroupButtons(
      session$ns("chart_view"),
      label    = NULL,
      choices  = c("Global" = "global", "Daily" = "daily"),
      selected = "global",
      size     = "sm"
    )
  })

  chart_df <- reactive({
    df  <- timeseries_data()
    req(nrow(df) > 0)
    sta <- selected_station()

    if (!is.null(sta)) {
      df <- df[df$station_name == sta, , drop = FALSE]
    } else {
      df <- df %>%
        group_by(ts) %>%
        summarise(
          num_bikes_available  = sum(num_bikes_available,  na.rm = TRUE),
          ebikes_available     = sum(ebikes_available,     na.rm = TRUE),
          mechanical_available = sum(mechanical_available, na.rm = TRUE),
          .groups = "drop"
        )
    }

    if (!is.null(input$chart_view) && input$chart_view == "daily") {
      df <- df[as.Date(df$ts) == selected_date(), , drop = FALSE]
    }

    df
  })

  output$chart_title <- renderText({
    sta <- selected_station()
    if (!is.null(sta)) sta else "All stations \u2014 commune total"
  })

  output$timeseries_chart <- renderPlotly({
    df  <- chart_df()
    req(nrow(df) > 0)
    sta <- selected_station()

    subtitle <- if (!is.null(sta)) {
      paste0("<b>", sta, "</b>")
    } else {
      "Commune total (sum)"
    }

    plot_ly(df, x = ~ts) %>%
      add_lines(
        y             = ~num_bikes_available,
        name          = CHART_LABELS[["num_bikes_available"]],
        line          = list(color = CHART_COLORS[["num_bikes_available"]], width = 2),
        hovertemplate = "%{y}<extra>Available bikes</extra>"
      ) %>%
      add_lines(
        y             = ~ebikes_available,
        name          = CHART_LABELS[["ebikes_available"]],
        line          = list(color = CHART_COLORS[["ebikes_available"]], width = 2),
        hovertemplate = "%{y}<extra>Electrical</extra>"
      ) %>%
      add_lines(
        y             = ~mechanical_available,
        name          = CHART_LABELS[["mechanical_available"]],
        line          = list(color = CHART_COLORS[["mechanical_available"]], width = 2),
        hovertemplate = "%{y}<extra>Mechanical</extra>"
      ) %>%
      layout(
        annotations = list(list(
          text      = subtitle,
          x         = 0, y = 1.12,
          xref      = "paper", yref = "paper",
          xanchor   = "left", showarrow = FALSE,
          font      = list(size = 12, color = "#6c757d")
        )),
        margin        = list(l = 40, r = 10, t = 40, b = 40),
        xaxis         = list(title = "", showgrid = FALSE),
        yaxis         = list(title = "Bikes", rangemode = "tozero"),
        legend        = list(orientation = "h", x = 0, y = 1.22),
        paper_bgcolor = "rgba(0,0,0,0)",
        plot_bgcolor  = "rgba(0,0,0,0)",
        hovermode     = "x unified"
      ) %>%
      config(displayModeBar = FALSE)
  })
}
