# =============================================================================
# 00_install.R : install gfwr (first) + the few packages the first analysis needs
# Run once in Positron:  source("R/00_install.R")
# =============================================================================

options(repos = c(CRAN = "https://cloud.r-project.org"))

# GFW_TOKEN lives in the repo's .Renviron (git-ignored, never commit it)
if (file.exists(".Renviron")) readRenviron(".Renviron")

# ---- 1. gfwr -----------------------------------------------------------------
# GFW r-universe (binaries, fastest). Falls back to GitHub if that fails.
if (!requireNamespace("gfwr", quietly = TRUE)) {
  try(install.packages(
    "gfwr",
    repos = c("https://globalfishingwatch.r-universe.dev",
              "https://cloud.r-project.org")
  ))
  if (!requireNamespace("gfwr", quietly = TRUE)) {
    if (!requireNamespace("remotes", quietly = TRUE)) install.packages("remotes")
    remotes::install_github("GlobalFishingWatch/gfwr", dependencies = TRUE)
  }
}
message("gfwr ", utils::packageVersion("gfwr"))
# This code uses the gfwr >= 3.0 function names
# (gfw_ais_fishing_hours, gfw_sar_vessel_detections).
stopifnot(utils::packageVersion("gfwr") >= "3.0.0")

# ---- 2. Other packages ----------------------------------------------------------
pkgs <- c("dplyr", "tidyr", "purrr", "readr", "sf", "ggplot2", "patchwork",
          "scales", "hexbin", "rnaturalearth", "rnaturalearthdata", "usethis")
miss <- setdiff(pkgs, rownames(installed.packages()))
if (length(miss)) install.packages(miss)

# ---- 3. API token ------------------------------------------------------------
# Token: https://globalfishingwatch.org/our-apis/tokens
# Stored in the repo-level .Renviron (git-ignored) as:  GFW_TOKEN="..."
# and loaded above with readRenviron(), so no restart is needed.
if (!nzchar(Sys.getenv("GFW_TOKEN"))) {
  message("No GFW_TOKEN yet: run usethis::edit_r_environ(), add GFW_TOKEN=\"...\", restart R.")
} else {
  eez <- gfwr::gfw_regions(region_source = "EEZ")
  message("GFW API OK: ", nrow(eez), " EEZs listed. Ready for R/01_download_gfw.R")
}
