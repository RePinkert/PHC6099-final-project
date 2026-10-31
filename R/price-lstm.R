# price-lstm.R —— 预测 regime 的 LSTM 前向（纯 R，无 torch 依赖）
# 权重/变换：inst/extdata/price_lstm_fit.rds（model_traning 分支训练，冻结产物）
# 契约（$contract）：点 = 自写 LSTMCell(candidate=relu, hidden=64) 多视界直出 h=1..5；
#   区间 = 留出校准窗（目标月 2026-02..2026-07）相对残差视界分位数（跨州尺度标准化）；
#   .sd = price * abs_q85 / qnorm(0.925) 保留下游 bill 证据的高斯标度桥：abs_q85 是 |残差| 的
#   85% 分位，正态下 P(|e| <= k*sd) = 0.85 给 k = qnorm(0.925) ≈ 1.44（冻结 fit 的 contract
#   字符串写的是 qnorm(0.95)，那会把 sd 低估约 12.5%；以此处为准）。
# 特征通道（11）与训练侧 model_traning/prepare.R 同口径：
#   price_mm / mom_z / rel12_z / sin12 / cos12 / ann_mm / ann_mask / ann_age /
#   c1_z / c1_mask / c1_age —— 异频协变量（EIA-861 年、EIA-112 仅 2024）带
#   mask + age 通道，陈旧可信度由模型自 learn（弥合数据源时间窗口不统一）。

.price_lstm_fit <- local({
  cached <- NULL
  function() {
    if (!is.null(cached)) return(cached)
    path <- system.file("extdata", "price_lstm_fit.rds", package = "lifewatt")
    if (!nzchar(path)) {
      stop("LSTM fit not shipped: inst/extdata/price_lstm_fit.rds missing.", call. = FALSE)
    }
    cached <<- readRDS(path)
    cached
  }
})

.price_history_wide <- local({
  cached <- NULL
  function() {
    if (!is.null(cached)) return(cached)
    path <- system.file("extdata", "price_history_slim.csv.gz", package = "lifewatt")
    if (!nzchar(path)) {
      stop("price history not shipped: inst/extdata/price_history_slim.csv.gz missing.",
           call. = FALSE)
    }
    d <- utils::read.csv(path, stringsAsFactors = FALSE)
    sts <- sort(unique(d$state))
    pers <- sort(unique(d$period))
    m <- matrix(NA_real_, length(sts), length(pers), dimnames = list(sts, pers))
    m[cbind(match(d$state, sts), match(d$period, pers))] <- d$price
    stopifnot(all(is.finite(m)))
    cached <<- m
    cached
  }
})

## EIA-861 州年客户加权价：排除 Adjustment；Y 年值从 Y+1 年 10 月起可用
.ann_wide <- function(months) {
  a <- utils::read.csv(system.file("extdata", "eia861_annual_slim.csv.gz", package = "lifewatt"),
                       stringsAsFactors = FALSE)
  sts <- dimnames(.price_history_wide())[[1]]
  a <- a[a$eiaid != 99999 & is.finite(a$cus) & a$cus > 0, ]
  agg <- stats::aggregate(cbind(wsum = a$price * a$cus, cus = a$cus),
                          by = list(state = a$state, year = a$year), sum, na.rm = TRUE)
  V <- matrix(NA_real_, length(sts), length(months), dimnames = list(sts, months))
  for (i in seq_len(nrow(agg))) {
    si <- match(agg$state[i], sts)
    stamp <- sprintf("%04d-10", agg$year[i] + 1L)
    if (!is.na(si) && stamp %in% months) V[si, match(stamp, months)] <- agg$wsum[i] / agg$cus[i]
  }
  .ffill_age(V)
}

## EIA-112 断供 per-1k（仅 2024）：向前填充；通道语义同训练侧
.c1_wide <- function(months) {
  c1 <- utils::read.csv(system.file("extdata", "eia112_state_month_slim.csv.gz", package = "lifewatt"),
                        stringsAsFactors = FALSE)
  sts <- dimnames(.price_history_wide())[[1]]
  V <- matrix(NA_real_, length(sts), length(months), dimnames = list(sts, months))
  for (i in seq_len(nrow(c1))) {
    si <- match(c1$state[i], sts)
    if (!is.na(si) && c1$period[i] %in% months) {
      V[si, match(c1$period[i], months)] <- c1$disconnections_per_1k[i]
    }
  }
  .ffill_age(V)
}

.ffill_age <- function(V) {
  n <- ncol(V)
  ff <- t(apply(V, 1, function(x) {
    for (k in seq_along(x)) if (is.na(x[k]) && k > 1) x[k] <- x[k - 1]
    x
  }))
  mask <- ifelse(is.na(ff), 0, 1)
  ff[is.na(ff)] <- 0
  age <- t(apply(V, 1, function(x) {
    last <- NA_real_
    out <- rep(60, length(x))
    for (k in seq_along(x)) {
      if (!is.na(x[k])) last <- k
      if (!is.na(last)) out[k] <- min(k - last, 60)
    }
    out
  }))
  list(value = ff, mask = mask, age = age / 60)
}

## 36 x 11 特征窗（origin = 某月，窗口 = origin 前 36 个月含当月）
.lstm_feature_window <- function(state, origin) {
  fit <- .price_lstm_fit()
  Ph <- .price_history_wide()
  months <- dimnames(Ph)[[2]]
  o <- match(origin, months)
  if (is.na(o)) stop(sprintf("origin %s outside shipped price history.", origin), call. = FALSE)
  idx <- (o - fit$seq_len + 1):o
  if (min(idx) < 1) stop("price history too short for the LSTM input window.", call. = FALSE)
  win_months <- months[idx]
  s <- match(state, dimnames(Ph)[[1]])
  if (is.na(s)) stop(sprintf("state %s outside price history coverage.", state), call. = FALSE)
  p <- Ph[s, ]
  mm <- fit$transforms$price_minmax[[state]]
  zp <- fit$transforms$zpar

  mom <- c(NA_real_, p[-1] / p[-length(p)] - 1)
  rel12 <- rep(NA_real_, length(p))
  for (k in 12:length(p)) rel12[k] <- p[k] / mean(p[(k - 11):k]) - 1
  zz <- function(x, par) {
    x[!is.finite(x)] <- par[1]
    (x - par[1]) / par[2]
  }
  ann <- .ann_wide(months)
  c1v <- .c1_wide(months)
  ann_rng <- fit$transforms$ann_rng
  if (is.null(rownames(ann_rng))) {
    stop("LSTM fit corrupt: transforms$ann_rng lacks state rownames.", call. = FALSE)
  }
  rng <- ann_rng[state, ]
  ann_mm <- 2 * (ann$value[s, ] - rng[1]) / (rng[2] - rng[1]) - 1
  ann_mm[ann$mask[s, ] == 0] <- 0
  c1_z <- zz(c1v$value[s, ], zp$c1)
  c1_z[c1v$mask[s, ] == 0] <- 0

  mon <- as.integer(substr(win_months, 6, 7))
  w <- matrix(NA_real_, fit$seq_len, fit$n_chan)
  w[, 1] <- 2 * (p[idx] - mm$min) / (mm$max - mm$min) - 1
  w[, 2] <- zz(mom, zp$mom)[idx]
  w[, 3] <- zz(rel12, zp$rel12)[idx]
  w[, 4] <- sin(2 * pi * mon / 12)
  w[, 5] <- cos(2 * pi * mon / 12)
  w[, 6] <- ann_mm[idx]
  w[, 7] <- ann$mask[s, idx]
  w[, 8] <- ann$age[s, idx]
  w[, 9] <- c1_z[idx]
  w[, 10] <- c1v$mask[s, idx]
  w[, 11] <- c1v$age[s, idx]
  w
}

.lstm_sigmoid <- function(x) 1 / (1 + exp(-x))

## 纯 R 前向：X [n, 36, 11] -> Y_norm [n, 5]（逐状态 minmax 空间）
.lstm_forward_norm <- function(X) {
  fit <- .price_lstm_fit()
  W <- fit$weights
  hs <- fit$n_hidden
  n <- dim(X)[1]
  Hm <- matrix(0, n, hs)
  Cm <- matrix(0, n, hs)
  for (t in seq_len(dim(X)[2])) {
    xt <- matrix(X[, t, ], nrow = n, ncol = dim(X)[3])
    gates <- xt %*% t(W$w_ih) +
      matrix(W$b_ih, n, 4 * hs, byrow = TRUE) +
      Hm %*% t(W$w_hh) + matrix(W$b_hh, n, 4 * hs, byrow = TRUE)
    i <- .lstm_sigmoid(gates[, 1:hs, drop = FALSE])
    f <- .lstm_sigmoid(gates[, (hs + 1):(2 * hs), drop = FALSE])
    g <- pmax(gates[, (2 * hs + 1):(3 * hs), drop = FALSE], 0)
    o <- .lstm_sigmoid(gates[, (3 * hs + 1):(4 * hs), drop = FALSE])
    Cm <- f * Cm + i * g
    Hm <- o * pmax(Cm, 0)
  }
  sweep(Hm %*% t(W$w_out), 2, W$b_out, "+")
}

.lstm_denorm <- function(y_norm, state) {
  mm <- .price_lstm_fit()$transforms$price_minmax[[state]]
  (y_norm + 1) / 2 * (mm$max - mm$min) + mm$min
}

.lstm_month_h <- function(period) {
  y <- as.integer(substr(period, 1, 4)); m <- as.integer(substr(period, 6, 7))
  (y - 2026L) * 12L + (m - 7L)
}

## 对齐 .triplet_predict() 签名语义：返回 price / .sd（+ 诚实区间列）
.lstm_predict <- function(state, period) {
  if (length(state) != length(period)) {
    stop("state and period must be aligned vectors.", call. = FALSE)
  }
  state <- as.character(state)
  period <- vapply(as.character(period), .month_key, character(1), USE.NAMES = FALSE)
  fit <- .price_lstm_fit()
  h <- vapply(period, .lstm_month_h, integer(1), USE.NAMES = FALSE)
  if (any(h < 1L | h > fit$h_max)) {
    stop(sprintf(
      "LSTM forecast covers %s only (fit_as_of = %s, horizons 1..%d); got %s.",
      fit$forecast_window, fit$fit_as_of, fit$h_max,
      paste(unique(period[h < 1L | h > fit$h_max]), collapse = ", ")
    ), call. = FALSE)
  }
  miss <- setdiff(unique(state), dimnames(.price_history_wide())[[1]])
  if (length(miss)) {
    stop(sprintf("State(s) outside the LSTM fit coverage: %s.", paste(miss, collapse = ", ")),
         call. = FALSE)
  }
  iv <- fit$intervals
  out <- lapply(unique(state), function(s) {
    w <- .lstm_feature_window(s, fit$fit_as_of)
    yn <- .lstm_forward_norm(array(w, c(1, dim(w)[1], dim(w)[2])))
    pr_all <- .lstm_denorm(yn[1, ], s) * (1 + fit$point_bias)
    k <- which(state == s)
    hh <- h[k]
    data.frame(
      state = s, period = period[k], h = hh,
      price = pr_all[hh],
      .sd = pr_all[hh] * iv$abs_q85[hh] / stats::qnorm(0.925),
      q_lo = pr_all[hh] * (1 + iv$r_q05[hh]),
      q_hi = pr_all[hh] * (1 + iv$r_q95[hh]),
      stringsAsFactors = FALSE, row.names = NULL
    )
  })
  res <- do.call(rbind, out)
  res <- res[match(paste(state, period), paste(res$state, res$period)), , drop = FALSE]
  row.names(res) <- NULL
  res
}
