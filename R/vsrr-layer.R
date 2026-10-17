# VSRR 数据层：随 life_expectancy() 一同落地，由 data-raw/assemble_vsrr_slim.R 一次性组装
# -> inst/extdata/vsrr_{state_quarter,national_age}_slim.csv.gz（data.cdc.gov 489q-934x）。
## VSRR（D1b 程序化替代源，exp#41）：州级全因季度死亡率 + 全国年龄组模式（crude only）。
## vintage：provisional 全行 TRUE；州年龄模式=全国为下游声明假设（源无州×年龄分解）。
.vsrr_state_cache <- local({
  m <- NULL
  function() {
    if (is.null(m)) {
      path <- system.file("extdata", "vsrr_state_quarter_slim.csv.gz", package = "lifewatt")
      if (!nzchar(path)) {
        stop("VSRR state slim not shipped: inst/extdata/vsrr_state_quarter_slim.csv.gz missing.", call. = FALSE)
      }
      m <<- utils::read.csv(path, colClasses = c(state = "character", quarter = "character"))
    }
    m
  }
})

.vsrr_age_cache <- local({
  m <- NULL
  function() {
    if (is.null(m)) {
      path <- system.file("extdata", "vsrr_national_age_slim.csv.gz", package = "lifewatt")
      if (!nzchar(path)) {
        stop("VSRR age slim not shipped: inst/extdata/vsrr_national_age_slim.csv.gz missing.", call. = FALSE)
      }
      m <<- utils::read.csv(path, colClasses = c(quarter = "character", age_band = "character"))
    }
    m
  }
})

.vsrr_state_rate <- function(state, quarter, period_type = c("12m", "3m"),
                             rate_type = c("age_adjusted", "crude")) {
  period_type <- match.arg(period_type)
  rate_type <- match.arg(rate_type)
  d <- .vsrr_state_cache()
  hit <- d[d$state == state & d$quarter == quarter &
             d$period_type == period_type & d$rate_type == rate_type, ]
  if (nrow(hit) != 1L) {
    stop(sprintf("VSRR has no %s/%s record for state %s at %s (window 2023Q1..2025Q3).",
                 period_type, rate_type, state, quarter), call. = FALSE)
  }
  hit
}

.vsrr_age_pattern <- function(quarter, period_type = c("12m", "3m")) {
  period_type <- match.arg(period_type)
  d <- .vsrr_age_cache()
  hit <- d[d$quarter == quarter & d$period_type == period_type, ]
  if (nrow(hit) != 10L) {
    stop(sprintf("VSRR national age pattern incomplete for %s/%s (expect 10 bands).",
                 period_type, quarter), call. = FALSE)
  }
  hit[order(match(hit$age_band, c("1-4", "5-14", "15-24", "25-34", "35-44", "45-54",
                                  "55-64", "65-74", "75-84", "85+"))), ]
}
