# electricity_price_trend() —— 电价趋势视图（实装自 exp#37；与 electricity_price() 同层，趋势差异按口径分列）。
# 年度同比 = A1 客户加权 ZIP 级年价差；月度环比 = B1 州级月频序列差（42 行）。
#' Change in average electricity price over time
#'
#' Year-over-year change of the customer-weighted ZIP-level annual price (EIA-861,
#' 2024 and 2025 rows), or month-over-month change of the B1 state-level monthly series
#' (42 rows; a flagged provisional change involves at least one provisional month).
#'
#' @param zip A character or numeric US ZIP code.
#' @param period One of `"yoy"` or `"mom"`.
#' @return A data.frame with the change (cents/kWh) and provenance columns. Positive
#'   change = price increase; negative = decrease.
#' @export
#'
#' @examples
#' \dontrun{
#' electricity_price_trend("32601", period = "yoy")
#' electricity_price_trend("32601", period = "mom")
#' }
electricity_price_trend <- function(zip, period = c("yoy", "mom")) {
  period <- match.arg(period)
  if (period == "yoy") {
    yrs <- .annual_years()
    ps <- lapply(yrs, function(y) .zip_annual_price(zip, y))
    out <- lapply(seq_along(yrs)[-1], function(i) {
      y <- yrs[i]
      data.frame(
        zip = .zip5(zip),
        state = ps[[i]]$state,
        year = y,
        prior_year = y - 1L,
        change = ps[[i]]$price - ps[[i - 1]]$price,
        pct_of_prior = (ps[[i]]$price - ps[[i - 1]]$price) / ps[[i - 1]]$price * 100,
        unit = "cents/kWh",
        n_priced = sprintf("%d(%d)/%d(%d)", ps[[i]]$n_priced, y, ps[[i - 1]]$n_priced, y - 1L),
        source = "EIA-861 annual diff (Bundled/Part A, customer-weighted; inst/extdata slim)",
        level = "utility (customer-weighted to zip)",
        degraded_from = "zip",
        mapping_vintage = "2024",
        provisional = FALSE,
        confidence_tier = .confidence_tier(if (ps[[i]]$n_priced == 1L && ps[[i - 1]]$n_priced == 1L) "A" else "B"),
        note = if (length(unique(vapply(ps, function(p) p$n_priced, integer(1)))) > 1L) {
          "priced-utility sets differ across years; per-year customer weighting keeps the blend honest but YoY comparability shifts"
        } else {
          ""
        },
        stringsAsFactors = FALSE,
        row.names = NULL
      )
    })
    return(do.call(rbind, out))
  }
  s <- .mom_series(zip)
  chg <- diff(s$price)
  n <- nrow(s)
  data.frame(
    zip = .zip5(zip),
    state = s$state[1],
    period = s$period[-1],
    prior_period = s$period[-n],
    change = as.numeric(chg),
    pct_of_prior = as.numeric(chg) / s$price[-n] * 100,
    unit = "cents/kWh",
    provisional = s$provisional[-1] | s$provisional[-n],
    source = "EIA retail-sales monthly diff (B1; inst/extdata cache)",
    level = "state",
    degraded_from = "zip",
    mapping_vintage = "2024",
    confidence_tier = .confidence_tier("B"),
    stringsAsFactors = FALSE,
    row.names = NULL
  )
}
