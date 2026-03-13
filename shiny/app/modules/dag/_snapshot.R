# dag/_snapshot.R
# Filtre de date pour le dashboard DAG
#
# Retourne: selected_date() — NULL (tout l'historique) ou "YYYY-MM-DD"

dag_snapshot_server <- function(input, output, session, pool) {

  output$date_picker_ui <- renderUI({
    req(isTRUE(input$use_custom_date))
    date_range <- query(pool, "
      SELECT
        DATE(MIN(logical_date) AT TIME ZONE 'Europe/Paris') AS min_date,
        DATE(MAX(logical_date) AT TIME ZONE 'Europe/Paris') AS max_date
      FROM dag_run
    ")
    tagList(
      tags$div(class = "mt-2"),
      dateInput(
        session$ns("selected_date"),
        label  = tags$span(bsicons::bs_icon("calendar3"), " Sélectionner une date"),
        value  = as.character(date_range$max_date),
        min    = as.character(date_range$min_date),
        max    = as.character(date_range$max_date),
        format = "dd/mm/yyyy",
        width  = "100%"
      )
    )
  })

  output$snapshot_info <- renderUI({
    if (!isTRUE(input$use_custom_date)) {
      tags$div(class = "text-muted mt-2", style = "font-size: 0.78rem;",
               bsicons::bs_icon("info-circle"), " Tout l'historique affiché.")
    } else {
      req(input$selected_date)
      tags$div(class = "text-info mt-2", style = "font-size: 0.78rem;",
               bsicons::bs_icon("clock-history"),
               tags$b(format(as.Date(input$selected_date), "%d/%m/%Y")))
    }
  })

  selected_date <- reactive({
    if (!isTRUE(input$use_custom_date)) return(NULL)
    req(input$selected_date)
    as.character(input$selected_date)
  })

  list(selected_date = selected_date)
}
