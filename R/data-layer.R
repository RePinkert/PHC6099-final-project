# Package-side extdata readers (program.md 阶段 C: 包函数一律走 inst/extdata，禁止读 data-raw/)

.monthly_cache <- function() {
  path <- system.file("extdata", "b1_monthly_cache.csv", package = "lifewatt")
  if (!nzchar(path)) {
    stop("B1 cache not shipped: inst/extdata/b1_monthly_cache.csv missing.", call. = FALSE)
  }
  utils::read.csv(path, colClasses = c(state = "character", period = "character", price = "numeric"))
}

.price_fit <- function() {
  path <- system.file("extdata", "price_forecast_fit.rds", package = "lifewatt")
  if (!nzchar(path)) {
    stop("phaseB fit artifact not shipped: inst/extdata/price_forecast_fit.rds missing.", call. = FALSE)
  }
  readRDS(path)
}