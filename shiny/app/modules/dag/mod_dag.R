# mod_dag.R
# Dashboard de monitoring des DAG Airflow
#
# Mode "Tout l'historique" (défaut) :
#   Waffle agrégé par (date × heure) — couleur = pire statut de l'heure
#
# Mode "Date spécifique" :
#   Waffle détaillé par (heure × run #) — couleur = statut individuel
#   + accès futur aux task_instance par clic sur un carré

mod_dag_ui <- function(id) {
  ns <- NS(id)

  layout_sidebar(
    sidebar = sidebar(
      title = tags$span(bsicons::bs_icon("diagram-3"), " DAG Monitoring"),
      width  = 260,

      materialSwitch(
        inputId = ns("use_custom_date"),
        label   = "Voir une date spécifique",
        status  = "info",
        value   = FALSE
      ),
      uiOutput(ns("date_picker_ui")),
      uiOutput(ns("snapshot_info"))
    ),

    # ----------- Contenu principal -----------
    tags$div(
      style = "padding: 12px; overflow-y: auto;",

      # Ligne KPIs
      layout_columns(
        col_widths = c(3, 3, 3, 3),

        value_box(
          title    = "DAGs actifs",
          value    = textOutput(ns("kpi_n_dags"), inline = TRUE),
          showcase = bsicons::bs_icon("diagram-3"),
          theme    = "primary"
        ),
        value_box(
          title    = "Runs totaux",
          value    = textOutput(ns("kpi_n_runs"), inline = TRUE),
          showcase = bsicons::bs_icon("play-circle"),
          theme    = "info"
        ),
        value_box(
          title    = "Taux de succès",
          value    = textOutput(ns("kpi_success_rate"), inline = TRUE),
          showcase = bsicons::bs_icon("check-circle-fill"),
          theme    = "success"
        ),
        value_box(
          title    = "Runs échoués",
          value    = textOutput(ns("kpi_n_failed"), inline = TRUE),
          showcase = bsicons::bs_icon("x-circle-fill"),
          theme    = "danger"
        )
      ),

      tags$div(class = "mt-3"),

      # Waffle charts dynamiques (une card par DAG)
      uiOutput(ns("waffle_ui"))
    )
  )
}

mod_dag_server <- function(id, pool) {
  moduleServer(id, function(input, output, session) {

    # --- Sous-module : sélection de date ---
    snap          <- dag_snapshot_server(input, output, session, pool)
    selected_date <- snap$selected_date

    # --- Données brutes : tous les dag runs (filtrés si date sélectionnée) ---
    dag_runs <- reactive({
      date_val <- selected_date()

      if (is.null(date_val)) {
        # Tout l'historique — colonnes nécessaires au waffle agrégé
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
        # Date spécifique — colonnes + run_of_hour pour le waffle détaillé
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

    # --- Sous-module : KPIs ---
    dag_kpis_server(input, output, session, dag_runs)

    # --- Sous-module : Waffle charts ---
    dag_waffle_server(input, output, session, dag_runs, selected_date)
  })
}
