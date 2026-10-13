#' Average residential electricity price for a ZIP code
#'
#' Returns the area-average residential electricity price (USD per kWh) for a
#' US ZIP code.
#'
#' @param zip A character or numeric US ZIP code.
#' @param ... Reserved for future arguments.
#'
#' @return A data frame with the ZIP code and the average electricity price.
#' @export
#'
#' @examples
#' \dontrun{
#' electricity_price("32601")
#' }
electricity_price <- function(zip, ...) {
  stop("electricity_price() is not implemented yet.", call. = FALSE)
}

#' Change in average electricity price over time
#'
#' Returns the period-over-period change in the average residential electricity
#' price for a US ZIP code.
#'
#' @param zip A character or numeric US ZIP code.
#' @param period One of `"yoy"` (year over year) or `"mom"` (month over month).
#' @param ... Reserved for future arguments.
#'
#' @return A data frame with the ZIP code and the requested trend.
#' @export
#'
#' @examples
#' \dontrun{
#' electricity_price_trend("32601", period = "yoy")
#' }
electricity_price_trend <- function(zip, period = c("yoy", "mom"), ...) {
  stop("electricity_price_trend() is not implemented yet.", call. = FALSE)
}
