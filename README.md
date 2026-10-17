# lifewatt

<!-- badges: start -->
<!-- badges: end -->

`lifewatt` turns a US ZIP code into environmental justice indicators.
This branch is being released one public function at a time; what follows is
what exists today.

## Installation

You can install the development version from GitHub with:

```r
# install.packages("devtools")
devtools::install_github("RePinkert/PHC6099-final-project")
```

## Main interfaces

```r
library(lifewatt)

# observed price (EIA-861 ZIP-level annual, customer-weighted)
electricity_price("32601", year = 2024)

# state monthly series (B1 cache, 2023-01 .. 2026-07; 2025+ flagged provisional)
electricity_price("32601", period = "mom")
```

Every row carries provenance columns (`source`, `level`, `degraded_from`,
`mapping_vintage`, `provisional`). Prices are state-level estimates for the
utility territory of the ZIP (OpenEI 2024 mapping); months from 2025-01 onward
are provisional and flagged.

The bill-evidence view (`my_electricity`), the expected life-expectancy loss
view (`expected_life_loss`) and the synthetic life-expectancy estimate
(`life_expectancy`, `life_expectancy_trend`) land in later slices of this
distribution; `electricity_price_trend` lands in the next one.

## Scope notes

- `life_expectancy()` / `life_expectancy_trend()` are still stubs on this branch
  and refuse to run; do not call them yet.
- Model development records live in `autoresearch/` (not shipped in the package).