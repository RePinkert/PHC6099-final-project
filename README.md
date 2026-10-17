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

# trend views
electricity_price_trend("32601", period = "yoy")
electricity_price_trend("32601", period = "mom")

# expected life-expectancy loss view (delta_le is a declared sensitivity
# parameter, not a sourced elasticity; loss columns are withheld without it)
expected_life_loss("32601", "2026-07")
expected_life_loss("32601", "2026-12", bill = 180, usage = 1200)
expected_life_loss("32601", "2026-09", delta_le = 0.01)
```

Every row carries provenance columns (`source`, `level`, `degraded_from`,
`mapping_vintage`, `provisional`). Prices are state-level estimates for the
utility territory of the ZIP (OpenEI 2024 mapping); months from 2025-01 onward
are provisional and flagged. Both price functions sit on the same layers, so a
trend and a level can never disagree.

## The life-expectancy claim, precisely

`expected_life_loss()` is anchored to the published national life table (NCHS
e0), and the life-loss columns are **withheld unless you supply `delta_le`**.
There is no sourced US ZIP-level price-to-life-expectancy elasticity, so the
parameter stays yours and the output says so in a `sensitivity_assumption`
column, carrying the closest published context: an energy-cost shock scenario
band (Richardson et al., *BMJ Public Health* 2023;1:e000097) and US
heating-price winter-mortality direction evidence (Chirakijja et al., NBER WP
25681, 2019). Neither is a unit-price elasticity and neither is used as one.

A bill is treated as evidence, not as an input you owe: on its own it yields
implied usage; with usage it forms a local price measurement that tightens the
forecast's interval. EIA-112 disconnection rates ride along for 2024.

The bill-evidence view (`my_electricity`) and the synthetic life-expectancy
estimate (`life_expectancy`, `life_expectancy_trend`) land in later slices of
this distribution.

## Scope notes

- `life_expectancy()` / `life_expectancy_trend()` are still stubs on this branch
  and refuse to run; do not call them yet.
- EIA-112 disconnection data covers 2024 only; outside that window the columns
  are NA with a note saying so.
- Model development records live in `autoresearch/` (not shipped in the package).