# my-pre-work: preliminary analyses (not used at the Data Lab)

Exploratory analyses prepared before the **Global Fishing Watch Mediterranean Data Lab** (20-21 October 2026). They were meant to support two possible topics:

1. Predicting fishing effort from AIS and SAR data with environmental and climate covariates.
2. Fishing in relation to marine protected area placement and establishment date.

**Status: not used at the workshop.** At the Lab I joined the `climate-env-ais` working group, which focused on red mullet (*Mullus barbatus*) in GSA 6 and the Adriatic. That work is in [`../climate-env-ais/`](../climate-env-ais/). This folder is kept as a record and as a starting point for later work.

## Report

| Output | Link |
|---|---|
| *Mediterranean fishing seen from space*: AIS fishing effort and Sentinel-1 SAR vessel detections, 2017-2024 | [index.html](https://theophilemt92.github.io/gfw-med-data-lab/my-pre-work/index.html) |

Served by GitHub Pages from the `main` branch. Click any figure to view it full size.

## What the report covers

| Section | Content |
|---|---|
| Study area | FAO Major Fishing Area 37, subareas 37.1-37.3 (Black Sea excluded), 0.1° cells, monthly, 2017-2024 |
| AIS fishing effort | Where AIS-tracked fishing happens, seasonality and gear (`gfw_ais_fishing_hours()`) |
| SAR detections | Share of radar detections not matched to AIS (`gfw_sar_vessel_detections()`) |
| Revisit correction | SAR detections divided by Sentinel-1 overpasses per cell and month (vessels per look) |
| FAO divisions | AIS effort, SAR vessels per look and unmatched share by FAO division |
| AIS vs SAR | How well AIS effort tracks radar-detected vessels, cell by cell |

## Main results

- AIS-broadcasting vessels logged about **3.9 million apparent fishing hours per year**, roughly flat over 2017-2024. Trawlers account for **80%** of these hours.
- **66%** of SAR detections in 2017 matched no AIS track. Unmatched detections concentrate along the coasts of Tunisia, Libya and Egypt, the Levant and the eastern Aegean.
- Raw SAR detections halved after 2021 because Sentinel-1B failed (overpasses per cell went from about 15 to 7 a month). Normalised by overpasses, the radar sees about **2,000 vessels per complete look of the basin**, nearly unchanged before and after.
- The split between AIS-matched and unmatched detections jumps in 2022, exactly when coverage changed. This looks like a processing artefact rather than a real change, so trends in "dark" activity should be estimated within each coverage period.
- The Adriatic has by far the highest AIS fishing intensity per cell. The Levant has the least AIS fishing but radar vessel density comparable to the western basin and the highest unmatched share, so AIS maps most likely understate fishing there.
- Per cell, AIS effort and SAR vessels per look are only weakly related (Spearman ρ = 0.35).

The MPA topic (topic 2) was not started.

## Files

| File | What it does |
|---|---|
| `R/00_install.R` | Installs `gfwr` and the other packages, checks the GFW API token |
| `R/01_download_gfw.R` | AIS fishing hours by gear and SAR detections (matched / unmatched) via `gfwr`, 0.1°, monthly, 2017-2024. Cached per year and half-basin |
| `R/02_first_look.R` | Quick figures (`figures/`) and summary tables (`outputs/`) |
| `R/03_s1_overpasses.R` | Sentinel-1 overpasses per cell and month from the Copernicus Data Space catalogue (no login). About 40 min, cached per month |
| `index.qmd` | The report (`quarto render index.qmd`, about a minute; no API calls) |
| `data_ref/fao_area37_med.geojson` | FAO Area 37.1-37.3 subareas and divisions, extracted from the FAO Major Fishing Areas layer |
| `template/` | DataSphere ocean Quarto template |

## Reproducing

Run everything from inside `my-pre-work/`. `data/` is not tracked, so steps 1 and 3 must be re-run to rebuild it. The GFW token is read from a `.Renviron` file in the working directory (`GFW_TOKEN="..."`). The repository's `.Renviron` sits at the repo root, so copy it into `my-pre-work/` (it is git-ignored) or call `readRenviron("../.Renviron")` first.

Sources: Global Fishing Watch AIS apparent fishing effort and SAR vessel detections via [`gfwr`](https://github.com/GlobalFishingWatch/gfwr); Sentinel-1 scene footprints from the [Copernicus Data Space Ecosystem](https://dataspace.copernicus.eu/); FAO Major Fishing Areas (FAO Fisheries and Aquaculture).
