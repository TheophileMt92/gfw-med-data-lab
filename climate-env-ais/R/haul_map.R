# Interactive map of MEDITS hauls, shared by the report and the slides.
# Hover over a haul to see its details. Basemap tiles need an internet connection;
# the haul points and hover labels work offline.

library(leaflet)

# One colour per GSA, used by the map and the hauls-per-year chart
gsa_colours <- function(gsa) {
  lv <- sort(unique(gsa))
  setNames(hcl.colors(length(lv), "Dark 3"), lv)
}

# hauls_map: one row per haul with id, GSA, country, year, month, lon, lat,
# depth, sst, botTemp, fishing_hours
haul_map <- function(hauls_map, focus_gsa = 6, height = 640) {
  cols <- gsa_colours(hauls_map$GSA)
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
          options = leafletOptions(preferCanvas = FALSE, zoomSnap = 0.25)) |>
    addProviderTiles(providers$Esri.WorldGrayCanvas,
                     options = providerTileOptions(maxZoom = 12)) |>
    fitBounds(-6, 34.5, 36, 46) |>
    addCircleMarkers(data = dplyr::filter(hm, !focus), lng = ~lon, lat = ~lat,
                     radius = 2.5, stroke = FALSE, fillOpacity = 0.75, fillColor = ~colour,
                     label = ~lapply(label, htmltools::HTML), labelOptions = lab_opts) |>
    addCircleMarkers(data = dplyr::filter(hm, focus), lng = ~lon, lat = ~lat,
                     radius = 3.5, color = "#062d4a", weight = 1, fillOpacity = 0.9,
                     fillColor = "#e4b363",
                     label = ~lapply(label, htmltools::HTML), labelOptions = lab_opts) |>
    addLegend("bottomleft", colors = "#e4b363",
              labels = paste0("GSA ", paste(focus_gsa, collapse = ", "), " (study area)"),
              opacity = 1)
}
