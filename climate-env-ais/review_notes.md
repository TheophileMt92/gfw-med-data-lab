# climate-env-ais: review notes

Quick review of the group's four scripts (`scripts/1_data exploration.R` to `scripts/4_Vulnerability Index.R`) and their outputs, 20 Oct 2026.

## What the pipeline does

All four steps focus on **GSA 6 (northern Spain)** and **trawlers**.

1. **Data exploration**: MEDITS trawl survey (2012-2021) plus Copernicus environmental variables at each haul. Yearly 0.1° trawler fishing hours are pulled with `gfwr` and joined to the hauls. Output: `data/processed/MEDITS_and_environment.csv`.
2. **Species distribution model (SDM)**: GAM of log total fish abundance (N/km²) against bottom temperature, salinity, chlorophyll and fishing hours. Predicts July abundance on the hindcast grid for every year, then maps the 2012 to 2021 change.
3. **Marine heatwaves (MHW)**: `heatwaveR` detection on daily SST (Hobday et al. 2016), summer events only. Compares summer trawler effort, depth, distance to coast and vessel count between MHW years (2017, 2018, 2020) and non-MHW years (2013, 2014, 2016), using daily 0.01° `gfwr` data clipped to GSA 6.
4. **Climate-Fisheries Vulnerability Index (CFVI)**: mean of three min-max scaled scores: MHW exposure, habitat loss and fishing pressure. Hotspots off Cap de Creus/Roses and along the Ebro and Valencia coast.

## Issues to raise

### 1. The AIS ramp-up drives the trends (most important)

Mean trawler fishing hours per grid cell (`outputs/Final_gam_prediction.csv`): **13 in 2012, 364 in 2013, 713 in 2014, about 900 from 2015 onward**. That jump reflects AIS adoption by the fleet, not more fishing. It affects three steps:

- **SDM**: `fishing_hours` is a covariate, so part of the 2012 to 2021 "habitat change" is the covariate jumping.
- **MHW comparison**: the non-MHW years (2013, 2014) are the low-AIS years, so higher effort in MHW years is almost guaranteed.
- **Possible fixes**: drop 2012-2014, use effort per vessel, or pick contrasting years from 2015 onward. GSA 6 mean cumulative MHW intensity was 0 in 2016 and 46.6 in 2017 (highest), with 19.0 in 2015 and 8.3 in 2019.

### 2. SDM predictions are on the log scale but treated as abundance

- `fit` is log(N/km²) (gaussian GAM on `log_N_km2`, `type = "response"`). The 2012 and 2021 maps then apply `log10(fit + 1)`: a log of a log.
- `perc.change` is a percent change of a log value. It is close to meaningless and compressed to about ±20%, and it feeds the CFVI sensitivity score.
- Fix: back-transform with `exp()` (ideally with a smearing or `exp(sigma^2/2)` bias correction) before computing change.

### 3. Zeros handled differently in fitting and prediction

- Fitting: hauls with no matched effort have `fishing_hours = NA` and are dropped by `na.omit`, so the model only sees fished cells.
- Prediction: NA effort on the grid is set to 0, i.e. outside the fitted range.
- Script 3: cells not fished in a given year are missing rather than 0. This inflates per-cell means, and `drop_na(mhw, no_mhw)` keeps only cells fished in both periods.

### 4. The CFVI mixes time windows

- Exposure uses 2021 only, a weak MHW year: 71% of cells score exactly 0.
- Sensitivity uses the 2012 to 2021 change.
- Pressure uses raw 2021 hours, very skewed (median 553, max 7,097), so min-max scaling squashes most cells (median pressure score 0.08).
- More defensible: mean exposure over 2015-2021, log-transformed effort, and a sensitivity analysis on the weights.

### 5. Smaller points

- **Missing input**: Script 3 needs `data/raw/sst_MED_daily_2010_2021.nc`, not in the shared folder.
- **Short MHW baseline**: climatology 2010-2021 vs the 30-year standard in Hobday et al. A short, recent, warming baseline under-detects events.
- **Grid join in Script 1**: GFW Lat/Lon are the lower-left corner of each cell (as in my pre-work), but the join rounds haul coordinates to the nearest 0.1°. About half the hauls get the neighbouring cell. Use `floor(x * 10) / 10` on the haul side.
- **Unweighted means**: depth and distance to coast are averaged over grid rows, not weighted by fishing hours.
- **Vessel count**: `n_distinct(MMSI)` assumes an MMSI column. The default `gfwr` grouping may not return one (`group_by = "MMSI"` is commented out in Script 1).
- **Unfinished daily block in Script 1**: requests `"YEARLY"` data, never uses `daily_fishing_hrs`, and joins yearly data at 0.01°.
- **Hindcast grid effort**: the origin and resolution of `fishing_hours` in `MED.env_grid_hindcast_2012_2021.csv` is not documented in the scripts. Worth confirming it matches the haul-level variable.
