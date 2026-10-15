# =============================================================================
# 03_s1_overpasses.R : Sentinel-1 overpasses per 0.1 deg cell and month
#
# SAR detection counts scale with how often the radar looks at a cell. Revisit
# roughly halved after Sentinel-1B failed (23 Dec 2021), so raw counts are not
# comparable over time. This script counts, for every cell and month, the number
# of distinct Sentinel-1 IW passes (satellite x absolute orbit) whose GRD scene
# footprints cover the cell centre. Detections are then normalised as
# detections per overpass (= mean number of vessels seen per satellite look).
#
# Source: Copernicus Data Space Ecosystem OData catalogue (no login needed).
# Runtime: a few minutes; one cached file per month in data/raw/s1/.
# Output: data/processed/s1_overpasses.rds  (lon, lat, year, month, overpasses)
#         lon/lat use the same lower-left-corner convention as the GFW grid.
# =============================================================================

library(httr2)
library(jsonlite)
library(sf)
# install.packages(c("httr2", "jsonlite")) if missing
library(dplyr)
library(purrr)

sf_use_s2(FALSE)
YEARS <- 2017:2024
dir.create("data/raw/s1", recursive = TRUE, showWarnings = FALSE)

# ---- Grid: 0.1 deg cells touching the FAO Mediterranean (Area 37.1-37.3) ------
fao <- st_read("data_ref/fao_area37_med.geojson", quiet = TRUE)
med <- fao |> filter(F_LEVEL == "SUBAREA") |> st_union() |> st_make_valid()

bb <- st_bbox(med)
x0 <- floor(bb[["xmin"]] * 10) / 10
y0 <- floor(bb[["ymin"]] * 10) / 10
sq <- st_make_grid(med, cellsize = 0.1, offset = c(x0, y0),
                   n = c(ceiling((bb[["xmax"]] - x0) / 0.1), ceiling((bb[["ymax"]] - y0) / 0.1)))
sq <- sq[lengths(st_intersects(sq, med)) > 0]
pts <- suppressWarnings(st_centroid(sq))
xy <- st_coordinates(pts)
cells <- tibble(lon = round(xy[, 1] - 0.05, 1), lat = round(xy[, 2] - 0.05, 1))
message(nrow(cells), " cells")

# Simple search polygon for the catalogue query (keeps the URL short)
aoi_wkt <- "POLYGON((-6 30,36.5 30,36.5 37.5,26.8 40.7,26 41.2,20 46,2.9 46,2.9 42.3,-6 42.3,-6 30))"

# ---- Catalogue query: all Sentinel-1 IW GRDH scenes for one month -------------
query_month <- function(y, m) {
  start <- sprintf("%d-%02d-01T00:00:00.000Z", y, m)
  end   <- if (m == 12) sprintf("%d-01-01T00:00:00.000Z", y + 1)
           else sprintf("%d-%02d-01T00:00:00.000Z", y, m + 1)
  filt <- paste0(
    "Collection/Name eq 'SENTINEL-1' and contains(Name,'IW_GRDH') and ",
    "OData.CSC.Intersects(area=geography'SRID=4326;", aoi_wkt, "') and ",
    "ContentDate/Start ge ", start, " and ContentDate/Start lt ", end)
  out <- list(); skip <- 0
  repeat {
    resp <- request("https://catalogue.dataspace.copernicus.eu/odata/v1/Products") |>
      req_url_query(`$filter` = filt, `$top` = 1000, `$skip` = skip,
                    `$orderby` = "ContentDate/Start asc") |>
      req_retry(max_tries = 5, backoff = \(i) 5 * i) |>
      req_timeout(120) |>
      req_perform()
    v <- resp_body_json(resp)$value
    out <- c(out, v)
    if (length(v) < 1000) break
    skip <- skip + 1000
  }
  out
}

# GeoJSON footprint (list) -> sfg, built directly (much faster than st_read)
ring <- function(r) do.call(rbind, lapply(r, \(pt) as.numeric(unlist(pt))[1:2]))
to_sfg <- function(g) {
  if (g$type == "Polygon") st_polygon(lapply(g$coordinates, ring))
  else st_multipolygon(lapply(g$coordinates, \(poly) lapply(poly, ring)))
}

# Product name -> satellite, sensing start, absolute orbit
# e.g. S1A_IW_GRDH_1SDV_20170105T053010_20170105T053035_014702_017E9E_8F3C[_COG].SAFE
parse_products <- function(v) {
  nm <- map_chr(v, "Name")
  parts <- strsplit(nm, "_")
  tibble(
    name  = nm,
    sat   = map_chr(parts, 1),
    start = map_chr(parts, 5),
    orbit = map_chr(parts, 7),
    geom  = st_sfc(map(v, \(p) to_sfg(p$GeoFootprint)), crs = 4326)
  ) |>
    # COG and reprocessed copies share satellite + start time: keep one
    distinct(sat, start, .keep_all = TRUE)
}

# ---- Loop over months ----------------------------------------------------
t0 <- Sys.time()
res <- list()
for (y in YEARS) for (m in 1:12) {
  f <- sprintf("data/raw/s1/s1_%d_%02d.rds", y, m)
  if (!file.exists(f)) {
    v <- query_month(y, m)
    sc <- parse_products(v)
    # One footprint per pass: union of consecutive scenes of the same orbit,
    # so overlaps between adjacent scenes are not double counted
    passes <- sc |>
      st_as_sf(sf_column_name = "geom") |>
      group_by(sat, orbit) |>
      summarise(.groups = "drop")
    n <- lengths(st_intersects(pts, passes))
    saveRDS(tibble(cells, year = y, month = m, overpasses = n,
                   n_scenes = nrow(sc), n_passes = nrow(passes)), f)
    message(sprintf("%d-%02d  %4d scenes  %3d passes  median %d overpasses/cell  (%.1f min)",
                    y, m, nrow(sc), nrow(passes), median(n),
                    as.numeric(difftime(Sys.time(), t0, units = "mins"))))
  }
  res[[f]] <- readRDS(f)
}

ov <- bind_rows(res)
saveRDS(select(ov, lon, lat, year, month, overpasses), "data/processed/s1_overpasses.rds")

ov |>
  group_by(year) |>
  summarise(median_overpasses_per_cell_month = median(overpasses),
            passes_per_month = mean(n_passes)) |>
  print()
