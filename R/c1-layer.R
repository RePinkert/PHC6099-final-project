# C1 断供机制层（Form EIA-112, 2024）：随 expected_life_loss() 一同落地，
# 由 data-raw/assemble_112_slim.R 一次性组装 -> inst/extdata/eia112_state_month_slim.csv.gz。
## C1 (Form EIA-112, 2024) 断供机制层（exp#39）：State Total 口径（utility 报告值 + State Adjustment）
.c1_cache <- local({
  m <- NULL
  function() {
    if (is.null(m)) {
      path <- system.file("extdata", "eia112_state_month_slim.csv.gz", package = "lifewatt")
      if (!nzchar(path)) {
        stop("EIA-112 slim not shipped: inst/extdata/eia112_state_month_slim.csv.gz missing.", call. = FALSE)
      }
      m <<- utils::read.csv(path, colClasses = c(state = "character", period = "character"))
    }
    m
  }
})

## 覆盖窗口 = 2024-01..2024-12（调查未延展）；窗口外回 NA 行，由调用方注记
.c1_at <- function(state, period) {
  d <- .c1_cache()
  hit <- d[d$state == state & d$period == period, ]
  if (nrow(hit) == 1L) {
    data.frame(
      c1_final_notices_per_1k = hit$final_notices_per_1k,
      c1_disconnections_per_1k = hit$disconnections_per_1k,
      c1_reconnections_per_1k = hit$reconnections_per_1k,
      c1_res_customers = hit$res_customers,
      c1_source = hit$source,
      stringsAsFactors = FALSE
    )
  } else {
    data.frame(
      c1_final_notices_per_1k = NA_real_,
      c1_disconnections_per_1k = NA_real_,
      c1_reconnections_per_1k = NA_real_,
      c1_res_customers = NA_real_,
      c1_source = NA_character_,
      stringsAsFactors = FALSE
    )
  }
}

.c1_note <- function(state, period) {
  d <- .c1_cache()
  hit <- d[d$state == state & d$period == period, ]
  if (nrow(hit) == 1L) {
    sprintf("C1 mechanism (Form EIA-112 State Total, 2024): disconnections %.2f per 1k residential customers",
            hit$disconnections_per_1k)
  } else {
    sprintf("C1 mechanism not available at %s (EIA-112 covers 2024 only; survey not extended)",
            period)
  }
}
