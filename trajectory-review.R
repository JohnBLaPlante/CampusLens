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
