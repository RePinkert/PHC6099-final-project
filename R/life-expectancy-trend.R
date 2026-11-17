# life_expectancy_trend() —— exp#43 季度合成趋势（yoy|qoq；源为季度频，mom 诚实拒绝；W0 起收州）。
#' Change in synthetic life expectancy over time
#'
#' Quarter-over-period change in the [life_expectancy()] synthetic estimate:
#' `period = "yoy"` compares the same quarter a year earlier, `"qoq"` the
#' previous quarter. The death-rate source (CDC VSRR) is quarterly, so
#' `"mom"` is refused with an explanation. Shipped quarters run from 2023Q1 to
#' 2025Q3.
#'
#' Takes a state, not a ZIP code: the VSRR source is state-level.
#'
#' @param state A two-letter USPS state code (`"FL"`) or a full state name.
#' @param period One of `"yoy"` or `"qoq"` (case-insensitive).
#' @param quarter A quarter such as `"2024Q4"` (`"2024-Q4"` is also accepted);
#'   default: the latest VSRR quarter shipped.
#' @return A one-row data.frame with the from/to synthetic e0 values
#'   (`e0_synth_from`, `e0_synth_to`, as [life_expectancy()] reports them), the
#'   change and full provenance plus the `sensitivity_assumption` declaration.
#'
#'   `e0_change_years` is the change driven by the state's own death rates:
#'   the change in life expectancy of the state's synthetic life table between
#'   the two quarters. It moves opposite to `rate_change_per_100k` whenever
#'   the rate changes by more than a few deaths per 100,000; for smaller rate
#'   changes, a shift in the national age pattern of deaths can decide the
#'   sign, and the change is then a few hundredths of a year either way.
#'   `e0_synth_diff_years` is the plain difference of the two reported values.
#'   The two differ because each reported e0 is a national anchor plus the
#'   state's distance from the national rate: the anchor is a different NCHS
#'   year for 2023 and 2024 quarters (78.4 vs 79.0), and the national rate
#'   moves too, so `e0_synth_diff_years` mixes the state's change with the
#'   national one, and the two can even differ in sign. Use `e0_change_years`
#'   to ask whether the state itself improved. The earliest usable `quarter`
#'   is 2023Q2 for `"qoq"` and 2024Q1 for `"yoy"`.
#'   `rate_from_per_100k`, `rate_to_per_100k` and `rate_change_per_100k` are
#'   the state's age-adjusted death rates per 100,000 (12-month ending).
#' @export
#'
#' @examples
#' life_expectancy_trend("FL", period = "yoy")
#' life_expectancy_trend("FL", period = "qoq")
life_expectancy_trend <- function(state, period = c("yoy", "qoq"), quarter = NULL) {
  if (is.character(period) && length(period) == 1L) period <- tolower(trimws(period))
  if (identical(period, "mom")) {
    stop(paste0("period = \"mom\" is not available: the death-rate source (CDC VSRR) is quarterly. ",
                "Use \"qoq\" (previous quarter) or \"yoy\" (same quarter a year earlier)."), call. = FALSE)
  }
  period <- match.arg(period)
  state <- .state_code(state)
  if (is.null(quarter)) quarter <- .vsrr_latest_quarter()
  quarter <- .quarter_key(quarter)
  from <- .quarter_shift(quarter, if (period == "yoy") -4L else -1L)
  first_q <- min(.vsrr_state_cache()$quarter)
  if (from < first_q) {
    stop(sprintf(paste0(
      "%s for %s needs %s, which is before the first shipped quarter (%s). ",
      "The earliest usable quarter is %s for \"%s\"."),
      period, quarter, from, first_q, .quarter_shift(first_q, if (period == "yoy") 4L else 1L), period),
      call. = FALSE)
  }
  to_s <- .le_synth(state, quarter, "12m")
  from_s <- .le_synth(state, from, "12m")
  data.frame(
    state = state,
    period = period,
    from_quarter = from,
    to_quarter = quarter,
    e0_synth_from = from_s$e0_synth,
    e0_synth_to = to_s$e0_synth,
    e0_change_years = to_s$e1_synth - from_s$e1_synth,
    e0_synth_diff_years = to_s$e0_synth - from_s$e0_synth,
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
    notes = paste(unique(c(
      "both endpoints provisional (CDC VSRR death rates may be revised)",
      if (to_s$e0_anchor_year != from_s$e0_anchor_year) sprintf(paste0(
        "the national anchor changes between the endpoints (%d: %.1f -> %d: %.1f), so e0_synth_diff_years ",
        "includes that national shift; e0_change_years does not"),
        from_s$e0_anchor_year, from_s$e0_anchor, to_s$e0_anchor_year, to_s$e0_anchor) else character(0),
      if (nzchar(from_s$notes)) from_s$notes else character(0),
      if (nzchar(to_s$notes)) to_s$notes else character(0)
    )), collapse = " | "),
    stringsAsFactors = FALSE,
    row.names = NULL
  )
}
