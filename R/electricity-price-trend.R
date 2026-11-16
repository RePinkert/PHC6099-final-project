# electricity_price_trend() —— 电价趋势视图（实装自 exp#37；W0 起收州）。
# 年度同比 = A1 州年价差（客户加权）；月度环比 = B1 州级月频序列差（42 行）。
#' Change in average electricity price over time
#'
#' Year-over-year change of the state-level annual price (EIA-861, 2024 and 2025
#' against their prior year), or month-over-month change of the B1 state-level
#' monthly series (42 rows; a flagged provisional change involves at least one
#' provisional month).
#'
#' Takes a state, not a ZIP code: see [electricity_price()] for why, and
#' [zip_to_state()] to resolve a ZIP.
#'
#' @param state A two-letter USPS state code (`"FL"`) or a full state name.
#' @param period One of `"yoy"` or `"mom"`.
#' @return A data.frame with the change (cents/kWh) and provenance columns.
#'   Positive change = price increase; negative = decrease. The year-over-year
#'   rows also carry `n_utility` and `n_utility_prior`, because the set of
#'   priced utilities can differ between the two years.
#' @export
#'
#' @examples
#' \dontrun{
#' electricity_price_trend("FL", period = "yoy")
#' electricity_price_trend("FL", period = "mom")
#' }
electricity_price_trend <- function(state, period = c("yoy", "mom")) {
  period <- match.arg(period)
  state <- .state_code(state)
  if (period == "yoy") {
    yrs <- .annual_years()
    ps <- lapply(yrs, function(y) .state_annual_price(state, y))
    out <- lapply(seq_along(yrs)[-1], function(i) {
      y <- yrs[i]
      data.frame(
        state = state,
        year = y,
        prior_year = y - 1L,
        change = ps[[i]]$price - ps[[i - 1]]$price,
        pct_of_prior = (ps[[i]]$price - ps[[i - 1]]$price) / ps[[i - 1]]$price * 100,
        unit = "cents/kWh",
        n_utility = ps[[i]]$n_utility,
        n_utility_prior = ps[[i - 1]]$n_utility,
        source = "EIA-861 annual diff (Bundled/Part A; inst/extdata slim)",
        level = "state",
        degraded_from = NA_character_,
        mapping_vintage = NA_character_,
        provisional = FALSE,
        confidence_tier = .confidence_tier("B"),
        note = if (length(unique(vapply(ps, function(p) p$n_utility, integer(1)))) > 1L) {
          "priced-utility sets differ across years; per-year customer weighting keeps each state value honest but YoY comparability shifts"
        } else {
          ""
        },
        stringsAsFactors = FALSE,
        row.names = NULL
      )
    })
    return(do.call(rbind, out))
  }
  s <- .mom_series(state)
  chg <- diff(s$price)
  n <- nrow(s)
  data.frame(
    state = s$state[1],
    period = s$period[-1],
    prior_period = s$period[-n],
    change = as.numeric(chg),
    pct_of_prior = as.numeric(chg) / s$price[-n] * 100,
    unit = "cents/kWh",
    provisional = s$provisional[-1] | s$provisional[-n],
    source = "EIA retail-sales monthly diff (B1; inst/extdata cache)",
    level = "state",
    degraded_from = NA_character_,
    mapping_vintage = NA_character_,
    confidence_tier = .confidence_tier("B"),
    stringsAsFactors = FALSE,
    row.names = NULL
  )
}
