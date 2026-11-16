# life_expectancy_trend() —— exp#43 季度合成趋势（yoy|qoq；源为季度频，mom 诚实拒绝；W0 起收州）。
#' Change in synthetic life expectancy over time
#'
#' Quarter-over-period change in the [life_expectancy()] synthetic estimate:
#' `period = "yoy"` compares the same quarter a year earlier, `"qoq"` the
#' previous quarter (the VSRR source is quarterly — the placeholder `"mom"`
#' period is not available and is refused honestly).
#'
#' Takes a state, not a ZIP code; resolve a ZIP with [zip_to_state()].
#'
#' @param state A two-letter USPS state code (`"FL"`) or a full state name.
#' @param period One of `"yoy"` or `"qoq"`.
#' @param quarter A quarter ("YYYY-Qn"); default: the latest VSRR quarter shipped.
#' @return A one-row data.frame with the from/to synthetic e0 values, their
#'   change (years and mortality-rate terms) and full provenance plus the
#'   `sensitivity_assumption` declaration.
#' @export
#'
#' @examples
#' \dontrun{
#' life_expectancy_trend("FL", period = "yoy")
#' life_expectancy_trend("FL", period = "qoq")
#' }
life_expectancy_trend <- function(state, period = c("yoy", "qoq"), quarter = NULL) {
  period <- match.arg(period)
  state <- .state_code(state)
  if (is.null(quarter)) quarter <- .vsrr_latest_quarter()
  quarter <- as.character(quarter)
  from <- .quarter_shift(quarter, if (period == "yoy") -4L else -1L)
  to_s <- .le_synth(state, quarter, "12m")
  from_s <- .le_synth(state, from, "12m")
  data.frame(
    state = state,
    period = period,
    from_quarter = from,
    to_quarter = quarter,
    e0_synth_from = from_s$e0_synth,
    e0_synth_to = to_s$e0_synth,
    e0_change_years = to_s$e0_synth - from_s$e0_synth,
    rate_from_per_100k = from_s$rate_state_per_100k,
    rate_to_per_100k = to_s$rate_state_per_100k,
    rate_change_per_100k = to_s$rate_state_per_100k - from_s$rate_state_per_100k,
    estimate_type = "synthetic_e0 change (mortality-based D1b/D2 sensitivity synthesis)",
    source = to_s$source,
    level = to_s$level,
    degraded_from = NA_character_,
    mapping_vintage = NA_character_,
    provisional = TRUE,
    sensitivity_assumption = to_s$sensitivity_assumption,
    confidence_tier = .confidence_tier("C"),
    notes = paste(c(
      "both endpoints provisional (VSRR vintage may be revised); quarter-over-period differs from monthly series elsewhere in the package",
      if (nzchar(from_s$notes)) from_s$notes else character(0),
      if (nzchar(to_s$notes)) to_s$notes else character(0)
    ), collapse = " | "),
    stringsAsFactors = FALSE,
    row.names = NULL
  )
}
