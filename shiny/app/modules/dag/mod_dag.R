# mod_dag.R
# Airflow DAG monitoring dashboard
#
# "Full history" mode (default):
#   Waffle aggregated by (date × hour) — color = worst status of the hour
#
# "Specific date" mode:
#   Detailed waffle by (hour × run #) — color = individual status
#   + future access to task_instance by clicking a cell

mod_dag_ui <- function(id) {
  ns <- NS(id)

  layout_sidebar(
    sidebar = sidebar(
      title = tags$span(bsicons::bs_icon("diagram-3"), " DAG Monitoring"),
      width  = 260,

      materialSwitch(
        inputId = ns("use_custom_date"),
        label   = "View specific date",
        status  = "info",
        value   = FALSE
      ),
      uiOutput(ns("date_picker_ui")),
      uiOutput(ns("snapshot_info"))
    ),

    # ----------- Main content -----------
    tags$div(
      style = "padding: 12px; overflow-y: auto;",

      # KPI row
      layout_columns(
        col_widths = c(3, 3, 3, 3),

        value_box(
          title    = "Active DAGs",
          value    = textOutput(ns("kpi_n_dags"), inline = TRUE),
          showcase = bsicons::bs_icon("diagram-3"),
          theme    = "primary"
        ),
        value_box(
          title    = "Total runs",
          value    = textOutput(ns("kpi_n_runs"), inline = TRUE),
          showcase = bsicons::bs_icon("play-circle"),
          theme    = "info"
        ),
        value_box(
          title    = "Success rate",
          value    = textOutput(ns("kpi_success_rate"), inline = TRUE),
          showcase = bsicons::bs_icon("check-circle-fill"),
          theme    = "success"
        ),
        value_box(
          title    = "Failed runs",
          value    = textOutput(ns("kpi_n_failed"), inline = TRUE),
          showcase = bsicons::bs_icon("x-circle-fill"),
          theme    = "danger"
        )
      ),

      tags$div(class = "mt-3"),

      # Dynamic waffle charts (one card per DAG)
      uiOutput(ns("waffle_ui"))
    )
  )
}

mod_dag_server <- function(id, pool) {
  moduleServer(id, function(input, output, session) {

    # --- Sub-module: date selection ---
    snap          <- dag_snapshot_server(input, output, session, pool)
    selected_date <- snap$selected_date

    # --- Raw data: all DAG runs (filtered if a date is selected) ---
    dag_runs <- reactive({
      date_val <- selected_date()

      if (is.null(date_val)) {
        # Full history — columns needed for the aggregated waffle
        query(pool, "
          SELECT
            dag_id,
            run_id,
            state,
            logical_date,
            start_date,
            end_date,
            DATE(logical_date AT TIME ZONE 'Europe/Paris') AS run_date,
            EXTRACT(HOUR FROM logical_date AT TIME ZONE 'Europe/Paris') AS run_hour
          FROM dag_run
          ORDER BY dag_id, logical_date
        ")
      } else {
        # Specific date — extra run_of_hour column for the detailed waffle
        query(pool, glue("
          SELECT
            dag_id,
            run_id,
            state,
            logical_date,
            start_date,
            end_date,
            EXTRACT(HOUR FROM logical_date AT TIME ZONE 'Europe/Paris') AS run_hour,
            ROW_NUMBER() OVER (
              PARTITION BY dag_id,
                           EXTRACT(HOUR FROM logical_date AT TIME ZONE 'Europe/Paris')
              ORDER BY logical_date
            ) AS run_of_hour
          FROM dag_run
          WHERE DATE(logical_date AT TIME ZONE 'Europe/Paris') = '{date_val}'
          ORDER BY dag_id, run_hour
        "))
      }
    })

    # --- Sub-module: KPIs ---
    dag_kpis_server(input, output, session, dag_runs)

    # --- Sub-module: Waffle charts ---
    dag_waffle_server(input, output, session, dag_runs, selected_date)
  })
}
