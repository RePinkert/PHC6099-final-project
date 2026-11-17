#' lifewatt: Environmental Justice Indicators by US State and ZCTA
#'
#' `lifewatt` reports environmental justice indicators at the granularity each
#' source publishes. By **state** (two-letter code or full name): residential
#' electricity price with year-over-year and month-over-month trends, recent
#' price features and lags, a forecast with an interval, bill-based evidence,
#' a synthetic life expectancy with its trends, and an optional declared
#' life-expectancy loss. By **ZIP code** (matched to its ZCTA): CDC PLACES
#' adult health prevalence via [health_measure()], the only function that
#' takes a ZIP.
#'
#' Exported functions: [electricity_price()], [electricity_price_trend()],
#' [price_features()], [lag_matrix()], [my_electricity()],
#' [expected_life_loss()], [life_expectancy()], [life_expectancy_trend()],
#' [health_measure()].
#'
#' @keywords internal
"_PACKAGE"
