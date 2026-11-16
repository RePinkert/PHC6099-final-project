# lifewatt

<!-- badges: start -->
<!-- badges: end -->

`lifewatt` answers questions about a place at the granularity each source
actually publishes:

- **By state** — residential electricity price (observed 2023-2025 and forecast
  through 2026-12) with YoY / MoM trends, bill evidence, an expected
  life-expectancy loss view anchored to published national life tables, and a
  synthetic life-expectancy estimate built from state mortality rates
  (explicitly labeled, fully assumption-declared). No source publishes a
  realised average residential price per ZIP code, so this layer takes a state;
  `zip_to_state()` resolves a ZIP to its state.
- **By ZCTA** — CDC PLACES adult health prevalence for the ZCTA that matches a
  ZIP code. This is the one interface that still takes a ZIP.

The package does not synthesise a ZIP-level price: every ZIP in a state would
return the same number, so the signature says state instead.

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

# a ZIP only ever selects a state; this is the only ZIP-facing lookup
zip_to_state("32601")            # zip / state / mapping_vintage / n_utility

# observed annual price, state-level (EIA-861, customer-weighted)
electricity_price("FL", year = 2024)

# state monthly series (B1 cache, 2023-01 .. 2026-07; EIA-preliminary months flagged provisional)
electricity_price("FL", period = "mom")

# trend views
electricity_price_trend("FL", period = "yoy")
electricity_price_trend("FL", period = "mom")

# price at a time point + bill as Bayesian evidence
my_electricity("FL", bill = 180, time = "2026-12")
my_electricity("FL", bill = 180, usage = 1200, time = "2026-12")

# expected life-expectancy loss view (delta_le is a declared sensitivity
# parameter, not a sourced elasticity; loss columns are withheld without it)
expected_life_loss("FL", "2026-07")
expected_life_loss("FL", "2026-12", bill = 180, usage = 1200)
expected_life_loss("FL", "2026-09", delta_le = 0.01)

# synthetic life expectancy (mortality-based D1b/D2 sensitivity synthesis;
# estimate_type labels it -- not an NCHS-published subnational value)
life_expectancy("FL")
life_expectancy("FL", quarter = "2024Q4")
life_expectancy_trend("FL", period = "yoy")
life_expectancy_trend("FL", period = "qoq")

# adult health estimates for the ZCTA (CDC PLACES 2025 release, BRFSS 2023;
# downloaded live, so this is the one call that needs the internet)
health_measure("32601")
health_measure("32601", measure = c("DIABETES", "BPHIGH"))
```

Price and life-expectancy functions take a two-letter USPS code or a full state
name; a ZIP code is refused by name and the error points at `zip_to_state()`.
Every row carries provenance columns (`source`, `level`, `degraded_from`,
`mapping_vintage`, `provisional`) and, where assumptions are declared, a
`sensitivity_assumption` column. `degraded_from` is `NA` on every price and
life-expectancy row: nothing is degraded from a ZIP any more, because nothing
claims ZIP granularity. Months EIA still marks Preliminary (2026-01 onward in
the shipped vintage) are flagged provisional. Months after 2026-07 are served by
the LSTM price forecast (`fit_as_of = 2026-07`), through 2026-12 — times beyond
the declared window are refused.

## Granularity and confidence

Every price and life-expectancy row is **state-level**; the health rows are
**ZCTA-level**. Nothing is observed at ZIP granularity, so no interface returns
tier A:

| tier | meaning | where |
|---|---|---|
| A | observed at the reported granularity | **no member**: the package has no ZIP-level observation |
| B | observed, but coarser than the ZIP | annual and monthly price (state), price trends |
| C | modeled or synthetic | forecast months, `life_expectancy()`, `health_measure()` |

**What "state-level" costs, stated in the output.** The annual row carries the
customer-weighted mean of the state's EIA-861 utility prices, plus `price_min`,
`price_max` and `n_utility` for that same set. The gap between a ZIP's own
utility price and the state mean is the price of the simplification: measured on
the shipped tables it is **7.5% at the median and 25.8% at p90**
(`model_traning/HANDOVER_confidence.md`, layer L1). `within_state_sd` (the
customer-weighted spread of utility prices in the state) carries the same
information as one number.

**The granularity loss can exceed the forecast band.** Across states, the ratio
of `within_state_sd` to the h = 1 forecast half-width has a median of 1.5-1.6
and exceeds 1 in 80-88% of states: at monthly resolution, which utility serves
the ZIP matters more than model uncertainty. The state value is reported with
that ratio available, not behind it.

**Bill evidence is the only household-level measurement.** With `bill` and
`usage`, `my_electricity()` and `expected_life_loss()` report a household
effective price (`bill * 100 / usage`) and, in the forecast regime, an
inverse-variance posterior against the state price as prior. That is a different
estimand from the state average, and the row's `notes` says which one it holds.

**Why the ZIP-level blend was removed** (2026-11). The package used to weight a
ZIP's utilities by their 2020 population share inside the ZIP. That weighting
never reached a downstream number — in the OpenEI 2024 mapping no ZIP straddles
a state line, so the blend could only ever pick the state — while it did import
an unvalidated rule for overlapping service territories (an overlapping block
resolved to the smallest territory put essentially all of ZIP 32601's and
32608's population in overlaps). The table, the assembler and the weighting are
gone; `zip_to_state()` keeps the one fact the mapping carries.

## Price forecast: what the validation shows and what it does not

Months 2026-08..2026-12 come from an LSTM whose fit ships in
`inst/extdata/price_lstm_fit.rds` together with its baselines and coverage.
- **Data:** it is trained on EIA-861M's state panel from 2010-01 (current
  vintage) and an annual EIA-861 covariate for 2010-2025. The year-Y annual
  value enters at Y+1 October, its assumed release date, and EIA's "Adjustment"
  pseudo-utility (eiaid 99999) is excluded.
- **Inputs and target are relative:** log price over its trailing 12-month mean,
  the month-over-month change, season, and the annual value over the monthly
  mean before its release. The target is log(P_{t+h} / P_t). There is no
  absolute price level anywhere in the inputs.
- **Third model of this kind:** the earlier two jumped at the seam, as the next
  section explains.

### The seam into 2026-08: fixed on the second retrain

The shipped forecast used to jump at its first month. The cause was found by
pure-R ablations in `model_traning/diagnose_seam.R` and
`diagnose_seam_channels.R`. Each fit had inputs outside what training had seen:
- **First fit:** two covariates appeared only at the end of the training history
  (EIA-112 disconnections for 2024 only; annual EIA-861 for 2023-2025 only).
- **First retrain (attempt 1):** per-state min-max price and annual levels ran
  past their training range in 65% and 71% of states.

Acceptance criteria were fixed before the retrains (`model_traning/accept_seam.R`):
- A1: the 2026-08 / 2026-07 median is in [0.99, 1.015] (historical
  August/July median 1.0035).
- A2: at most 15% of states exceed their own 2015-2025 August/July maximum.
- A3: calibration MSE is below the last value.
- A4: calibration MSE is at most 0.95 x the drift baseline. A4 was added before
  the second retrain was run, after a random-weight network was found to pass
  A1-A3.

| fit | A1 seam median | A2 states above own max | calibration MSE | 2026-08 MSE (last value 0.452) |
|---|---|---|---|---|
| previously shipped | 1.064 | 82% | 2.224 | 3.364 |
| attempt 1 | 1.038 | 47% | 2.137 | 3.849 |
| **attempt 2 (shipped)** | **0.992** | **0%** | **2.522** | **0.487** |

Calibration baselines: drift (last value x exp(mean training log change))
2.868, last value 3.130, seasonal naive 4.056. The 2026-08 truth was looked at
during the diagnosis, so that column is a reference, not a held-out test.

### Limits of the shipped forecast

- **Lower calibration accuracy than the two earlier fits.** Calibration MSE is
  2.522, against 2.137 and 2.224. Those fits earned their lower MSE while
  missing the first forecast month badly (2026-08 MSE 3.85 and 3.36). The
  current fit is not better on every measure: it trades some calibration
  accuracy for a forecast that starts where the data ends. It beats drift by
  12% (A4) and last value by 19%.
- **Forecasts run low.** Calibration residual medians are +1.7%, +4.3%, +4.3%,
  +5.2%, +4.7% at h = 1..5 (positive = forecast too low), growing with the
  horizon. Every July origin from 2013 to 2026 under-forecasts August by roughly
  0.5-2.2%. A log-ratio target pulls toward the average drift of the training
  years, which understates a period of fast increases. No bias correction is
  applied: an earlier attempt at one, estimated on the early-stopping window,
  pointed the wrong way on the calibration window.
- **The first month carries little state-specific information.** Across states,
  the predicted 2026-08 / 2026-07 ratio barely correlates with the true one
  (Pearson 0.09, Spearman 0.18). In 2026-08 alone the forecast is slightly worse
  than carrying July forward (0.487 vs 0.452). Read h = 1 as "about the last
  observed price".
- **Use the calibration window for comparisons.** `mse_es` comes from the
  early-stopping window, which chose the model; `mse_cal` (targets
  2026-02..2026-07) played no part in fitting or model selection. Likewise
  `coverage$transfer_early_window` is not independent evidence.
- **The two LSTM bias vectors are equal** (`b_ih == b_hh` in the fit). Both start
  at zero and enter the gates only as a sum, so they get identical updates. The
  model is equivalent to one bias vector, and the pure-R forward matches torch
  (`model_traning/check_parity.R`).

### Intervals

`price_sd` is the Gaussian scale implied by the 85% absolute-residual quantile,
`abs_q85 / qnorm(0.925)`. `q_lo` / `q_hi` are the 5% and 95% relative-residual
quantiles, not symmetrized.

`model_traning/check_interval_coverage.R` replays the validation forecasts from
the shipped weights (it reproduces the frozen quantiles to 1e-8). It checks
coverage by leaving out one calibration month at a time, the only check that
does not reuse the residuals that set the quantiles:

| interval | nominal | held-out coverage, h = 1..5 |
|---|---|---|
| `q_lo` / `q_hi` | 90% | 0.85, 0.89, 0.88, 0.84, 0.89 |
| ±`qnorm(0.925)` × `price_sd` | 85% | 0.85, 0.84, 0.83, 0.84, 0.84 |

Both run slightly narrow. h = 1 rests on only two calibration months.

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

- **Breaking change (2026-11)**: the price and life-expectancy interfaces take a
  state instead of a ZIP; `zip_to_state()` is the only ZIP lookup;
  `inst/extdata/zip_utility_share_slim.csv.gz` and the ZIP population-share blend
  are gone; `degraded_from` and `mapping_vintage` are `NA` on state-level rows.
  See `NEWS.md`.
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
