# ==============================================================================
# GLOBAL FISHING WATCH LABORATORY - climate-env-ais
# Marine heatwaves, biomass trend and trawling trend (GSA 6 and GSAs 17-18)
# ==============================================================================
# Adapted from the group's Plot_MHW_BiologicalTrend_Effor_ttrend.R, with these changes:
#   - relative paths: run from the climate-env-ais folder (the RStudio project)
#   - both areas, from the same function
#   - heatwave panel: mean annual summer cumulative intensity over 2014-2021, the period
#     of the trends (the original grouped by year and cell, so the ten yearly maps were
#     drawn on top of each other and only the last year was visible)
#   - trends expressed relative to each cell's mean (% per year), so biomass (kg/km²) and
#     effort (hours) can be compared and one threshold means the same for both; the
#     original ±0.1 threshold was in absolute units and classed only ~3% of cells as stable
#   - cells without SST data (north of 45.0°N) are shown as missing, not as zero heatwaves
#
# Inputs : outputs/MHW_grid_<area>.csv            (scripts/5_MHW_grids.R)
#          data/group/df_slope_6.rds, df_slope.rds  (group: per-cell linear slopes 2014-2021)
#          data/group/pred_<area>.rds, eff_grid_<area>.rds (group: predictions, trawling hours)
# Output : trend_maps("6"), trend_maps("1718") return a three-panel ggplot (patchwork)

library(dplyr)
library(ggplot2)
library(patchwork)

trend_cap  <- 15     # colour scale capped at ±15% per year
min_effort <- 1      # cells with < 1 trawling hour per year on average: effort trend not shown
mhw_max    <- 40     # same heatwave colour scale for both areas (°C days per summer)

trend_data <- function(area) {
  key <- function(d) mutate(d, X = round(X, 5), Y = round(Y, 5))
  slope_file <- if (area == "6") "df_slope_6.rds" else "df_slope.rds"
  slopes <- readRDS(file.path("data/group", slope_file)) |>
    rename(any_of(c(slope_bio = "slope_den"))) |> key()
  means <- readRDS(file.path("data/group", paste0("pred_", area, ".rds"))) |>
    group_by(X, Y) |> summarise(dens_mean = mean(dens), .groups = "drop") |> key() |>
    inner_join(readRDS(file.path("data/group", paste0("eff_grid_", area, ".rds"))) |>
                 group_by(X, Y) |> summarise(eff_mean = mean(trawl_y), .groups = "drop") |> key(),
               by = c("X", "Y"))
  mhw <- read.csv(file.path("outputs", paste0("MHW_grid_", area, ".csv"))) |>
    filter(YEAR %in% 2014:2021) |>
    group_by(X, Y) |>
    summarise(mhw_cum = mean(mhw_cum_intensity), .groups = "drop") |> key()

  slopes |>
    inner_join(means, by = c("X", "Y")) |>
    left_join(mhw, by = c("X", "Y")) |>
    mutate(trend_bio = 100 * slope_bio / dens_mean,
           trend_eff = if_else(eff_mean >= min_effort, 100 * slope_eff / eff_mean, NA_real_))
}

trend_maps <- function(area, d = trend_data(area)) {
  world <- map_data("world")
  view <- coord_fixed(1.3, xlim = range(d$X) + c(-0.3, 0.3), ylim = range(d$Y) + c(-0.2, 0.2))
  base <- function() ggplot() +
    geom_polygon(data = world, aes(long, lat, group = group),
                 fill = "grey88", colour = "grey65", linewidth = 0.2) +
    view + theme_void(base_size = 10) +
    theme(legend.position = "bottom", plot.title = element_text(face = "bold", size = 10),
          legend.title = element_text(size = 8.5)) +
    guides(fill = guide_colourbar(barwidth = unit(9, "lines"), barheight = unit(0.5, "lines"),
                                  title.position = "top", title.hjust = 0.5))
  tile <- function(var) geom_tile(data = d, aes(X, Y, fill = .data[[var]]), width = 1/24, height = 1/24)
  div <- function(name) scale_fill_gradient2(low = "#2166AC", mid = "#F7F7F7", high = "#B2182B", midpoint = 0,
                                             limits = c(-trend_cap, trend_cap), oob = scales::squish,
                                             na.value = "grey70", name = name)

  p1 <- base() + tile("mhw_cum") +
    scale_fill_viridis_c(option = "inferno", na.value = "grey70", limits = c(0, mhw_max), oob = scales::squish,
                         name = "Cumulative intensity\n(°C days per summer)") +
    labs(title = "A. Marine heatwaves, 2014-2021 mean")
  p2 <- base() + tile("trend_bio") + div("Biomass trend\n(% of cell mean per year)") +
    labs(title = "B. Red mullet biomass trend")
  p3 <- base() + tile("trend_eff") + div("Trawling trend\n(% of cell mean per year)") +
    labs(title = "C. Trawling effort trend")
  p1 | p2 | p3
}
