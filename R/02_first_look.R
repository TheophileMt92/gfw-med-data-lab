# =============================================================================
# 02_first_look.R : first analysis of Mediterranean AIS effort vs SAR detections
#
# Outputs (figures/ and outputs/):
#  1. map_ais_effort.png     mean annual AIS apparent fishing hours per 0.1 deg cell
#  2. map_sar_dark_share.png share of SAR detections NOT matched to AIS per cell
#  3. ts_monthly.png         monthly AIS hours by gear + SAR matched/unmatched
#  4. ais_vs_sar.png         cell-level AIS hours vs SAR detections (topic 1 baseline)
#  5. summary_by_year.csv    annual totals
#
# Runs on whatever years 01_download_gfw.R has already fetched.
# =============================================================================

library(dplyr)
library(tidyr)
library(readr)
library(sf)
library(ggplot2)
library(patchwork)
library(scales)

dir.create("figures", showWarnings = FALSE)
dir.create("outputs", showWarnings = FALSE)

ais <- readRDS("data/processed/ais_med_monthly.rds")
sar <- readRDS("data/processed/sar_med_monthly.rds")
med <- st_read("data/processed/med_domain.gpkg", quiet = TRUE)

# Keep only years present in both sources so comparisons are like-for-like
yrs <- intersect(unique(ais$year), unique(sar$year))
ais <- filter(ais, year %in% yrs)
sar <- filter(sar, year %in% yrs)
n_years <- length(yrs)
message("Years used: ", paste(sort(yrs), collapse = ", "))

# Gear grouping
ais <- ais |>
  mutate(gear = case_when(
    geartype == "trawlers" ~ "Trawlers",
    grepl("longline", geartype) ~ "Longlines",
    grepl("purse_seine", geartype) ~ "Purse seines",
    TRUE ~ "Other / unknown"))

land <- rnaturalearth::ne_countries(scale = "medium", returnclass = "sf") |>
  st_make_valid() |>
  st_crop(c(xmin = -6.5, xmax = 37, ymin = 29.5, ymax = 46.5))

map_base <- list(
  geom_sf(data = land, fill = "grey88", colour = "grey70", linewidth = 0.15, inherit.aes = FALSE),
  coord_sf(xlim = c(-6, 36.5), ylim = c(30, 46), expand = FALSE),
  theme_minimal(base_size = 10),
  theme(axis.title = element_blank(), legend.position = "bottom",
        legend.key.width = unit(12, "mm"), plot.title.position = "plot",
        plot.title = element_text(face = "bold"))
)

# ---- 1. Mean annual AIS fishing effort -------------------------------------------
ais_cell <- ais |>
  group_by(lon, lat) |>
  summarise(hours = sum(fishing_hours, na.rm = TRUE) / n_years, .groups = "drop")

p1 <- ggplot(ais_cell |> filter(hours > 0)) +
  geom_tile(aes(lon, lat, fill = hours), width = 0.1, height = 0.1) +
  scale_fill_viridis_c(trans = "log10", option = "mako", direction = -1,
                       labels = label_comma(), name = "Fishing hours / year") +
  map_base +
  labs(title = "AIS apparent fishing effort, Mediterranean",
       subtitle = sprintf("Mean per year, %d-%d, 0.1° cells", min(yrs), max(yrs)),
       caption = "Source: Global Fishing Watch (gfwr)")
ggsave("figures/map_ais_effort.png", p1, width = 9, height = 4.8, dpi = 200, bg = "white")

# ---- 2. Share of SAR detections without AIS --------------------------------------
sar_cell <- sar |>
  group_by(lon, lat) |>
  summarise(total = sum(detections), unmatched = sum(detections[!matched]),
            .groups = "drop") |>
  mutate(dark_share = unmatched / total)

p2 <- ggplot(sar_cell |> filter(total >= 5)) +      # >= 5 detections to limit noise
  geom_tile(aes(lon, lat, fill = dark_share), width = 0.1, height = 0.1) +
  scale_fill_viridis_c(option = "rocket", direction = -1, labels = label_percent(),
                       limits = c(0, 1), name = "Unmatched to AIS") +
  map_base +
  labs(title = "Vessels seen by radar but not broadcasting AIS",
       subtitle = sprintf("Share of Sentinel-1 SAR detections unmatched to AIS, %d-%d (cells with >= 5 detections)",
                          min(yrs), max(yrs)),
       caption = "All vessel types; SAR misses most vessels < ~15 m. Source: Global Fishing Watch (gfwr)")
ggsave("figures/map_sar_dark_share.png", p2, width = 9, height = 4.8, dpi = 200, bg = "white")

# ---- 3. Monthly time series --------------------------------------------------
ts_ais <- ais |>
  group_by(year, month, gear) |>
  summarise(hours = sum(fishing_hours), .groups = "drop") |>
  mutate(date = as.Date(sprintf("%d-%02d-01", year, month)))

ts_sar <- sar |>
  group_by(year, month, matched) |>
  summarise(det = sum(detections), .groups = "drop") |>
  mutate(date = as.Date(sprintf("%d-%02d-01", year, month)),
         type = ifelse(matched, "Matched to AIS", "Unmatched (dark)"))

p3a <- ggplot(ts_ais, aes(date, hours / 1e3, fill = gear)) +
  geom_area() +
  scale_fill_manual(values = c("Trawlers" = "#1b4f72", "Longlines" = "#48a9a6",
                               "Purse seines" = "#e4b363", "Other / unknown" = "#b0b7bf")) +
  labs(x = NULL, y = "Thousand fishing hours", fill = NULL,
       title = "AIS apparent fishing hours per month") +
  theme_minimal(base_size = 10) + theme(legend.position = "bottom")

p3b <- ggplot(ts_sar, aes(date, det, colour = type)) +
  geom_line(linewidth = 0.6) +
  scale_colour_manual(values = c("Matched to AIS" = "#1b4f72", "Unmatched (dark)" = "#c0392b")) +
  scale_y_continuous(labels = label_comma()) +
  labs(x = NULL, y = "SAR detections", colour = NULL,
       title = "SAR vessel detections per month") +
  theme_minimal(base_size = 10) + theme(legend.position = "bottom")

ggsave("figures/ts_monthly.png", p3a / p3b, width = 9, height = 7, dpi = 200, bg = "white")

# ---- 4. Cell-level AIS effort vs SAR detections ----------------------------------
# Baseline for topic 1: how much of the spatial pattern in AIS effort does
# radar-visible vessel activity explain, and where do they diverge?
cell <- full_join(ais_cell, sar_cell, by = c("lon", "lat")) |>
  mutate(across(c(hours, total, unmatched), \(x) coalesce(x, 0)))

both <- filter(cell, hours > 0, total > 0)
rho  <- cor(both$hours, both$total, method = "spearman")
fit  <- lm(log10(hours) ~ log10(total / n_years), data = both)

p4 <- ggplot(both, aes(total / n_years, hours)) +
  geom_hex(bins = 60) +
  geom_smooth(method = "lm", formula = y ~ x, colour = "#c0392b", linewidth = 0.7) +
  scale_x_log10(labels = label_comma()) + scale_y_log10(labels = label_comma()) +
  scale_fill_viridis_c(option = "mako", direction = -1, trans = "log10", name = "Cells") +
  labs(x = "SAR detections per year (all vessels)", y = "AIS fishing hours per year",
       title = "AIS fishing effort vs radar-detected vessels, per 0.1° cell",
       subtitle = sprintf("Spearman rho = %.2f; log-log R² = %.2f; n = %s cells with both",
                          rho, summary(fit)$r.squared, comma(nrow(both)))) +
  theme_minimal(base_size = 10)
ggsave("figures/ais_vs_sar.png", p4, width = 7, height = 5.5, dpi = 200, bg = "white")

# Where does SAR see vessels but AIS records no fishing?
coverage <- cell |>
  summarise(
    cells_sar_only = sum(total > 0 & hours == 0),
    cells_ais_only = sum(total == 0 & hours > 0),
    cells_both     = sum(total > 0 & hours > 0),
    sar_det_in_sar_only_cells = sum(total[hours == 0]) / sum(total)
  )

# ---- 5. Annual summary table ----------------------------------------------------
summary_year <- ais |>
  group_by(year) |>
  summarise(ais_fishing_hours = sum(fishing_hours),
            ais_trawl_share   = sum(fishing_hours[gear == "Trawlers"]) / sum(fishing_hours),
            ais_cells_fished  = n_distinct(paste(lon, lat))) |>
  left_join(
    sar |> group_by(year) |>
      summarise(sar_detections = sum(detections),
                sar_unmatched_share = sum(detections[!matched]) / sum(detections)),
    by = "year")

write_csv(summary_year, "outputs/summary_by_year.csv")
write_csv(coverage, "outputs/ais_sar_coverage.csv")
print(summary_year, width = Inf)
print(coverage)
message("Figures in figures/, tables in outputs/")
