# modules/mod_sql_explorer.R

mod_sql_explorer_ui <- function(id) {
  ns <- NS(id)
  tagList(
    card(
      card_header("SQL explorer"),
        # request editor
        tags$textarea(
          id = ns("query_input"),
          class = "form-control font-monospace",
          style = "height: 15vh; font-size: 13px;",
          placeholder = "SELECT * FROM marts.fct_station_availability LIMIT 100;"
        ),
        # DB selection + action button
        layout_columns(
          height     = "15vh",
          col_widths = c(3, -5, 2, 2),
          selectInput(ns("db_choice"), "Select Database",
            choices = c("Velib (PostGIS)" = "velib", "Airflow DAG" = "dag")
          ),
          actionButton(ns("run"), "▶ Run", class = "btn-primary"),
          actionButton(ns("clear"), "✕ Erase")
        )
    ),
    card(
      height = "50vh",
      card_header(
      class = "d-flex justify-content-between",
      "Result",
      uiOutput(ns("query_info"))),
      # Table résultats , 
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

      # Improve security and prevent DB alteration
      keywords_interdits <- c("INSERT", "UPDATE", "DELETE", "DROP", "TRUNCATE", "ALTER", "CREATE")
      if (any(sapply(keywords_interdits, function(k) grepl(k, toupper(sql))))) {
        error("Ony SELECT request are allowed")
        result(NULL)
        return()
      }

      error(NULL)
      t0 <- proc.time()

      tryCatch({
        df      <- query(active_pool(), sql)
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
      df           <- result()$data
      posixct_cols <- vapply(df, inherits, logical(1), what = "POSIXct")
      df[posixct_cols] <- lapply(df[posixct_cols], format, format = "%Y-%m-%d %H:%M:%S")
      datatable(df, options = list(scrollX = TRUE, pageLength = 25, dom = 'pti'))
    })
    
    output$query_info <- renderUI({
      req(result())
      tags$span(
        class = "text-muted",
        glue::glue("✓ {result()$nrow} lines — {result()$time}s")
      )
    })
    
    output$error_msg <- renderUI({
      req(error())
      div(class = "alert alert-danger", error())
    })
  })
}