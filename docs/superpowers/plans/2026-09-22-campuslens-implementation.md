# CampusLens Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build CampusLens, a governed student-retention Q&A agent built with Posit's `commons` R package, ported from `sol-eng/TrialLens`'s clinical-trial demo to synthetic higher-education data.

**Architecture:** A Shiny chat app (`app.R`) backed by a `commons()` agent (`agent.R`) that queries a DuckDB database loaded from four generated CSV tables (`STUSL`, `ACAE`, `TERMGPA`, `RETTTE`). The agent answers from 7 validated R measures (Verified), two context Markdown docs (Cited), or ad-hoc sandboxed code (Untrusted).

**Tech Stack:** R, `commons`, `ellmer` (AWS Bedrock, model `us.anthropic.claude-sonnet-5`), `duckdb`/`DBI`/`dplyr`/`dbplyr`, `survival`/`ggsurvfit`/`ggplot2`, `shiny`/`bslib`/`shinychat`.

**Spec:** `docs/superpowers/specs/2026-09-22-campuslens-design.md`

## Global Constraints

- DuckDB backend only in v1 — no Snowflake branch, no `push_snowflake.R` equivalent.
- Single synthetic institution ("Meridian State University"), one entering cohort (`COHORT_YEAR = 2022`), 400 students, 3 programs (`Business`, `Engineering`, `Liberal Arts`), 8 terms tracked.
- Table names are uppercase: `STUSL`, `ACAE`, `TERMGPA`, `RETTTE` — one dictionary, one set of measures.
- Probation threshold is `TERM_GPA < 2.0`; dismissal triggers after 2 consecutive probation terms. This threshold must be identical in `generate_synthetic_data.R`, `measures/retention.R`, and `context/policy-conventions.md` — never restate it a fourth way.
- Engineering must show a higher year-1 (terms 1–2) attrition hazard than Business — the designed-in KM-curve separation the demo relies on. Do not remove or "balance" this.
- Repo root: `/Users/john.laplante/Posit/MyDemos/CampusLens`. No GitHub remote yet — local git only.
- Bedrock model id is `us.anthropic.claude-sonnet-5`; `AWS_REGION` must be set to `us-east-1` before the first `ellmer` call in every script that makes one.
- No `www/logo.svg` / image assets — text-only header, unlike TrialLens.

---

### Task 1: Project scaffold

**Files:**
- Create: `DESCRIPTION`
- Create: `.gitignore`
- Create: `README.md`

**Interfaces:**
- Produces: the directory layout (`measures/`, `dictionaries/`, `context/`, `docs/`) that every later task writes into.

- [ ] **Step 1: Create the directories**

```bash
mkdir -p measures dictionaries context
```

- [ ] **Step 2: Write `DESCRIPTION`**

```
Package: campuslens
Type: Project
Title: CampusLens -- Governed Student-Retention Q&A Agent
Description: A commons-based governed AI agent demo over synthetic
    higher-education student-retention data. Ported from sol-eng/TrialLens.
Imports:
    bsicons,
    bslib,
    commons,
    DBI,
    dplyr,
    duckdb,
    ellmer,
    ggplot2,
    ggsurvfit,
    htmltools,
    paws.common,
    shiny,
    shinychat,
    survival
```

- [ ] **Step 3: Write `.gitignore`**

```
.Rproj.user
.Rhistory
.RData
.Ruserdata
renv/library
renv/staging
renv/python
```

- [ ] **Step 4: Write `README.md`**

```markdown
# CampusLens

A governed Q&A agent over synthetic student-retention data, built with
[commons](https://posit-dev.github.io/commons/). Ported from
[sol-eng/TrialLens](https://github.com/sol-eng/TrialLens) (a clinical-trial
demo) to a higher-education storyline. Design spec:
`docs/superpowers/specs/2026-09-22-campuslens-design.md`.

No real student data -- Meridian State University and its Fall 2022
entering cohort are entirely synthetic (see `generate_synthetic_data.R`).

## Setup

```r
pak::pak(c(
  "posit-dev/commons/pkg-r", "duckdb", "survival", "ggsurvfit", "ellmer"
))
```

AWS credentials for Bedrock must be available; region is set in `agent.R`
(`us-east-1`). Then:

```r
source("generate_synthetic_data.R")  # one-time: writes the 4 CSVs
source("check-setup.R")              # everything should print OK
shiny::runApp()                      # or source("app.R")
```
```

- [ ] **Step 5: Verify the layout**

Run: `ls -la && ls measures dictionaries context`
Expected: `DESCRIPTION`, `.gitignore`, `README.md` at the root; three empty subdirectories exist.

- [ ] **Step 6: Commit**

```bash
git add DESCRIPTION .gitignore README.md
git commit -m "Scaffold CampusLens project layout"
```

---

### Task 2: Synthetic data generator

**Files:**
- Create: `generate_synthetic_data.R`
- Create (by running the script): `stusl.csv`, `acae.csv`, `termgpa.csv`, `rettte.csv`

**Interfaces:**
- Produces: 4 CSVs with columns —
  `STUSL`: `STUID, PROGRAM, COHORT_YEAR, AGE, SEX, ENTRY_GPA, ENTRY_TEST_SCORE, FINAL_STATUS`
  `ACAE`: `STUID, PROGRAM, TERM, EVENT_TYPE`
  `TERMGPA`: `STUID, PROGRAM, TERM, TERM_GPA, CREDITS_ATTEMPTED, CREDITS_EARNED`
  `RETTTE`: `STUID, PROGRAM, TIME, EVENT`
- Consumed by: Task 3 (dictionary documents these columns), Task 5 (measures query these tables), Task 6 (`agent.R` loads these CSVs into DuckDB).

- [ ] **Step 1: Write `generate_synthetic_data.R`**

```r
# generate_synthetic_data.R -- one-time generator for CampusLens's synthetic
# student-retention data. No public synthetic-higher-ed package exists to
# lean on (unlike pharmaverseadam for TrialLens), so all four tables are
# built here from seeded random distributions and written to CSV.
#
# Run once (or whenever the model needs regenerating):
#   Rscript generate_synthetic_data.R
#
# Designed-in signal: Engineering students face a higher withdrawal hazard
# in terms 1-2 (year 1) than Business or Liberal Arts, so the KM curve in
# km_plot_by_program() shows a real, visible separation between programs.

set.seed(42)

programs <- c("Business", "Engineering", "Liberal Arts")
n_students <- 400
program_probs <- c(Business = 0.35, Engineering = 0.35, `Liberal Arts` = 0.30)

# Probation/dismissal thresholds must match context/policy-conventions.md.
PROBATION_GPA_THRESHOLD <- 2.0
DISMISSAL_CONSECUTIVE_PROBATIONS <- 2
N_TERMS <- 8

stuid <- sprintf("STU%04d", seq_len(n_students))
program <- sample(programs, n_students, replace = TRUE, prob = program_probs)
cohort_year <- rep(2022L, n_students)
age <- pmin(20L, pmax(17L, round(rnorm(n_students, 18, 0.6))))
sex <- sample(c("F", "M"), n_students, replace = TRUE, prob = c(0.52, 0.48))
entry_gpa <- round(pmin(4.0, pmax(2.0, rnorm(n_students, 3.3, 0.4))), 2)
entry_test_score <- round(pmin(1600, pmax(800, rnorm(n_students, 1200, 150))))

# Per-student baseline GPA trajectory center, correlated with entry GPA but
# with enough spread that some students genuinely risk probation/dismissal.
base_gpa <- pmin(4.0, pmax(0.0, entry_gpa * 0.5 + rnorm(n_students, 1.5, 0.7)))

# Per-term withdrawal hazard. Engineering's terms 1-2 hazard is deliberately
# higher -- this is the designed-in first-year attrition gap.
term_hazard <- function(prog, term) {
  if (prog == "Engineering" && term <= 2) 0.05 else 0.015
}

termgpa_rows <- vector("list", n_students)
acae_rows <- list()
final_status <- character(n_students)
attrition_term <- rep(NA_integer_, n_students)

for (i in seq_len(n_students)) {
  status <- "ENROLLED"
  consecutive_probations <- 0L
  student_termgpa <- vector("list", N_TERMS)
  n_recorded <- 0L

  for (term in seq_len(N_TERMS)) {
    if (runif(1) < term_hazard(program[i], term)) {
      acae_rows[[length(acae_rows) + 1]] <- data.frame(
        STUID = stuid[i], PROGRAM = program[i], TERM = term,
        EVENT_TYPE = "WITHDRAWAL"
      )
      status <- "WITHDRAWN"
      attrition_term[i] <- term
      break
    }

    term_gpa <- round(pmin(4.0, pmax(0.0, rnorm(1, base_gpa[i], 0.4))), 2)
    n_recorded <- n_recorded + 1L
    student_termgpa[[n_recorded]] <- data.frame(
      STUID = stuid[i], PROGRAM = program[i], TERM = term,
      TERM_GPA = term_gpa,
      CREDITS_ATTEMPTED = 15L,
      CREDITS_EARNED = if (term_gpa >= 1.0) 15L else 9L
    )

    if (term_gpa < PROBATION_GPA_THRESHOLD) {
      consecutive_probations <- consecutive_probations + 1L
      acae_rows[[length(acae_rows) + 1]] <- data.frame(
        STUID = stuid[i], PROGRAM = program[i], TERM = term,
        EVENT_TYPE = "PROBATION"
      )
      if (consecutive_probations >= DISMISSAL_CONSECUTIVE_PROBATIONS) {
        acae_rows[[length(acae_rows) + 1]] <- data.frame(
          STUID = stuid[i], PROGRAM = program[i], TERM = term,
          EVENT_TYPE = "DISMISSAL"
        )
        status <- "DISMISSED"
        attrition_term[i] <- term
        break
      }
    } else {
      consecutive_probations <- 0L
    }

    if (runif(1) < 0.02) {
      acae_rows[[length(acae_rows) + 1]] <- data.frame(
        STUID = stuid[i], PROGRAM = program[i], TERM = term,
        EVENT_TYPE = "LOA"
      )
    }
    if (runif(1) < 0.05) {
      acae_rows[[length(acae_rows) + 1]] <- data.frame(
        STUID = stuid[i], PROGRAM = program[i], TERM = term,
        EVENT_TYPE = "ADVISING_FLAG"
      )
    }
  }

  if (status == "ENROLLED") status <- "GRADUATED"
  final_status[i] <- status
  termgpa_rows[[i]] <- do.call(rbind, student_termgpa[seq_len(n_recorded)])
}

STUSL <- data.frame(
  STUID = stuid, PROGRAM = program, COHORT_YEAR = cohort_year,
  AGE = age, SEX = sex, ENTRY_GPA = entry_gpa,
  ENTRY_TEST_SCORE = entry_test_score, FINAL_STATUS = final_status
)

TERMGPA <- do.call(rbind, termgpa_rows)
ACAE <- do.call(rbind, acae_rows)

RETTTE <- data.frame(
  STUID = stuid,
  PROGRAM = program,
  TIME = ifelse(is.na(attrition_term), N_TERMS, attrition_term),
  EVENT = ifelse(is.na(attrition_term), 0L, 1L)
)

write.csv(STUSL, "stusl.csv", row.names = FALSE)
write.csv(ACAE, "acae.csv", row.names = FALSE)
write.csv(TERMGPA, "termgpa.csv", row.names = FALSE)
write.csv(RETTTE, "rettte.csv", row.names = FALSE)

cat("Wrote stusl.csv:", nrow(STUSL), "rows\n")
cat("Wrote acae.csv:", nrow(ACAE), "rows\n")
cat("Wrote termgpa.csv:", nrow(TERMGPA), "rows\n")
cat("Wrote rettte.csv:", nrow(RETTTE), "rows\n")

# Sanity check: Engineering's year-1 (terms 1-2) attrition rate must exceed
# Business's, or the km_plot_by_program() demo beat has no story.
year1_attrition <- function(prog) {
  idx <- RETTTE$PROGRAM == prog
  mean(RETTTE$EVENT[idx] == 1 & RETTTE$TIME[idx] <= 2)
}
eng_rate <- year1_attrition("Engineering")
biz_rate <- year1_attrition("Business")
cat("Engineering year-1 attrition:", round(100 * eng_rate, 1), "%\n")
cat("Business year-1 attrition:", round(100 * biz_rate, 1), "%\n")
stopifnot(eng_rate > biz_rate)
cat("OK: Engineering year-1 attrition exceeds Business.\n")
```

- [ ] **Step 2: Run it and verify the designed-in signal**

Run: `Rscript generate_synthetic_data.R`
Expected (deterministic with `set.seed(42)`):
```
Wrote stusl.csv: 400 rows
Wrote acae.csv: 413 rows
Wrote termgpa.csv: 2810 rows
Wrote rettte.csv: 400 rows
Engineering year-1 attrition: 10.6 %
Business year-1 attrition: 6 %
OK: Engineering year-1 attrition exceeds Business.
```

- [ ] **Step 3: Commit the generator and the generated CSVs**

```bash
git add generate_synthetic_data.R stusl.csv acae.csv termgpa.csv rettte.csv
git commit -m "Add synthetic student-retention data generator"
```

---

### Task 3: Data dictionary

**Files:**
- Create: `dictionaries/student.data-dict.yaml`

**Interfaces:**
- Consumes: the exact column names produced in Task 2.
- Produces: the dictionary path `dictionaries/student.data-dict.yaml`, referenced by `agent.R` in Task 6.

- [ ] **Step 1: Write `dictionaries/student.data-dict.yaml`**

```yaml
glossary:
  - term: SAP
    definition: >
      Satisfactory Academic Progress. The university's policy defining the
      GPA thresholds for academic probation and dismissal.
  - term: probation
    definition: >
      Academic probation, triggered when a student's term GPA falls below
      2.0, flagged with EVENT_TYPE = 'PROBATION' in ACAE.
  - term: dismissal
    definition: >
      Academic dismissal, triggered by two consecutive terms of probation,
      flagged with EVENT_TYPE = 'DISMISSAL' in ACAE.
  - term: entering cohort
    definition: >
      The group of first-time, full-time students who enrolled in the same
      starting term, identified by COHORT_YEAR in STUSL.
  - term: attrition
    definition: >
      A student leaving before completing the program without graduating,
      via either voluntary withdrawal or academic dismissal.

tables:
  - name: STUSL
    description: >
      Student-level table. One row per student in the entering cohort.
      Contains program assignment, demographics, entry credentials, and
      final outcome status for the synthetic Meridian State University
      retention dataset. No real student data.
    columns:
      - name: STUID
        type: string
        description: Unique student identifier.
      - name: PROGRAM
        type: string
        description: >
          Declared program. Values: 'Business', 'Engineering',
          'Liberal Arts'. Use this for by-program summaries.
      - name: COHORT_YEAR
        type: number
        description: Entering cohort year (fall term of first enrollment).
      - name: AGE
        type: number
        description: Age in years at entry.
      - name: SEX
        type: string
        description: Sex ('F'/'M').
      - name: ENTRY_GPA
        type: number
        description: High-school GPA at entry, on a 4.0 scale.
      - name: ENTRY_TEST_SCORE
        type: number
        description: Standardized admissions test score.
      - name: FINAL_STATUS
        type: string
        description: >
          Outcome as of the end of the tracked 8-term window. Values:
          'GRADUATED', 'WITHDRAWN' (voluntary), 'DISMISSED' (academic).
    definitions:
      - name: withdrawn
        label: Voluntarily withdrawn
        description: Student left the university voluntarily.
        expr: FINAL_STATUS = 'WITHDRAWN'
      - name: dismissed
        label: Academically dismissed
        description: Student was dismissed for academic reasons.
        expr: FINAL_STATUS = 'DISMISSED'
      - name: graduated
        label: Graduated
        description: Student completed the program.
        expr: FINAL_STATUS = 'GRADUATED'

  - name: ACAE
    description: >
      Academic events table. One row per academic event record: academic
      probation, dismissal, voluntary withdrawal, leave of absence, or an
      advising flag. Includes PROGRAM duplicated from STUSL for convenience.
    columns:
      - name: STUID
        type: string
        description: Unique student identifier; joins to STUSL.
      - name: PROGRAM
        type: string
        description: Declared program (same values as STUSL.PROGRAM).
      - name: TERM
        type: number
        description: Term number (1-8) the event occurred in.
      - name: EVENT_TYPE
        type: string
        description: >
          Event category. Values: 'PROBATION', 'DISMISSAL', 'WITHDRAWAL',
          'LOA' (leave of absence), 'ADVISING_FLAG'.
    definitions:
      - name: on_probation
        label: Academic probation event
        description: Event record marking a term of academic probation.
        expr: EVENT_TYPE = 'PROBATION'
      - name: dismissal_event
        label: Dismissal event
        description: Event record marking an academic dismissal.
        expr: EVENT_TYPE = 'DISMISSAL'
      - name: withdrawal_event
        label: Withdrawal event
        description: Event record marking a voluntary withdrawal.
        expr: EVENT_TYPE = 'WITHDRAWAL'

  - name: TERMGPA
    description: >
      Term performance table. One row per student per term enrolled.
      A student's rows stop at the term they withdrew or were dismissed;
      students who graduated have all 8 rows.
    columns:
      - name: STUID
        type: string
        description: Unique student identifier; joins to STUSL.
      - name: PROGRAM
        type: string
        description: Declared program (same values as STUSL.PROGRAM).
      - name: TERM
        type: number
        description: Term number, 1-8 (terms 1-2 are year 1, 3-4 year 2, etc).
      - name: TERM_GPA
        type: number
        description: GPA earned that term, on a 4.0 scale.
      - name: CREDITS_ATTEMPTED
        type: number
        description: Credit hours attempted that term.
      - name: CREDITS_EARNED
        type: number
        description: Credit hours earned that term.
    definitions:
      - name: below_probation_threshold
        label: Below probation GPA threshold
        description: >
          Term GPA below the 2.0 SAP probation threshold (see
          context/policy-conventions.md).
        expr: TERM_GPA < 2.0

  - name: RETTTE
    description: >
      Time-to-event table. One row per student. Time to first attrition
      event (voluntary withdrawal or academic dismissal), or censored at
      graduation/end of the tracked window if no such event occurred.
      Joins to STUSL on STUID.
    columns:
      - name: STUID
        type: string
        description: Unique student identifier; joins to STUSL.
      - name: PROGRAM
        type: string
        description: Declared program (same values as STUSL.PROGRAM).
      - name: TIME
        type: number
        description: >
          Term number of the attrition event, or 8 if censored
          (graduated or otherwise completed all tracked terms).
      - name: EVENT
        type: number
        description: >
          Event indicator. 1 = attrition event observed (withdrawal or
          dismissal); 0 = censored (graduated).
    definitions:
      - name: observed_event
        label: Observed attrition event
        description: Record where attrition was actually observed, not censored.
        expr: EVENT = 1
      - name: censored
        label: Censored record
        description: >
          Record where the student completed the tracked window without
          attriting; TIME reflects time to censoring, not time to event.
        expr: EVENT = 0
```

- [ ] **Step 2: Validate it parses**

Run: `Rscript -e 'x <- yaml::read_yaml("dictionaries/student.data-dict.yaml"); cat("tables:", paste(sapply(x$tables, function(t) t$name), collapse=", "), "\n")'`
Expected: `tables: STUSL, ACAE, TERMGPA, RETTTE`

- [ ] **Step 3: Commit**

```bash
git add dictionaries/student.data-dict.yaml
git commit -m "Add student data dictionary"
```

---

### Task 4: Context documents

**Files:**
- Create: `context/catalog-excerpt.md`
- Create: `context/policy-conventions.md`

**Interfaces:**
- Produces: the two file paths referenced by `context_layer()` in `agent.R` (Task 6).
- Must stay consistent with: the thresholds in Task 2's generator and Task 3's dictionary (`TERM_GPA < 2.0`, 2 consecutive probations → dismissal).

- [ ] **Step 1: Write `context/catalog-excerpt.md`**

```markdown
# University catalog excerpt (demo institution)

> This is a demonstration built entirely from synthetic data. Meridian
> State University, its programs, and its Fall 2022 entering cohort do not
> exist. It contains no real student data.

## Institution and cohort

Meridian State University tracks one entering cohort for this demo: the
first-time, full-time students who enrolled in Fall 2022 (`COHORT_YEAR =
2022` in STUSL). Degree completion requires 120 credit hours, tracked over
8 terms across 4 academic years (Fall and Spring each year).

## Programs

Students declare one of three programs at entry:

- **Business**
- **Engineering**
- **Liberal Arts**

## Credit-hour convention

Full-time enrollment is 15 credit hours attempted per term
(`CREDITS_ATTEMPTED` in TERMGPA).
```

- [ ] **Step 2: Write `context/policy-conventions.md`**

```markdown
# Academic policy conventions (demo institution)

> Policy excerpt for demonstration purposes; synthetic institution.

## Satisfactory Academic Progress (SAP)

A student is placed on **academic probation** when their term GPA falls
below 2.0 (`TERM_GPA < 2.0` in TERMGPA), flagged with `EVENT_TYPE =
'PROBATION'` in ACAE.

A student is **academically dismissed** after two consecutive terms of
probation, flagged with `EVENT_TYPE = 'DISMISSAL'` in ACAE. A dismissed
student's TERMGPA record ends at the term of dismissal.

## Attrition

**Attrition** means a student left before completing all 8 tracked terms
without graduating, via either:

- **voluntary withdrawal** (`EVENT_TYPE = 'WITHDRAWAL'` in ACAE,
  `FINAL_STATUS = 'WITHDRAWN'` in STUSL), or
- **academic dismissal** (`FINAL_STATUS = 'DISMISSED'` in STUSL).

## Term-numbering convention

Terms 1-8 span 4 academic years, two terms (fall, spring) per year: Year 1
= terms 1-2, Year 2 = terms 3-4, Year 3 = terms 5-6, Year 4 = terms 7-8.
"First-year attrition" means an attrition event with `TIME <= 2`.

## Leave of absence and advising flags

A leave of absence (`EVENT_TYPE = 'LOA'`) and an advising flag
(`EVENT_TYPE = 'ADVISING_FLAG'`) are recorded independently of GPA and do
not by themselves end enrollment.

## Denominators

Percentages by program use the number of students in STUSL for that
program as the denominator, unless a measure states otherwise.

## Exploratory analyses

Any analysis not covered by a validated measure in `measures/retention.R`
is exploratory. Exploratory results should be reviewed by institutional
research staff before being shared outside the team.
```

- [ ] **Step 3: Verify both files exist and are non-empty**

Run: `wc -l context/catalog-excerpt.md context/policy-conventions.md`
Expected: both files report a nonzero line count.

- [ ] **Step 4: Commit**

```bash
git add context/catalog-excerpt.md context/policy-conventions.md
git commit -m "Add catalog and academic policy context documents"
```

---

### Task 5: Validated measures

**Files:**
- Create: `measures/retention.R`

**Interfaces:**
- Consumes: tables `STUSL`, `ACAE`, `TERMGPA`, `RETTTE` (Task 2) via a `DBI` connection (`trial` parameter, matching TrialLens's convention of naming the first argument after the data source).
- Produces: 7 functions the agent calls as trusted calculations — `attrition_by_program(trial)`, `demog_profile_by_program(trial)`, `probation_by_category(trial, program = NULL)`, `gpa_trend_table(trial)`, `completion_status_summary(trial)`, `attrition_rate_by_program(trial, through_term = NULL)`, `km_plot_by_program(trial)`. These exact names and signatures are consumed by `agent.R`'s `semantic_layer("measures/retention.R")` (Task 6) and by `check-setup.R` (Task 9).

- [ ] **Step 1: Write `measures/retention.R`**

```r
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
attrition_by_program <- function(trial) {
  dplyr::tbl(trial, "STUSL") |>
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
demog_profile_by_program <- function(trial) {
  dplyr::tbl(trial, "STUSL") |>
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
probation_by_category <- function(trial, program = NULL) {
  events <- dplyr::tbl(trial, "ACAE")
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
gpa_trend_table <- function(trial) {
  termgpa <- dplyr::tbl(trial, "TERMGPA")

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

  stusl <- dplyr::tbl(trial, "STUSL") |> dplyr::select(STUID, PROGRAM)

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
completion_status_summary <- function(trial) {
  dplyr::tbl(trial, "STUSL") |>
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
attrition_rate_by_program <- function(trial, through_term = NULL) {
  rette <- dplyr::tbl(trial, "RETTTE")
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
km_plot_by_program <- function(trial) {
  raw <- dplyr::tbl(trial, "RETTTE") |>
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
```

- [ ] **Step 2: Run all 7 measures against a real DuckDB connection built from the CSVs**

Run:
```bash
Rscript -e '
library(dplyr); library(DBI); library(duckdb)
con <- dbConnect(duckdb::duckdb())
dbWriteTable(con, "STUSL", read.csv("stusl.csv"))
dbWriteTable(con, "ACAE", read.csv("acae.csv"))
dbWriteTable(con, "TERMGPA", read.csv("termgpa.csv"))
dbWriteTable(con, "RETTTE", read.csv("rettte.csv"))
source("measures/retention.R")
print(collect(attrition_by_program(con)))
print(collect(demog_profile_by_program(con)))
print(collect(probation_by_category(con, "Engineering")))
print(collect(gpa_trend_table(con)))
print(collect(completion_status_summary(con)))
print(collect(attrition_rate_by_program(con, through_term = 2)))
p <- km_plot_by_program(con)
cat("km class:", paste(class(p), collapse=", "), "\n")
tryCatch(collect(probation_by_category(con, "Nonexistent")),
         error = function(e) cat("caught:", conditionMessage(e), "\n"))
dbDisconnect(con, shutdown = TRUE)
'
```

Expected (key lines):
```
  PROGRAM          N n_attrited   pct
1 Business       134         30  22.4
2 Engineering    142         32  22.5
3 Liberal Arts   124         17  13.7
...
1 Business       134       8      6
2 Engineering    142      15   10.6
3 Liberal Arts   124       8    6.5
km class: ggsurvfit, ggplot2::ggplot, ggplot, ggplot2::gg, S7_object, gg
caught: Unknown program 'Nonexistent'. Valid programs: Business, Engineering, Liberal Arts
```

- [ ] **Step 3: Commit**

```bash
git add measures/retention.R
git commit -m "Add 7 validated retention measures"
```

---

### Task 6: Agent constructor

**Files:**
- Create: `agent.R`

**Interfaces:**
- Consumes: `dictionaries/student.data-dict.yaml` (Task 3), `measures/retention.R` (Task 5), `context/catalog-excerpt.md` + `context/policy-conventions.md` (Task 4), `instructions.md` (Task 7), the 4 CSVs (Task 2).
- Produces: `make_connection()` (no args → `DBI` connection), `close_connection(con)`, `make_agent(con = make_connection())` (→ a `commons()` agent object). These three names are consumed by `app.R` (Task 8) and `check-setup.R` (Task 9).

- [ ] **Step 1: Write `agent.R`**

```r
# agent.R -- constructor for the commons CampusLens agent.
# DuckDB-only backend in v1: loads the synthetic student-retention CSVs
# generated by generate_synthetic_data.R. Uppercase table names match the
# dictionary and measures.

library(commons)
library(ellmer)

Sys.setenv(AWS_REGION = "us-east-1")

make_connection <- function() {
  con <- DBI::dbConnect(duckdb::duckdb())
  DBI::dbWriteTable(con, "STUSL", read.csv("stusl.csv"))
  DBI::dbWriteTable(con, "ACAE", read.csv("acae.csv"))
  DBI::dbWriteTable(con, "TERMGPA", read.csv("termgpa.csv"))
  DBI::dbWriteTable(con, "RETTTE", read.csv("rettte.csv"))
  con
}

# DuckDB needs shutdown = TRUE to fully release its file lock. Safe to call
# from session$onSessionEnded(), where errors are otherwise swallowed.
close_connection <- function(con) {
  DBI::dbDisconnect(con, shutdown = TRUE)
}

make_agent <- function(con = make_connection()) {
  campus <- data_source(
    con,
    tables     = c("STUSL", "ACAE", "TERMGPA", "RETTTE"),
    dictionary = "dictionaries/student.data-dict.yaml"
  )

  commons(
    client         = chat_aws_bedrock(model = "us.anthropic.claude-sonnet-5"),
    data_sources   = list(campus = campus),
    semantic_layer = semantic_layer("measures/retention.R"),
    context_layer  = context_layer(files = c(
      "context/catalog-excerpt.md",
      "context/policy-conventions.md"
    )),
    instructions   = "instructions.md",
    log = TRUE
  )
}
```

- [ ] **Step 2: Verify it parses**

`agent.R` unconditionally runs `library(commons)` and `library(ellmer)` at
the top, so it cannot be `source()`d until those packages are installed
(neither is available in this sandbox). This step only checks syntax; the
real run — sourcing `agent.R` and exercising `make_connection()` /
`close_connection()` / `make_agent()` for real — happens in Task 11 once
`commons` and `ellmer` are installed.

Run: `Rscript -e 'parse("agent.R"); cat("parse OK\n")'`
Expected: `parse OK`

- [ ] **Step 3: Commit**

```bash
git add agent.R
git commit -m "Add DuckDB-backed agent constructor"
```

---

### Task 7: Agent instructions

**Files:**
- Create: `instructions.md`

**Interfaces:**
- Consumed by: `agent.R`'s `instructions = "instructions.md"` (Task 6, already written — this task only creates the file it points to).

- [ ] **Step 1: Write `instructions.md`**

```markdown
You assist institutional-research staff and academic advisors with
questions about Meridian State University's Fall 2022 entering cohort (a
synthetic dataset; no real student data).

Three programs: Business, Engineering, Liberal Arts. Students are tracked
for 8 terms (4 academic years).

Conventions:

- Before writing any custom SQL or R, always search the trusted
  calculations first, and prefer a trusted calculation whenever one
  plausibly answers the question -- even partially. Only write custom
  code for what no trusted calculation covers. Do not produce plots
  unless the user asks for one.
- Default denominator for percentages by program is the number of
  students in that program (STUSL).
- "Attrition" means voluntary withdrawal or academic dismissal (see
  context/policy-conventions.md); state which you mean if the question
  is ambiguous.
- Present results by program in the order: Business, Engineering,
  Liberal Arts.
- Do not make or imply decisions about individual, identifiable students
  (e.g., whether a specific student should be dismissed or placed on
  probation); these are cohort-level descriptive summaries for
  institutional research, not individual advising decisions.
- If a question cannot be answered from the available tables (STUSL,
  ACAE, TERMGPA, RETTTE), say so rather than approximating.
```

- [ ] **Step 2: Verify it's valid Markdown and non-empty**

Run: `wc -l instructions.md`
Expected: a nonzero line count.

- [ ] **Step 3: Commit**

```bash
git add instructions.md
git commit -m "Add agent instructions"
```

---

### Task 8: Shiny chat app

**Files:**
- Create: `app.R`

**Interfaces:**
- Consumes: `make_connection()`, `close_connection()`, `make_agent()` from `agent.R` (Task 6).
- Produces: a runnable Shiny app (`shinyApp(ui, server)`), the project's entry point.

- [ ] **Step 1: Write `app.R`**

```r
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
  list(label = "Midterm withdrawal clustering",
       question = "Do withdrawals cluster right after midterms?",
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
```

- [ ] **Step 2: Verify it parses**

Run: `Rscript -e 'parse("app.R"); cat("parse OK\n")'`
Expected: `parse OK`

(Actually running the app requires `commons`, `shinychat`, and AWS Bedrock credentials — not available in this sandbox. Manual run-through happens in Task 11.)

- [ ] **Step 3: Commit**

```bash
git add app.R
git commit -m "Add CampusLens Shiny chat app"
```

---

### Task 9: Setup smoke test

**Files:**
- Create: `check-setup.R`

**Interfaces:**
- Consumes: all measure function names from Task 5, `stusl.csv`/`acae.csv`/`termgpa.csv`/`rettte.csv` from Task 2.

- [ ] **Step 1: Write `check-setup.R`**

```r
# check-setup.R -- run before rehearsing the demo.
# Verifies packages, data columns used by measures/dictionary, Bedrock access.

ok <- function(x, msg) cat(if (x) "OK  " else "FAIL", msg, "\n")

# Packages
for (p in c("commons", "ellmer", "duckdb", "DBI", "dplyr", "survival", "ggsurvfit")) {
  ok(requireNamespace(p, quietly = TRUE), paste("package:", p))
}

# Columns required by measures + dictionary
need <- list(
  STUSL   = c("STUID", "PROGRAM", "COHORT_YEAR", "AGE", "ENTRY_GPA", "FINAL_STATUS"),
  ACAE    = c("STUID", "PROGRAM", "TERM", "EVENT_TYPE"),
  TERMGPA = c("STUID", "PROGRAM", "TERM", "TERM_GPA"),
  RETTTE  = c("STUID", "PROGRAM", "TIME", "EVENT")
)
files <- list(STUSL = "stusl.csv", ACAE = "acae.csv",
              TERMGPA = "termgpa.csv", RETTTE = "rettte.csv")
for (tbl in names(need)) {
  have <- names(read.csv(files[[tbl]], nrows = 1))
  missing <- setdiff(need[[tbl]], have)
  ok(length(missing) == 0,
     paste0(tbl, if (length(missing)) paste0(" missing: ",
            paste(missing, collapse = ", ")) else " columns"))
}

# Measures run standalone against DuckDB
con <- DBI::dbConnect(duckdb::duckdb())
DBI::dbWriteTable(con, "STUSL", read.csv("stusl.csv"))
DBI::dbWriteTable(con, "ACAE", read.csv("acae.csv"))
DBI::dbWriteTable(con, "TERMGPA", read.csv("termgpa.csv"))
DBI::dbWriteTable(con, "RETTTE", read.csv("rettte.csv"))
source("measures/retention.R")
try_measure <- function(name, expr) {
  res <- tryCatch(dplyr::collect(expr), error = function(e) e)
  ok(!inherits(res, "error"),
     paste("measure:", name,
           if (inherits(res, "error")) conditionMessage(res) else ""))
}
try_measure("attrition_by_program",      attrition_by_program(con))
try_measure("demog_profile_by_program",  demog_profile_by_program(con))
try_measure("probation_by_category",     probation_by_category(con))
try_measure("gpa_trend_table",           gpa_trend_table(con))
try_measure("completion_status_summary", completion_status_summary(con))
try_measure("attrition_rate_by_program", attrition_rate_by_program(con, through_term = 2))
res <- tryCatch(km_plot_by_program(con), error = function(e) e)
ok(!inherits(res, "error"), paste("measure: km_plot_by_program",
   if (inherits(res, "error")) conditionMessage(res) else ""))
DBI::dbDisconnect(con, shutdown = TRUE)

# Bedrock
Sys.setenv(AWS_REGION = "us-east-1")
res <- tryCatch(
  ellmer::chat_aws_bedrock(model = "us.anthropic.claude-sonnet-5")$chat("Say OK"),
  error = function(e) e
)
ok(!inherits(res, "error"), "Bedrock chat smoke test")
```

- [ ] **Step 2: Run the parts that don't need `commons`/Bedrock in this sandbox**

Run:
```bash
Rscript -e '
ok <- function(x, msg) cat(if (x) "OK  " else "FAIL", msg, "\n")
need <- list(
  STUSL   = c("STUID", "PROGRAM", "COHORT_YEAR", "AGE", "ENTRY_GPA", "FINAL_STATUS"),
  ACAE    = c("STUID", "PROGRAM", "TERM", "EVENT_TYPE"),
  TERMGPA = c("STUID", "PROGRAM", "TERM", "TERM_GPA"),
  RETTTE  = c("STUID", "PROGRAM", "TIME", "EVENT")
)
files <- list(STUSL = "stusl.csv", ACAE = "acae.csv", TERMGPA = "termgpa.csv", RETTTE = "rettte.csv")
for (tbl in names(need)) {
  have <- names(read.csv(files[[tbl]], nrows = 1))
  missing <- setdiff(need[[tbl]], have)
  ok(length(missing) == 0, paste0(tbl, if (length(missing)) paste0(" missing: ", paste(missing, collapse=", ")) else " columns"))
}
'
```
Expected:
```
OK   STUSL columns
OK   ACAE columns
OK   TERMGPA columns
OK   RETTTE columns
```
(Full `check-setup.R`, including the `commons` package check and Bedrock smoke test, is run for real in Task 11 once `commons` and AWS credentials are available.)

- [ ] **Step 3: Commit**

```bash
git add check-setup.R
git commit -m "Add pre-demo setup smoke test"
```

---

### Task 10: Trajectory review script

**Files:**
- Create: `trajectory-review.R`

**Interfaces:**
- Standalone script, run manually in Workbench after deployment; not consumed by any other file in this repo.

- [ ] **Step 1: Write `trajectory-review.R`**

```r
# trajectory-review.R -- the audit/review demo beat (run in Workbench)
#
# Prereqs for trajectories to flow on Connect:
#   1. Connect admin: enable OpenTelemetry + content instrumentation
#   2. This app: commons(log = TRUE)  (already set in agent.R)
#   3. Content observability activates after the content process restarts
# You must be owner or collaborator on the deployed content item.

library(commons)

# The deployed app's content GUID (Connect dashboard > Info panel). Not
# deployed yet in v1 -- set this once CampusLens has a Connect content item.
content_guid <- Sys.getenv("CAMPUSLENS_GUID")
if (!nzchar(content_guid)) {
  stop("CAMPUSLENS_GUID is not set. Set it once CampusLens is deployed to Connect.")
}

# Env vars (put in ~/.Renviron for persistence -- never commit real values
# here). CONNECT_SERVER / CONNECT_API_KEY are read from the environment.
if (!nzchar(Sys.getenv("CONNECT_SERVER")) || !nzchar(Sys.getenv("CONNECT_API_KEY"))) {
  stop(
    "CONNECT_SERVER and/or CONNECT_API_KEY are not set. Add them to ",
    "~/.Renviron (never hardcode credentials in this script) and restart R."
  )
}

# ---- 1. Pull recent conversations ------------------------------------------
trajectories <- trajectory_read(content_guid)
print(trajectories)

# ---- 2. Interactive review ---------------------------------------------------
# Opens the reviewer: step through conversations, see every tool call the
# agent made (which measure ran, what SQL/R it wrote), flag or annotate.
trajectory_review(trajectories)

# ---- Demo talk track ---------------------------------------------------------
# "Last week an advisor asked whether withdrawals cluster right after
#  midterms. The agent wrote exploratory code, and the answer was flagged
#  Untrusted. Here is institutional research reviewing exactly what the
#  agent did -- the question, the code it wrote, the result. If this
#  question keeps coming up, the team promotes it into a validated measure,
#  and from then on it's a green Verified answer."
```

- [ ] **Step 2: Verify it parses**

Run: `Rscript -e 'parse("trajectory-review.R"); cat("parse OK\n")'`
Expected: `parse OK`

- [ ] **Step 3: Commit**

```bash
git add trajectory-review.R
git commit -m "Add trajectory review script"
```

---

### Task 11: End-to-end acceptance check

**Files:** none created — this task verifies Tasks 1–10 together in an environment with `commons`, `ellmer`, and AWS Bedrock credentials available (this sandbox has neither).

**Interfaces:** none — terminal task.

- [ ] **Step 1: Install the remaining packages**

Run: `Rscript -e 'pak::pak(c("posit-dev/commons/pkg-r", "ellmer", "shinychat"))'`
Expected: installs without error (requires network + a working `pak`).

- [ ] **Step 2: Run the full setup check**

Run: `Rscript check-setup.R`
Expected: every line starts with `OK`, including `OK   Bedrock chat smoke test` (requires valid AWS credentials for Bedrock in the environment).

- [ ] **Step 3: Run the app and rehearse the demo script**

Run: `Rscript -e 'shiny::runApp()'`

Manually verify, per the spec's 6-beat demo script:
1. Click "Attrition by program" → green Verified badge, numbers match `attrition_by_program()`.
2. Click "Entry GPA by program" → green Verified badge.
3. Click "Attrition survival plot" → green Verified badge, Engineering's curve visibly drops faster than Business's in the first 2 terms.
4. Click "Probation definition" → blue Cited badge, quotes `context/policy-conventions.md`.
5. Click "Midterm withdrawal clustering" → yellow Untrusted badge, agent writes its own code.
6. Talk through the governance close (SELECT-only SQL, sandboxed R subprocess, trajectory logging) — no click needed, this is narration over the prior 5 beats.

- [ ] **Step 4: Commit if Steps 1–3 required any fixes**

```bash
git add -A
git commit -m "Fix issues found in end-to-end acceptance check"
```
(Skip this step if no fixes were needed.)
