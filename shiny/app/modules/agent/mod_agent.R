# modules/agent/mod_agent.R
# Interface de chat pour interroger l'agent LLM Vélib via l'API FastAPI.

AGENT_API_URL <- Sys.getenv("AGENT_API_URL", unset = "http://agent-api:8000")

# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------

mod_agent_ui <- function(id) {
  ns <- NS(id)
  tagList(
    layout_columns(
      col_widths = c(8, 4),
      # --- Colonne gauche : conversation ---
      card(
        full_screen = TRUE,
        card_header("Agent Vélib — Questions en langage naturel"),
        card_body(
          # Historique de la conversation
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
              placeholder = "Ex : Quelles communes ont le plus de stations critiques ?"
            ),
            actionButton(ns("send"), "Envoyer", class = "btn-primary w-100")
          )
        )
      ),

      # --- Colonne droite : suggestions ---
      card(
        card_header("Suggestions"),
        card_body(
          p(class = "text-muted small", "Cliquez sur une question pour la charger."),
          div(
            class = "d-flex flex-column gap-2",
            actionLink(ns("q1"), "🔴 Quelles communes ont le plus de stations critiques en ce moment ?"),
            actionLink(ns("q2"), "📊 Quelle est la disponibilité moyenne par arrondissement ?"),
            actionLink(ns("q3"), "⏱️ À quelle heure la disponibilité est-elle la plus faible en semaine ?"),
            actionLink(ns("q4"), "🚲 Quelles stations ont le taux de vélos électriques le plus élevé ?"),
            actionLink(ns("q5"), "🏙️ Comparez la disponibilité entre zones urbaines denses et périphériques.")
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

    # Historique : liste de list(role, content)
    history <- reactiveVal(list())
    loading  <- reactiveVal(FALSE)

    # Suggestions → pré-remplit l'input
    suggestions <- list(
      q1 = "Quelles communes ont le plus de stations critiques en ce moment ?",
      q2 = "Quelle est la disponibilité moyenne par arrondissement au dernier snapshot ?",
      q3 = "À quelle heure la disponibilité est-elle la plus faible en semaine sur les 7 derniers jours ?",
      q4 = "Quelles sont les 10 stations avec le taux de vélos électriques le plus élevé ?",
      q5 = "Comparez la disponibilité moyenne entre zones Urban Core et Peripheral."
    )

    for (qid in names(suggestions)) {
      local({
        question_text <- suggestions[[qid]]
        observeEvent(input[[qid]], {
          updateTextInput(session, "question", value = question_text)
        })
      })
    }

    # Envoi d'une question
    observeEvent(input$send, {
      question <- trimws(input$question)
      req(nchar(question) > 0)
      req(!loading())

      # Ajoute la question à l'historique et vide l'input
      history(c(history(), list(list(role = "user", content = question))))
      updateTextInput(session, "question", value = "")
      loading(TRUE)

      # Appel HTTP à l'API agent
      answer <- tryCatch({
        resp <- httr2::request(AGENT_API_URL) |>
          httr2::req_url_path_append("ask") |>
          httr2::req_body_json(list(question = question)) |>
          httr2::req_timeout(120) |>
          httr2::req_perform()
        httr2::resp_body_json(resp)$answer
      }, error = function(e) {
        paste0("**Erreur :** ", conditionMessage(e))
      })

      history(c(history(), list(list(role = "assistant", content = answer))))
      loading(FALSE)
    })

    # Rendu de l'historique
    output$chat_history <- renderUI({
      msgs <- history()

      if (length(msgs) == 0) {
        return(div(
          class = "text-muted text-center mt-5",
          "Posez une question sur les données Vélib..."
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
              # Rendu Markdown basique via shiny::markdown()
              shiny::markdown(m$content)
            )
          )
        }
      })

      # Indicateur de chargement
      if (loading()) {
        bubbles <- c(bubbles, list(
          div(
            class = "align-self-start",
            div(
              class = "bg-light border rounded p-2 px-3 text-muted small fst-italic",
              "L'agent réfléchit..."
            )
          )
        ))
      }

      tagList(bubbles)
    })

    # Scroll automatique vers le bas après chaque message
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
