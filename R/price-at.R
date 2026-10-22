# Internal price estimator `.price_at(zip, time)`（exp#32 实测分支，exp#33 补预测分支）
# 口径：returns the state-level residential price at a month for the utility territory a zip belongs to.
# B1 cache units = cents/kWh；provisional 若 period >= 2025-01（EIA 将回改，输出必须声明）。
# 时间归一化：YYYY-MM 字符串、YYYY-M、"YYYY/MM"、Date；标量调用（mock 契约）。

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

.price_at <- function(zip, time) {
  fit <- .price_fit()
  period <- .month_key(time)
  cutoff <- fit$fit_as_of
  if (period > "2026-12") {
    stop(sprintf(paste0("time %s is outside the supported window (2023-01..2026-12); ",
                        "the forecast regime stops at 2026-12 (fit_as_of = %s, intervals ",
                        "calibrated for horizons <= 13 months)."), period, cutoff),
         call. = FALSE)
  }
  zs <- .zip_state(zip)
  if (period > cutoff) {
    pr <- .triplet_predict(zs$state, period)
    return(data.frame(
      zip = .zip5(zip),
      state = zs$state,
      utilities = paste(zs$utilities$utility_name, collapse = "; "),
      n_utility = zs$n_utility,
      period = period,
      price = pr$price,
      unit = "cents/kWh",
      price_sd = pr$.sd,
      regime = "predicted",
      provisional = NA,
      fit_as_of = cutoff,
      source = "phaseB triplet forecast (HoltWinters additive + drift ensemble + lag12 drift; q85 horizon-binned pooled interval)",
      level = "state",
      degraded_from = "zip",
      mapping_vintage = "2024",
      weight_note = zs$note,
      stringsAsFactors = FALSE,
      row.names = NULL
    ))
  }
  d <- .monthly_cache()
  row <- d[d$state == zs$state & d$period == period, ]
  if (nrow(row) == 0L) {
    stop(sprintf("B1 cache has no record for state %s at %s (observed window 2023-01 -> %s).",
                 zs$state, period, cutoff), call. = FALSE)
  }
  if (!is.finite(row$price) || row$price <= 0) {
    stop(sprintf("B1 cache price invalid for %s at %s; refusing to build evidence on it.",
                 zs$state, period), call. = FALSE)
  }
  data.frame(
    zip = .zip5(zip),
    state = zs$state,
    utilities = paste(zs$utilities$utility_name, collapse = "; "),
    n_utility = zs$n_utility,
    period = period,
    price = row$price,
    unit = "cents/kWh",
    price_sd = NA_real_,
    regime = "observed",
    provisional = period >= "2025-01",
    fit_as_of = NA_character_,
    source = "EIA retail-sales monthly (B1; inst/extdata cache)",
    level = "state",
    degraded_from = "zip",
    mapping_vintage = "2024",
    weight_note = zs$note,
    stringsAsFactors = FALSE,
    row.names = NULL
  )
}
