# dag/_kpis.R
# KPI value boxes pour le dashboard DAG

dag_kpis_server <- function(input, output, session, dag_runs) {

  output$kpi_n_dags <- renderText({
    length(unique(dag_runs()$dag_id))
  })

  output$kpi_n_runs <- renderText({
    scales::comma(nrow(dag_runs()))
  })

  output$kpi_success_rate <- renderText({
    df  <- dag_runs()
    n   <- nrow(df)
    if (n == 0) return("—")
    pct <- sum(df$state == "success", na.rm = TRUE) / n * 100
    paste0(round(pct, 1), "%")
  })

  output$kpi_n_failed <- renderText({
    scales::comma(sum(dag_runs()$state == "failed", na.rm = TRUE))
  })
}
