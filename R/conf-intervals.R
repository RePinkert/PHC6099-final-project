# conf_intervals.R —— 区间构造族（置信度目标的可优化对象）
#
# 全部构造都遵守同一条纪律：**参数只用参考集（ref）估，应用只用目标集（d）**；
# ref 与 d 的月份不相交，由 conf_protocol.R 的前向链保证。
#
# 命名与语义：
#   shipped          随包口径：逐 horizon 相对残差的经验分位数（r_q05/r_q95）
#   conformal_asym   有限样本（conformal）分位秩的上下侧构造，保证边缘覆盖 >= 名义值
#   conformal_sym    有限样本的绝对残差对称带
#   scaled_*         先用"仅 origin 及之前可见"的尺度（近 12 月波动）归一化再 conformal，
#                    得到**条件覆盖**（波动大的州区间更宽）
#   bias_*           先按 ref 的逐 horizon 中位偏差校正点预测，再 conformal；
#                    （随包 v3 曾试过偏差校正，但在早停窗上估计、方向相反而失败——那是
#                      "用错窗口估参数"的嵌套问题；这里强制在 ref 内前向链估计）
#
# 尺度（scale）只用 origin 及之前的数据：
#   vol12 = 该州 origin 前 13 个月价格的 12 个对数变化的 sd（>0 才用，否则回退 pooled 中位数）

conf_scale_col <- "scale_vol12"

## 给 replay 表附加尺度列（只用到 origin 及之前的价格）
conf_add_scale <- function(d, P) {
  months <- colnames(P)
  s <- rep(NA_real_, nrow(d))
  for (i in seq_len(nrow(d))) {
    j <- match(d$origin[i], months)
    if (is.na(j) || j < 13) { s[i] <- NA_real_; next }
    p <- P[d$state[i], (j - 12):j]
    s[i] <- stats::sd(diff(log(p)))
  }
  d[[conf_scale_col]] <- s
  ## 归一化为**相对倍数**（中位数 = 1）：scaled_* 构造要的是"谁更波动"，不是绝对波动率；
  ## 直接拿绝对 sd 当除数会把标准化残差放大 30 倍，区间宽度失真。
  med <- stats::median(s[is.finite(s)])
  if (!is.finite(med) || med <= 0) med <- 1
  d[[conf_scale_col]][!is.finite(d[[conf_scale_col]])] <- med
  d[[conf_scale_col]] <- d[[conf_scale_col]] / med
  d
}

## 逐 horizon 的经验/有限样本分位数
conf_q_empirical <- function(x, p) unname(stats::quantile(x, p, na.rm = TRUE))
conf_q_finite <- function(x, p) conf_finite_quantile(x, p)

## 拟合区间参数（ref: 含 h, rel[, scale, rel_corr]）
conf_fit_iv <- function(ref, method = "shipped", nominal = CONF_NOMINAL, shrink_k = 10) {
  alpha <- 1 - nominal
  hs <- sort(unique(ref$h))
  par <- list()
  for (h in hs) {
    d <- ref[ref$h == h, ]
    p <- switch(method,
      shipped = {
        list(lo = conf_q_empirical(d$rel, alpha / 2),
             hi = conf_q_empirical(d$rel, 1 - alpha / 2),
             abs = conf_q_empirical(abs(d$rel), nominal),
             bias = conf_q_empirical(d$rel, 0.5))
      },
      conformal_asym = {
        list(lo = conf_q_finite(d$rel, alpha / 2),
             hi = conf_q_finite(d$rel, 1 - alpha / 2),
             abs = conf_q_finite(abs(d$rel), nominal),
             bias = conf_q_empirical(d$rel, 0.5))
      },
      conformal_sym = {
        q <- conf_q_finite(abs(d$rel), nominal)
        list(lo = -q, hi = q, abs = q, bias = conf_q_empirical(d$rel, 0.5))
      },
      scaled_conformal = {
        z <- d$rel / d[[conf_scale_col]]
        list(lo = conf_q_finite(z, alpha / 2), hi = conf_q_finite(z, 1 - alpha / 2),
             abs = conf_q_finite(abs(z), nominal), bias = conf_q_empirical(d$rel, 0.5))
      },
      bias_conformal = {
        b <- conf_q_empirical(d$rel, 0.5)
        rc <- (d$true - d$pred * (1 + b)) / (d$pred * (1 + b))
        list(lo = conf_q_finite(rc, alpha / 2), hi = conf_q_finite(rc, 1 - alpha / 2),
             abs = conf_q_finite(abs(rc), nominal), bias = b)
      },
      bias_scaled_conformal = {
        b <- conf_q_empirical(d$rel, 0.5)
        rc <- (d$true - d$pred * (1 + b)) / (d$pred * (1 + b))
        z <- rc / d[[conf_scale_col]]
        list(lo = conf_q_finite(z, alpha / 2), hi = conf_q_finite(z, 1 - alpha / 2),
             abs = conf_q_finite(abs(z), nominal), bias = b)
      },
      shrunk_state = {
        ## 逐州残差尺度，按 n_s 收缩到 pooled（Mondrian 式的稳定化）
        sp <- split(d, d$state)
        v <- vapply(sp, function(x) stats::sd(x$rel), numeric(1))
        nn <- vapply(sp, length, integer(1))
        pooled <- stats::sd(d$rel)
        s <- sqrt((nn / (nn + shrink_k)) * v^2 + (shrink_k / (nn + shrink_k)) * pooled^2)
        list(lo = conf_q_finite(d$rel / s[match(d$state, names(s))], alpha / 2),
             hi = conf_q_finite(d$rel / s[match(d$state, names(s))], 1 - alpha / 2),
             abs = conf_q_finite(abs(d$rel) / s[match(d$state, names(s))], nominal),
             bias = conf_q_empirical(d$rel, 0.5),
             state_scale = s)
      },
      stop("unknown method: ", method))
    par[[as.character(h)]] <- p
  }
  list(method = method, nominal = nominal, par = par, n_ref = nrow(ref))
}

## 应用区间参数到目标集
conf_apply_iv <- function(fit, d) {
  lo <- rep(NA_real_, nrow(d)); hi <- rep(NA_real_, nrow(d))
  for (i in seq_len(nrow(d))) {
    p <- fit$par[[as.character(d$h[i])]]
    base <- d$pred[i] * (1 + p$bias)
    if (grepl("scaled", fit$method) || fit$method == "shrunk_state") {
      s <- if (!is.null(p$state_scale)) p$state_scale[[d$state[i]]] else d[[conf_scale_col]][i]
      lo[i] <- base * (1 + p$lo * s); hi[i] <- base * (1 + p$hi * s)
    } else {
      lo[i] <- base * (1 + p$lo); hi[i] <- base * (1 + p$hi)
    }
  }
  d$lo <- lo; d$hi <- hi
  d
}

## 单个 horizon 的对称带（随包 .sd 口径：abs_q85 / qnorm(0.925)）
conf_apply_sd_band <- function(ref, d) {
  sd_ <- numeric(length(unique(d$h)))
  for (h in sort(unique(d$h))) {
    r <- ref$rel[ref$h == h]
    q <- conf_q_empirical(abs(r), 0.85)
    sd_[as.character(h)] <- q / stats::qnorm(0.925)
  }
  d$lo <- d$pred * (1 - sd_[as.character(d$h)])
  d$hi <- d$pred * (1 + sd_[as.character(d$h)])
  d
}
