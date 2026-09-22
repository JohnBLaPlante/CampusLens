# CampusLens: Governed Student-Retention Q&A Agent — Design

**Date:** 2026-09-22
**Author:** John LaPlante (drafted with Claude)
**Status:** Approved, ready for implementation planning
**Modeled on:** [sol-eng/TrialLens](https://github.com/sol-eng/TrialLens) — same [commons](https://posit-dev.github.io/commons/) framework, ported from clinical-trial data to synthetic higher-education data.

## Purpose

A reusable, general higher-ed-vertical demo (not tied to a specific prospect) showing a governed AI agent — built with Posit's `commons` R package — answering questions over student-success/retention data. Same three-tier trust model as TrialLens: **Verified** (validated measure, no model-written code), **Cited** (quoted from a policy document), **Untrusted** (agent writes its own sandboxed code).

## Scope for v1

- Single synthetic institution, one entering cohort, ~300–500 students, 3 programs, 8 terms of history.
- DuckDB backend only. No Snowflake branch, no `push_snowflake.R` equivalent, in this version. Code should stay simple rather than pre-built for a future Snowflake branch — that's a v2 concern, not a v1 abstraction to design around now.
- Built and run locally in this repo (`~/Posit/MyDemos/CampusLens`). No GitHub remote yet — that's a later decision, not blocking this build.

## Data model

Four tables replace TrialLens's ADSL/ADAE/ADLB/ADTTE:

| Table | Grain | Columns (indicative) | Role |
|---|---|---|---|
| `STUSL` | 1 row per student | student ID, program (Business / Engineering / Liberal Arts), entering cohort year, demographics, entry GPA/test score | subject-level, analogous to `ADSL` |
| `ACAE` | 1 row per academic event | student ID, term, event type (probation / dismissal / leave-of-absence / advising-flag), severity | event log, analogous to `ADAE` |
| `TERMGPA` | 1 row per student per term | student ID, term number (1–8), term GPA, credit hours attempted/earned | performance-over-time, analogous to `ADLB` |
| `RETTTE` | 1 row per student | student ID, program, time-to-event (terms until first withdrawal/dismissal), event indicator (1 = attrited, 0 = censored at graduation/end-of-data) | time-to-event, analogous to `ADTTE` |

**Designed-in signal:** Engineering has a higher year-1 attrition hazard than Business, so `km_plot_by_program()` shows a real, visible separation between programs — not a flat/fabricated curve (mirrors TrialLens's real dermatologic-AE separation between arms).

**Internal consistency requirement:** `ACAE` probation/dismissal events must be derived from `TERMGPA` using the same thresholds documented in `context/policy-conventions.md` (e.g., GPA < 2.0 triggers probation; consecutive probations trigger dismissal), so the data and the policy doc the agent cites never contradict each other.

## Validated measures (`measures/retention.R`)

7 measures, each a pre-written, governed R function the agent calls instead of writing its own SQL/R:

| Measure | Mirrors (TrialLens) | Answers |
|---|---|---|
| `attrition_by_program()` | `ae_incidence_by_arm()` | % of students per program who withdrew or were dismissed |
| `demog_profile_by_program()` | `demog_age_by_arm()` | Age / entry-GPA distribution by program |
| `km_plot_by_program()` | `km_plot_by_arm()` | Kaplan-Meier survival curve, time-to-attrition by program |
| `probation_by_category()` | `teae_by_soc()` | Academic-event counts by category, by program |
| `gpa_trend_table()` | `lab_shift_table()` | First-term vs. most-recent-term GPA shift table |
| `completion_status_summary()` | `disposition_summary()` | Counts: graduated / still enrolled / withdrawn / dismissed |
| `attrition_rate_by_program()` | `tte_event_rate_by_arm()` | Attrition rate at a fixed time point (e.g., end of year 2), by program |

(7 rather than TrialLens's 9 — no higher-ed equivalent was forced for the remaining two; more can be added later if a gap surfaces during demo rehearsal.)

## Context docs (Cited answers)

- `context/catalog-excerpt.md` — program structure, entering-cohort definition, credit-hour requirements. Mirrors `protocol-excerpt.md`.
- `context/policy-conventions.md` — Satisfactory Academic Progress (SAP) policy, probation/dismissal GPA thresholds, attrition-event definition, term-numbering convention. Mirrors `sap-conventions.md`. Must stay consistent with how `ACAE` is derived (see Data model above).

## Data dictionary

`dictionaries/student.data-dict.yaml` — tables, columns, glossary, governed definitions. Mirrors `dictionaries/adam.data-dict.yaml`. Same constraint as TrialLens applies: the dictionary parser only supports simple boolean/comparison expressions, not `CASE WHEN` — if a definition needs that, drop the expression and keep the description text only.

## File layout

| File | Role |
|---|---|
| `agent.R` | Connects to DuckDB, constructs the agent (single backend branch) |
| `app.R` | Chat UI (`commons_server()` + `chat_ui()`), suggestion cards |
| `generate_synthetic_data.R` | One-time generator (replaces `pharmaverseadam` + `push_snowflake.R`): simulates all 4 tables, seeded for reproducibility, loads into DuckDB |
| `measures/retention.R` | The 7 validated measures |
| `dictionaries/student.data-dict.yaml` | Data dictionary |
| `context/catalog-excerpt.md` | Program/cohort context → Cited answers |
| `context/policy-conventions.md` | SAP policy, thresholds, conventions → Cited answers |
| `instructions.md` | Agent persona and reporting conventions |
| `check-setup.R` | Pre-demo smoke test (packages, columns, measures, Bedrock) |
| `trajectory-review.R` | Reviews logged agent trajectories (`commons(log = TRUE)`) |

## Synthetic data generation

`generate_synthetic_data.R` builds all four tables from seeded random distributions — no external synthetic-higher-ed package exists to lean on (unlike `pharmaverseadam` for clinical data):

1. **`STUSL`**: assign each student a program, entering cohort year, demographics, and entry GPA/test score (`rnorm`/`sample`-based).
2. **`TERMGPA`**: simulate an 8-term GPA trajectory per student, with per-program noise and Engineering's steeper early-term decline baked into the generating distribution.
3. **`ACAE`**: derive probation/dismissal/LOA events from `TERMGPA` using the exact thresholds in `context/policy-conventions.md`.
4. **`RETTTE`**: derive time-to-first-attrition-event (or censoring at graduation/end-of-data) per student from `ACAE`/`TERMGPA`, with Engineering's higher year-1 hazard flowing through naturally from step 2 rather than being hard-coded into `RETTTE` directly.

## Demo script (6 beats)

1. **Verified** — "What % of students in each program withdrew or were dismissed?" → `attrition_by_program()`
2. **Verified** — "Show me the entry-GPA distribution by program." → `demog_profile_by_program()`
3. **Verified** — "Plot the survival curve for time-to-attrition by program." → `km_plot_by_program()`; shows Engineering's real, designed-in higher first-year attrition vs. Business
4. **Cited** — "How is academic probation defined?" → quotes `context/policy-conventions.md`
5. **Untrusted** — an ad-hoc question with no matching measure (e.g., "Do withdrawals cluster right after midterms?") → agent writes sandboxed code, yellow badge
6. **Governance close** — SELECT-only SQL, OS-sandboxed R subprocess, trajectory logging reviewed via `trajectory_review()`

## Tech stack

Same core as TrialLens, minus the Snowflake-only pieces:

```r
pak::pak(c(
  "posit-dev/commons/pkg-r", "duckdb", "survival", "ggsurvfit", "ellmer"
))
```

AWS credentials for Bedrock must be available; newer Claude models on Bedrock need the `us.` inference-profile prefix (same gotcha as TrialLens). `odbc`, `snowflakeauth`, and `connectcreds` are dropped from v1 since there is no Snowflake backend yet.

## Known gotchas (carried over from TrialLens, where still applicable)

- commons is experimental — pin the working version; rerun `check-setup.R` before every demo.
- Newer Claude models on Bedrock need the `us.` inference-profile prefix.
- Set `AWS_REGION` before the first `ellmer` call (credentials are cached per session).
- If a `data-dict.yaml` definition fails validation, remove the expression and keep the description text only (parser doesn't support `CASE WHEN`).
- macOS uses the Seatbelt sandbox; don't demo from Windows (no OS sandbox).

## Deliberately deferred (not in v1)

- Snowflake backend / `TRIAL_BACKEND`-style switch.
- GitHub repo home (sol-eng vs. personal) — decide once the demo is proven out locally.
- Scaling to multiple cohort years or a larger student population.
