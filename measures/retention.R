# Validated analysis measures for the CampusLens retention agent.
# Each function is a "trusted calculation": answers produced by these
# functions carry the green Verified provenance marker.
#
# Conventions (per context/policy-conventions.md): probation threshold is
# TERM_GPA < 2.0; dismissal after 2 consecutive probation terms; attrition
# means voluntary withdrawal or academic dismissal (STUSL.FINAL_STATUS in
# ('WITHDRAWN', 'DISMISSED')); percentages by program use the number of
# students in that program (STUSL) as the denominator.

#' Attrition by program
#'
#' Number and percentage of students in each program who ever withdrew or
#' were academically dismissed, based on STUSL.FINAL_STATUS.
#'
#' @measure
attrition_by_program <- function(campus) {
  dplyr::tbl(campus, "STUSL") |>
    dplyr::mutate(
      ATTRITED = dplyr::if_else(FINAL_STATUS %in% c("WITHDRAWN", "DISMISSED"), 1L, 0L)
    ) |>
    dplyr::group_by(PROGRAM) |>
    dplyr::summarize(
      N = dplyr::n(),
      n_attrited = sum(ATTRITED, na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::mutate(pct = round(100 * n_attrited / N, 1)) |>
    dplyr::arrange(PROGRAM)
}

#' Demographic profile by program
#'
#' Age and entry-GPA summary statistics by declared program: n, mean age,
#' mean and SD entry GPA. Use for any question about age, entry GPA, or
#' demographics by program.
#'
#' @measure
demog_profile_by_program <- function(campus) {
  dplyr::tbl(campus, "STUSL") |>
    dplyr::group_by(PROGRAM) |>
    dplyr::summarize(
      n = dplyr::n(),
      mean_age = round(mean(AGE, na.rm = TRUE), 1),
      mean_entry_gpa = round(mean(ENTRY_GPA, na.rm = TRUE), 2),
      sd_entry_gpa = round(sd(ENTRY_GPA, na.rm = TRUE), 2),
      .groups = "drop"
    ) |>
    dplyr::arrange(PROGRAM)
}

#' Academic events by category and program
#'
#' Number of academic-event records and number of distinct students, by
#' event category (EVENT_TYPE: PROBATION, DISMISSAL, WITHDRAWAL, LOA,
#' ADVISING_FLAG) and program.
#'
#' @param program `string` Optional program name (e.g. "Engineering") to
#'   restrict to. Defaults to all programs.
#' @measure
probation_by_category <- function(campus, program = NULL) {
  events <- dplyr::tbl(campus, "ACAE")
  if (!is.null(program)) {
    valid <- events |> dplyr::distinct(PROGRAM) |> dplyr::pull(PROGRAM)
    if (!program %in% valid) {
      stop(
        "Unknown program '", program, "'. Valid programs: ",
        paste(sort(valid), collapse = ", "),
        call. = FALSE
      )
    }
    events <- dplyr::filter(events, PROGRAM == program)
  }
  events |>
    dplyr::group_by(PROGRAM, EVENT_TYPE) |>
    dplyr::summarize(
      n_events = dplyr::n(),
      n_students = dplyr::n_distinct(STUID),
      .groups = "drop"
    ) |>
    dplyr::arrange(PROGRAM, dplyr::desc(n_events))
}

#' GPA shift table (first term vs. most recent term)
#'
#' Counts students by first-term and last-recorded-term GPA band (LOW <
#' 2.0, MEDIUM 2.0-3.5, HIGH > 3.5), by program. Use for questions about
#' GPA trends or shifts over a student's time at the university.
#'
#' @measure
gpa_trend_table <- function(campus) {
  termgpa <- dplyr::tbl(campus, "TERMGPA")

  first_gpa <- termgpa |>
    dplyr::group_by(STUID) |>
    dplyr::filter(TERM == min(TERM, na.rm = TRUE)) |>
    dplyr::ungroup() |>
    dplyr::select(STUID, FIRST_TERM_GPA = TERM_GPA)

  last_gpa <- termgpa |>
    dplyr::group_by(STUID) |>
    dplyr::filter(TERM == max(TERM, na.rm = TRUE)) |>
    dplyr::ungroup() |>
    dplyr::select(STUID, LAST_TERM_GPA = TERM_GPA)

  stusl <- dplyr::tbl(campus, "STUSL") |> dplyr::select(STUID, PROGRAM)

  stusl |>
    dplyr::inner_join(first_gpa, by = "STUID") |>
    dplyr::inner_join(last_gpa, by = "STUID") |>
    dplyr::mutate(
      FIRST_BAND = dplyr::case_when(
        FIRST_TERM_GPA < 2.0 ~ "LOW",
        FIRST_TERM_GPA < 3.5 ~ "MEDIUM",
        TRUE ~ "HIGH"
      ),
      LAST_BAND = dplyr::case_when(
        LAST_TERM_GPA < 2.0 ~ "LOW",
        LAST_TERM_GPA < 3.5 ~ "MEDIUM",
        TRUE ~ "HIGH"
      )
    ) |>
    dplyr::count(PROGRAM, FIRST_BAND, LAST_BAND, name = "n_students") |>
    dplyr::arrange(PROGRAM, FIRST_BAND, LAST_BAND)
}

#' Completion status summary by program
#'
#' Counts of final status (GRADUATED, WITHDRAWN, DISMISSED) by program.
#'
#' @measure
completion_status_summary <- function(campus) {
  dplyr::tbl(campus, "STUSL") |>
    dplyr::count(PROGRAM, FINAL_STATUS, name = "n_students") |>
    dplyr::arrange(PROGRAM, FINAL_STATUS)
}

#' Attrition rate by program, optionally through a fixed term
#'
#' Number and percentage of students with an observed attrition event by
#' program. If `through_term` is given, only counts attrition events that
#' occurred by that term (e.g. through_term = 2 for first-year attrition);
#' otherwise counts attrition at any point in the tracked window.
#'
#' @param through_term `number` Optional term cutoff (1-8). Defaults to no
#'   cutoff (attrition at any point).
#' @measure
attrition_rate_by_program <- function(campus, through_term = NULL) {
  rette <- dplyr::tbl(campus, "RETTTE")
  if (!is.null(through_term)) {
    rette <- rette |>
      dplyr::mutate(EVENT = dplyr::if_else(EVENT == 1 & TIME <= through_term, 1L, 0L))
  }
  rette |>
    dplyr::group_by(PROGRAM) |>
    dplyr::summarize(
      n_students = dplyr::n(),
      # sum(EVENT == 1) is boolean and not portable across SQL backends;
      # cast to integer first.
      n_events = sum(as.integer(EVENT == 1), na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::mutate(pct_events = round(100 * n_events / n_students, 1)) |>
    dplyr::arrange(PROGRAM)
}

#' Kaplan-Meier survival plot by program
#'
#' Publication-style Kaplan-Meier curve for time to first attrition event
#' (withdrawal or dismissal), stratified by program, with a pointwise
#' confidence band and an at-risk table. Returns a ggplot2 object -- use
#' for any request to plot, chart, or visualize time to attrition or
#' retention by program. Built with ggsurvfit on top of survival::survfit2().
#'
#' @measure
km_plot_by_program <- function(campus) {
  raw <- dplyr::tbl(campus, "RETTTE") |>
    dplyr::select(PROGRAM, TIME, EVENT) |>
    dplyr::collect()

  df <- data.frame(
    PROGRAM = factor(raw$PROGRAM, levels = c("Business", "Engineering", "Liberal Arts")),
    TIME = raw$TIME,
    EVENT = raw$EVENT
  )

  ggsurvfit::survfit2(survival::Surv(TIME, EVENT) ~ PROGRAM, data = df) |>
    ggsurvfit::ggsurvfit(linewidth = 0.8) +
    ggsurvfit::add_confidence_interval() +
    ggsurvfit::add_risktable(risktable_stats = "n.risk") +
    ggplot2::labs(
      title = "Kaplan-Meier estimate: time to attrition",
      subtitle = "By declared program",
      x = "Term", y = "Retention probability",
      color = NULL, fill = NULL
    ) +
    ggsurvfit::theme_ggsurvfit_default()
}
