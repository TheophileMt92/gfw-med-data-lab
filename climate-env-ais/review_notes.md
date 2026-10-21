# climate-env-ais: review notes

Prepared by Théophile Mouton for the climate-env-ais working group, Global Fishing Watch Mediterranean Data Lab.
**Last updated: 21 Oct 2026, 12:47 (Rome time).**

**Live report: [Climate, environment and AIS fishing effort in GSA 6](https://theophilemt92.github.io/gfw-med-data-lab/climate-env-ais/Quarto_report_CLIMATE-ENV-AIS.html)**

A downloadable copy (`Quarto_report_CLIMATE-ENV-AIS.html`) and its Quarto source (`Quarto_report_CLIMATE-ENV-AIS.qmd`) are in this Drive folder and on [GitHub](https://github.com/TheophileMt92/gfw-med-data-lab/tree/main/climate-env-ais). Click any figure in the report to view it full screen.

## What the pipeline does

All steps focus on **GSA 6 (northern Spain)** and **trawlers**.

1. **Data exploration** (`scripts/1_data exploration.R`): MEDITS trawl survey (2012-2021) plus Copernicus environmental variables at each haul. Yearly 0.1° trawler fishing hours are pulled with `gfwr` and joined to the hauls. Output: `data/processed/MEDITS_and_environment.csv`.
2. **SDM, total fish abundance** (`scripts/2_SDMs.R`, report Section 2a): GAM of log total fish abundance (N/km²) against bottom temperature, salinity, chlorophyll and fishing hours. Predicts July abundance on the hindcast grid for every year, then maps the 2012 to 2021 change (back-transformed to N/km² in the report).
3. **SDM, red mullet** (new, report Section 2b): the group's focal species, *Mullus barbatus* (`MULLBAR`). See below.
4. **Marine heatwaves (MHW)** (`scripts/3_MHW.R`): `heatwaveR` detection on daily SST (Hobday et al. 2016), summer events only. Compares summer trawler effort between MHW years (2017, 2018, 2020) and non-MHW years (2013, 2014, 2016), using daily 0.01° `gfwr` data clipped to GSA 6.
5. **Climate-Fisheries Vulnerability Index (CFVI)** (`scripts/4_Vulnerability Index.R`): mean of three min-max scaled scores: MHW exposure, habitat loss (total fish) and fishing pressure. Hotspots off Cap de Creus/Roses and along the Ebro and Valencia coast.

No Adriatic (GSA 17-18) code or outputs are in the working folder yet.

## Red mullet model (report Section 2b)

Built in the report from the group's merged dataset, following the Section 2a workflow with these changes:

- **Absences added back**: red mullet was caught in 634 of 959 GSA 6 hauls (66%). The other 325 hauls are set to zero rather than dropped.
- **Tweedie GAM** (log link) on N/km², which handles zeros and predicts density directly, so no back-transformation is needed.
- **Depth added**: deviance explained rises from 20% to 51% and AIC drops by about 511. Density is high down to about 200 m, then falls steeply. Density increases with bottom temperature and decreases with chlorophyll; salinity adds little (p ≈ 0.07). All VIFs < 2.
- **Unmatched AIS effort set to zero** in both fitting and prediction.
- **Predictions for June** (main MEDITS month in GSA 6), restricted to depths within the sampled range.
- **Habitat change 2015-2021** (after the AIS ramp-up), also with fishing effort held at each cell's 2015-2021 mean.

Results: the median cell declines by about 12% from 2015 to 2021, with or without effort held constant. With effort held constant, 92% of the 416 cells decline (range -77% to +16%). The full model gives the same median but outliers up to +767%, driven by changes in recorded effort.

Points to discuss:

- **Fishing-hours smooth**: strong but non-monotonic, highest at zero effort. Likely confounding (trawlers target red mullet grounds; zero effort mixes untrawled cells with early hauls lacking AIS). Best treated as a nuisance covariate.
- **Driver of the decline not yet identified**: mean bottom temperature on the grid is similar in 2015 and 2021. Next: partial predictions one covariate at a time, a check against the observed MEDITS trend, and a 2015-2021 trend instead of two single years.
- **Vulnerability index**: still uses total fish habitat change. Next step: feed in the red mullet change instead.

New outputs written by the report: `outputs/MULLBAR_gam_prediction_GSA6.csv`, `outputs/MULLBAR_change_GSA6.csv`. None of the group's existing outputs were modified.

## Issues in the existing pipeline

### 1. The AIS ramp-up drives the trends (most important)

At MEDITS hauls, the share with matched AIS trawler effort rises from **49% in 2012 to 98% in 2021**, and mean effort at matched hauls from **64 hours in 2012 to 835 in 2015**, then stabilises. This reflects AIS adoption by the fleet, not more fishing. It affects:

- **SDM**: `fishing_hours` is a covariate, so part of the 2012 to 2021 "habitat change" is the covariate jumping.
- **MHW comparison**: the non-MHW years (2013, 2014) are low-AIS years, so higher effort in MHW years is almost guaranteed (56% of cells show more effort in MHW summers).
- **Possible fixes**: drop 2012-2014, use effort per vessel, or pick contrasting years from 2015 onward. GSA 6 mean cumulative MHW intensity was 0 in 2016 and 46.6 in 2017 (highest), with 19.0 in 2015 and 8.3 in 2019.

### 2. Total fish SDM: back-transformation (fixed in the report) and July extrapolation

- **Fixed:** the group's change maps and `perc.change` were computed on log(N/km²). The report now back-transforms predictions (N/km² = exp(fit)) before mapping and computing change, and the vulnerability index uses the corrected change. The corrected table is `outputs/fish.change6_abundance.csv`; the group's `fish.change6.csv` is left untouched.
- **Still open:** the model is fitted on May-June hauls (all deeper than 35 m, bottom temperature ≤ 17.2 °C) but predicts July over the whole grid. Shallow coastal cells reach 26.9 °C in July, and the rising bottom-temperature smooth then gives implausible abundances (up to ~10^11 per km²). About 11% of grid-year predictions are outside the sampled bottom-temperature range; the report greys them out and excludes them from the change summary. Predicting for June and within the sampled depth range would avoid this.

### 3. Model details for the total fish SDM

- gam1 and gam2 are identical: with `select = TRUE` the SST smooth is already shrunk to zero.
- Fishing hours is in the lowest-AICc model but only marginally significant (p ≈ 0.06). Deviance explained about 21%.
- Collinearity is milder than the script comments suggest: `botso` has VIF 3.1, correlated mainly with depth (r = 0.79) and bottom temperature (r = -0.63).

### 4. Zeros handled differently in fitting and prediction

- Fitting: hauls with no matched effort have `fishing_hours = NA` and are dropped by `na.omit`, so the model only sees fished cells.
- Prediction: NA effort on the grid is set to 0, outside the fitted range.
- Script 3: cells not fished in a given year are missing rather than 0, inflating per-cell means; `drop_na(mhw, no_mhw)` keeps only cells fished in both periods.

### 5. The CFVI mixes time windows

- Exposure uses 2021 only, a weak MHW year: 71% of cells score exactly 0.
- Sensitivity uses the 2012 to 2021 change.
- Pressure uses raw 2021 hours, very skewed (median 553, max 7,097), so min-max scaling squashes most cells (median pressure score 0.08).
- More defensible: mean exposure over 2015-2021, log-transformed effort, habitat change from within the sampled range only, and a sensitivity analysis on the weights.

### 6. Smaller points

- **SST input**: Script 3 needs `data/raw/sst_MED_daily_2010_2021.nc`, not in the shared folder (2.2 GB).
- **Short MHW baseline**: climatology 2010-2021 vs the 30-year standard in Hobday et al. A short, recent, warming baseline under-detects events.
- **Grid join in Script 1**: GFW Lat/Lon are the lower-left corner of each cell, but the join rounds haul coordinates to the nearest 0.1°, so about half the hauls get the neighbouring cell. Use `floor(x * 10) / 10` on the haul side.
- **Unweighted means**: depth and distance to coast are averaged over grid rows, not weighted by fishing hours.
- **Vessel count**: `n_distinct(MMSI)` assumes an MMSI column. The default `gfwr` grouping may not return one (`group_by = "MMSI"` is commented out in Script 1).
- **Unfinished daily block in Script 1**: requests `"YEARLY"` data, never uses `daily_fishing_hrs`, and joins yearly data at 0.01°.
- **Hindcast grid effort**: the origin and resolution of `fishing_hours` in `MED.env_grid_hindcast_2012_2021.csv` is not documented. Worth confirming it matches the haul-level variable.
- **Hindcast grid depth** is stored as negative values; haul depth is positive.
