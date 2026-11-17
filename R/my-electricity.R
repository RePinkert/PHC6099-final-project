# my_electricity() —— UX 契约正门的能源侧兄弟包装（exp#35，2026-10-16 mock 签名）
# 与 expected_life_loss() 共用 .price_at() 与 .bill_evidence()；只做能量核算，不碰 LE。

#' Estimated electricity situation for a state at a month
#'
#' Energy-side view of the [expected_life_loss()] machinery: the price estimate at
#' `time` (observed B1 state price up to 2026-07, LSTM forecast afterwards),
#' with `bill` treated as Bayesian evidence (descriptive by itself; posterior when
#' `usage` is also supplied).
#'
#' @param state A two-letter USPS state code (`"FL"`) or a full state name.
#'   The price layer is state-level, so a ZIP is refused.
#' @param bill Optional monthly electricity bill in USD; default unset (it is evidence,
#'   not a required input).
#' @param time A month ("YYYY-MM", "YYYY/M", "YYYY/MM" or Date); exactly one value.
#' @param usage Optional monthly usage in kWh; with `bill` it forms a local price
#'   measurement blended into a posterior (predicted regime) or reported alongside the
#'   measured state price (observed regime).
#' @param meas_sd Declared sd of the local price measurement (cents/kWh).
#' @return A one-row data.frame with the price estimate, implied usage, evidence
#'   columns, C1 utility disconnection columns (monthly counts per 1,000
#'   residential customers, Form EIA-112 2024 State Total; NA outside 2024, with `c1_source` saying why) and full
#'   provenance (source/level/degraded_from/mapping_vintage/provisional).
#'   `within_state_sd` and `n_utility` come from the EIA-861 utility table of
#'   year `n_utility_year` (the latest released year not after `time`). In the
#'   predicted regime the row also carries the model interval
#'   (`price_lo`/`price_hi`, a nominal 85% interval given in
#'   `price_interval_level`, with its `price_interval_basis` declaration).
#'   The forecast has run low in calibration (the truth was a median 1.7% to
#'   5.2% above it, growing with the horizon) and is not bias-corrected, so a
#'   forecast below the last observed month is not by itself evidence of a
#'   price fall; in
#'   the observed regime those four and `price_sd` are NA because a measured
#'   month has no forecast band.
#' @export
#'
#' @examples
#' my_electricity("FL", time = "2026-07")
#' my_electricity("FL", bill = 180, time = "2026-12")
my_electricity <- function(state, bill = NULL, time, usage = NULL, meas_sd = 1) {
  base <- .price_at(state, time)
  if (!is.numeric(meas_sd) || length(meas_sd) != 1L || !is.finite(meas_sd) || meas_sd <= 0) {
    stop("meas_sd must be a positive number (declared measurement sd, cents/kWh).", call. = FALSE)
  }
  ev <- .bill_evidence(base$price, base$price_sd, bill, usage, meas_sd, base$within_state_sd)
  notes <- c(
    if (nzchar(ev$note)) ev$note else character(0),
    .c1_note(base$state, base$period),
    if (identical(base$regime, "predicted"))
      "future months served by the LSTM price model (fit_as_of = 2026-07)"
  )
  out <- base
  out$bill <- if (is.null(bill)) NA_real_ else bill
  out$usage_kwh <- if (is.null(usage)) NA_real_ else usage
  out$price_meas <- ev$price_meas
  out$evidence_regime <- ev$regime
  out$price_posterior <- if (is.null(ev$posterior)) NA_real_ else ev$posterior
  out$price_posterior_sd <- if (is.null(ev$posterior_sd)) NA_real_ else ev$posterior_sd
  out$implied_usage_kwh <- ev$implied_usage
  c1 <- .c1_at(base$state, base$period)
  out$c1_final_notices_per_1k <- c1$c1_final_notices_per_1k
  out$c1_disconnections_per_1k <- c1$c1_disconnections_per_1k
  out$c1_reconnections_per_1k <- c1$c1_reconnections_per_1k
  out$c1_res_customers <- c1$c1_res_customers
  out$c1_source <- c1$c1_source
  out$notes <- paste(notes, collapse = " | ")
  row.names(out) <- NULL
  out
}
