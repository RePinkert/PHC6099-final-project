# lifewatt

<!-- badges: start -->
<!-- badges: end -->

`lifewatt` turns a US ZIP code into environmental justice indicators:
residential electricity price estimates (observed and forecast) with YoY / MoM
trends, bill evidence, an expected life-expectancy loss view anchored to
published national life tables, a synthetic life-expectancy estimate built from
state mortality rates (explicitly labeled, fully assumption-declared), and
CDC PLACES adult health prevalence for the ZCTA that matches the ZIP.

## Installation

You can install the development version from GitHub with:

```r
# install.packages("devtools")
devtools::install_github("RePinkert/PHC6099-final-project", ref = "develop")
```

The seven public functions reached `develop` one at a time, each as its own
commit: foundation, `electricity_price`, `electricity_price_trend`,
`expected_life_loss`, `my_electricity`, `life_expectancy`,
`life_expectancy_trend`, `health_measure`. Every commit is buildable and
checkable on its own; tags `slice/S0` through `slice/S6` mark the first six
slices, and `health_measure` landed as its own commit after them.

## Main interfaces

```r
library(lifewatt)

# observed price (EIA-861 ZIP-level annual, customer-weighted)
electricity_price("32601", year = 2024)

# state monthly series (B1 cache, 2023-01 .. 2026-07; EIA-preliminary months flagged provisional)
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

# adult health estimates for the ZCTA (CDC PLACES 2025 release, BRFSS 2023;
# downloaded live, so this is the one call that needs the internet)
health_measure("32601")
health_measure("32601", measure = c("DIABETES", "BPHIGH"))
```

Every row carries provenance columns (`source`, `level`, `degraded_from`,
`mapping_vintage`, `provisional`) and, where assumptions are declared, a
`sensitivity_assumption` column. Prices are state-level estimates for the
utility territory of the ZIP (OpenEI 2024 mapping); months EIA still marks
Preliminary (2026-01 onward in the shipped vintage) are flagged provisional. Months after 2026-07 are served by the LSTM
price forecast (`fit_as_of = 2026-07`), through 2026-12 — times beyond the
declared window are refused. ZIP inputs must be 5 digits (leading zeros
required) or ZIP+4; ambiguous shapes are rejected, never silently rewritten.

## Granularity and confidence

Only the annual price reaches the ZIP itself: one utility's price for a
single-utility ZIP, or a population-share blend of several. Everything else is
coarser or modeled, and each row says which through `confidence_tier`:

| tier | meaning | where |
|---|---|---|
| A | observed at the reported granularity | annual price, single-utility ZIP |
| B | observed, but coarser than the ZIP or blended | monthly price (state); annual price of a multi-utility ZIP |
| C | modeled or synthetic | forecast months, `life_expectancy()`, `health_measure()` |

Two limits are worth stating plainly:

- **Monthly and forecast prices are the state value.** Every ZIP in a state gets
  the same number. The utility weights in the ZIP mapping only pick the state, and
  in the OpenEI 2024 mapping no ZIP straddles a state line, so the weighting never
  changes the price. `within_state_sd` (customer-weighted spread of EIA-861 utility
  prices in the state) shows how far a ZIP's real price can typically sit from the
  state value.
- **Annual multi-utility prices are weighted by each utility's 2020 population
  share inside the ZIP.** Every populated census block in the ZCTA is placed in
  the HIFLD retail service territories that contain it (only utilities the OpenEI
  mapping assigns to the ZIP count). The shares cover 14,661 of the 15,331
  multi-utility ZIPs; the rest fall back to system-wide residential customers, and
  `weight_basis` says which applied. Before this, a large utility touching the edge
  of a ZIP could dominate: 32608 was 87% Duke Energy Florida and priced at 16.26
  cents/kWh; it is now a Clay Electric / GRU split at 13.95.
- **The shares depend on how overlapping territories are resolved.** HIFLD draws
  many cooperatives and large investor-owned utilities as whole counties, so they
  overlap the precisely drawn municipal territories. An overlapping block goes to
  the smallest territory (the most specific boundary). Across ZIPs, a median 24%
  of the population sits in overlaps, and 4,318 ZIPs are entirely in overlap;
  `share_overlap_frac` reports this per ZIP, and the shipped table keeps an
  equal-split alternative (`pop_share_equal`) for sensitivity checks. Read the
  point estimate together with `price_min` / `price_max`.

## Price forecast: what the validation shows and what it does not

Months 2026-08..2026-12 come from an LSTM whose fit ships in
`inst/extdata/price_lstm_fit.rds` together with its baselines and coverage. Read
those numbers with three caveats:

- **Use the calibration window for the comparison.** The `mse_es` column comes
  from the early-stopping window, which chose the model, so it flatters it (LSTM
  0.93 vs last value 1.43). The calibration window (`mse_cal`, targets
  2026-02..2026-07) played no part in fitting or model selection: LSTM 3.56,
  last value 4.17, seasonal naive 5.02, about 15% better than the best baseline.
  Likewise `coverage$transfer_early_window` is measured on the early-stopping
  window and is not independent evidence.
- **Training used each year's EIA-861 average from January of that year**,
  months before it was published. Re-scoring the early-stopping window with only
  the annual values available at the time raises the LSTM's MSE from 1.18 to 1.34
  (the last-value baseline is 1.72), so validation overstates accuracy by about
  14%. Live forecasts are not affected: the 2025 value they use is published.
  A refit that stamps annual values at their release date is open work.
- **The first forecast month jumps.** Across states, the median 2026-08 / 2026-07
  ratio is 1.040, against a historical August/July median of 1.005, and the
  calibration residuals have a positive median (+1.7% at h=1 to +4.4% at h=5).
  The point forecast is not bias-corrected.

- **The model's inputs are an older vintage than the observed series.** Observed
  months come from the refreshed EIA-861M cache; the LSTM reads
  `price_history_slim.csv.gz`, the vintage it was trained on, which still has
  EIA's initial 2025-2026 values (MD 2026-03 at 35.85 rather than 22.2). A refit
  on the current vintage is open work.

`price_sd` is the Gaussian scale implied by the 85% absolute-residual quantile,
`abs_q85 / qnorm(0.925)`. `q_lo` / `q_hi` are the 5% and 95% relative-residual
quantiles. `model_traning/check_interval_coverage.R` replays the validation
forecasts from the shipped weights (it reproduces the frozen quantiles to 1e-7)
and checks coverage by leaving out one calibration month at a time, the only
check that does not reuse the residuals that set the quantiles:

| interval | nominal | held-out coverage, h = 1..5 |
|---|---|---|
| `q_lo` / `q_hi` | 90% | 0.82, 0.88, 0.87, 0.89, 0.88 |
| ±`qnorm(0.925)` × `price_sd` | 85% | 0.84, 0.85, 0.84, 0.85, 0.84 |

So `q_lo` / `q_hi` run slightly narrow, worst at h = 1, which rests on only two
calibration months.

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

## Health: PLACES prevalence, not a risk model

`health_measure()` returns CDC PLACES model-based estimates for the ZCTA that
matches the ZIP: crude adult prevalence in percent with its 95% confidence
interval, one row per measure (`DIABETES`, `BPHIGH`, `CSMOKING`, ...). Two
things it does not claim. It is not a mortality or life-expectancy measure —
that axis belongs to `life_expectancy()` and `expected_life_loss()`. And it is
not a forecast: PLACES is a single published cross-section, so the release
window is fixed by the source, not chosen by the caller.

Only the 2023 BRFSS measures are returned (the candidate-list E1 rule; the five
BRFSS-2022 measures — `COLON_SCREEN`, `DENTAL`, `MAMMOUSE`, `SLEEP`,
`TEETHLOST` — are refused). Asking for an unknown ID and asking for a measure
PLACES suppressed for that ZCTA fail with the same honest error, because a
suppressed measure is genuinely absent from the response: at most 35 measures
are published per ZCTA, and ZIP 32601 has 28. `measure = NULL` returns whatever
the ZCTA has, so row counts differ across ZIPs by design.

A ZIP code is treated as the ZCTA with the same five digits. The two usually,
but not always, cover the same area; `level = "zcta"` and
`degraded_from = "zip"` say so on every row.

## Scope notes

- `delta_le` has no sourced elasticity yet (as of 2026-11-18 contract); it is a
  caller-supplied sensitivity parameter and the output labels it as such.
- EIA-112 disconnection mechanism data covers 2024 only.
- `health_measure()` is the only interface that is not served from a shipped
  snapshot under `inst/extdata/`: it queries data.cdc.gov (PLACES ZCTA dataset
  `qnzd-25i4`) on every call, so it needs the internet and its result is not
  reproducible against a frozen vintage. Freezing it (an `inst/extdata` slim
  snapshot plus a `data-raw/` assembly script) is open work, and the dataset ID
  and `$limit` are hard-coded until then.
- Model development records (the experiment ledger, the research harness and its
  programme notes) deliberately do **not** live in this repository: the code that
  produces `inst/extdata/` ships in `data-raw/`, while the research layer around it
  is kept outside so the package history stays a package history. The one artefact
  the suite depended on, the reference `predict_fn` used as a 1:1 anchor for
  `.triplet_predict()`, is frozen under `tests/testthat/fixtures/`.
