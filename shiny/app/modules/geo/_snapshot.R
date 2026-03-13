# geo/_snapshot.R
# Snapshot selection: date picker, AM/PM filter, time slider, timestamp resolution
#
# Architecture :
#   available_timestamps() → data.frame(ts_sql, ts_label)
#     ts_sql   : string exacte issue de PostgreSQL (to_char) → injectée telle quelle dans WHERE
#     ts_label : "HH:MM" en Europe/Paris → affiché sur le slider
#
# Plus de round-trip POSIXct → string → pas d'erreur de précision virgule flottante.

filter_by_ampm <- function(ts_df, ampm) {
  hours <- as.integer(substr(ts_df$ts_label, 1, 2))
  if (ampm == "AM") ts_df[hours < 12, ] else ts_df[hours >= 12, ]
}

geo_snapshot_server <- function(input, output, session, pool) {

  # Retourne data.frame(ts_sql, ts_label) pour le jour sélectionné
  available_timestamps <- reactive({
    req(isTRUE(input$use_custom_ts), input$ts_date)
    query(pool, glue("
      SELECT DISTINCT
        to_char(extracted_at, 'YYYY-MM-DD HH24:MI:SS.USOF') AS ts_sql,
        to_char(extracted_at AT TIME ZONE 'Europe/Paris', 'HH24:MI') AS ts_label
      FROM marts.fct_station_availability
      WHERE DATE(extracted_at AT TIME ZONE 'Europe/Paris') = '{input$ts_date}'
      ORDER BY ts_sql
    "))
  })

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

  output$ts_slider_ui <- renderUI({
    req(isTRUE(input$use_custom_ts), input$ts_date)
    ts_df <- available_timestamps()
    req(nrow(ts_df) > 0)

    hours        <- as.integer(substr(ts_df$ts_label, 1, 2))
    ampm_choices <- c()
    if (any(hours < 12))  ampm_choices <- c(ampm_choices, "AM (00h–11h)" = "AM")
    if (any(hours >= 12)) ampm_choices <- c(ampm_choices, "PM (12h–23h)" = "PM")
    default_ampm <- if ("PM" %in% ampm_choices) "PM" else "AM"

    tagList(
      tags$div(class = "mt-2"),
      radioGroupButtons(
        session$ns("ts_ampm"),
        label     = NULL,
        choices   = ampm_choices,
        selected  = default_ampm,
        justified = TRUE,
        size      = "sm"
      ),
      tags$div(class = "mt-2"),
      uiOutput(session$ns("ts_index_ui")),
      div(
        style = "display: flex; justify-content: space-between; align-items: center; margin-top: 6px;",
        actionButton(session$ns("ts_prev"), label = bsicons::bs_icon("chevron-left"),  class = "btn-sm btn-outline-secondary"),
        tags$span(style = "font-size: 1rem; font-weight: bold;",
                  textOutput(session$ns("ts_current_label"), inline = TRUE)),
        actionButton(session$ns("ts_next"), label = bsicons::bs_icon("chevron-right"), class = "btn-sm btn-outline-secondary")
      )
    )
  })

  output$ts_index_ui <- renderUI({
    req(isTRUE(input$use_custom_ts), input$ts_date, input$ts_ampm)
    filtered <- filter_by_ampm(available_timestamps(), input$ts_ampm)
    req(nrow(filtered) > 0)
    labels <- filtered$ts_label
    sliderTextInput(
      session$ns("ts_index"),
      label       = NULL,
      choices     = labels,
      selected    = labels[length(labels)],
      force_edges = TRUE,
      width       = "100%"
    )
  })

  output$ts_current_label <- renderText({
    req(input$ts_index)
    input$ts_index
  })

  observeEvent(input$ts_prev, {
    req(input$ts_ampm, input$ts_index)
    labels <- filter_by_ampm(available_timestamps(), input$ts_ampm)$ts_label
    idx    <- which(labels == input$ts_index)
    req(length(idx) > 0, idx[1] > 1)
    updateSliderTextInput(session, "ts_index", selected = labels[idx[1] - 1])
  })

  observeEvent(input$ts_next, {
    req(input$ts_ampm, input$ts_index)
    labels <- filter_by_ampm(available_timestamps(), input$ts_ampm)$ts_label
    idx    <- which(labels == input$ts_index)
    req(length(idx) > 0, idx[1] < length(labels))
    updateSliderTextInput(session, "ts_index", selected = labels[idx[1] + 1])
  })

  output$snapshot_info <- renderUI({
    if (!isTRUE(input$use_custom_ts)) {
      tags$div(class = "text-muted mt-2", style = "font-size: 0.78rem;",
               bsicons::bs_icon("info-circle"), " Data from latest snapshot.")
    } else {
      ts_sql <- selected_ts()
      if (!is.null(ts_sql)) {
        display <- paste(format(as.Date(input$ts_date), "%d/%m/%Y"), input$ts_index)
        tags$div(class = "text-info mt-2", style = "font-size: 0.78rem;",
                 bsicons::bs_icon("clock-history"), tags$b(display))
      }
    }
  })

  # Retourne la string ts_sql exacte (issue de PostgreSQL) pour le timestamp sélectionné
  selected_ts <- reactive({
    if (!isTRUE(input$use_custom_ts)) return(NULL)
    req(input$ts_date, input$ts_ampm, input$ts_index)
    filtered <- filter_by_ampm(available_timestamps(), input$ts_ampm)
    req(nrow(filtered) > 0)
    idx <- which(filtered$ts_label == input$ts_index)
    req(length(idx) > 0)
    filtered$ts_sql[idx[1]]
  })

  # Clause WHERE injectée telle quelle — ts_sql est la représentation exacte de PostgreSQL
  ts_filter <- reactive({
    ts_sql <- selected_ts()
    if (is.null(ts_sql)) {
      "extracted_at = (SELECT MAX(extracted_at) FROM marts.fct_station_availability)"
    } else {
      glue("extracted_at = '{ts_sql}'::timestamptz")
    }
  })

  list(ts_filter = ts_filter, selected_ts = selected_ts)
}
