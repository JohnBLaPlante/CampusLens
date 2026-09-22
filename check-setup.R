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
