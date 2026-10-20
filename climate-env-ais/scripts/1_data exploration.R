
# ==============================================================================
# GLOBAL FISHING WATCH LABORATORY
# EXERCISE 1 - DATA PREPARATION AND FAMILIARIZATION
# ======================================================================

rm(list = ls())

# libraries to visualize data
library(tidyverse)
library(maps)
library(ggplot2)

# libraries to download and process GFW data
library(gfwr)
library(sf)
library(terra)
library(cli)
library(purrr) 

# Authenticate GFW API (Ensure API token is configured)
# Refer to instructions (https://github.com/GlobalFishingWatch/gfwr) to get an API token
key <- gfw_auth()


##------------------------------------
## MEDITS dataset from 2012 to 2021
##------------------------------------

# MEDITS data can be accessed from JRC: https://data.jrc.ec.europa.eu/dataset/ef36af5d-eb4e-4a9f-9513-82a877fe71fe
# be aware data directly download from here may content inconsistencies, missing fields, invalid values, and table-level mismatches

# Details on MEDITS surveys: https://scientiamarina.revistas.csic.es/index.php/scientiamarina/article/download/1829/2597/0

medits<-read.csv('data/raw/MEDITS_2012_2021.csv',sep=',')

head(medits)
str(medits)


# Let´s explore MEDITS data

# Map of sampling stations (hauls)
#---------------------------------
world <- map_data("world")

medits %>%
  distinct(id, .keep_all = TRUE) %>% # plot only unique ids
  ggplot() +
  geom_polygon(data = world,
               aes(long, lat, group = group),
               fill = "grey85",colour = "grey60",linewidth = 0.2) +
  geom_point(aes(MEAN_LONGITUDE_DEC,MEAN_LATITUDE_DEC, color = factor(GSA)),
             alpha = 0.7, size = 1.2) +
  coord_fixed(1.3,xlim = c(-5, 35),ylim = c(34.7, 45.4)) +
  theme_bw() +
  labs(x = "Longitude", y = "Latitude",color = "GSA" )


# hauls per year and GSA
#------------------------
medits %>%
  distinct(id, .keep_all = TRUE) %>%
  count(GSA, YEAR) %>%
  ggplot(aes(YEAR,n,fill = factor(GSA))) +
  geom_col() +
  theme_bw() +
  labs(fill = "GSA",y = "Number of hauls")


# hauls per bathymetry
#------------------------------------
medits %>%
  distinct(id, .keep_all = TRUE) %>%
  ggplot(aes(MEAN_DEPTH)) +
  geom_histogram(binwidth = 50, ## one bar per 50m
                 fill = "steelblue",
                 colour = "black") +
  theme_bw()


## Map total species richness
#------------------------------------

# Species richness is used here as a simple biodiversity indicator
richness <- medits %>%
  filter(N_km2 > 0) %>% ## select abundance column
  group_by(id, YEAR, GSA) %>%
  summarise(richness = n_distinct(MEDITS_CODE),
            MEAN_LONGITUDE_DEC = first(MEAN_LONGITUDE_DEC), ## keep coordinates to map richness values
            MEAN_LATITUDE_DEC = first(MEAN_LATITUDE_DEC),
            .groups = "drop")


ggplot() +
  geom_polygon(data = world,
               aes(long, lat, group = group),
               fill = "grey85",colour = "grey60",linewidth = 0.2) +
  geom_point(data = richness,
             aes(MEAN_LONGITUDE_DEC,MEAN_LATITUDE_DEC,colour = richness),
             alpha = 0.8,size = 1.8) +
  scale_colour_viridis_c(option = "plasma",name = "Richness") +
  coord_fixed(1.3,xlim = c(-5, 35),ylim = c(34.7, 45.4)) +
  theme_bw() +
  labs(x = "Longitude", y = "Latitude") +
  theme(panel.grid = element_blank(), legend.position = "right")


## Dominant species
#-------------------
top_species <- medits %>%
  group_by(MEDITS_CODE) %>%
  summarise( biomass = sum(TOTAL_WEIGHT_IN_THE_HAUL, na.rm = TRUE), ## you can also select abundance or change to occurrence
            .groups = "drop") %>%
  arrange(desc(biomass))

top_species %>%
  slice_max(biomass, n = 20) %>%
  ggplot(aes(reorder(MEDITS_CODE,biomass),biomass)) +
  geom_col(fill = "darkorange") +
  coord_flip() +
  theme_bw()+
  labs( y = "Biomass (total kg)",x = "Species")



## Map single species abundance
#------------------------------

# We can also explore distribution of single species

# the MEDITS codes for species are here
# spp <-read.csv('data/raw/MEDITS_listTM.csv',sep=';')

sp <- "MERLMER"   # Merluccius merluccius

medits %>%
  filter(MEDITS_CODE == sp) %>%
  ggplot() +
  geom_polygon(data = world,aes(long, lat, group = group),
               fill = "grey85",colour = "grey60",linewidth = 0.2) +
  geom_point(aes(MEAN_LONGITUDE_DEC, MEAN_LATITUDE_DEC,
                 colour = log10(N_km2 + 1)),size = 0.5) +      ## for biomass: aes(color = log10(kg_km2 + 1))
  scale_colour_gradientn(
    colours = c("lightyellow",
                "gold",
                "orange",
                "red",
                "darkred"),
    name = "log10(N/km² + 1)" )+
  coord_fixed(1.3,xlim = c(-5, 35),ylim = c(34.7, 45.4)) +
      facet_wrap(~YEAR) +
      theme_bw() 



##-----------------------------------------
## Environmental variables at haul level
##----------------------------------------

# The evironmental variables used come from Copernicus Marine Products and were extracted at haul locations:
  # Mediterranean Sea Physics Reanalysis (MEDSEA_MULTIYEAR_PHY_006_004): https://data.marine.copernicus.eu/es/product/MEDSEA_MULTIYEAR_PHY_006_004/description?view=-&option=-&product_id=-the 
  # Mediterranean Sea Biogeochemistry Reanalysis (MEDSEA_MULTIYEAR_BGC_006_008): https://data.marine.copernicus.eu/es/product/MEDSEA_MULTIYEAR_BGC_006_008/description?view=-&option=-&product_id=-

env<-read.csv('data/raw/MED.env_haul_2012_2021.csv',sep=',')
head(env)
str(env)

# Explore environmental gradientes in the Mediterranean

var <- "sst"

env %>%
  ggplot() +
  geom_polygon(data = world, aes(long, lat, group = group),
               fill = "grey85",colour = "grey60",linewidth = 0.2) +
  geom_point(aes(X, Y, colour = .data[[var]]),size = 0.5) +
  scale_colour_viridis_c(name = paste(var) ) +
  coord_fixed(1.3,xlim = c(-5, 35),ylim = c(34.7, 45.4)) +
    facet_wrap(~YEAR) +
  theme_bw() 



##-----------------------------------------
## GFW Fishing effort
##----------------------------------------

# We will use GFW data on trawling fleets to quantify fishing pressure

# calculate TOTAL FISHING HOURS of TRAWLERS by YEAR for every point (haul) and merge with the environmental dataframe

years <- sort(unique(env$YEAR))

# Fetch AIS Fishing Hours 

# we use 0.1º (LOW) fishing effort data since it provides better coverage of MEDITS haul locations
# you can also use 0.01º (HIGH) resolution, but it generally results in more missing spatial matches

start_time <- Sys.time() # The data download takes a few minutes

yearly_fishing_hrs <- map_dfr(years, function(yr) {
  message(paste("Fetching AIS fishing hours for year:", yr))
  gfw_ais_fishing_hours(
    spatial_resolution = "LOW",               # LOW = 0.1°, HIGH = 0.01°
    temporal_resolution = "YEARLY",           # annual effort ; MONTHLY or DAILY can be used as well
    start_date = paste0(yr, "-01-01"),
    end_date = paste0(yr+1, "-01-01"),        # end date is excluded
    region_source = "RFMO",
    region = "GFCM",
    #group_by = "MMSI", 
    key = key
  )
})
sprintf("finished in %.2f minutes", round(as.numeric(difftime(Sys.time(),start_time, units = "mins")), 2))


yearly_fishing_hrs <-
  yearly_fishing_hrs %>% 
  filter(`Gear Type`=="TRAWLERS") %>%               # Keep only trawling fleet
  group_by(year = `Time Range`, Lat, Lon) %>%       # the lat and lon represent the center of the 0.1 grid cells
  summarize(fishing_hours = sum(`Apparent Fishing Hours`,na.rm=T),.groups = "drop")
head(yearly_fishing_hrs)

# Let's create a function that would get the GFW value (e.g., fishing_hours) corresponding to a point dataset using lat, lon, and time (could be date, month, year, etc). 
# By rounding the two datasets' lat-lon to the resolution of the data downloaded gridded datasets from GFW using gfw_ais_fishing_hours (or gfw_ais_presence), we can do a join against lat, lon, and time. 
# We can use this function to add apparent fishing hours to the MEDITS and/or the environmental datasets.
match_gfw_grid_data <- function(target_df, 
                           source_df, 
                           key_col = "date", 
                           value_col = "fishing_hours", 
                           target_coords = c("X", "Y"),    # the name of coordinates is different in each dataset
                           source_coords = c("Lon", "Lat"), 
                           res = 0.1) {  
  
  # Calculate rounding decimal places from resolution (e.g., 0.1 -> 1 decimal; 0.01 -> 2 decimal)
  digits <- -floor(log10(res))
  
  # 1. Prepare target dataset (env)
  target_prep <- target_df %>%
    mutate(
      .grid_lon = round(.data[[target_coords[1]]], digits),
      .grid_lat = round(.data[[target_coords[2]]], digits)
    )
  
  # 2. Filter and prepare source dataset (GFW)
  target_keys <- unique(target_df[[key_col]])
  
  source_prep <- source_df %>%
    filter(.data[[key_col]] %in% target_keys) %>%
    mutate(
      .grid_lon = round(.data[[source_coords[1]]], digits),
      .grid_lat = round(.data[[source_coords[2]]], digits)
    ) %>%
    select(all_of(c(key_col, ".grid_lon", ".grid_lat", value_col)))
  
  # 3. Direct vector join
  out_df <- target_prep %>%
    left_join(
      source_prep,
      by = c(key_col, ".grid_lon", ".grid_lat")
    ) %>%
    select(-.grid_lon, -.grid_lat) # Clean up temporary grid keys

  return(out_df)
}

# Apply the function to append fishing_hours to the MEDITS dataset
env_years <- sort(unique(env$YEAR))
env_with_fishing <-
  match_gfw_grid_data(target_df = env %>% rename(year = YEAR), 
                    source_df = yearly_fishing_hrs, 
                    key_col = "year", 
                    value_col = "fishing_hours", 
                    target_coords = c("X", "Y"), 
                    source_coords = c("Lon", "Lat"), 
                    res = 0.1)

summary(env_with_fishing ) 


# map fishing effort
var <- "fishing_hours"

env_with_fishing   %>%
  ggplot() +
  geom_polygon(data = world, aes(long, lat, group = group),
               fill = "grey85",colour = "grey60",linewidth = 0.2) +
  geom_point(aes(X, Y, colour = .data[[var]]),size = 0.5) +
  scale_colour_viridis_c(name = paste(var) ) +
  coord_fixed(1.3,xlim = c(-5, 35),ylim = c(34.7, 45.4)) +
  facet_wrap(~year) +
  theme_bw() 


##-----------------------------------------
## Merge all dataframes
##----------------------------------------

# We now combine biological, environmental and fishing pressure data into a single dataset ready to use

# select some environmental variables of interest and fishing_hours for further analyses
env_with_fishing  <- env_with_fishing  %>% select(ids, sst,botTemp,so,botso,chl,fishing_hours) 

      # Only these environmental variables are fully available for further analyses:
      # "sst","botTemp", "so", "botso", "chl", "nppv",
      # "Substrate", "MSFD_BBHT", "depth.mean", "depth.min" , "depth.max"
      # "fishing_hours"


# keep just useful columns from medits dataset
medits<-medits %>% select(-c(SHOOTING_LATITUDE, SHOOTING_LONGITUDE, HAULING_LATITUDE, HAULING_LONGITUDE, HAUL_DURATION, DISTANCE, WING_OPENING, GENUS, SPECIES))

# merge into a single dataframe
medits_env <- medits %>%
  left_join(env_with_fishing , by = c("id" = "ids"))

head(medits_env)

# save
write.csv(medits_env,"data/processed/MEDITS_and_environment.csv",row.names = FALSE)









## ------------------------------------------------------------------------ ##

#####################################################################
# Get AIS fishing hours for the environmental data at daily values
#####################################################################

# For this, we follow the same process as before but using daily instead of annual fishing effort. 
# If monthly or annual fishing hours is needed, the code can easily be modified by changing the temporal_resolution in gfw_ais_fishing_hours to "MONTHLY" or "YEARLY". For MONTHLY or YEARLY, the 

# create date field to env to use as matching key with the GFW fishing effort dataset
env <- env %>% mutate(date = as.Date(paste0(YEAR,"-",MONTH,"-",DAY)))

env_years <- sort(unique(env$YEAR))

# This finished in 20 mins
# I added timer to check how long it takes. This can be removed in the final version. 
start_time <- Sys.time()
daily_fishing_hrs <- map_dfr(years, function(yr) {
  res <- gfw_ais_fishing_hours(
    spatial_resolution = "HIGH",
    temporal_resolution = "YEARLY",
    start_date = paste0(yr, "-01-01"),
    end_date = paste0(yr + 1, "-01-01"), # this date is excluded
    region_source = "RFMO",
    region = "GFCM",
    key = key
  )
  return(res)
})
sprintf("finished in %.2f", round(as.numeric(difftime(Sys.time(),start_time, units = "mins")), 2), " mins.")

# aggregate fishing hours per day per lat-lon grid and filter only for TRAWLERS to match the MEDITS data
daily_fishing_hrs <-
  daily_fishing_hrs %>% 
  filter(`Gear Type`=="TRAWLERS") %>%
  group_by(date = `Time Range`, Lat, Lon) %>%
  summarize(fishing_hours = sum(`Apparent Fishing Hours`,na.rm=T),.groups = "drop") %>%
  filter(date %in% unique(env$date)) # filter only for dates that match the env dataset to reduce size

# Apply the function to append fishing_hours to the MEDITS dataset
start_time <- Sys.time()
env_with_fishing <-
  match_gfw_grid_data(target_df = env %>% rename(year = YEAR), 
                      source_df = yearly_fishing_hrs, 
                      key_col = "year", 
                      value_col = "fishing_hours", 
                      target_coords = c("X", "Y"), 
                      source_coords = c("Lon", "Lat"), 
                      res = 0.01)
sprintf("finished in %.2f", round(as.numeric(difftime(Sys.time(),start_time, units = "mins")), 2), " mins.")


