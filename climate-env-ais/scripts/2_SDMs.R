

# ==============================================================================
# GLOBAL FISHING WATCH LABORATORY
# EXERCISE 2 - SPECIES DISTRIBUTION MODELLING
# ======================================================================

rm(list = ls())

library(dplyr)
library(corrplot)
library(tidyr)
library(ggplot2)
library(usdm)
library(mgcv)
library(MuMIn)
library(patchwork)


# load final dataset with medits, environmental and fishing pressure data
med<-read.csv("data/processed/MEDITS_and_environment.csv",sep=',')
head(med)

# Details on MEDITS surveys: https://scientiamarina.revistas.csic.es/index.php/scientiamarina/article/download/1829/2597/0


# In this exercise we will build a Species Distribution Model (SDM).
# SDMs relate biological observations to environmental conditions in order to estimate habitat suitability
# and predict species distributions in  unsampled locations.

# The same workflow can be applied to a single species, a species group,
# biodiversity indicators or even fishing-related variables.


# Select your response variable of interest 
#----------------------------------------------------------------------------------------------

# Here, we´ll use total abundance of fish (N/km²) as the response variable
# so, we aggregate all fish species recorded in each haul

spp.list<-read.csv("data/raw/MEDITS_listTM.csv",sep=';') # this is Medits codes list and faunistic categories
  
fish<- med %>%
  left_join(spp.list %>%
            select(MEDITS.Code, CATFAU),
            by = c("MEDITS_CODE" = "MEDITS.Code")) %>%
  filter(CATFAU %in% c("A", "Aa", "Ae", "Ao")) %>%           # A categories correspond to fish
  group_by(id) %>%
  summarise(across( -c(MEDITS_CODE, CATFAU, N_h, N_km2, kg_h, kg_km2),  first),
            N_km2 = sum(N_km2, na.rm = TRUE), .groups = "drop")%>%
  as.data.frame()

head(fish)


# We focus on a single GSA because environmental conditions and species-habitat
# relationships are more homogeneous at smaller scales. 
# Particularly in highly heterogeneous systems such as the Mediterranean Sea.
# This generally improves model performance and ecological interpretation.

fish6<-fish%>%filter(GSA==6) # we use GSA 6
range(fish6$N_km2)     # range of abundance values


# Abundance and biomass data are often highly skewed.
# Log-transformations are commonly used to reduce the influence of extreme values
# and improve model performance.
hist(log(fish6$N_km2)) 
fish6$log_N_km2<-log(fish6$N_km2)


##----------------------------------
# Check collinearity among variables
#------------------------------------

# we´ll use a model to relate environment and biological data, but we cannot incorporate all possible environmental variables
# 1) we aim to retain just informative ones to simplify the model
# Correlated predictors may contain redundant information and can complicate the interpretation of model responses.
# 2) if we included correlated variables the model estimates are unreliable
# so we need to make an a priori selection of uncorrelated variables

# start with all variables
vars <- fish6 %>% select(sst, botTemp, so, botso, chl, MEAN_DEPTH,fishing_hours)

# check correlation matrix
cor.mat <- cor(vars, use = "pairwise.complete.obs")
cor.mat

# As a general rule, pairs of variables with |r| > 0.6 should be examined carefully
# and one of them may need to be removed.

ggplot(as.data.frame(as.table(cor.mat)),
       aes(Var1, Var2)) +
  geom_point(aes(size = abs(Freq), fill = Freq),
             shape = 21, colour = "grey30") +
  geom_text(aes(label = round(Freq, 2)), size = 4) +
  scale_size(range = c(2, 15), guide = "none") +
  scale_fill_gradient2(
    low = "red",
    mid = "white",
    high = "darkblue",
    midpoint = 0,
    limits = c(-1, 1)
  ) +
  coord_fixed() +
  theme_bw() +
  theme(
    axis.title = element_blank(),
    axis.text.x = element_text(angle = 45,
                               hjust = 0)
  )

# double check correlations with Variance Inflation Factors
# Ideally all variables should have VIF < 3.
# Higher values may indicate problematic collinearity.
vif(vars)
vifstep(vars, th = 3)

# Bottom salinity (botso) shows high collinearity with bottom temperature and should be removed before fitting the final model.
# Mean depth also shows moderate to high collinearity and should be evaluated carefully before inclusion.


##--------------------
## SDM using GAMs
##--------------------

# We use Generalized Additive models to describe relationships between environmental conditions and species abundance
# and predict habitat suitability across space (same process can be done with any other kind of model)

# GAMs allow flexible, non-linear relationships between abundance and
# environmental predictors, making them particularly well suited for
# ecological applications.

summary(fish6)         
fish6 <- na.omit(fish6) # GAMs cannot use NAs, so we remove rows with NAs in any variable


# backwards model selection
#--------------------------
# Fit a full GAM and evaluate the contribution of each explanatory variable.
# Variables with low explanatory power can be removed to obtain a simpler model.

gam1<- gam(log_N_km2~ s(sst, k=4)+s(botTemp, k=4)+s(so, k=4)+s(chl, k=4)+s(fishing_hours, k=4), 
           family=gaussian,  data=fish6, method = "REML",select = TRUE)
summary(gam1)
AIC(gam1)
plot(gam1, pages = 1)

      # Examine model outputs:
      # - Significant smooth terms indicate influential predictors.
      # - Estimated smooth shapes.
      # - R² and deviance explained provide an indication of model performance.
      # - AIC to compare with different model configurations.

gam2<- gam(log_N_km2~ s(botTemp, k=4)+s(so, k=4)+s(chl, k=4)+s(fishing_hours, k=4),  
           family=gaussian,  data=fish6, method = "REML",select = TRUE)
summary(gam2)
AIC(gam2)
plot(gam2, residuals = TRUE,
     pch = 16,cex = 0.2, pages = 1)

# Automatic model selection can help identify parsimonious models,
# but ecological reasoning should always take precedence over purely statistical selection criteria.
# The model with the lowest AIC is not always the most biologically meaningful.
options(na.action = "na.fail")
all.models<- dredge(gam1, rank=AICc)
print(all.models)


# In this example, bottom temperature, salinity, chlorophyll
# provide the best balance between explanatory power and model simplicity.
# Although, fishing hours can be also meaningful - let´s keep it in this example

# NOTE: any final selected model requires MODEL VALIDATION in terms of
# residuals, outliers, spatial and temporal autocorrelation, predictive performances
# These steps are omitted here to keep the exercise concise, but some basic examples are provided below.



# Generate model prediction over space
#------------------------------------------------

# Now we use the fitted model to predict the abundance distribution of fish in the GSA6,
# including unsampled locations

# load the prediction grid and crop it to the area used (in this case GSA6)
new.env<-read.csv("data/raw/MED.env_grid_hindcast_2012_2021.csv",sep=',')
summary(new.env)

# Remove grid cells lacking environmental information.
# These cells usually correspond to coastal, land or boundary locations where environmental predictors are unavailable.
new.env <- new.env %>% drop_na(GSA, sst, botTemp,so,botso,chl)

# Missing trawling effort values can be interpreted as no detected trawling activity
# (but alternatively, they can be excluded from the analysis)
new.env$fishing_hours <- replace_na(new.env$fishing_hours, 0)

# Now, we select the area and month used to predict
new.env6<-new.env %>% filter (GSA==6,     # select GSA
                              MONTH == 7) # select only one month for predictions


# predict
gam.pred<- predict.gam(gam2, new.env6, se.fit=TRUE, type="response")

# built a new dataframe with predictions, errors and confidence intervals
fish.pred6 <- new.env6 %>%
  mutate(fit = gam.pred$fit,
         se.fit = gam.pred$se.fit,
         lwr = fit - 1.96 * se.fit,
         upr = fit + 1.96 * se.fit)

head(fish.pred6)
write.table(fish.pred6,'outputs/Final_gam_prediction.csv',sep=';',row.names=F)


# plot anual maps of predicted distribution: habitat suitability
#---------------------------------------------------------------

# Predicted abundance maps can be interpreted as habitat suitability
# assuming that suitable habitats support higher abundances.
# Areas with higher predicted values correspond to more suitable conditions
# according to the fitted model.

world <- map_data("world")

fish.pred6 %>%
  ggplot() +
  geom_polygon(data = world,aes(long, lat, group = group),
               fill = "grey85",colour = "grey60",linewidth = 0.2) +
  geom_point(aes(grid.X,grid.Y, colour = fit) , size = 0.5) +
  scale_colour_gradientn(
    colours = c("lightyellow",
                "gold",
                "orange",
                "red",
                "darkred"),
    name = "log(predicted N/km²)"
  ) +
  coord_fixed(1.3,xlim = c(-1.0, 3.8),ylim = c(37.5, 42.5))+
  facet_wrap(~year) +
  theme_bw()


# Changes in habitat suitability
#---------------------------------- 

# Compare predictions between the first and last year
# to identify potential distributional changes through time.

first.year <- 2012
last.year  <- 2021

fish.change6 <- fish.pred6 %>%
  filter(year %in% c(first.year, last.year)) %>%
  select(grid.id, grid.X, grid.Y, year, fit) %>%
  tidyr::pivot_wider(
    names_from = year,
    values_from = fit,
    names_prefix = "fit_")%>%
  mutate( difference = .[[paste0("fit_", last.year)]] -  .[[paste0("fit_", first.year)]] )%>%
  mutate(perc.change = 100 * (.[[paste0("fit_", last.year)]] -  .[[paste0("fit_", first.year)]]) / .[[paste0("fit_", first.year)]])%>%
  as.data.frame()

head(fish.change6)
write.csv(fish.change6,"outputs/fish.change6.csv",row.names = FALSE)



theme_map <- theme_bw() +
  theme(
    axis.title = element_blank(),
    axis.text = element_blank(),
    axis.ticks = element_blank(),
    legend.position = "bottom"
  )


p1 <- ggplot() +
  geom_polygon(data = world,aes(long, lat, group = group),
               fill = "grey85",colour = "grey60",linewidth = 0.2) +
  geom_point(data = fish.change6,aes(grid.X, grid.Y,
             colour = log10(.data[[paste0("fit_", first.year)]] + 1)),size = 0.5) +
  scale_colour_gradientn(colours = c("lightyellow","gold","orange","red","darkred"),
                        name = paste0("log(N/km²)")) +
  labs(title = first.year) +
  coord_fixed(1.3,xlim = c(-1,4),ylim = c(37.5,42.5)) +
  theme_map

p2 <- ggplot() +
  geom_polygon(data = world,aes(long, lat, group = group),
               fill = "grey85",colour = "grey60",linewidth = 0.2) +
  geom_point(data = fish.change6,aes(grid.X, grid.Y,
             colour = log10(.data[[paste0("fit_", last.year)]] + 1)),size = 0.5) +
  scale_colour_gradientn(colours = c("lightyellow","gold","orange","red","darkred"),
                        name = paste0("log(N/km²)")) +
  labs(title = last.year) +
  coord_fixed(1.3,xlim = c(-1,4),ylim = c(37.5,42.5)) +
  theme_map

p3 <- ggplot() +
  geom_polygon(data = world,aes(long, lat, group = group),
               fill = "grey85",colour = "grey60",linewidth = 0.2) +
  geom_point(data = fish.change6,aes(grid.X, grid.Y,colour = difference),size = 0.5) +
  scale_colour_gradient2(
    low = "blue",
    mid = "white",
    high = "red",
    midpoint = 0,
    name = "Δ abundance" ) +
  labs(title = paste0(last.year, " - ", first.year)) +
  coord_fixed(1.3,xlim = c(-1,4),ylim = c(37.5,42.5)) +
  theme_map

p4 <- ggplot() +
  geom_polygon(data = world,aes(long, lat, group = group),
               fill = "grey85", colour = "grey60",linewidth = 0.2) +
  geom_point(data = fish.change6,aes(grid.X, grid.Y,colour = perc.change),size = 0.5) +
  scale_colour_gradient2(
    low = "blue",
    mid = "white",
    high = "red",
    midpoint = 0,
    name = "% change" ) +
  labs(title = "% change") +
  coord_fixed(1.3,  xlim = c(-1,4),ylim = c(37.5,42.5)) +
  theme_map


dev.new()
final_plot <- (p1 + p2) / (p3 + p4)
final_plot

ggsave(filename = "outputs/Habitat_suitability_change.png",
       plot = final_plot, width = 12, height = 10,dpi = 300)








##----------------------------------
# MODEL VALIDATION
#------------------------------------

# A complete SDM validation would evaluate:

# - residual distributions
# - influential observations and outliers
# - spatial autocorrelation
# - cross-validation
# - predictive performance metrics
#

gam.check(gam2)

# Basic residual diagnostics

fish6$pred <- predict(gam2)
fish6$res <- residuals(gam2)

ggplot(fish6,
       aes(pred, res)) +
  geom_point(alpha = 0.5) +
  geom_hline(yintercept = 0,
             linetype = 2,
             colour = "red") +
  theme_bw() +
  labs(
    x = "Predicted abundance",
    y = "Residuals"
  )