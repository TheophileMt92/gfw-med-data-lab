# ==============================================================================
# GLOBAL FISHING WATCH LABORATORY - climate-env-ais
# Marine heatwaves on the red mullet prediction grids (GSA 6 and GSAs 17-18)
# ==============================================================================
# Adapted from the group's mhw_GSA6.R (Exercise 3), with these changes:
#   - relative paths: run from the climate-env-ais folder (the RStudio project)
#   - one function for both areas, on the same grid as the sdmTMB predictions
#     (data/group/pred_6.rds, data/group/pred_1718.rds)
#   - cells with no SST data are kept as NA instead of being set to 0
#     (the SST product stops at 45.0°N, north of part of the Adriatic grid)
#   - the fleet comparison of mhw_GSA6.R is unchanged from scripts/3_MHW.R and is
#     not repeated here
#
# Input : data/raw/sst_MED_daily_2010_2021.nc  (Copernicus SST_MED_SST_L4_REP_OBSERVATIONS_010_021,
#         daily L4 SST, 2010-2021, about 2.2 GB, not in the repository)
# Output: outputs/MHW_grid_6.csv, outputs/MHW_grid_1718.csv
#         (one row per grid cell and year, 2012-2021, summer events only)
# Runtime: a few minutes for GSA 6, about 20 minutes for GSAs 17-18 (uses several cores).

library(terra)
library(dplyr)
library(tidyr)
library(lubridate)
library(heatwaveR)
library(parallel)

sst_file <- "data/raw/sst_MED_daily_2010_2021.nc"

# SST anomalies are computed against a 2010-2021 climatology, as in the group's script.
# Hobday et al. (2016) recommend a 30-year baseline; with 12 years, event counts are
# indicative and comparable between areas and years, not with other studies.
clim_period <- c("2010-01-01", "2021-12-31")

mhw_grid <- function(area, cores = max(1, detectCores() - 1)) {
  grid <- readRDS(file.path("data/group", paste0("pred_", area, ".rds"))) |>
    distinct(X, Y) |>
    mutate(grid.id = row_number())

  sst <- rast(sst_file)
  ext_area <- ext(min(grid$X) - 0.1, max(grid$X) + 0.1, min(grid$Y) - 0.1, max(grid$Y) + 0.1)
  sst <- crop(sst, ext_area) - 273.15                       # Kelvin to °C
  dates <- as.Date(time(sst))

  # Daily SST at each grid cell (nearest SST pixel)
  vals <- terra::extract(sst, vect(grid, geom = c("X", "Y"), crs = "EPSG:4326"), ID = FALSE)
  vals <- as.matrix(vals)
  has_sst <- rowSums(!is.na(vals)) > 0.9 * ncol(vals)      # cells with a usable SST series

  one_cell <- function(i) {
    ts <- data.frame(t = dates, temp = vals[i, ])
    clim <- ts2clm(ts, climatologyPeriod = clim_period)
    ev <- detect_event(clim)$event
    if (nrow(ev) == 0) return(NULL)
    ev |>
      filter(month(date_peak) %in% 6:8) |>                 # summer events (peak in June-August)
      mutate(grid.id = grid$grid.id[i], YEAR = year(date_peak)) |>
      select(grid.id, YEAR, duration, intensity_mean, intensity_max, intensity_cumulative)
  }
  events <- bind_rows(mclapply(which(has_sst), one_cell, mc.cores = cores))

  # Annual summary per cell; cells with SST but no event get 0, cells without SST stay NA
  expand.grid(grid.id = grid$grid.id, YEAR = 2012:2021) |>
    left_join(grid, by = "grid.id") |>
    left_join(events |>
                group_by(grid.id, YEAR) |>
                summarise(mhw_frequency      = n(),                         # number of events
                          mhw_days           = sum(duration),               # days under MHW conditions
                          mhw_mean_duration  = mean(duration),              # mean event duration (days)
                          mhw_mean_intensity = mean(intensity_mean),        # mean SST anomaly (°C)
                          mhw_max_intensity  = max(intensity_max),          # maximum SST anomaly (°C)
                          mhw_cum_intensity  = sum(intensity_cumulative),   # cumulative intensity (°C days)
                          .groups = "drop"),
              by = c("grid.id", "YEAR")) |>
    mutate(sst_available = has_sst[grid.id],
           across(starts_with("mhw_"), \(x) if_else(sst_available, replace_na(x, 0), NA_real_))) |>
    arrange(grid.id, YEAR)
}

dir.create("outputs", showWarnings = FALSE)
for (area in c("6", "1718")) {
  t0 <- Sys.time()
  out <- mhw_grid(area)
  write.csv(out, file.path("outputs", paste0("MHW_grid_", area, ".csv")), row.names = FALSE)
  message("GSA ", area, ": ", n_distinct(out$grid.id), " cells, ",
          round(difftime(Sys.time(), t0, units = "mins"), 1), " min")
}
