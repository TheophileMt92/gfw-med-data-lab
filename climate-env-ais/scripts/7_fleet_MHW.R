# ==============================================================================
# GLOBAL FISHING WATCH LABORATORY - climate-env-ais
# Trawling in strong and weak heatwave summers, GSA 6 and GSAs 17-18
# ==============================================================================
# Builds on the fleet comparison of scripts/3_MHW.R (and the draft mhw_GSA6.R), with:
#   - both areas, each with its own contrasting years, picked from the heatwave metrics
#     on the prediction grid (scripts/5_MHW_grids.R): the three strongest and three
#     weakest summers from 2015 onward, after the AIS ramp-up
#   - trawlers only, filtered in the API request
#   - fleet metrics per summer: total hours, mean daily hours, active vessels, hours per
#     vessel, effort-weighted mean depth and distance to coast
#   - cell maps on a 0.05° grid, with cells not fished in a summer counted as 0
#
# Run from the climate-env-ais folder. Needs a GFW API token (GFW_TOKEN in .Renviron).
# Downloads are cached in data/processed/ (not in the repository); a full run downloads
# 12 summers of daily 0.01° trawler effort and takes a few minutes.
# Outputs: outputs/fleet_MHW_years.csv, outputs/fleet_MHW_summary.csv, outputs/fleet_MHW_cells.csv

library(gfwr)
library(sf)
library(dplyr)
library(tidyr)
library(lubridate)
library(marmap)
library(rnaturalearth)

if (Sys.getenv("GFW_TOKEN") == "" && file.exists("../.Renviron")) readRenviron("../.Renviron")
dir.create("data/processed", showWarnings = FALSE)

areas <- list(`GSA 6` = list(code = "6", smu = 6), `GSAs 17-18` = list(code = "1718", smu = c(17, 18)))
gsa <- st_read("data/raw/GSAs/GSAs_simplified.shp", quiet = TRUE)

# 1. Contrasting summers per area ------------------------------------------------
pick_years <- function(code) {
  read.csv(file.path("outputs", paste0("MHW_grid_", code, ".csv"))) |>
    filter(YEAR >= 2015) |>
    group_by(YEAR) |>
    summarise(cum = mean(mhw_cum_intensity, na.rm = TRUE), .groups = "drop") |>
    arrange(desc(cum)) |>
    mutate(class = case_when(row_number() <= 3 ~ "strong", row_number() > n() - 3 ~ "weak")) |>
    filter(!is.na(class))
}
years <- bind_rows(lapply(names(areas), \(a) pick_years(areas[[a]]$code) |> mutate(region = a)))
write.csv(years, "outputs/fleet_MHW_years.csv", row.names = FALSE)

# 2. Daily trawler effort, June-August, cached per area and year ------------------
summer_effort <- function(a, yr) {
  f <- file.path("data/processed", sprintf("gfw_summer_%s_%d.rds", areas[[a]]$code, yr))
  if (!file.exists(f)) {
    poly <- gsa |> filter(SMU_CODE %in% areas[[a]]$smu) |> st_union() |> st_as_sf()
    x <- gfw_ais_fishing_hours(spatial_resolution = "HIGH", temporal_resolution = "DAILY",
                               start_date = paste0(yr, "-06-01"), end_date = paste0(yr, "-09-01"),
                               filter_by = "geartype IN ('trawlers')",
                               region_source = "USER_SHAPEFILE", region = poly, key = gfw_auth())
    saveRDS(x, f)
  }
  readRDS(f) |>
    transmute(region = a, year = yr, date = `Time Range`, Lon, Lat, vessel = `Vessel ID`,
              hours = `Apparent Fishing Hours`)
}
eff <- bind_rows(lapply(seq_len(nrow(years)), \(i) summer_effort(years$region[i], years$YEAR[i]))) |>
  left_join(years |> select(region, year = YEAR, class), by = c("region", "year"))

# 3. Depth and distance to coast of each 0.01° cell ------------------------------
cells <- distinct(eff, Lon, Lat)
bathy_file <- "data/processed/bathy_fleet_MHW.rds"
if (!file.exists(bathy_file)) {
  b <- getNOAA.bathy(lon1 = min(cells$Lon) - 0.5, lon2 = max(cells$Lon) + 0.5,
                     lat1 = min(cells$Lat) - 0.5, lat2 = max(cells$Lat) + 0.5, resolution = 1, keep = FALSE)
  saveRDS(b, bathy_file)
}
cells$depth <- -get.depth(readRDS(bathy_file), x = cells[, c("Lon", "Lat")], locator = FALSE)$depth
coast <- ne_coastline(scale = "large", returnclass = "sf") |>
  st_crop(st_bbox(c(xmin = min(cells$Lon) - 2, xmax = max(cells$Lon) + 2,
                    ymin = min(cells$Lat) - 2, ymax = max(cells$Lat) + 2), crs = st_crs(4326)))
pts <- st_as_sf(cells, coords = c("Lon", "Lat"), crs = 4326)
cells$dist_coast_km <- as.numeric(st_distance(pts, st_union(coast))) / 1000
eff <- left_join(eff, cells, by = c("Lon", "Lat"))

# 4. Fleet metrics per area and summer --------------------------------------------
summary_tab <- eff |>
  group_by(region, year, class) |>
  summarise(total_hours     = sum(hours),
            vessels         = n_distinct(vessel),
            hours_per_vessel = total_hours / vessels,
            mean_daily_hours = total_hours / 92,                     # 92 days, June to August
            cells_fished    = n_distinct(Lon, Lat),
            mean_depth_m    = weighted.mean(depth, hours, na.rm = TRUE),
            mean_dist_coast_km = weighted.mean(dist_coast_km, hours, na.rm = TRUE),
            shelf_share     = sum(hours[depth <= 200], na.rm = TRUE) / sum(hours[!is.na(depth)]),  # red mullet depths
            .groups = "drop")
write.csv(eff |> mutate(depth_band = cut(depth, c(-Inf, 50, 100, 200, 500, Inf),
                                         labels = c("0-50 m", "50-100 m", "100-200 m", "200-500 m", ">500 m"))) |>
            group_by(region, year, class, depth_band) |> summarise(hours = sum(hours), .groups = "drop"),
          "outputs/fleet_MHW_depth.csv", row.names = FALSE)
write.csv(summary_tab, "outputs/fleet_MHW_summary.csv", row.names = FALSE)

# 5. Cell maps on a 0.05° grid: mean summer hours in strong and weak summers ------
cell_tab <- eff |>
  mutate(Lon = floor(Lon / 0.05) * 0.05 + 0.025, Lat = floor(Lat / 0.05) * 0.05 + 0.025) |>
  group_by(region, year, class, Lon, Lat) |>
  summarise(hours = sum(hours), .groups = "drop") |>
  complete(nesting(region, year, class), nesting(Lon, Lat), fill = list(hours = 0)) |>
  semi_join(eff |> mutate(Lon = floor(Lon / 0.05) * 0.05 + 0.025, Lat = floor(Lat / 0.05) * 0.05 + 0.025) |>
              distinct(region, Lon, Lat), by = c("region", "Lon", "Lat")) |>  # keep each area's own cells
  group_by(region, class, Lon, Lat) |>
  summarise(hours = mean(hours), .groups = "drop") |>
  pivot_wider(names_from = class, values_from = hours, values_fill = 0) |>
  mutate(difference = strong - weak, log_ratio = log((strong + 1) / (weak + 1)))
write.csv(cell_tab, "outputs/fleet_MHW_cells.csv", row.names = FALSE)
