# phaseB triplet 预测的包内复刻（exp#33）。
# 契约来源：inst/extdata/price_forecast_fit.rds 的 $contract 字段（与参考实现 predict_fn 逐行等价）；
# 复刻偏差由 dev-only 回归测试钉死（tests/testthat/test-price-model.R，对账
# tests/testthat/fixtures/predict_fn_reference.R —— 该夹具是从研究树冻结出来的唯一副本）。
# 点 = mean{lag12+12m 漂移(exp#19), 末端水平 v0+b·h, HoltWinters(additive)};
# 区间 = 漂移口径 origin-sim + horizon 分桶(1..13) + 全州池化 q85（exp#22），n<40 桶退回 obs_max（exp#7）。

.triplet_predict <- function(state, period) {
  if (length(state) != length(period)) {
    stop("state and period must be aligned vectors.", call. = FALSE)
  }
  state <- as.character(state)
  period <- vapply(as.character(period), .month_key, character(1), USE.NAMES = FALSE)
  fit <- .price_fit()
  miss <- setdiff(unique(state), fit$states)
  if (length(miss)) {
    stop(sprintf("State(s) outside the phaseB fit coverage: %s.", paste(miss, collapse = ", ")),
         call. = FALSE)
  }
  params <- fit$params
  pv <- structure(params$v0, names = params$state)
  pb <- structure(params$b, names = params$state)
  pt <- structure(params$t0, names = params$state)
  hist <- .monthly_cache()

  tnow <- as.numeric(as.Date(paste0(period, "-01")))
  prev12 <- format(as.Date(paste0(period, "-01")) - 365.25, "%Y-%m")
  key <- paste(hist$state, hist$period)
  base <- structure(hist$price, names = key)

  basev <- base[paste(state, prev12)]
  drift_pred <- basev + pb[state] * (tnow - as.numeric(as.Date(paste0(prev12, "-01"))))
  h_num <- (tnow - pt[state]) / 30.44
  last_anchor <- pv[state] + pb[state] * (tnow - pt[state])
  hw_pred <- vapply(seq_along(state), function(i) {
    f <- fit$hw[[state[i]]]
    if (is.null(f)) return(NA_real_)
    unname(tryCatch(stats::predict(f, n.ahead = max(1, round(h_num[i])))[1],
                    error = function(e) NA_real_))
  }, numeric(1))
  mats <- cbind(drift_pred, last_anchor, hw_pred)
  n_ok <- rowSums(!is.na(mats))
  blended <- rowMeans(mats, na.rm = TRUE)
  blended[n_ok == 0] <- drift_pred[n_ok == 0]
  need <- is.na(blended)
  if (any(need)) {
    blended[need] <- pv[state[need]] + pb[state[need]] * (tnow[need] - pt[state[need]])
  }

  t0_map <- structure(params$t0, names = params$state)
  h_test <- (tnow - t0_map[state]) / 30.44
  sim_raw <- lapply(split(hist, hist$state), function(g) {
    g <- g[order(g$period), ]
    n <- nrow(g)
    if (n < 26) return(NULL)
    dates <- as.numeric(as.Date(paste0(g$period, "-01")))
    b_s <- pb[[g$state[1]]]
    rows <- list()
    for (o in 25:min(n, n - 2)) {
      for (h in 1:13) {
        j <- o + h
        if (j > n) break
        lag_p <- format(as.Date(dates[j], origin = "1970-01-01") - 365.25, "%Y-%m")
        lag_idx <- match(paste(g$state[o], lag_p), paste(g$state, g$period))
        if (is.na(lag_idx)) next
        pred <- g$price[lag_idx] + b_s * (dates[j] - dates[lag_idx])
        rows[[length(rows) + 1]] <-
          data.frame(state = g$state[1], h = h, resid = abs(g$price[j] - pred))
      }
    }
    do.call(rbind, rows)
  })
  sim <- do.call(rbind, Filter(is.data.frame, sim_raw))
  if (is.null(sim) || nrow(sim) == 0) stop("horizon sim empty", call. = FALSE)

  h_bin <- pmin(ceiling(h_test), 13)
  q_h <- tapply(sim$resid, sim$h, stats::quantile, probs = 0.85, na.rm = TRUE)
  n_h <- as.integer(table(sim$h))
  names(n_h) <- names(q_h)
  obs_max <- unname(max(q_h, na.rm = TRUE))
  qv <- unname(q_h[as.character(h_bin)])
  qv[is.na(qv)] <- obs_max
  for (i in seq_along(h_bin)) {
    hb <- as.character(h_bin[i])
    if (!hb %in% names(n_h) || n_h[[hb]] < 40) qv[i] <- obs_max
  }
  df <- data.frame(
    state = state, period = period, price = blended,
    stringsAsFactors = FALSE, row.names = NULL
  )
  df$.sd <- qv / stats::qnorm(0.95)  # 赋值式保留 1 维 array 的 dim，与 predict_fn 语义一致
  df
}
