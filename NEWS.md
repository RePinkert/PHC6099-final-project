# lifewatt 0.0.0.9000

* Fix: the forecast `price_sd` now uses `qnorm(0.925)`, the factor that turns the
  85% absolute-residual quantile into a Gaussian sd. The old `qnorm(0.95)`
  understated it by about 12.5%, which made bill posteriors too narrow. The
  golden fixture and the scenario-2 snapshot move accordingly (32601 @ 2026-12:
  1.054 -> 1.204); point forecasts and `q_lo` / `q_hi` are unchanged.
* `expected_life_loss()` / `my_electricity()` refuse a bill / usage pair that
  implies a price outside 1..150 cents/kWh instead of turning it into evidence
  (bill = 5000, usage = 1 used to give a posterior of about 154,000 cents/kWh).
* `within_state_sd` no longer counts EIA's "Adjustment" pseudo-utility
  (eiaid 99999, sometimes with negative customers) as a utility. The LSTM's
  annual covariate still includes those rows, as it did in training.
* README gains "Price forecast: what the validation shows and what it does not":
  the honest baseline comparison is the calibration window (about 15% better
  than last value, not the early-stopping figures), training used annual
  averages before their release (validation MSE 1.18 vs 1.34 when re-scored),
  and the first forecast month jumps about 4% with no bias correction.
* `model_traning/check_interval_coverage.R` replays the validation forecasts
  from the shipped weights and reports interval coverage, including a
  leave-one-month-out check: `q_lo` / `q_hi` (nominal 90%) cover 0.82-0.89, the
  `price_sd` band (nominal 85%) 0.84-0.85. A `skip_on_cran()` test pins that the
  frozen calibration quantiles reproduce from the shipped weights and data.
* In the observed regime (months up to 2026-07), bill + usage no longer fills
  `price_posterior` with the caller's own measurement. There is no prior sd to
  blend with, so `price_posterior` / `price_posterior_sd` stay NA and the local
  measurement is in `price_meas`.
* The no-torch test now passes under `R CMD check` (it read `../../NAMESPACE`,
  which does not exist in an installed package).

* The annual ZIP price of a multi-utility ZIP is now weighted by each utility's
  2020 population share inside the ZIP (census blocks x HIFLD retail service
  territories; overlapping territories resolved to the smallest one), replacing
  system-wide residential customers. New columns `weight_basis` and
  `share_overlap_frac`; ZIPs without a share fall back to customers and say so.
  New shipped table `inst/extdata/zip_utility_share_slim.csv.gz`, assembled by
  `data-raw/assemble_zip_utility_share.R`. 32601 moves from 13.72 to 14.87
  cents/kWh (2024) and 32608 from 16.26 to 13.95.

* Every value row now carries `confidence_tier` (A observed at the reported
  granularity / B observed but coarser than the ZIP / C modeled or synthetic).
* State-level price rows (`electricity_price(period = "mom")`, and the price in
  `my_electricity()` / `expected_life_loss()`) gain `within_state_sd`, the
  customer-weighted spread of EIA-861 utility prices inside the state, so the
  ZIP-to-state granularity loss is quantified instead of implied away.
* The annual ZIP price gains `price_min` / `price_max` across the mapped
  utilities, and `weight_scheme` now states that the weights are system-wide
  customers, not within-ZIP shares.
* Fix: the multi-utility `weight_note` no longer suggests the state value is a
  ZIP-weighted blend; the weights only select the state.

* Breaking: ZIP inputs now follow a strict US ZIP contract instead of being
  silently rewritten. After unambiguous preprocessing (numeric whole numbers,
  ZIP+4, 9-digit strings, surrounding whitespace) the value must match
  `^[0-9]{5}$`; the legacy New England 4-digit shorthand ("1002") is refused
  with a hint to pass "01002", so a mistyped "3260" can no longer be routed to
  an unrelated Maine ZIP.
* Breaking: `expected_life_loss()` / `my_electricity()` refuse times after
  2026-12, the declared window; the forecast regime covers 2026-08..2026-12
  only (`fit_as_of = 2026-07`, intervals calibrated for horizons <= 13 months).
* Fix: residential-customer weighting now falls back across data years as
  documented (a utility missing the newest year's customer count keeps its
  older-year weight instead of silently degrading to equal weighting).
* Fix: `health_measure()` validates the PLACES response schema (a CDC dataset
  change now fails loudly instead of being misreported as a bad ZIP), keeps
  only `Crude prevalence` rows, and separates "not a ZCTA" from "other
  vintages/value types only".
* Fix: `electricity_price_trend(period = "yoy")` gains the `provisional`
  column (always `FALSE`: both endpoints are EIA-861 final years), so every
  output row now carries the full provenance contract.
* Fix: anchor fallback notes state the correct direction ("earliest available"
  when falling back to the table head); `my_electricity()` mentions the
  forecast model only for predicted months; internal price/evidence inputs are
  scalar-validated (bill/usage/meas_sd/delta_le) and refuse non-positive
  prices.
* The OpenEI ZIP mapping is vintage 2024 while EIA-861 carries 2025 final
  prices; every row carries `mapping_vintage` so this lag stays visible.
* Seven public functions replace the placeholder stubs, each released as its own
  commit on `develop`:
  - `electricity_price()` / `electricity_price_trend()`: the ZIP-level annual
    price (residential-customer-weighted blend of EIA-861 utility prices over the
    OpenEI 2024 utility mapping) and the state monthly series, with YoY and MoM
    views. Both drop the `...` placeholder argument, and both refuse ambiguous
    calls instead of guessing.
  - `expected_life_loss()`: the price at a month plus the bill as Bayesian
    evidence, anchored to the published NCHS national life table. The
    life-expectancy loss columns are withheld unless the caller supplies
    `delta_le`, because no sourced US ZIP-level price-to-life-expectancy
    elasticity exists; the output carries the nearest published context in
    `sensitivity_assumption` and labels it as context, not a coefficient.
  - `my_electricity()`: the same engine with no life columns, for callers who
    want the energy picture only.
  - `life_expectancy()` / `life_expectancy_trend()`: a **synthetic** life
    expectancy from NCHS VSRR state mortality rates applied to the national age
    pattern and anchored to the NCHS e0. Every assumption is declared in
    `sensitivity_assumption`, and `estimate_type` states that this is not an
    NCHS-published subnational life expectancy. **Breaking:** the trend periods
    are now `"yoy"` and `"qoq"`; `"mom"` is refused, because the mortality source
    is quarterly.
  - `health_measure()`: ZCTA-level adult health estimates (crude prevalence with
    95% confidence limits) from the CDC PLACES 2025 release, restricted to the
    2023 BRFSS measures (the candidate-list E1 rule; the 5 BRFSS-2022 measures
    are refused). This is the only interface that is **not** served from a
    shipped `inst/extdata/` snapshot: it queries data.cdc.gov (`qnzd-25i4`) on
    every call, so it needs the internet and is not reproducible against a
    frozen vintage. Row counts vary by ZIP because PLACES omits measures
    suppressed for the ZCTA (at most 35 BRFSS-2023 measures).
* New shipped data under `inst/extdata/` (B1 monthly cache, phase-B forecast fit,
  OpenEI mapping, EIA-861 annual, NCHS life tables, EIA-112 disconnections, VSRR
  mortality), each reproducible from the assembly scripts in `data-raw/`.
* Every returned row carries provenance columns (`source`, `level`,
  `degraded_from`, `mapping_vintage`, `provisional`).
* The forecast MASE ledger lives with the research tree, which is deliberately
  **not** part of this repository and never read by the package. The dev-only
  regression that pins the triplet predictor keeps a frozen copy of the
  reference `predict_fn` under `tests/testthat/fixtures/`.
* Documentation is now generated by roxygen and reproduces from the source
  blocks; `man/` was previously absent, so the exports were undocumented.
