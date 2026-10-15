# =============================================================================
# 01_download_gfw.R : Mediterranean AIS fishing hours + SAR detections via gfwr
#
# - AIS apparent fishing hours, 0.1 deg, monthly, by gear  (gfw_ais_fishing_hours)
# - SAR vessel detections, 0.1 deg, monthly, AIS-matched vs unmatched
#                                                            (gfw_sar_vessel_detections)
# Each year x half-basin request is cached in data/raw/, so the script can be
# stopped and re-run: it only fetches what is missing. The first-look script
# works with whatever years are already downloaded.
# =============================================================================

library(gfwr)

# GFW_TOKEN lives in the repo's .Renviron (git-ignored, never commit it)
if (file.exists(".Renviron")) readRenviron(".Renviron")
library(dplyr)
library(purrr)
library(sf)

# ---- Settings -----------------------------------------------------------------
YEARS <- 2017:2024           # Sentinel-1 SAR starts 2017. Use e.g. 2023:2024 for a quick test.
dir.create("data/raw/ais", recursive = TRUE, showWarnings = FALSE)
dir.create("data/raw/sar", recursive = TRUE, showWarnings = FALSE)
dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)

# ---- Study area ----------------------------------------------------------------
# Approximate GFCM Mediterranean: excludes the Atlantic west of Gibraltar,
# Bay of Biscay, Sea of Marmara and Black Sea. Vertices run over land.
med <- st_sf(
  name = "Mediterranean",
  geometry = st_sfc(st_polygon(list(matrix(c(
    -5.6, 30.0,  36.5, 30.0,  36.5, 37.5,  26.6, 40.2,  26.0, 41.2,
    20.0, 46.0,   2.9, 46.0,   2.9, 42.3,  -5.6, 42.3,  -5.6, 30.0
  ), ncol = 2, byrow = TRUE))), crs = 4326)
)

# Split into west / east halves at 15 E so each API report stays small
halves <- list(
  west = st_crop(med, xmin = -6, xmax = 15,  ymin = 29, ymax = 47),
  east = st_crop(med, xmin = 15, xmax = 37,  ymin = 29, ymax = 47)
) |> map(\(x) st_sf(geometry = st_geometry(x)))
st_write(med, "data/processed/med_domain.gpkg", delete_dsn = TRUE, quiet = TRUE)

# ---- Cached, retrying gfwr call ---------------------------------------------------
# On a timeout the GFW API keeps building the report and returns HTTP 429 to new
# calls until done; gfw_last_report() then collects the finished result.
fetch <- function(file, fun, ...) {
  if (file.exists(file)) return(invisible(readRDS(file)))
  for (i in 1:3) {
    out <- tryCatch(fun(...), error = \(e) e)
    if (!inherits(out, "error")) { saveRDS(out, file); Sys.sleep(2); return(invisible(out)) }
    message("   ! ", conditionMessage(out))
    if (grepl("429|time", conditionMessage(out), ignore.case = TRUE)) {
      for (k in 1:20) {                      # poll up to ~10 min
        Sys.sleep(30)
        lr <- tryCatch(gfw_last_report(), error = \(e) NULL)
        if (is.data.frame(lr)) { saveRDS(lr, file); return(invisible(lr)) }
      }
    } else Sys.sleep(10)
  }
  warning("Failed: ", file, " (re-run the script later to retry)")
  invisible(NULL)
}

# ---- Download loop -------------------------------------------------------------
t0 <- Sys.time()
for (y in YEARS) for (h in names(halves)) {
  dates <- list(start_date = sprintf("%d-01-01", y), end_date = sprintf("%d-01-01", y + 1))
  message(format(Sys.time(), "%H:%M"), "  ", y, " ", h)

  # AIS apparent fishing hours by gear type
  do.call(fetch, c(list(
    file = sprintf("data/raw/ais/ais_%d_%s.rds", y, h),
    fun  = gfw_ais_fishing_hours,
    spatial_resolution = "LOW", temporal_resolution = "MONTHLY",
    group_by = "GEARTYPE",
    region_source = "USER_SHAPEFILE", region = halves[[h]]), dates))

  # SAR detections, split into AIS-matched and unmatched ("dark") vessels
  for (m in c("true", "false")) {
    do.call(fetch, c(list(
      file = sprintf("data/raw/sar/sar_%s_%d_%s.rds",
                     ifelse(m == "true", "matched", "unmatched"), y, h),
      fun  = gfw_sar_vessel_detections,
      spatial_resolution = "LOW", temporal_resolution = "MONTHLY",
      filter_by = sprintf("matched='%s'", m),
      region_source = "USER_SHAPEFILE", region = halves[[h]]), dates))
  }
}
message("Done in ", round(difftime(Sys.time(), t0, units = "mins"), 1), " min")

# ---- Tidy into two tables ----------------------------------------------------------
read_dir <- function(pattern) {
  fs <- list.files(c("data/raw/ais", "data/raw/sar"), pattern, full.names = TRUE)
  set_names(fs, basename(fs)) |> map(readRDS) |> compact() |> bind_rows(.id = "file")
}

ais <- read_dir("^ais_") |>
  transmute(lon = Lon, lat = Lat,
            year  = as.integer(substr(`Time Range`, 1, 4)),
            month = as.integer(substr(`Time Range`, 6, 7)),
            geartype = geartype,
            fishing_hours = `Apparent Fishing Hours`,
            vessels = `Vessel IDs`) |>
  # a cell on the 15E cut can come back from both halves: keep one copy
  distinct(lon, lat, year, month, geartype, .keep_all = TRUE)

sar <- read_dir("^sar_") |>
  transmute(lon = Lon, lat = Lat,
            year  = as.integer(substr(`Time Range`, 1, 4)),
            month = as.integer(substr(`Time Range`, 6, 7)),
            matched = grepl("_matched_", file),
            detections = Detections) |>
  distinct(lon, lat, year, month, matched, .keep_all = TRUE)

saveRDS(ais, "data/processed/ais_med_monthly.rds")
saveRDS(sar, "data/processed/sar_med_monthly.rds")
message("AIS: ", nrow(ais), " rows, years ", paste(range(ais$year), collapse = "-"),
        " | SAR: ", nrow(sar), " rows")
