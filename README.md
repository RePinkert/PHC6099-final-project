# lifewatt: AI facility community-health explorer

A draft MVP for the PHC 6099 project. It connects a query location to nearby
census tracts, displays a documented health snapshot, compares tract-rate
distributions, and exports the selected rows. The bundled Gainesville example
uses a public UF HiPerGator AI site address and real official community data.

## Install and run

Install the draft branch from GitHub (internet access is needed for installation):

```r
install.packages("remotes")  # Once, if not already installed
remotes::install_github("RePinkert/PHC6099-final-project",
                        ref = "mvp-community-health", build_vignettes = FALSE)
library(lifewatt)

facility <- example_facility()
nearby <- nearby_communities(facility$longitude, facility$latitude, radius_km = 10)
plot_communities(nearby)
plot_communities(nearby, view = "distance")
compare_communities(nearby)
export_communities(nearby, "nearby_communities.csv")
county_context()  # Separate county-level background, not a tract outcome
```

Alternatively, install a downloaded source folder with
`install.packages("path/to/PHC6099-final-project", repos = NULL, type = "source")`,
or install the separately supplied source tarball. Open `START_HERE.md` for
Chinese instructions. Download `demo/MVP_demo.html` and open it in a browser
to view the self-contained demonstration; GitHub displays its source by default.

The installed package uses only base/recommended R packages. Its included
data work offline; no account, API key, network connection, `sf`, or Shiny
installation is needed to run this example. Development checks and the
vignette use the packages listed in `Suggests`.

## Included data

- **58 Alachua County census tracts:** 2020 Census boundaries, GEOIDs,
  internal-point coordinates and 2020 population, from Census TIGERweb.
- **Health:** Florida Department of Health all-cause death rates per 100,000
  and death counts, 2020-2024. All 58 rows match Census GEOIDs. Two tracts have
  fewer than five deaths; their values remain in the raw data and exports,
  but they are grey on the map and excluded from default comparison summaries.
- **Facility:** UF documents the HiPerGator AI system in 2021. The query point
  is the Census geocoder's interpolation of the publicly documented East
  Campus Data Center address, not a surveyed footprint or emissions source.
- **County background:** Alachua life expectancy, 2022-2024, is 78.9 years
  (reported 95% CI 78.5-79.2). This is stored separately from tract outcomes.

See `inst/extdata/SOURCES.md` for provenance, periods, definitions and limits.
The immutable raw inputs and a rebuild script are in `data-raw/`.

## Interpretation

1. Distance is measured to the tract's **internal point**, not to all residents
   or to the nearest edge. A tract may extend across the search circle.
2. Rates are **crude**, not age-adjusted, and are not life expectancy. The
   five-year window straddles the AI-system expansion and the pandemic years.
3. Distance bands are adjustable descriptive choices, not safety thresholds.
4. `compare_communities()` reports the **unweighted distribution of tract
   rates**, not a pooled mortality rate for a combined population. No p-values,
   health-risk classification, exposure estimate or causal effect is produced.
5. The default data cover Alachua County only. A query outside that coverage
   can return zero rows; this does not imply that no communities exist there.
6. Other facilities can use the same functions with compatible community data.
   Polygon mapping is bundled for Alachua only; custom GEOIDs use point markers.

## Relationship to the original repository

This MVP develops the idea in `RePinkert/PHC6099-final-project` from the reviewed
initial commit `2d0776f5fab6ce50b68e4d535c224f1ef7c8a7ad`. It introduces a
community-health API. The original electricity-price and monthly life-expectancy
placeholder functions are outside this MVP and are not advertised as implemented.
This draft proposes the new workflow on `mvp-community-health` for team review.
The original skeleton remains available at the initial commit linked above.

## Development and authorship

The code, tests, data preparation and documentation were developed with Codex
assistance. Team members should review and understand the code, verify the
scientific interpretation, and describe AI use in the course report. The
collective maintainer entry uses a non-contact GitHub address for this draft MVP;
the team should set its actual author and maintainer metadata before submission.

Suggested two-person ownership: facility provenance and geographic selection;
health definitions, descriptive comparisons and figures. Review integration
and the final report together.
