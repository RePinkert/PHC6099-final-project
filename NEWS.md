# lifewatt 0.0.0.9000

* (Awaiting retrain.) Fix for the 2026-08 seam jump, prepared before the
  retrain. `model_traning/diagnose_seam.R` showed the jump is not real: the true
  Aug/Jul median is 0.9995 against 1.064 predicted, and in 2026-08 alone the LSTM
  has an MSE of 3.36 vs 0.45 for the last value. It comes from two sparse
  covariates that appear only at the end of the training history:
  - The annual EIA-861 channel had data only for 2023-2025. With release dating
    it first entered in 2024-10, so a training window held at most 4 such months,
    against 22 at the 2026-07 origin.
  - EIA-112 has only 2024. After 2024 it is carried forward, and its age reached
    19 months at the 2026-07 origin; training never saw more than 1.

  Changes:
  - EIA-112 (c1) channels are removed from training. The annual channel is
    backfilled to 2010 from the EIA-861 archives
    (`data-raw/assemble_861_state_annual.R` ->
    `inst/extdata/eia861_state_annual.csv.gz`; same definitions as the utility
    slim, 2023-2025 identical). That leaves 8 channels.
  - The serving path builds inputs from `fit$chan_names` and
    `fit$transforms$ann_source`, so the shipped 11-channel fit is unchanged until
    the retrain lands. `model_traning/check_feature_parity.R` checks that
    training and serving build identical inputs (max difference 0).
  - Architecture, seed, `fit_as_of` = 2026-07 and all three windows are
    unchanged.

  Acceptance criteria were fixed before the retrain and must not change after it
  (`model_traning/accept_seam.R`):
  - A1: the 2026-08 / 2026-07 median across states is in [0.99, 1.015].
  - A2: at most 15% of states exceed their own 2015-2025 Aug/Jul maximum.
  - A3: calibration-window MSE is below the last-value baseline.

  The script also reports 2026-08 single-month MSE against last value and
  seasonal ratio. It does not count toward the verdict, because 2026-08 was
  already seen in the diagnosis.

* The price LSTM is refit (same architecture: hidden 64, 36-month window,
  h = 1..5, 51 states pooled; `fit_as_of` still 2026-07):
  - Data: EIA-861M's state panel from 2010-01 in the current vintage
    (`data-raw/assemble_price_history_slim.R`). The model and the observed
    series now read the same values.
  - Look-ahead fixed: the annual EIA-861 value for year Y enters at Y+1 October,
    in both training (`model_traning/prepare.R`) and serving (`.ann_wide`).
    The covariate's scaling is fit on the training window only, and EIA's
    "Adjustment" pseudo-utility (eiaid 99999) is excluded.
  - No bias correction. A per-horizon correction estimated on the
    early-stopping window pointed the opposite way on the calibration window.
    The decision to drop it also looked at the calibration results, as listed
    below. `train_price_lstm.R` now only reports the estimate
    (`es_bias_diagnostic`); `model_traning/rebuild_fit_without_bias.R` rebuilt
    the shipped fit from the same weights without it.

  Fair comparison: all three versions are scored on the same current-vintage
  truth, targets 2026-02..07; baselines are last value 3.130 and seasonal
  naive 4.056.

  | version | calibration MSE | residual median h = 1..5 | 2026-08 / 07 median | states above own Aug/Jul max |
  |---|---|---|---|---|
  | previously shipped | 2.345 | +1.7, 2.6, 2.8, 4.1, 4.4% | 1.040 | 47% |
  | refit + correction | 2.274 | +3.2, 2.9, 1.1, 1.5, 2.8% | 1.040 | 61% |
  | refit (shipped) | 2.224 | +0.9, 2.0, 1.5, 0.9, 0.3% | 1.064 | 82% |

  The jump into 2026-08 is still unexplained and is now larger (historical
  August/July median 1.0035); README documents it as a limitation.
  Leave-one-month-out coverage: `q_lo` / `q_hi` (nominal 90%) 0.84-0.89, the
  `price_sd` band (nominal 85%) 0.83-0.85. Scenario 2 (32601 @ 2026-12) moves
  from 15.02 / 1.204 to 16.39 / 0.973. The README section is rewritten with
  these numbers, replacing the leakage and old-vintage caveats.
* Contract test: intervals must not be symmetrized. The test used to require
  right skew at every horizon, but h = 5 is now left-skewed.

* The observed monthly price cache (`inst/extdata/b1_monthly_cache.csv`) is
  rebuilt from EIA-861M's bulk file (`data-raw/assemble_eia861m_monthly.R`, no
  API key needed) and picks up EIA's revisions: 625 of 2,193 state-months move,
  4 by more than 1 cent/kWh (MD 2026-03 was an initial 35.85, now 22.2; CA
  2025-04 33.82 -> 27.76). Values before 2025 are unchanged.
* Breaking: `provisional` on observed months now follows EIA's own data status
  (`Preliminary`, 2026-01 onward in this vintage) instead of a fixed 2025-01
  cut-off; the cache gains a `data_status` column. 2025 months are now final.
* (Superseded by the refit above: the LSTM now reads the same vintage.)

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
