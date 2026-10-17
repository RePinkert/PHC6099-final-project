# electricity_price() —— ZIP 级电价 accessor（实装自 exp#37；本文件只放本函数，
# electricity_price_trend() 独立成 R/electricity-price-trend.R 以便按函数分片落地）。
# mock 意向：expected_life_loss/my_electricity 是正门，这里保持可用的探索性 accessor。
# 年度 = A1×A2（客户数加权，zip 级 2023/2024/2025）；mom = B1 州级月频序列（2023-01→2026-07，2025-01 起 provisional）。

.mom_series <- function(zip) {
  zs <- .zip_state(zip)
  d <- .monthly_cache()
  rows <- d[d$state == zs$state, ]
  rows <- rows[order(rows$period), ]
  if (nrow(rows) == 0L) {
    stop(sprintf("B1 cache has no rows for state %s.", zs$state), call. = FALSE)
  }
  n <- nrow(rows)
  data.frame(
    zip = rep(.zip5(zip), n),
    state = rep(zs$state, n),
    utilities = rep(paste(zs$utilities$utility_name, collapse = "; "), n),
    n_utility = rep(zs$n_utility, n),
    period = rows$period,
    price = rows$price,
    unit = "cents/kWh",
    price_sd = rep(NA_real_, n),
    regime = rep("observed", n),
    provisional = rows$period >= "2025-01",
    fit_as_of = rep(NA_character_, n),
    source = rep("EIA retail-sales monthly (B1; inst/extdata cache)", n),
    level = rep("state", n),
    degraded_from = rep("zip", n),
    mapping_vintage = rep("2024", n),
    weight_note = rep(zs$note, n),
    stringsAsFactors = FALSE,
    row.names = NULL
  )
}

#' Average residential electricity price for a ZIP code
#'
#' Returns the residential electricity price estimate for the utility territory a US
#' ZIP code belongs to. The annual ZIP-level estimate is a residential-customer-weighted
#' blend of EIA-861 utility prices (final releases 2023-2025) over the utilities the
#' OpenEI 2024 mapping assigns to the ZIP. The monthly series is the B1 state-level
#' retail-sales cache (2023-01 to 2026-07); months from 2025-01 onward are provisional
#' and flagged.
#'
#' @param zip A character or numeric US ZIP code.
#' @param year A single integer year (2023-2025) for the ZIP-level annual estimate.
#' @param period Pass `"mom"` for the state-level monthly series of the ZIP (43 rows).
#' @return A data.frame with the price (cents/kWh) and provenance columns
#'   (source/level/degraded_from/mapping_vintage/provisional); one row for the annual
#'   regime, 43 rows for the monthly series.
#' @export
#'
#' @examples
#' \dontrun{
#' electricity_price("32601", year = 2024)
#' electricity_price("32601", period = "mom")
#' }
electricity_price <- function(zip, year = NULL, period = NULL) {
  if (is.null(year) && is.null(period)) {
    stop("Provide either year (2023-2025 annual ZIP-level) or period = \"mom\" (state monthly series).",
         call. = FALSE)
  }
  if (!is.null(year) && !is.null(period)) {
    stop("Provide year OR period, not both.", call. = FALSE)
  }
  if (!is.null(year)) return(.zip_annual_price(zip, year))
  if (!identical(period, "mom")) {
    stop(sprintf("Unknown period: %s (expects 'mom').", period), call. = FALSE)
  }
  .mom_series(zip)
}