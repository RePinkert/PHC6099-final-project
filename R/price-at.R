# Internal price estimator `.price_at(state, time)`（exp#32 实测分支，exp#33 补预测分支；W0 起收州）
# 口径：returns the state-level residential price at a month.
# B1 cache units = cents/kWh；provisional = EIA-861M 标 Preliminary（EIA 将回改，输出必须声明）。
# 时间归一化：YYYY-MM 字符串、YYYY-M、"YYYY/MM"、Date；标量调用（mock 契约）。
# W0：输入是州，不是 ZIP。`zip`、`utilities`、`weight_note` 三列随之消失，
#     `degraded_from` 从 "zip" 变为 NA（不再有降级可声明），`n_utility` 改为该州的家数。

.month_key <- function(time) {
  if (length(time) != 1L) stop("time expects exactly one value.", call. = FALSE)
  if (inherits(time, "Date")) {
    t <- format(time, "%Y-%m")
  } else {
    t <- as.character(time)
    if (grepl("^[0-9]{4}[/-][0-9]{1,2}$", t)) {
      t <- paste0(substr(t, 1L, 4L), "-", sprintf("%02d", as.integer(gsub("[^0-9]", "", substr(t, 6L, nchar(t))))))
    }
  }
  if (!grepl("^[0-9]{4}-[0-9]{2}$", t)) {
    stop(sprintf("Invalid time: %s (expects YYYY-MM, YYYY/MM or Date).", time), call. = FALSE)
  }
  m <- as.integer(substr(t, 6L, 7L))
  if (m < 1L || m > 12L) {
    stop(sprintf("Invalid month: %s.", t), call. = FALSE)
  }
  t
}

.price_at <- function(state, time) {
  fit <- .price_fit()
  state <- .state_code(state)
  period <- .month_key(time)
  cutoff <- fit$fit_as_of
  if (period > "2026-12") {
    stop(sprintf(paste0("time %s is outside the supported window (2023-01..2026-12); ",
                        "the forecast regime stops at 2026-12 (fit_as_of = %s, intervals ",
                        "calibrated for horizons <= 13 months)."), period, cutoff),
         call. = FALSE)
  }
  spread <- .within_state_spread(state, as.integer(substr(period, 1L, 4L)))
  if (period > cutoff) {
    pr <- .lstm_predict(state, period)
    ## 区间：随包台账量的是 |r| <= abs_q85 这条带（与 price_sd 同口径）；
    ## .lstm_predict() 里 r_q05/r_q95 那条带没有随包覆盖台账 -> 不外发，只发这一条。
    half <- pr$.sd * stats::qnorm(0.925)   # = price * abs_q85[h]
    return(data.frame(
      state = state,
      period = period,
      price = pr$price,
      unit = "cents/kWh",
      price_sd = pr$.sd,
      price_lo = pmax(0, pr$price - half),
      price_hi = pr$price + half,
      price_interval_basis = .interval_basis(),
      regime = "predicted",
      provisional = NA,
      fit_as_of = cutoff,
      source = "LSTM price forecast (multi-horizon h=1..5; relative-residual horizon intervals, calibration window 2026-02..2026-07)",
      level = "state",
      degraded_from = NA_character_,
      mapping_vintage = NA_character_,
      within_state_sd = spread$sd,
      n_utility = spread$n_utility,
      confidence_tier = .confidence_tier("C"),
      stringsAsFactors = FALSE,
      row.names = NULL
    ))
  }
  d <- .monthly_cache()
  row <- d[d$state == state & d$period == period, ]
  if (nrow(row) == 0L) {
    stop(sprintf("B1 cache has no record for state %s at %s (observed window 2023-01 -> %s).",
                 state, period, cutoff), call. = FALSE)
  }
  if (!is.finite(row$price) || row$price <= 0) {
    stop(sprintf("B1 cache price invalid for %s at %s; refusing to build evidence on it.",
                 state, period), call. = FALSE)
  }
  data.frame(
    state = state,
    period = period,
    price = row$price,
    unit = "cents/kWh",
    price_sd = NA_real_,
    price_lo = NA_real_,
    price_hi = NA_real_,
    price_interval_basis = NA_character_,
    regime = "observed",
    provisional = row$data_status == "Preliminary",
    fit_as_of = NA_character_,
    source = "EIA retail-sales monthly (B1; inst/extdata cache)",
    level = "state",
    degraded_from = NA_character_,
    mapping_vintage = NA_character_,
    within_state_sd = spread$sd,
    n_utility = spread$n_utility,
    confidence_tier = .confidence_tier("B"),
    stringsAsFactors = FALSE,
    row.names = NULL
  )
}
