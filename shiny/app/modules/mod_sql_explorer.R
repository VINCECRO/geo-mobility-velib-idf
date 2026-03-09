# modules/mod_sql_explorer.R

mod_sql_explorer_ui <- function(id) {
  ns <- NS(id)
  tagList(
    layout_columns(
      col_widths = c(12),
      card(
        card_header("Explorateur SQL"),
        # Éditeur de requête
        tags$textarea(
          id = ns("query_input"),
          class = "form-control font-monospace",
          style = "height: 200px; font-size: 13px;",
          placeholder = "SELECT * FROM fct_station_availability LIMIT 100;"
        ),
        # Boutons
        layout_columns(
          col_widths = c(2, 2, 8),
          actionButton(ns("run"), "▶ Exécuter", class = "btn-primary"),
          actionButton(ns("clear"), "✕ Effacer"),
          uiOutput(ns("query_info"))   # temps d'exécution, nb lignes
        )
      )
    ),
    card(
      card_header("Résultats"),
      # Table résultats
      DTOutput(ns("result_table")),
      # Zone erreur
      uiOutput(ns("error_msg"))
    )
  )
}

mod_sql_explorer_server <- function(id) {
  moduleServer(id, function(input, output, session) {
    
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
        df <- query(sql)
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