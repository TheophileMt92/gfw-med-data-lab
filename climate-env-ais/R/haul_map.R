# Interactive map of MEDITS hauls, shared by the report and the slides.
# Dark-blue, Global Fishing Watch-style background: navy ocean and blue-grey land
# drawn from Natural Earth outlines, so no basemap tiles (and no internet) are needed.
# Hover over a haul to see its details.

library(leaflet)

map_style <- list(ocean = "#0b1d3a", land = "#22375c", border = "#36507d",
                  focus = "#f2c14e")

# One colour per GSA, used by the map and the hauls-per-year chart.
# The focus GSA gets gold; the others get hues from green to red that skip
# yellow and orange, so nothing competes with the focus colour.
gsa_colours <- function(gsa, focus_gsa = 6) {
  lv <- sort(unique(gsa))
  others <- setdiff(lv, focus_gsa)
  hues <- seq(130, 390, length.out = length(others)) %% 360
  cols <- setNames(hcl(h = hues, c = 55, l = 68), others)
  cols[as.character(focus_gsa)] <- map_style$focus
  cols[as.character(lv)]
}

med_land <- function() {
  sf::sf_use_s2(FALSE)
  rnaturalearth::ne_countries(scale = "medium", returnclass = "sf") |>
    sf::st_make_valid() |>
    sf::st_crop(c(xmin = -12, xmax = 42, ymin = 28, ymax = 50)) |>
    suppressWarnings() |> suppressMessages()
}

# hauls_map: one row per haul with id, GSA, country, year, month, lon, lat,
# depth, sst, botTemp, fishing_hours
haul_map <- function(hauls_map, focus_gsa = 6, height = 640) {
  cols <- gsa_colours(hauls_map$GSA, focus_gsa)
  hm <- hauls_map |>
    dplyr::mutate(
      colour = unname(cols[as.character(GSA)]),
      focus  = GSA %in% focus_gsa,
      label  = sprintf(
        paste0("<b>GSA %s</b> · %s<br>%s/%02d · haul %s<br>",
               "Depth %s m · bottom %s °C · SST %s °C<br>",
               "AIS trawling: %s"),
        GSA, country, year, month, sub(".*_", "", id),
        round(depth), round(botTemp, 1), round(sst, 1),
        ifelse(is.na(fishing_hours), "no match",
               paste0(format(round(fishing_hours), big.mark = ","), " h/yr in cell"))))

  lab_opts <- labelOptions(textsize = "13px", direction = "top")

  leaflet(hm, height = height, width = "100%",
          # SVG markers (not canvas): hover hit-testing stays correct when reveal.js scales the slide
          options = leafletOptions(preferCanvas = FALSE, zoomSnap = 0.25,
                                   attributionControl = FALSE)) |>
    addPolygons(data = med_land(), fillColor = map_style$land, fillOpacity = 1,
                color = map_style$border, weight = 0.6,
                options = pathOptions(interactive = FALSE)) |>
    fitBounds(-6, 34.5, 36, 46) |>
    addCircleMarkers(data = dplyr::filter(hm, !focus), lng = ~lon, lat = ~lat,
                     radius = 2.2, stroke = FALSE, fillOpacity = 0.6, fillColor = ~colour,
                     label = ~lapply(label, htmltools::HTML), labelOptions = lab_opts) |>
    addCircleMarkers(data = dplyr::filter(hm, focus), lng = ~lon, lat = ~lat,
                     radius = 4, color = "#ffffff", weight = 0.8, fillOpacity = 1,
                     fillColor = map_style$focus,
                     label = ~lapply(label, htmltools::HTML), labelOptions = lab_opts) |>
    addLegend("bottomleft", colors = map_style$focus,
              labels = paste0("GSA ", paste(focus_gsa, collapse = ", "), " (study area)"),
              opacity = 1) |>
    htmlwidgets::onRender(sprintf(
      "function(el) { el.style.background = '%s'; }", map_style$ocean))
}
