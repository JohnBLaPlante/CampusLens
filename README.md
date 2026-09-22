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
  "posit-dev/commons/pkg-r", "duckdb", "survival", "ggsurvfit", "ellmer",
  "paws.common"
))
```

AWS credentials for Bedrock must be available; region is set in `agent.R`
(`us-east-1`). Then:

```r
source("generate_synthetic_data.R")  # one-time: writes the 4 CSVs
source("check-setup.R")              # everything should print OK
shiny::runApp()                      # or source("app.R")
```
