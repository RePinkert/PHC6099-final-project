# conf_protocol.R —— 置信度目标的**无嵌套**协议（角色划分 + 前向链）+ 区间评分库
#
# 目的：把"四年窗口内数据的置信度 + 数据外推的置信度"变成一个可优化、可证伪的目标，
#       并显式处理"嵌套使用数据"（同一批月份既用来定分位数又用来量覆盖）的问题。
#
# 角色（按**目标月**划分，不是 origin）：
#   FIT      目标月 <= 2019-12      -> 只用来学权重
#   ES       目标月 2020-01..2021-12 -> 只用来早停（walk-forward），不看 test
#   CAL      目标月 2022-01..2024-12 -> 只用来定区间构造（分位数/偏差/尺度）；内部前向链
#   EVAL     目标月 2025-01..2025-12 -> **只碰一次**，用于最终报告
#   W4       = CAL + EVAL = 2022-01..2025-12（四年置信度窗口）
#
# 嵌套防护（三条硬约束，任何违反都直接 stop）：
#   1) 角色集合两两不相交（目标月层面）；
#   2) CAL 内部前向链：第 k 折的区间参数**只用**第 k 折之前的月份；
#   3) EVAL 不参与任何选择（选择只在 FIT/ES/CAL 上做）。
#   -> 这三条由 tests/testthat/test-conf-protocol.R 钉住；conf_assert_no_nesting() 在运行期再查一遍。

CONF_ROLES <- list(
  fit   = c("2010-01", "2019-12"),
  es    = c("2020-01", "2021-12"),
  cal   = c("2022-01", "2024-12"),
  eval  = c("2025-01", "2025-12")
)

CONF_H <- 5L
CONF_NOMINAL <- 0.90   # 区间名义覆盖
CONF_ALPHA <- 1 - CONF_NOMINAL

## 目标月 -> 角色
conf_role_of_month <- function(month) {
  r <- rep(NA_character_, length(month))
  for (nm in names(CONF_ROLES)) {
    rng <- CONF_ROLES[[nm]]
    hit <- month >= rng[1] & month <= rng[2]
    r[hit] <- nm
  }
  r
}

## 协议对象：给出每个角色的月份区间、以及前向链折
conf_protocol <- function(roles = CONF_ROLES, h = CONF_H) {
  stopifnot(is.list(roles), all(c("fit", "es", "cal", "eval") %in% names(roles)))
  spans <- lapply(roles, function(r) c(r[1], r[2]))
  names(spans) <- names(roles)
  ## 两两不相交
  for (i in seq_along(spans)) for (j in seq_along(spans)) if (i < j) {
    if (spans[[i]][2] >= spans[[j]][1] && spans[[j]][2] >= spans[[i]][1]) {
      stop(sprintf("conf_protocol: roles '%s' and '%s' overlap (%s..%s vs %s..%s) -- nested data use.",
                   names(spans)[i], names(spans)[j], spans[[i]][1], spans[[i]][2],
                   spans[[j]][1], spans[[j]][2]))
    }
  }
  ## CAL 内部按年前向链；每折的"参考集"= 该折之前的 CAL 年 + （首折时）ES 窗口
  cal_span <- spans$cal
  cal_years <- as.integer(substr(cal_span[1], 1, 4)):as.integer(substr(cal_span[2], 1, 4))
  folds <- lapply(cal_years, function(y) {
    list(year = y,
         eval_from = sprintf("%04d-01", y), eval_to = sprintf("%04d-12", y),
         ref_from = if (y == cal_years[1]) spans$es[1] else sprintf("%04d-01", cal_years[1]),
         ref_to   = if (y == cal_years[1]) spans$es[2] else sprintf("%04d-12", y - 1L))
  })
  list(spans = spans, folds = folds, h = h, nominal = CONF_NOMINAL, alpha = CONF_ALPHA,
       w4 = c(spans$cal[1], spans$eval[2]))
}

## 运行期嵌套核查：给定一份 replay（每行含 target_month 与 role），确认角色无重叠使用
conf_assert_no_nesting <- function(protocol, usage) {
  ## usage: data.frame(target_month = ..., used_for = c("fit","es","cal","eval"))
  stopifnot(all(c("target_month", "used_for") %in% names(usage)))
  bad <- character(0)
  for (u in unique(usage$used_for)) {
    sub <- usage[usage$used_for == u, "target_month"]
    for (r in names(protocol$spans)) {
      sp <- protocol$spans[[r]]
      if (u == r) next
      if (any(sub >= sp[1] & sub <= sp[2])) {
        bad <- c(bad, sprintf("target months of role '%s' fall inside role '%s' (%s..%s)",
                               u, r, sp[1], sp[2]))
      }
    }
  }
  if (length(bad)) stop(paste(c("conf_assert_no_nesting: nested data use detected:", bad), collapse = "\n"))
  invisible(TRUE)
}

# ---------------------------------------------------------------- 评分库 ----

## Winkler 区间评分（WIS）：严格合适的区间评分规则，覆盖与宽度同时惩罚
##   y 在 [lo, hi] 内 -> (hi - lo)；在界外 -> (hi - lo) + (2/alpha) * 距离
conf_wis <- function(y, lo, hi, alpha = CONF_ALPHA) {
  width <- hi - lo
  (width +
     (2 / alpha) * pmax(lo - y, 0) +
     (2 / alpha) * pmax(y - hi, 0))
}

## 有限样本（conformal）分位秩：保证 >= 名义覆盖所需的顺序统计量位置
##   rank = ceil((n + 1) * (1 - p))，用 type=1 经验分位实现；rank > n 时返回 Inf（样本不足）
conf_conformal_rank <- function(n, p) {
  r <- ceiling((n + 1) * p)
  if (r > n) return(Inf)
  r
}

## 有限样本分位数：取第 r 个顺序统计量（不是插值），保证 conformal 覆盖
conf_finite_quantile <- function(x, p) {
  x <- sort(x[is.finite(x)])
  n <- length(x)
  r <- conf_conformal_rank(n, p)
  if (!is.finite(r)) return(NA_real_)
  x[r]
}

## 经验覆盖（区间包含真值的比例）
conf_coverage <- function(y, lo, hi) mean(y >= lo & y <= hi)

## 平均区间宽度（相对量纲）
conf_width <- function(lo, hi, scale = 1) mean((hi - lo) / scale)

## 逐 horizon 汇总：覆盖、WIS、宽度
conf_summary <- function(d, nominal = CONF_NOMINAL) {
  alpha <- 1 - nominal
  rows <- lapply(sort(unique(d$h)), function(h) {
    s <- d[d$h == h, ]
    list(h = h, n = nrow(s),
         coverage = conf_coverage(s$true, s$lo, s$hi),
         coverage_lo = conf_coverage(s$true, s$lo, s$hi),  # 占位，下面用单侧分位另算
         wis = mean(conf_wis(s$true, s$lo, s$hi, alpha)),
         width = mean(s$hi - s$lo),
         width_rel = mean((s$hi - s$lo) / s$true),
         bias = mean((s$true - s$pred) / s$pred))
  })
  do.call(rbind, lapply(rows, function(r) as.data.frame(r)))
}

## 单侧覆盖（低于 lo / 高于 hi 的比例），用于诊断区间偏窄的方向
conf_tail_frac <- function(d) {
  out <- do.call(rbind, lapply(sort(unique(d$h)), function(h) {
    s <- d[d$h == h, ]
    data.frame(h = h, below = mean(s$true < s$lo), above = mean(s$true > s$hi),
               n = nrow(s))
  }))
  out
}
