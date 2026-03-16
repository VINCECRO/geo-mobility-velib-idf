# dag/_waffle.R
#
# "Full history" mode (selected_date = NULL):
#   plotly heatmap — x = date, y = hour (0-23)
#   color = aggregated status (worst of the hour)
#   → perfect adjacent cells without marker size calculation
#
# "Specific date" mode (selected_date = "YYYY-MM-DD"):
#   plotly scatter + square markers, arranged in 2×6 blocks per hour:
#     - 6 hours per block row → 4 block rows (24h)
#     - each hour = 2-row × 6-column block (max 12 cells)
#     - 1-cell separator between blocks
#   → resembles a reference waffle grid

DAG_STATE_COLORS <- c(
  "success"      = "#2ecc71",
  "failed"       = "#e74c3c",
  "running"      = "#3498db",
  "queued"       = "#95a5a6",
  "up_for_retry" = "#e67e22",
  "empty"        = "#dfe6e9"
)

# State ordering for aggregation and colorscale
.STATE_LEVELS   <- c("success", "failed", "running", "queued", "up_for_retry", "empty")
.state_priority <- c(failed = 5, running = 4, up_for_retry = 3, queued = 2, success = 1, empty = 0)

.agg_state <- function(states) {
  known <- states[states %in% names(.state_priority)]
  if (length(known) == 0) return("empty")
  names(which.max(.state_priority[known]))
}

# Discrete colorscale for plotly heatmap (sharp transitions, no interpolation)
# zmin = 0, zmax = n-1; state i → z = i → fraction = i/(n-1)
.discrete_colorscale <- function(state_levels, colors) {
  n  <- length(state_levels)
  cs <- vector("list", 2L * n - 1L)
  for (i in seq_len(n - 1L)) {
    frac        <- (i - 1L) / (n - 1L)
    cs[[2L*i-1L]] <- list(frac,                    colors[state_levels[i]])
    cs[[2L*i]]    <- list(frac + 1/(n-1) - 1e-4,  colors[state_levels[i]])
  }
  cs[[2L*n - 1L]] <- list(1.0, colors[state_levels[n]])
  cs
}

# ===========================================================================
# History mode: date × hour heatmap
# ===========================================================================

.make_history_waffle <- function(df_dag) {

  df_agg <- df_dag %>%
    group_by(run_date, run_hour) %>%
    summarise(
      n_runs    = n(),
      agg_state = .agg_state(state),
      states    = paste(unique(state), collapse = ", "),
      .groups   = "drop"
    )

  all_dates <- sort(unique(as.Date(df_agg$run_date)))
  n_dates   <- length(all_dates)
  date_strs <- format(all_dates, "%d/%m")

  state_idx <- setNames(seq_along(.STATE_LEVELS) - 1L, .STATE_LEVELS)

  # Matrices [24 hours × n_dates]
  z_mat     <- matrix(state_idx["empty"], nrow = 24L, ncol = n_dates)
  hover_mat <- matrix("", nrow = 24L, ncol = n_dates)

  for (k in seq_len(nrow(df_agg))) {
    d  <- which(all_dates == as.Date(df_agg$run_date[k]))
    h  <- as.integer(df_agg$run_hour[k]) + 1L   # 1-based (hour 0 → row 1)
    st <- df_agg$agg_state[k]
    if (!(st %in% names(state_idx))) st <- "empty"
    z_mat[h, d]     <- state_idx[st]
    hover_mat[h, d] <- paste0(
      "<b>", st, "</b><br>",
      format(as.Date(df_agg$run_date[k]), "%d/%m/%Y"), " – ",
      sprintf("%02dh", h - 1L), "<br>",
      "Runs: ", df_agg$n_runs[k]
    )
  }

  # Fill hover text for empty cells
  for (h in seq_len(24L)) {
    for (d in seq_len(n_dates)) {
      if (hover_mat[h, d] == "") {
        hover_mat[h, d] <- paste0(
          format(all_dates[d], "%d/%m/%Y"), " – ",
          sprintf("%02dh", h - 1L), " — no runs"
        )
      }
    }
  }

  cs <- .discrete_colorscale(.STATE_LEVELS, DAG_STATE_COLORS)
  n  <- length(.STATE_LEVELS)

  # x-axis ticks: at most 20 dates shown
  tick_step <- max(1L, ceiling(n_dates / 20L))
  tick_idxs <- seq(1L, n_dates, by = tick_step)

  plot_ly(
    x          = seq_len(n_dates) - 1L,
    y          = 0:23,
    z          = z_mat,
    type       = "heatmap",
    colorscale = cs,
    zmin       = 0, zmax = n - 1L,
    showscale  = TRUE,
    text       = hover_mat,
    hoverinfo  = "text",
    xgap       = 1,
    ygap       = 1,
    colorbar   = list(
      tickvals  = seq_len(n) - 1L,
      ticktext  = .STATE_LEVELS,
      title     = "",
      len       = 0.45,
      thickness = 14
    )
  ) %>%
    layout(
      xaxis  = list(
        title     = "",
        tickvals  = tick_idxs - 1L,
        ticktext  = date_strs[tick_idxs],
        tickangle = -45,
        showgrid  = FALSE
      ),
      yaxis  = list(
        title     = "",
        tickvals  = seq(0, 21, by = 3),
        ticktext  = sprintf("%02dh", seq(0, 21, by = 3)),
        autorange = "reversed",
        showgrid  = FALSE
      ),
      paper_bgcolor = "rgba(0,0,0,0)",
      plot_bgcolor  = "rgba(0,0,0,0)",
      margin = list(t = 10, b = 65, l = 45, r = 80)
    ) %>%
    config(displayModeBar = FALSE)
}

# ===========================================================================
# Specific date mode: 2×6 hourly blocks
# ===========================================================================
# Layout: 6 hours per block row, 4 rows → 24 hours
# Each hour h occupies a 2-row × 6-column block
# 1-cell separator between blocks (multiplier 7 in x, 3 in y)

.hour_run_xy <- function(h, i_0based) {
  # h        : 0..23 — hour number
  # i_0based : 0..N-1 — run rank within the hour (0-indexed)
  x <- (h %% 6L) * 7L + (i_0based %% 6L)    # absolute column (0..41)
  y <- (h %/% 6L) * 3L + (i_0based %/% 6L)  # absolute row    (0..10)
  c(x = x, y = y)
}

.make_day_waffle <- function(df_dag) {

  df <- df_dag %>%
    mutate(h = as.integer(run_hour), i = as.integer(run_of_hour) - 1L)

  xy       <- t(mapply(.hour_run_xy, df$h, df$i))
  df$x_val <- xy[, "x"]
  df$y_val <- xy[, "y"]
  df$plot_state <- df$state
  df$hover_txt  <- paste0(
    "<b>", df$state, "</b><br>",
    sprintf("%02dh – run #%d", df$h, df$i + 1L), "<br>",
    "Run ID: ", df$run_id, "<br>",
    "Start: ", format(df$start_date, "%H:%M:%S"), "<br>",
    "End: ",   ifelse(is.na(df$end_date), "—", format(df$end_date, "%H:%M:%S"))
  )

  # Full 24h × 12 runs = 288 slots grid (light grey placeholders)
  slots  <- data.frame(h = rep(0:23, each = 12L), i = rep(0:11, times = 24L))
  xy_all <- t(mapply(.hour_run_xy, slots$h, slots$i))
  df_empty <- data.frame(
    x_val      = xy_all[, "x"],
    y_val      = xy_all[, "y"],
    plot_state = "empty",
    hover_txt  = " ",
    stringsAsFactors = FALSE
  )
  # Remove positions already occupied by actual runs
  actual_xy <- paste(df$x_val, df$y_val)
  df_empty  <- df_empty[!paste(df_empty$x_val, df_empty$y_val) %in% actual_xy, ]

  df_plot <- bind_rows(
    df %>% select(x_val, y_val, plot_state, hover_txt),
    df_empty
  )

  # Hour labels above each block (annotation)
  hour_annots <- lapply(0:23, function(h) {
    list(
      x         = (h %% 6L) * 7L + 2.5,
      y         = (h %/% 6L) * 3L - 0.62,
      text      = sprintf("<b>%02dh</b>", h),
      showarrow = FALSE,
      xanchor   = "center",
      font      = list(size = 8, color = "#777"),
      xref = "x", yref = "y"
    )
  })

  colors_used <- DAG_STATE_COLORS[names(DAG_STATE_COLORS) %in% df_plot$plot_state]

  plot_ly(
    df_plot,
    x         = ~x_val,
    y         = ~y_val,
    type      = "scatter",
    mode      = "markers",
    color     = ~plot_state,
    colors    = colors_used,
    marker    = list(
      symbol = "square",
      size   = 14,
      line   = list(width = 1, color = "white")
    ),
    text      = ~hover_txt,
    hoverinfo = "text"
  ) %>%
    layout(
      annotations = hour_annots,
      xaxis = list(
        showticklabels = FALSE, showgrid = FALSE, zeroline = FALSE,
        title = "", range = c(-0.8, 42.5)
      ),
      yaxis = list(
        showticklabels = FALSE, showgrid = FALSE, zeroline = FALSE,
        title = "", autorange = "reversed", range = c(11.5, -1.3)
      ),
      legend = list(orientation = "h", y = -0.05, x = 0),
      paper_bgcolor = "rgba(0,0,0,0)",
      plot_bgcolor  = "rgba(0,0,0,0)",
      margin = list(t = 10, b = 45, l = 10, r = 10)
    ) %>%
    config(displayModeBar = FALSE)
}

# ===========================================================================
# Dispatcher + dynamic rendering
# ===========================================================================

.make_waffle <- function(df_dag, is_date_mode) {
  if (nrow(df_dag) == 0) {
    return(plotly_empty() %>% layout(
      paper_bgcolor = "rgba(0,0,0,0)",
      plot_bgcolor  = "rgba(0,0,0,0)"
    ))
  }
  if (is_date_mode) .make_day_waffle(df_dag) else .make_history_waffle(df_dag)
}

dag_waffle_server <- function(input, output, session, dag_runs, selected_date) {

  dag_ids <- reactive({ sort(unique(dag_runs()$dag_id)) })

  # Dynamic UI: one card per DAG
  output$waffle_ui <- renderUI({
    ids <- dag_ids()
    if (length(ids) == 0) {
      return(tags$div(class = "text-muted text-center mt-4",
                      bsicons::bs_icon("inbox"), " No DAG runs found."))
    }
    df_all <- dag_runs()

    lapply(ids, function(dag_id) {
      safe_id  <- gsub("[^a-zA-Z0-9]", "_", dag_id)
      df_this  <- df_all[df_all$dag_id == dag_id, ]
      n_runs   <- nrow(df_this)
      n_ok     <- sum(df_this$state == "success", na.rm = TRUE)
      n_fail   <- sum(df_this$state == "failed",  na.rm = TRUE)
      rate_pct <- if (n_runs > 0) round(n_ok / n_runs * 100, 1) else NA

      card(
        class = "mb-3",
        card_header(
          class = "d-flex justify-content-between align-items-center",
          tags$span(bsicons::bs_icon("diagram-3"), " ", tags$b(dag_id)),
          tags$span(
            class = "d-flex gap-3",
            style = "font-size: 0.82rem;",
            tags$span(class = "text-muted",
                      bsicons::bs_icon("play-circle"), " ", scales::comma(n_runs), " runs"),
            tags$span(class = "text-success",
                      bsicons::bs_icon("check-circle"), " ",
                      if (!is.na(rate_pct)) paste0(rate_pct, "%") else "—"),
            tags$span(class = "text-danger",
                      bsicons::bs_icon("x-circle"), " ", scales::comma(n_fail))
          )
        ),
        plotlyOutput(session$ns(paste0("waffle_", safe_id)),
                     height = if (is.null(selected_date())) "480px" else "360px")
      )
    })
  })

  # Render plots
  observe({
    ids      <- dag_ids()
    df_all   <- dag_runs()
    date_sel <- selected_date()
    is_date  <- !is.null(date_sel)

    for (dag_id in ids) {
      local({
        local_dag  <- dag_id
        local_safe <- gsub("[^a-zA-Z0-9]", "_", local_dag)
        local_df   <- df_all[df_all$dag_id == local_dag, ]
        local_date <- is_date

        output[[paste0("waffle_", local_safe)]] <- renderPlotly({
          .make_waffle(local_df, local_date)
        })
      })
    }
  })
}
