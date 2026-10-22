# my_electricity() —— UX 契约正门的能源侧兄弟包装（exp#35，2026-10-16 mock 签名）
# 与 expected_life_loss() 共用 .price_at() 与 .bill_evidence()；只做能量核算，不碰 LE。

#' Estimated electricity situation for a ZIP code at a month
#'
#' Energy-side view of the [expected_life_loss()] machinery: the price estimate at
#' `time` (observed B1 state price up to 2026-07, LSTM forecast afterwards),
#' with `bill` treated as Bayesian evidence (descriptive by itself; posterior when
#' `usage` is also supplied).
#'
#' @param zipcode A character or numeric US ZIP code.
#' @param bill Optional monthly electricity bill in USD; default unset (it is evidence,
#'   not a required input).
#' @param time A month ("YYYY-MM", "YYYY/M", "YYYY/MM" or Date); exactly one value.
#' @param usage Optional monthly usage in kWh; with `bill` it forms a local price
#'   measurement blended into a posterior (predicted regime) or reported alongside the
#'   measured state price (observed regime).
#' @param meas_sd Declared sd of the local price measurement (cents/kWh).
#' @return A one-row data.frame with the price estimate, implied usage, evidence
#'   columns, C1 disconnection mechanism columns (per-1k rates, Form EIA-112
#'   2024 State Total; NA outside 2024) and full provenance
#'   (source/level/degraded_from/mapping_vintage/provisional).
#' @export
#'
#' @examples
#' \dontrun{
#' my_electricity("32601", time = "2026-07")
#' my_electricity("32601", bill = 180, time = "2026-12")
#' }
my_electricity <- function(zipcode, bill = NULL, time, usage = NULL, meas_sd = 1) {
  base <- .price_at(zipcode, time)
  if (!is.numeric(meas_sd) || length(meas_sd) != 1L || !is.finite(meas_sd) || meas_sd <= 0) {
    stop("meas_sd must be a positive number (declared measurement sd, cents/kWh).", call. = FALSE)
  }
  ev <- .bill_evidence(base$price, base$price_sd, bill, usage, meas_sd)
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
