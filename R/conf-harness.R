# conf_harness.R —— 纯 R 重放器：给定任意冻结拟合，按 origin 重放 h=1..5 的点预测与真值
#
# 为什么要自己写而不用包内 .lstm_predict()：包内只服务"origin = fit_as_of"这一个发货场景；
# 置信度实验需要在**任意 origin**上重放（4 年窗口 = 48 个 origin），并且要能喂**候选拟合**
# （Stage A 的新权重），因此这里做一份与包内同口径的通用前向（同一 LSTM 结构、同一通道顺序）。
#
# 口径一致性由 conf_check_parity() 验证：用随包 v3 权重重放其校准窗，
# 复算出的分位数必须与 price_lstm_fit.rds$intervals 一致（容差 1e-6）。


## 州集合直接取自随包面板的 rownames（51 = 50 州 + DC），不依赖 datasets::state.abb

## extdata 目录：开发时用 "inst/extdata"，测试/安装后用 system.file("extdata", package="lifewatt")
conf_extdata <- function(root = ".") {
  if (dir.exists(file.path(root, "inst", "extdata"))) return(file.path(root, "inst", "extdata"))
  system.file("extdata", package = "lifewatt")
}

conf_load_panel <- function(root = ".", extdata = NULL) {
  if (is.null(extdata)) extdata <- conf_extdata(root)
  d <- utils::read.csv(file.path(extdata, "price_history_slim.csv.gz"),
                       stringsAsFactors = FALSE)
  months <- sort(unique(d$period))
  sts <- sort(unique(d$state))
  P <- matrix(NA_real_, length(sts), length(months), dimnames = list(sts, months))
  ok <- d$state %in% sts & is.finite(d$price)
  P[cbind(match(d$state[ok], sts), match(d$period[ok], months))] <- d$price[ok]
  stopifnot(all(is.finite(P)))
  P
}

## 年度相对通道（与 prepare.R::ann_rel_covariate 同口径）：Y 年州年价 / (Y+1 年 10 月发布前 12 个月月均价)
conf_ann_rel <- function(P, root = ".", extdata = NULL) {
  if (is.null(extdata)) extdata <- conf_extdata(root)
  agg <- utils::read.csv(file.path(extdata, "eia861_state_annual.csv.gz"),
                         stringsAsFactors = FALSE)
  months <- colnames(P)
  V <- matrix(NA_real_, nrow(P), ncol(P), dimnames = dimnames(P))
  for (i in seq_len(nrow(agg))) {
    si <- match(agg$state[i], rownames(P))
    j <- match(sprintf("%04d-10", agg$year[i] + 1L), months)
    if (!is.na(si) && !is.na(j) && j > 12) {
      V[si, j] <- log(agg$price[i] / mean(P[si, (j - 12):(j - 1)]))
    }
  }
  ff <- t(apply(V, 1, function(x) {
    for (k in seq_along(x)) if (is.na(x[k]) && k > 1) x[k] <- x[k - 1]
    x
  }))
  mask <- ifelse(is.na(ff), 0, 1)
  ff[is.na(ff)] <- 0
  age <- t(apply(V, 1, function(x) {
    last <- NA_real_; out <- rep(60, length(x))
    for (k in seq_along(x)) {
      if (!is.na(x[k])) last <- k
      if (!is.na(last)) out[k] <- min(k - last, 60)
    }
    out
  }))
  list(value = ff, mask = mask, age = age / 60)
}

## 特征窗（批量：一次算完该 origin 下全部州）-> array [n_states, seq_len, n_chan]
## 用拟合里存下来的 z 参数，不在别处重新 fit（与包内运行时同口径）。
conf_feature_batch <- function(fit, P, ann, states, origin) {
  months <- colnames(P)
  o <- match(origin, months)
  idx <- (o - fit$seq_len + 1):o
  win_months <- months[idx]
  mon <- as.integer(substr(win_months, 6, 7))
  zp <- fit$transforms$zpar
  zz <- function(x, par) { x[!is.finite(x)] <- par[1]; (x - par[1]) / par[2] }
  n <- length(states)
  W <- array(NA_real_, c(n, fit$seq_len, length(fit$chan_names)),
             dimnames = list(states, win_months, fit$chan_names))
  for (ii in seq_len(n)) {
    s <- states[ii]
    si <- match(s, rownames(P))
    p <- P[s, ]
    mom <- c(NA_real_, p[-1] / p[-length(p)] - 1)
    lrel12 <- rep(NA_real_, length(p))
    for (k in 12:length(p)) lrel12[k] <- log(p[k] / mean(p[(k - 11):k]))
    W[ii, , "lrel12_z"] <- zz(lrel12, zp$lrel12)[idx]
    W[ii, , "mom_z"] <- zz(mom, zp$mom)[idx]
    W[ii, , "sin12"] <- sin(2 * pi * mon / 12)
    W[ii, , "cos12"] <- cos(2 * pi * mon / 12)
    W[ii, , "ann_rel_z"] <- { x <- (ann$value[si, ] - zp$ann_rel[1]) / zp$ann_rel[2]
                              x[ann$mask[si, ] == 0] <- 0; x[idx] }
    W[ii, , "ann_mask"] <- ann$mask[si, idx]
    W[ii, , "ann_age"] <- ann$age[si, idx]
  }
  W
}

## 纯 R 前向：X [n, 36, n_chan] -> Y_norm [n, h_max]（结构与包内 .lstm_forward_norm 相同）
conf_forward_norm <- function(fit, X) {
  W <- fit$weights; hs <- fit$n_hidden; n <- dim(X)[1]
  Hm <- matrix(0, n, hs); Cm <- matrix(0, n, hs)
  sig <- function(x) 1 / (1 + exp(-x))
  for (t in seq_len(dim(X)[2])) {
    xt <- matrix(X[, t, ], nrow = n, ncol = dim(X)[3])
    gates <- xt %*% t(W$w_ih) + matrix(W$b_ih, n, 4 * hs, byrow = TRUE) +
      Hm %*% t(W$w_hh) + matrix(W$b_hh, n, 4 * hs, byrow = TRUE)
    i <- sig(gates[, 1:hs, drop = FALSE])
    f <- sig(gates[, (hs + 1):(2 * hs), drop = FALSE])
    g <- pmax(gates[, (2 * hs + 1):(3 * hs), drop = FALSE], 0)
    o <- sig(gates[, (3 * hs + 1):(4 * hs), drop = FALSE])
    Cm <- f * Cm + i * g
    Hm <- o * pmax(Cm, 0)
  }
  sweep(Hm %*% t(W$w_out), 2, W$b_out, "+")
}

## 归一空间 -> 绝对价（v3 为 logratio 目标：P_t * exp(mu + sd*y)）
conf_denorm <- function(fit, y_norm, p0) {
  tt <- fit$transforms$target
  h <- seq_along(y_norm)
  p0 * exp(tt$mu[h] + tt$sd[h] * y_norm)
}

## 重放：给定拟合与 origin 列表，返回每 (state, origin, h) 一行（按 origin 批量前向）
conf_replay <- function(fit, P, ann, origins, h_max = fit$h_max, verbose = TRUE) {
  months <- colnames(P)
  states <- rownames(P)
  rows <- list(); k <- 0L
  for (o in origins) {
    j <- match(o, months)
    if (is.na(j) || j - fit$seq_len + 1 < 1) stop("origin too early: ", o)
    X <- conf_feature_batch(fit, P, ann, states, o)
    yn <- conf_forward_norm(fit, X)
    for (ii in seq_along(states)) {
      pr <- conf_denorm(fit, yn[ii, ], P[states[ii], o])
      for (h in seq_len(h_max)) {
        tgt <- j + h
        if (tgt > ncol(P)) next
        k <- k + 1L
        rows[[k]] <- data.frame(state = states[ii], origin = o, h = h,
                                 target = months[tgt], pred = pr[h], true = P[states[ii], tgt],
                                 stringsAsFactors = FALSE)
      }
    }
    if (verbose) cat(sprintf("  replayed origin %s
", o))
  }
  out <- do.call(rbind, rows)
  ## 稳定性闸门：月度住宅电价不可能在 5 个月内变动超过 +-50%（相对 origin 月的观测价）。
  ## 非有限或越界的预测记为 **失败**（ok = FALSE）：评估时按"未覆盖"计，不允许被悄悄丢掉。
  lastv <- P[cbind(match(out$state, rownames(P)), match(out$origin, months))]
  out$last <- lastv
  out$ok <- is.finite(out$pred) & is.finite(out$true) &
    abs(out$pred / lastv - 1) <= 0.5
  out$rel <- ifelse(out$ok, (out$true - out$pred) / out$pred, NA_real_)
  out
}

## 一致性核查：用随包 v3 权重重放其校准窗，分位数必须复现 fit$intervals
conf_check_parity <- function(root = ".", tol = 1e-6, extdata = NULL) {
  if (is.null(extdata)) extdata <- conf_extdata(root)
  fit <- readRDS(file.path(extdata, "price_lstm_fit.rds"))
  P <- conf_load_panel(root, extdata); ann <- conf_ann_rel(P, root, extdata)
  months <- colnames(P)
  ## 与 model_traning/check_interval_coverage.R 同口径：origin 2025-06..2026-02，目标月 >= 2026-02
  origins <- months[match("2025-06", months):match("2026-02", months)]
  d <- conf_replay(fit, P, ann, origins, verbose = FALSE)
  d <- d[d$target >= "2026-02", ]
  q <- function(x, p) unname(stats::quantile(x, p))
  rep_iv <- do.call(rbind, lapply(1:5, function(h) {
    r <- d$rel[d$h == h]; ar <- abs(r)
    data.frame(h = h, n = length(r), r_q05 = q(r, .05), r_q95 = q(r, .95), abs_q85 = q(ar, .85))
  }))
  drift <- max(abs(as.matrix(rep_iv[, c("r_q05", "r_q95", "abs_q85")]) -
                      as.matrix(fit$intervals[, c("r_q05", "r_q95", "abs_q85")])))
  list(rep_iv = rep_iv, drift = drift, ok = drift < tol, fit = fit, replay = d)
}
