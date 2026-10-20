
# ==============================================================================
# GLOBAL FISHING WATCH LABORATORY
# EXERCISE 3 - MARINE HEATWAVES
# ======================================================================

rm(list = ls())

library(terra)
library(lubridate)
library (sf)
library(dplyr)
library(tidyr)
library(ggplot2)
library(heatwaveR)
library(patchwork)


# Marine Heatwaves (MHWs) are periods of unusually warm sea temperatures that persist for several days or weeks.
# They can alter species distributions, community structure and ecosystem functioning.

# In this exercise we quantify the frequency and intensity of MHWs and map their spatial variability 
# Then, we investigate whether fishing fleet behaviour may also be influenced by MHW

## open daily SST from Copernicus
# data are available at: https://data.marine.copernicus.eu/product/SST_MED_SST_L4_REP_OBSERVATIONS_010_021/services
sst <- rast("data/raw/sst_MED_daily_2010_2021.nc")
sst

sst <- sst - 273.15 # transform to celsius
range(time(sst)) 

dates <- time(sst)
  sort(unique(lubridate::year(dates)))
  sort(unique(lubridate::month(dates)))

    
# Crop SST dataset to your area of interest; this case GSA6
 #--------------------------------------------------------
# load GSAs shapefile
gsa <- st_read("data/raw/GSAs/GSAs_simplified.shp")
  
  
  # get your GSA polygon    
gsa6 <- gsa %>%filter(SMU_CODE == 6)
gsa6 <- terra::vect(gsa6)

# cut the sst file    
sst6 <- crop(sst, gsa6)
sst6 <- mask(sst6, gsa6)

plot(sst6[[1]]); lines(gsa6) # check the result
    

# Keep only the points of our predicted grid for calculations
#-------------------------------------------------------------          
new.env<-read.csv("data/raw/MED.env_grid_hindcast_2012_2021.csv",sep=',')
     
new.env6<-new.env %>% filter (GSA==6,MONTH == 7) # select month to have only one point per year
     
pts <- new.env6 %>%distinct(grid.id, grid.X, grid.Y)
pts.v <- vect(pts,geom = c("grid.X", "grid.Y"),crs = "EPSG:4326")

# check points are within the raster and extract
plot(sst6[[1]])
points(pts.v, col = "red", cex = 0.4)
sst6.ext <- terra::extract(sst6, pts.v)

# change to long format
sst6.long <- as.data.frame(sst6.ext[, -1])
names(sst6.long) <- as.character(as.Date(time(sst6)))
sst6.long$grid.id <- pts.v$grid.id
 
sst6.long <- sst6.long %>%
            pivot_longer( -grid.id,names_to = "date",values_to = "sst") %>%
            mutate(date = as.Date(date)  )
head(sst6.long);dim(sst6.long)

# check and remove NAs
summary(sst6.long$sst) # check NAs 
sst6.long <- sst6.long %>% # remove points with entire ts with NAs
  group_by(grid.id) %>%
  filter(!all(is.na(sst))) %>%
  ungroup()
head(sst6.long);dim(sst6.long)


#-------------------------------
# CALCULATE MARINE HEATWAVES
#-------------------------------

# Marine Heatwaves are identified following Hobday et al. (2016): https://doi.org/10.1016/j.pocean.2015.12.014

# A MHW is defined as a period of at least five consecutive days during
# which SST exceeds the seasonally varying 90th percentile threshold relative to a baseline climatology.

# Let´s start with just one point
test <- sst6.long %>% filter(grid.id == unique(grid.id)[1])

# First, a climatology is calculated for each grid cell.
# MHWs are then identified as periods exceeding the seasonally varying threshold.
clim <- ts2clm( test, x = date, y = sst,climatologyPeriod = c("2010-01-01", "2021-12-31")) # the longer ts, the better

# detect events
mhw <- detect_event(clim,x = date,y=sst)
head(mhw$event)

     # HeatwaveR also allows classification of MHWs into categories (Moderate, Strong, Severe and Extreme) 
     # following Hobday et al. (2018): https://doi.org/10.5670/oceanog.2018.205

# Now, we can calculate events for all the points
# We focus on MHW events occurring during summer months (june,july,august),
# when thermal stress is typically highest and ecological impacts are expected to be strongest in the Mediterranean.
mhw.events <- sst6.long %>%
                group_by(grid.id) %>%
                group_modify(~{
             clim <- ts2clm( .x, x = date, y = sst, climatologyPeriod = c("2010-01-01", "2021-12-31") )
             ev <- detect_event( clim, x = date, y = sst)$event
             if(nrow(ev) == 0)
             return(data.frame())
             ev
  })
mhw.events <- mhw.events %>% filter( month(date_peak) %in% c(6,7,8) )

# Annual summary per point
# We summarise MHW metrics by grid cell and year.
# Grid cells without events receive a value of zero.
mhw.year <- expand.grid( grid.id = unique(pts$grid.id), YEAR = 2012:2021) %>% # make sure we kept all years in all points even if no events detected
            left_join(pts, by = "grid.id") %>% # add points coordinates
            left_join(mhw.events %>%
                      mutate(YEAR = lubridate::year(date_peak)) %>%
                      group_by(grid.id, YEAR) %>%
                      summarise(
                          mhw_frequency = n(),                            # number of events
                          mhw_days = sum(duration),                       # total number of days under MHW conditions
                          mhw_mean_duration = mean(duration),             # average event duration
                          mhw_mean_intensity = mean(intensity_mean),      # average SST anomaly during events (°C)
                          mhw_max_intensity = max(intensity_max),         # maximum SST anomaly recorded (°C)
                          mhw_cum_intensity = sum(intensity_cumulative),  # cumulative thermal stress experienced during the year
                          .groups = "drop"
                        ),
                      by = c("grid.id", "YEAR") ) %>%
            mutate(
                across( starts_with("mhw_"), ~replace_na(.x, 0)) # Grid cells without detected MHWs are assigned zeros for all annual MHW metrics
  )
head(mhw.year)

write.table(mhw.year,'outputs/MHW_gsa6.csv',sep=';',row.names=F)

# GSA annual summary
mhw.gsa <- mhw.year %>%
  group_by(YEAR) %>%
  summarise(
    mhw_frequency      = mean(mhw_frequency, na.rm = TRUE),
    mhw_days           = mean(mhw_days, na.rm = TRUE),
    mhw_mean_duration  = mean(mhw_mean_duration, na.rm = TRUE),
    mhw_mean_intensity = mean(mhw_mean_intensity, na.rm = TRUE),
    mhw_max_intensity  = mean(mhw_max_intensity, na.rm = TRUE),
    mhw_cum_intensity  = mean(mhw_cum_intensity, na.rm = TRUE),
    .groups = "drop"
  )%>% as.data.frame()

mhw.gsa



# plot MHW indicators
world <- map_data("world")

var <- "mhw_cum_intensity"

# Cumulative intensity is often considered a useful integrated measure
# of thermal stress because it combines both event duration and intensity.

lims <- range(mhw.year[[var]], na.rm = TRUE) # set limits to make color scale comparable among year plots

mhw.year %>% ggplot() +
  geom_polygon( data = world, aes(long, lat, group = group),
                fill = "grey85",colour = "grey60",linewidth = 0.2) +
  geom_point( aes( grid.X, grid.Y, colour = .data[[var]]), size = 0.5) +
  scale_colour_viridis_c( option = "inferno", limits = lims, name = var) +
  coord_fixed(1.3, xlim = c(-1, 4), ylim = c(37.5, 42.5) ) +
  facet_wrap(~YEAR) +
  theme_bw() +
  theme(
    axis.title = element_blank(),
    axis.text = element_blank(),
    axis.ticks = element_blank()
  )

# These years were selected as illustrative examples of relatively
# high- and low-MHW conditions within the study period.
years.MHW<-c(2017,2018,2020) 
years.noMHW<-c(2013,2014,2016)

# They are used to explore whether fishing behaviour differs between periods of contrasting thermal stress.


#-------------------------------------------
# FLEET BEHAVIOUR UNDER MARINE HEATWAVES
#------------------------------------------

library(gfwr)
library(purrr) 
library(scales) # Needed for squish()
library(marmap)
# install.packages("igraph") # if marmap is looking for this; answer No if prompted to "do you want to install from sources the package which needs compilation?"
# install.packages("rnaturalearthhires", repos = "https://ropensci.r-universe.dev")
library(rnaturalearth)

# Authenticate GFW API (Ensure API token is configured)
# Refer to instructions (https://github.com/GlobalFishingWatch/gfwr) to get an API token
key <- gfw_auth()


# Now we compare fishing activity between the two periods of high (summer 2017,2018 and 2020) and low (summer 2013, 2014, 2016) MHW
# In terms of:
  # total fishing effort as annual hours
  # mean daily fishing hours
  # mean fishing distance as mean distance to the coast line (km)
  # mean fishing depth
  # number of vessels as distinct MMSI (Maritime Mobile Service Identity)
  # spatial footprint as maps of fishing hours

# IMPORTANT:
# This comparison does not demonstrate causality.
# Differences between MHW and non-MHW years may also reflect technological, economic, management or regulatory changes occurring through time.


# Fetch AIS Fishing Hours                      
# Since we want to calculate mean daily fishing hours, we have to download daily data from GFW
# We can still limit the downloads to the years and months (6 to 8) of interest.
# Geartype can also be passed on as a filter (refer to https://globalfishingwatch.org/our-apis/documentation/docs/v3/general-api-doc/reference-data#gear-types-supported)

start_time <- Sys.time() # This took a few minutes

daily_fishing_hrs <- map_dfr(c(years.MHW,years.noMHW), function(yr) {
  message(paste("Fetching AIS fishing hours for year:", yr))
  gfw_ais_fishing_hours(
    spatial_resolution = "HIGH",              # HIGH = 0.01 degree grids
    temporal_resolution = "DAILY",            # DAILY effort in this case
    start_date = paste0(yr, "-06-01"),
    end_date = paste0(yr, "-09-01"),          # remember that this date is excluded
    # filter_by = "geartype in ('trawlers')", # you can also filter geartype directly
    region_source = "USER_SHAPEFILE",
    region = st_as_sf(gsa6),
    key = key
  )
})
sprintf("finished in %.2f minutes", round(as.numeric(difftime(Sys.time(),start_time, units = "mins")), 2))

# Identify years by MHW classification (MHW or noMHW)
# Simplify the analysis also to focus on TRAWLERS only
trawlers_gridded_hrs <-
  daily_fishing_hrs %>% 
  mutate(
    year = year(`Time Range`),
    month = month.abb[month(`Time Range`)],
    # Assign MHW status based on year
    mhw = case_when(
      year %in% years.MHW ~ "mhw",
      year %in% years.noMHW ~ "no_mhw",
      TRUE ~ NA_character_
    )
  ) %>%
  filter(`Gear Type`=="TRAWLERS")


# Add bathymetry information to each point
#==========================================
# Depth is extracted for each fishing location to evaluate mean fishing depth

# Download the data matrix directly 
# resolution = 1 fetches the highest native resolution available (~450m-1km depending on region)
bathy_grid <- getNOAA.bathy(
  lon1 = min(trawlers_gridded_hrs$Lon) - 1,
  lon2 = max(trawlers_gridded_hrs$Lon) + 1,
  lat1 = min(trawlers_gridded_hrs$Lat) - 1,
  lat2 = max(trawlers_gridded_hrs$Lat) + 1,
  resolution = 1, keep = TRUE) 
                            
# Extract depth for each lat-lon point and add to the trawlers_gridded_hrs
trawlers_gridded_hrs$depth <- get.depth(
  mat = bathy_grid, 
  x = trawlers_gridded_hrs[, c("Lon", "Lat")], 
  locator = FALSE
)$depth


# Add distance from nearest coastline to each point
#===================================================
# Distance to coastline is used as a simple descriptor of displacement of the fleet 

# Extract unique lat-lon grid points from trawler data
unique_coords <- trawlers_gridded_hrs %>%
  select(Lon, Lat) %>%
  distinct()

# Convert unique points to sf object
unique_sf <- st_as_sf(unique_coords, coords = c("Lon", "Lat"), crs = 4326)

# Get coastline and crop it to the points' bounding box (+ 2 degree buffer) to speed up distance calculations
bbox <- st_bbox(unique_sf)
bbox_buffered <- bbox + c(-2, -2, 2, 2) # Expand bounds slightly
coastline <- ne_coastline(scale = "large", returnclass = "sf") %>% 
  st_crop(bbox_buffered)

# Compute min distance to coastline for unique points (converted to km)
unique_coords$dist_to_coast_km <- as.numeric(apply(st_distance(unique_sf, coastline), 1, min)) / 1000

# Join back to full dataset
trawlers_gridded_hrs <- trawlers_gridded_hrs %>%
  left_join(unique_coords, by = c("Lon", "Lat"))


# Create a summary table of all fishing indicators
#===================================================

# for each of the years
fishing_summary <- 
  trawlers_gridded_hrs %>%
  # create the annual summaries
  group_by(year, mhw) %>% 
  summarize(
    annual_hrs = sum(`Apparent Fishing Hours`, na.rm = TRUE),
    vessel_count = n_distinct(MMSI),
    mean_depth = mean(depth, na.rm = TRUE),
    mean_dist_to_coast_km = mean(dist_to_coast_km, na.rm = TRUE),
    .groups = "drop"
  ) %>% 
  # add mean daily fishing hours
  left_join(
    trawlers_gridded_hrs %>% 
      group_by(`Time Range`, year, mhw) %>% 
      summarize(daily_hrs = sum(`Apparent Fishing Hours`, na.rm = TRUE), .groups = "drop") %>% 
      group_by(year, mhw) %>% 
      summarize(mean_daily_fishing_hrs = mean(daily_hrs, na.rm = TRUE), .groups = "drop"),
    by = c("year", "mhw")
  )

head(fishing_summary)

# averaging annual fishing effort per cell in MHW and no-MHW years
fishing.maps <- trawlers_gridded_hrs %>%
  group_by(Lon,Lat,year,mhw) %>%
  summarise(annual_fishing_hours =sum(`Apparent Fishing Hours`,
          na.rm = TRUE),.groups = "drop") %>%
  summarise(mean_fishing_hours = mean(annual_fishing_hours),
            .by = c(Lon, Lat, mhw) )

head(fishing.maps)

# transform to long format and calculate change
fishing.change <- fishing.maps %>%
  pivot_wider(names_from = mhw,values_from = mean_fishing_hours) %>%
  drop_na(mhw, no_mhw) %>%
  mutate(difference = mhw - no_mhw,
         log_ratio =log((mhw + 1) /(no_mhw + 1)) # better for visualization
    )                                            # since just a few cells with large change

head(fishing.change)

write.csv(fishing.maps,"outputs/fishing_maps_MHW.csv",row.names = FALSE)
write.csv(fishing.change,"outputs/fishing_change_MHW.csv",row.names = FALSE)


# Changes in spatial footprint
#===================================================

# Compare spatial distribution of fishing effort during MHW and noMHW periods
# in a similar way as we explored changes in habitat suitability

p1 <- ggplot() +
        geom_polygon(data = world,aes(long, lat, group = group),
               fill = "grey85", colour = "grey60",linewidth = 0.2) +
        geom_point( data = fishing.change,
                    aes(Lon, Lat, colour = log10(no_mhw + 1) ), size = 0.5) + ## Color in log scale !
        scale_colour_viridis_c( name = "log(Fishing hours)") +
     labs(title = "Mean Fishing Effort\nNon-MHW years" ) +
     coord_fixed(1.3,  xlim = c(-1,4),ylim = c(37.5,42.5)) +
     theme_bw()

 
p2 <- ggplot() +
        geom_polygon(data = world,aes(long, lat, group = group),
               fill = "grey85", colour = "grey60",linewidth = 0.2) +
        geom_point(data = fishing.change,
                   aes(Lon,Lat,colour = log10(mhw + 1) ), size = 0.5) +
        scale_colour_viridis_c(name = "log(Fishing hours)") +
     labs(title = "Mean Fishing Effort\nMHW years") +
     coord_fixed(1.3,  xlim = c(-1,4),ylim = c(37.5,42.5)) +
     theme_bw()


p3 <- ggplot() +
        geom_polygon(data = world,aes(long, lat, group = group),
               fill = "grey85", colour = "grey60",linewidth = 0.2) +
        geom_point(data = fishing.change,
                   aes(Lon,Lat, colour = difference), size = 0.5) +
        scale_colour_gradient2( low = "blue",
                                mid = "white",
                                high = "red",
                                midpoint = 0,
                                name = "Δ effort") +
       labs(title = "MHW - non-MHW") +
       coord_fixed(1.3,  xlim = c(-1,4),ylim = c(37.5,42.5)) +
       theme_bw()


p4 <- ggplot() +
        geom_polygon(data = world,aes(long, lat, group = group),
               fill = "grey85", colour = "grey60",linewidth = 0.2) +
        geom_point(data = fishing.change,
                   aes(Lon,Lat,colour = log_ratio), size = 0.5) +
        scale_colour_gradient2( low = "blue",
                                mid = "white",
                                high = "red",
                                midpoint = 0,
                                name = "log(MHW/noMHW)") +
     labs(title = "Relative change") +
     coord_fixed(1.3,  xlim = c(-1,4),ylim = c(37.5,42.5)) +
     theme_bw()
    # The relative-change map uses a log-ratio transformation to avoid
    # spurious extreme percentage values in cells with very low fishing effort

dev.new()
final_plot <- (p1 + p2) / (p3 + p4)
final_plot

ggsave(filename = "outputs/Fishing_effort_MHW_comparison.png",
  plot = final_plot, width = 12, height = 10,dpi = 300)