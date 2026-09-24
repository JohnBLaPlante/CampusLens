# app.R -- CampusLens: governed student-retention Q&A agent (multi-user)
library(shiny)
library(bslib)
library(shinychat)
library(commons)
library(ggplot2)
library(ggsurvfit)
library(paws.common)
source("agent.R")   # defines make_agent(); nothing heavy runs at load time

greeting <- paste(
  "**Welcome to CampusLens.** Ask me anything about Meridian State",
  "University's Fall 2022 entering cohort (a synthetic dataset; no real",
  "student data).\n\n",
  "Every answer carries a provenance marker:\n\n",
  "- **Verified** (green): I ran a validated calculation authored by",
  "institutional research, no AI-written code.\n",
  "- **Cited** (blue): my answer quotes the academic catalog or policy",
  "conventions, and the quote was verified against the source.\n",
  "- **Untrusted** (yellow): I wrote exploratory code myself. Treat the",
  "result as a draft for institutional-research review.\n\n",
  "Try a suggestion above, or ask your own question."
)

# Suggestion cards: label, question, expected provenance. Badge is always
# one of the three categories the greeting defines (Verified/Cited/
# Untrusted), including the one question that ends up Untrusted because it
# calls for exploratory code no trusted calculation covers.
suggestions <- list(
  list(label = "Attrition by program",
       question = "What % of students in each program withdrew or were dismissed?",
       badge = "Verified"),
  list(label = "Entry GPA by program",
       question = "Show me the entry-GPA distribution by program.",
       badge = "Verified"),
  list(label = "Probation definition",
       question = "How is academic probation defined?",
       badge = "Cited"),
  list(label = "Program GPA",
       question = "What is the Standard deviation of Term 1 GPA by program?",
       badge = "Untrusted"),
  list(label = "Attrition survival plot",
       question = "Plot the survival curve for time-to-attrition by program.",
       badge = "Verified")
)

# Badge classes mirror the provenance colors described in the greeting:
# Verified = green, Cited = blue, Untrusted = yellow.
badge_class <- function(badge) {
  switch(badge,
    Verified  = "badge bg-success-subtle text-success-emphasis mt-1",
    Cited     = "badge bg-info-subtle text-info-emphasis mt-1",
    Untrusted = "badge bg-warning-subtle text-warning-emphasis mt-1",
    "badge bg-light text-secondary mt-1"
  )
}

suggestion_card <- function(i, s) {
  card(
    class = "suggestion-card",
    style = "cursor: pointer;",
    card_body(
      padding = "0.7rem",
      actionLink(
        paste0("suggest_", i),
        label = div(
          div(s$label, style = "font-weight: 600; font-size: 0.9rem;"),
          div(s$question, class = "card-question",
              style = "font-size: 0.72rem; color: var(--bs-secondary-color);"),
          span(s$badge, class = badge_class(s$badge))
        ),
        style = "text-decoration: none; color: inherit;"
      )
    )
  )
}

suggestion_card_style <- tags$style(HTML("
  .suggestion-card {
    transition: box-shadow 0.15s ease, transform 0.15s ease;
  }
  .suggestion-card:hover, .suggestion-card:focus-within {
    box-shadow: 0 0.25rem 0.75rem rgba(0, 0, 0, 0.08);
    transform: translateY(-1px);
  }
  .suggestion-card .card-question {
    display: -webkit-box;
    -webkit-line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
    min-height: 2.2em;
  }
"))

ui <- page_fillable(
  title = "CampusLens",
  theme = commons_theme(),
  suggestion_card_style,
  div(
    style = "padding: 0.25rem 0 0.5rem 0;",
    h3("CampusLens", style = "margin-bottom: 0.1rem;"),
    div("Meridian State University — Fall 2022 entering cohort",
        style = "color: var(--bs-secondary-color); font-size: 0.85rem;")
  ),
  layout_column_wrap(
    width = 1 / 5, gap = "0.5rem", fill = FALSE,
    !!!Map(suggestion_card, seq_along(suggestions), suggestions)
  ),
  chat_ui("chat", height = "100%")
)

server <- function(input, output, session) {
  # MULTI-USER: one agent per session -- isolated chat state, own database
  # connection, own sandboxed R subprocess. Hold `con` here (rather than
  # inside make_agent()) so it can be closed when the session ends instead
  # of leaking until GC/process restart.
  con   <- make_connection()
  agent <- make_agent(con = con)
  session$onSessionEnded(function() {
    try(close_connection(con), silent = TRUE)
  })
  commons_server("chat", agent)

  chat_set_greeting("chat", greeting)

  lapply(seq_along(suggestions), function(i) {
    observeEvent(input[[paste0("suggest_", i)]], {
      update_chat_user_input("chat", value = suggestions[[i]]$question,
                             submit = TRUE)
    })
  })
}

shinyApp(ui, server)
