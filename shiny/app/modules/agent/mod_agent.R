# modules/agent/mod_agent.R
# Chat interface to query the Vélib LLM agent via the FastAPI endpoint.

AGENT_API_URL <- Sys.getenv("AGENT_API_URL", unset = "http://agent-api:8000")

# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------

mod_agent_ui <- function(id) {
  ns <- NS(id)
  tagList(
    layout_columns(
      col_widths = c(8, 4),
      # --- Left column: conversation ---
      card(
        full_screen = TRUE,
        card_header("Vélib Agent — Natural language queries"),
        card_body(
          # Conversation history
          div(
            id = ns("chat_box"),
            style = "height: 55vh; overflow-y: auto; display: flex; flex-direction: column; gap: 1rem; padding: 0.5rem;",
            uiOutput(ns("chat_history"))
          )
        ),
        card_footer(
          layout_columns(
            col_widths = c(10, 2),
            textInput(
              ns("question"),
              label    = NULL,
              value    = "",
              placeholder = "e.g. Which municipalities have the most critical stations?"
            ),
            actionButton(ns("send"), "Send", class = "btn-primary w-100")
          )
        )
      ),

      # --- Right column: suggestions ---
      card(
        card_header("Suggestions"),
        card_body(
          p(class = "text-muted small", "Click a question to load it."),
          div(
            class = "d-flex flex-column gap-2",
            actionLink(ns("q1"), "\U0001f534 Which municipalities have the most critical stations right now?"),
            actionLink(ns("q2"), "\U0001f4ca What is the average availability per district at the last snapshot?"),
            actionLink(ns("q3"), "\U23f1\ufe0f At what hour is availability lowest on weekdays?"),
            actionLink(ns("q4"), "\U0001f6b2 Which stations have the highest e-bike ratio?"),
            actionLink(ns("q5"), "\U0001f3d9\ufe0f Compare availability between Urban Core and Peripheral zones.")
          )
        )
      )
    )
  )
}

# ---------------------------------------------------------------------------
# Server
# ---------------------------------------------------------------------------

mod_agent_server <- function(id) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # History: list of list(role, content)
    history <- reactiveVal(list())
    loading  <- reactiveVal(FALSE)

    # Suggestions → pre-fill the input
    suggestions <- list(
      q1 = "Which municipalities have the most critical stations right now?",
      q2 = "What is the average availability per district at the last snapshot?",
      q3 = "At what hour is availability lowest on weekdays over the last 7 days?",
      q4 = "What are the 10 stations with the highest e-bike ratio?",
      q5 = "Compare average availability between Urban Core and Peripheral zones."
    )

    for (qid in names(suggestions)) {
      local({
        .qid          <- qid
        question_text <- suggestions[[.qid]]
        observeEvent(input[[.qid]], {
          updateTextInput(session, "question", value = question_text)
        })
      })
    }

    # Send a question
    observeEvent(input$send, {
      question <- trimws(input$question)
      req(nchar(question) > 0)
      req(!loading())

      # Add question to history and clear input
      history(c(history(), list(list(role = "user", content = question))))
      updateTextInput(session, "question", value = "")
      loading(TRUE)

      # HTTP call to the agent API
      answer <- tryCatch({
        resp <- httr2::request(AGENT_API_URL) |>
          httr2::req_url_path_append("ask") |>
          httr2::req_body_json(list(question = question)) |>
          httr2::req_timeout(120) |>
          httr2::req_perform()
        httr2::resp_body_json(resp)$answer
      }, error = function(e) {
        paste0("**Error:** ", conditionMessage(e))
      })

      history(c(history(), list(list(role = "assistant", content = answer))))
      loading(FALSE)
    })

    # Render conversation history
    output$chat_history <- renderUI({
      msgs <- history()

      if (length(msgs) == 0) {
        return(div(
          class = "text-muted text-center mt-5",
          "Ask a question about the Vélib data..."
        ))
      }

      bubbles <- lapply(msgs, function(m) {
        if (m$role == "user") {
          div(
            class = "align-self-end",
            style = "max-width: 80%;",
            div(
              class = "bg-primary text-white rounded p-2 px-3 small",
              m$content
            )
          )
        } else {
          div(
            class = "align-self-start",
            style = "max-width: 95%;",
            div(
              class = "bg-light border rounded p-2 px-3 small",
              shiny::markdown(m$content)
            )
          )
        }
      })

      # Loading indicator
      if (loading()) {
        bubbles <- c(bubbles, list(
          div(
            class = "align-self-start",
            div(
              class = "bg-light border rounded p-2 px-3 text-muted small fst-italic",
              "Agent is thinking..."
            )
          )
        ))
      }

      tagList(bubbles)
    })

    # Auto-scroll to bottom after each message
    observe({
      history()
      loading()
      shinyjs::runjs(glue::glue(
        "var el = document.getElementById('{ns('chat_box')}');
         if (el) el.scrollTop = el.scrollHeight;"
      ))
    })
  })
}
