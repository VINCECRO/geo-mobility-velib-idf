# modules/mod_sql_explorer.R

mod_sql_explorer_ui <- function(id) {
  ns <- NS(id)
  tagList(
    layout_columns(
      col_widths = c(12),
      card(
        fill       = FALSE,
        height     = "500px",        # hauteur fixe sur la card elle-même
        card_header("Explorateur SQL"),
        # Éditeur de requête
        tags$textarea(
          id = ns("query_input"),
          class = "form-control font-monospace",
          style = "height: 200px; font-size: 13px;",
          placeholder = "SELECT * FROM fct_station_availability LIMIT 100;"
        ),
        # Sélecteur de base + boutons
        layout_columns(
          col_widths = c(3, 2, 2, 5),
          selectInput(ns("db_choice"), "Base de données",
            choices = c("Velib (PostGIS)" = "velib", "Airflow DAG" = "dag")
          ),
          actionButton(ns("run"), "▶ Exécuter", class = "btn-primary"),
          actionButton(ns("clear"), "✕ Effacer"),
          uiOutput(ns("query_info"))   # temps d'exécution, nb lignes
        )
      )
    ),
    card(
      fill       = FALSE,           # s'étend pour remplir l'espace restant
      min_height = "200px",
      card_header("Résultats"),
      # Table résultats
      DTOutput(ns("result_table")),
      # Zone erreur
      uiOutput(ns("error_msg"))
    )
  )
}

mod_sql_explorer_server <- function(id, pool_velib, pool_dag) {
  moduleServer(id, function(input, output, session) {

    active_pool <- reactive({
      if (input$db_choice == "dag") pool_dag else pool_velib
    })

    result <- reactiveVal(NULL)
    error  <- reactiveVal(NULL)

    observeEvent(input$run, {
      sql <- trimws(input$query_input)
      req(nchar(sql) > 0)

      # Sécurité minimale : bloquer les écritures
      keywords_interdits <- c("INSERT", "UPDATE", "DELETE", "DROP", "TRUNCATE", "ALTER", "CREATE")
      if (any(sapply(keywords_interdits, function(k) grepl(k, toupper(sql))))) {
        error("Seules les requêtes SELECT sont autorisées.")
        result(NULL)
        return()
      }

      error(NULL)
      t0 <- proc.time()

      tryCatch({
        df <- dbGetQuery(active_pool(), sql)
        elapsed <- round((proc.time() - t0)["elapsed"], 2)
        result(list(data = df, time = elapsed, nrow = nrow(df)))
      }, error = function(e) {
        error(conditionMessage(e))
        result(NULL)
      })
    })
    
    observeEvent(input$clear, {
      updateTextAreaInput(session, "query_input", value = "")
      result(NULL)
      error(NULL)
    })
    
    output$result_table <- renderDT({
      req(result())
      datatable(
        result()$data,
        options = list(scrollX = TRUE, pageLength = 25),
        filter  = "top"
      )
    })
    
    output$query_info <- renderUI({
      req(result())
      tags$span(
        class = "text-muted",
        glue::glue("✓ {result()$nrow} lignes — {result()$time}s")
      )
    })
    
    output$error_msg <- renderUI({
      req(error())
      div(class = "alert alert-danger", error())
    })
  })
}