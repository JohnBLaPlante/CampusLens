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
