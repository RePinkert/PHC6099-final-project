# electricity_price() —— 州级电价 accessor（实装自 exp#37；W0 起收州，不再收 ZIP）。
# 年度 = A1 州年价（客户加权，2023/2024/2025）＋该州 utility 范围；
# mom = B1 州级月频序列（2023-01→2026-07，provisional = EIA 标 Preliminary 的月份）。
# 本函数只收州码；ZIP 形状被指名拒绝（见 .state_code()）。

.mom_series <- function(state) {
  state <- .state_code(state)
  d <- .monthly_cache()
  rows <- d[d$state == state, ]
  rows <- rows[order(rows$period), ]
  if (nrow(rows) == 0L) {
    stop(sprintf("B1 cache has no rows for state %s.", state), call. = FALSE)
  }
  n <- nrow(rows)
  sp <- lapply(as.integer(substr(rows$period, 1L, 4L)), function(y) .within_state_spread(state, y))
  data.frame(
    state = rep(state, n),
    period = rows$period,
    price = rows$price,
    unit = "cents/kWh",
    price_sd = rep(NA_real_, n),
    regime = rep("observed", n),
    provisional = rows$data_status == "Preliminary",
    fit_as_of = rep(NA_character_, n),
    source = rep("EIA retail-sales monthly (B1; inst/extdata cache)", n),
    level = rep("state", n),
    degraded_from = rep(NA_character_, n),
    mapping_vintage = rep(NA_character_, n),
    within_state_sd = vapply(sp, function(x) x$sd, numeric(1)),
    n_utility = vapply(sp, function(x) as.integer(x$n_utility), integer(1)),
    n_utility_year = vapply(sp, function(x) as.integer(x$year), integer(1)),
    confidence_tier = rep(.confidence_tier("B"), n),
    stringsAsFactors = FALSE,
    row.names = NULL
  )
}

#' Average residential electricity price for a state
#'
#' Returns the state-level residential electricity price. The annual value is
#' the customer-weighted mean of the state's EIA-861 utility prices (final
#' releases 2023-2025), with the cheapest and dearest utility in the state
#' reported alongside it (only utilities with at least 100 residential
#' customers count for that range, so a retailer with a handful of customers
#' cannot set it); the monthly series is the B1 state-level retail-sales
#' cache (2023-01 to 2026-07), and months EIA marks Preliminary are provisional.
#'
#' This function takes a state, not a ZIP code: no source publishes a realised
#' average residential price per ZIP, so every ZIP in a state would return the
#' same number. Read `price_min` / `price_max` (annual row) or `within_state_sd`
#' (monthly rows) as the
#' declared distance between the state value and the utilities inside it.
#'
#' @param state A two-letter USPS state code (`"FL"`) or a full state name
#'   (`"Florida"`). A ZIP code is refused by name, because it would promise a
#'   granularity the data do not have.
#' @param year A single integer year (2023-2025) for the state-level annual
#'   estimate.
#' @param period Pass `"mom"` for the state-level monthly series (43 rows).
#' @return A data.frame with the price (cents/kWh), the provenance columns
#'   (`source`/`level`/`degraded_from`/`mapping_vintage`/`provisional`) and a
#'   `confidence_tier` label; one row for the annual regime (with `price_min`
#'   and `price_max`, the cheapest and dearest utility among those with at
#'   least 100 residential customers, `n_utility_in_range` for how many those
#'   are, and `n_utility` for all priced utilities behind `price`), 43 rows for the
#'   monthly series (with `within_state_sd`, the customer-weighted spread of
#'   utility prices inside the state, `n_utility`, and `n_utility_year`, the
#'   EIA-861 year those two come from: the latest released year not after the
#'   month).
#'
#'   The annual price and the monthly series are built differently: the annual
#'   value is a customer-weighted mean of utility prices, the monthly value is
#'   state revenue divided by state sales. In most states they agree within a
#'   few percent, but in some they sit up to about 16% apart on a yearly average (Texas 2024: 12.9 annual vs
#'   15.0 monthly average), so compare like with like.
#' @seealso [electricity_price_trend()], [my_electricity()]
#' @export
#'
#' @examples
#' electricity_price("FL", year = 2024)
#' electricity_price("FL", period = "mom")
#' electricity_price("Florida", year = 2024)
electricity_price <- function(state, year = NULL, period = NULL) {
  if (is.null(year) && is.null(period)) {
    stop(paste0("Provide either year (2023-2025 annual, state-level) or period = \"mom\" ",
                "(state monthly series)."), call. = FALSE)
  }
  if (!is.null(year) && !is.null(period)) {
    stop("Provide year OR period, not both.", call. = FALSE)
  }
  state <- .state_code(state)
  if (!is.null(year)) return(.state_annual_price(state, year))
  if (is.character(period) && length(period) == 1L) period <- tolower(trimws(period))
  if (!identical(period, "mom")) {
    stop(sprintf("Unknown period: %s (expects 'mom').", period), call. = FALSE)
  }
  .mom_series(state)
}
