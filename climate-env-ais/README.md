# climate-env-ais

Working group of the **Global Fishing Watch Mediterranean Data Lab** (20-21 October 2026): how climate and environmental conditions relate to the distribution of demersal fish and to the behaviour of the trawl fleet, as seen through AIS.

## Outputs

| Output | Link |
|---|---|
| Full report (code, tables, diagnostics) | [Quarto_report_CLIMATE-ENV-AIS.html](https://theophilemt92.github.io/gfw-med-data-lab/climate-env-ais/Quarto_report_CLIMATE-ENV-AIS.html) |
| Slides, whole analysis | [Quarto_slides_CLIMATE-ENV-AIS.html](https://theophilemt92.github.io/gfw-med-data-lab/climate-env-ais/Quarto_slides_CLIMATE-ENV-AIS.html) |
| Slides, Section 2c only (red mullet spatio-temporal model, GSA 6 and Adriatic) | [Quarto_slides_2C_red_mullet.html](https://theophilemt92.github.io/gfw-med-data-lab/climate-env-ais/Quarto_slides_2C_red_mullet.html) |

The pages are served by GitHub Pages from the `main` branch. In the slides, press `F` for full screen, `O` for an overview and `Esc` to exit.

## What the analysis covers

| Step | Question |
|---|---|
| 1. Data preparation | MEDITS trawl survey (2012-2021), Copernicus environmental variables at each haul, and GFW AIS trawler fishing hours pulled with `gfwr` |
| 2a. Total fish SDM | How does total fish abundance relate to the environment in GSA 6, and how has it changed? |
| 2b. Red mullet SDM | The same for red mullet (*Mullus barbatus*), with a Tweedie GAM |
| 2c. Red mullet, spatio-temporal model | Biomass, biomass index, habitat suitability (0-1) and overlap with trawling in GSA 6 and the Adriatic (GSAs 17-18), 2014-2021, from the group's sdmTMB predictions |
| 3. Marine heatwaves | Where and when do summer marine heatwaves occur, and does trawling differ in heatwave summers? |
| 4. Vulnerability index | Which areas combine heatwave exposure, habitat loss and fishing pressure? |

## How the files fit together

- `Quarto_report_CLIMATE-ENV-AIS.qmd`: the report. Its last chunk copies its figures to `figures/` and writes key numbers to `outputs/report_numbers.rds`.
- `Quarto_slides_CLIMATE-ENV-AIS.qmd` and `Quarto_slides_2C_red_mullet.qmd`: the two slide decks. They take every figure and number from the report, so a change in the report flows into the slides.
- `R/haul_map.R`: the interactive haul map, shared by the report and the main deck.
- `scripts/`: the group's original scripts (steps 1 to 4).
- `template/`: styling for the report and the slides.
- `outputs/`, `figures/`: saved outputs and figures.
- `review_notes.md`: review notes on the pipeline and the points to discuss.

## Rendering

Render either deck, for example:

```bash
quarto render Quarto_slides_CLIMATE-ENV-AIS.qmd
```

If the report (or `R/`) has changed since it was last rendered, the deck re-renders the report first, so one command updates both. The report can also be rendered on its own.

## Data

`data/` is not tracked in the repository (raw data and large files). It holds the MEDITS, Copernicus and GFW extracts used in steps 1 to 4, and `data/group/` holds the files shared by the group for Section 2c (haul tables, effort and prediction grids, and the group's figures). Steps that call the GFW API or need the 2.2 GB daily SST file are shown in the report but not re-run; their saved outputs are loaded instead.

Sources: MEDITS (JRC data portal), Copernicus Marine Mediterranean reanalyses, Global Fishing Watch AIS apparent fishing effort via [`gfwr`](https://github.com/GlobalFishingWatch/gfwr).
