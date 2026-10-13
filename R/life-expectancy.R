#' Average life expectancy for a ZIP code
#'
#' Returns the average life expectancy (years) for a US ZIP code.
#'
#' @param zip A character or numeric US ZIP code.
#' @param ... Reserved for future arguments.
#'
#' @return A data frame with the ZIP code and the average life expectancy.
#' @export
#'
#' @examples
#' \dontrun{
#' life_expectancy("32601")
#' }
life_expectancy <- function(zip, ...) {
  stop("life_expectancy() is not implemented yet.", call. = FALSE)
}

#' Change in life expectancy over time
#'
#' Returns the period-over-period change in average life expectancy for a US
#' ZIP code.
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
#' life_expectancy_trend("32601", period = "yoy")
#' }
life_expectancy_trend <- function(zip, period = c("yoy", "mom"), ...) {
  stop("life_expectancy_trend() is not implemented yet.", call. = FALSE)
}
