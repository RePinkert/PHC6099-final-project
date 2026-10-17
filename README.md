# lifewatt

<!-- badges: start -->
<!-- badges: end -->

`lifewatt` turns a US ZIP code into environmental justice indicators:
residential electricity price estimates (observed and forecast) with YoY / MoM
trends, bill evidence, an expected life-expectancy loss view anchored to
published national life tables, and a synthetic life-expectancy estimate built
from state mortality rates (explicitly labeled, fully assumption-declared).

## Installation

You can install the development version from GitHub with:

```r
# install.packages("devtools")
devtools::install_github("RePinkert/PHC6099-final-project", ref = "develop")
```

The six public functions reached `develop` one at a time, each as its own
commit: foundation, `electricity_price`, `electricity_price_trend`,
`expected_life_loss`, `my_electricity`, `life_expectancy`,
`life_expectancy_trend`. Every commit is buildable and checkable on its own, and
tags `slice/S0` through `slice/S6` mark them.

## Main interfaces

```r
library(lifewatt)

# observed price (EIA-861 ZIP-level annual, customer-weighted)
electricity_price("32601", year = 2024)

# state monthly series (B1 cache, 2023-01 .. 2026-07; 2025+ flagged provisional)
electricity_price("32601", period = "mom")

# trend views
electricity_price_trend("32601", period = "yoy")
electricity_price_trend("32601", period = "mom")

# price at a time point + bill as Bayesian evidence
my_electricity("32601", bill = 180, time = "2026-12")
my_electricity("32601", bill = 180, usage = 1200, time = "2026-12")

# expected life-expectancy loss view (delta_le is a declared sensitivity
# parameter, not a sourced elasticity; loss columns are withheld without it)
expected_life_loss("32601", "2026-07")
expected_life_loss("32601", "2026-12", bill = 180, usage = 1200)
expected_life_loss("32601", "2026-09", delta_le = 0.01)

# synthetic life expectancy (mortality-based D1b/D2 sensitivity synthesis;
# estimate_type labels it -- not an NCHS-published subnational value)
life_expectancy("32601")
life_expectancy("32601", quarter = "2024Q4")
life_expectancy_trend("32601", period = "yoy")
life_expectancy_trend("32601", period = "qoq")
```

Every row carries provenance columns (`source`, `level`, `degraded_from`,
`mapping_vintage`, `provisional`) and, where assumptions are declared, a
`sensitivity_assumption` column. Prices are state-level estimates for the
utility territory of the ZIP (OpenEI 2024 mapping); months from 2025-01 onward
are provisional and flagged. Months after 2026-07 are served by the phase-B
triplet forecast (`fit_as_of = 2026-07`).

## Life expectancy: a synthetic estimate

`life_expectancy()` returns a **synthetic** estimate built from state mortality
rates (NCHS VSRR provisional) plus the published national life-table anchor
(NCHS e0): the state's mortality index is applied to the national age pattern
through an abridged life table. Every assumption (state age pattern = national,
life-table conventions, delta_e1 portability) is declared in the
`sensitivity_assumption` column and the `estimate_type` label states it is not
an NCHS-published subnational life expectancy. `life_expectancy_trend()`
reports quarter-over-period change (`"yoy"` / `"qoq"`; the source is quarterly,
so `"mom"` is refused honestly). Premature-mortality metrics (YPLL-75 proxy,
pre-75 death share) ride along in the same row.

## Scope notes

- `delta_le` has no sourced elasticity yet (as of 2026-11-18 contract); it is a
  caller-supplied sensitivity parameter and the output labels it as such.
- EIA-112 disconnection mechanism data covers 2024 only.
- Model development records live in `autoresearch/` (not shipped in the package).
