# GFW Mediterranean Data Lab: pre-workshop analyses

**Report:** [`index.html`](index.html), *Mediterranean fishing seen from space*. A first look at AIS fishing effort and Sentinel-1 SAR vessel detections across the Mediterranean, 2017-2024. Built with the DataSphere ocean Quarto template (`template/`).

All Global Fishing Watch data are pulled with the [`gfwr`](https://globalfishingwatch.github.io/gfwr/) R package (v3 API).

## Reproduce

Run from the repo root:

| Step | File | What it does |
|---|---|---|
| 0 | `R/00_install.R` | Installs gfwr + packages, checks the GFW API token |
| 1 | `R/01_download_gfw.R` | AIS fishing hours (by gear) + SAR detections (matched / unmatched), 0.1°, monthly, whole Med, 2017-2024. Cached per year and half-basin |
| 2 | `R/02_first_look.R` | Quick figures (`figures/`) and summary tables (`outputs/`) |
| 3 | `index.qmd` | The report: `quarto render index.qmd` |

The API token goes in a git-ignored `.Renviron` at the repo root (`GFW_TOKEN="..."`). Raw and processed data (`data/`) are git-ignored, so re-run step 1 to rebuild them.

## Next

- Topic 1: environmental and climate covariates (Copernicus Marine) to model fishing effort and the SAR-AIS gap.
- Topic 2: MPA placement, designation date, protection level and inside/outside effort.
