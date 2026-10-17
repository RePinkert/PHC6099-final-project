# life_expectancy_trend() —— 桩（本片未实装；实装随下一片分发）。
# 保持 NAMESPACE 导出面不缩水：life_expectancy 已实装而本函数仍是桩，
# 因此这里原样保留 develop 的占位实现，直到实现落地为止。

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