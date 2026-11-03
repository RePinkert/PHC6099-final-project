# conf_extrap_distance.R —— 外推距离曲线：误差/覆盖随"输入间隔"和"外推距离"怎么变
#
# 为什么需要它：随包预测窗 2026-08..12 的输入间隔是 18 个月（训练 origin 只到 2025-01，
# 预测 origin 是 2026-07），外推距离 14..18 个月。滚动起点的四个折正好覆盖这个区间，
# 所以"误差随外推距离的曲线"就是外推段的诚实刻画；2026-08 的真值（EIA-861M 2026-10-23 版）
# 给出了这条曲线上第一个真实锚点。
#
# 两种距离：
#   gap  = 预测 origin 距最后一个训练 origin 的月数（输入有多久没见过的）
#   dist = 目标月距最后一个训练目标月（train_last）的月数（被外推了多远）
#
# 输出：
#   model_traning/conf_extrap_distance.csv   逐折逐 gap/dist/h
#   model_traning/conf_extrap_curve.csv       跨折汇总（曲线）
#
# 用法：Rscript model_traning/conf_extrap_distance.R

source("R/conf-protocol.R")
source("R/conf-harness.R")
source("R/conf-intervals.R")

ROOT <- "."
EVAL_YEARS <- c(2022L, 2023L, 2024L, 2025L)
CRITS <- c("mse")
METHODS <- c("shipped", "bias_scaled_conformal")
NOMINAL <- CONF_NOMINAL

P <- conf_load_panel(ROOT); ann <- conf_ann_rel(P, ROOT); months <- colnames(P)
mi <- function(s) match(s, months)

fold_of <- function(y) list(
  eval_year = y,
  train_last = sprintf("%04d-12", y - 3L),
  cal_first = sprintf("%04d-01", y - 1L), cal_last = sprintf("%04d-12", y - 1L),
  eval_first = sprintf("%04d-01", y), eval_last = sprintf("%04d-12", y))

origins_for_fold <- function(y) {
  lo <- mi(sprintf("%04d-01", y - 1L)) - 5L + 1L
  hi <- mi(sprintf("%04d-12", y)) - 1L
  months[lo:hi]
}

rows <- list(); kk <- 0L
for (y in EVAL_YEARS) {
  f <- fold_of(y)
  org <- origins_for_fold(y)
  for (crit in CRITS) {
    fp <- sprintf("model_traning/candidates/conf_fit_y%d_%s.rds", y, crit)
    if (!file.exists(fp)) { cat("missing candidate:", fp, "\n"); next }
    fit <- readRDS(fp)
    d <- conf_replay(fit, P, ann, org, verbose = FALSE)
    d <- conf_add_scale(d, P)
    j_last <- mi(f$train_last)
    d$gap <- mi(d$origin) - j_last + fit$h_max
    d$dist <- mi(d$target) - j_last
    cal <- d[d$target >= f$cal_first & d$target <= f$cal_last, ]
    ev <- d[d$target >= f$eval_first & d$target <= f$eval_last, ]
    cat(sprintf("fold %d %-3s: cal %d eval %d | gap %d..%d | dist %d..%d\n", y, crit,
                nrow(cal), nrow(ev), min(ev$gap), max(ev$gap), min(ev$dist), max(ev$dist)))
    for (meth in METHODS) {
      pars <- conf_fit_iv(cal, meth, NOMINAL)
      e2 <- conf_apply_iv(pars, ev)
      for (g in sort(unique(e2$gap))) {
        for (dd in sort(unique(e2$dist[e2$gap == g]))) {
          s <- e2[e2$gap == g & e2$dist == dd, ]
          if (nrow(s) == 0L) next
          good <- s[s$ok, ]
          kk <- kk + 1L
          rows[[kk]] <- data.frame(
            eval_year = y, crit = crit, method = meth, gap = g, dist = dd,
            h = if (nrow(s)) s$h[1] else NA_integer_, n = nrow(s), n_ok = nrow(good),
            fail_rate = mean(!s$ok),
            coverage = mean(s$ok & s$true >= s$lo & s$true <= s$hi),
            median_rel_err = if (nrow(good)) stats::median((good$true - good$pred) / good$pred) else NA_real_,
            p90_abs_rel_err = if (nrow(good)) unname(stats::quantile(abs((good$true - good$pred) / good$pred), 0.9)) else NA_real_,
            wis = if (nrow(good)) mean(conf_wis(good$true, good$lo, good$hi, 1 - NOMINAL)) else NA_real_,
            width_rel = if (nrow(good)) mean((good$hi - good$lo) / good$true) else NA_real_,
            stringsAsFactors = FALSE)
        }
      }
    }
  }
}
D <- do.call(rbind, rows)
utils::write.csv(D, "model_traning/conf_extrap_distance.csv", row.names = FALSE)

curve <- aggregate(cbind(coverage, wis, width_rel, fail_rate, median_rel_err, p90_abs_rel_err, n) ~
                     method + gap + dist + h, D, mean, na.rm = TRUE)
utils::write.csv(curve, "model_traning/conf_extrap_curve.csv", row.names = FALSE)

cat("\n=== 外推曲线：按 gap（输入间隔）与 h ===\n")
for (meth in METHODS) {
  cat(sprintf("\n--- method: %s ---\n", meth))
  s <- curve[curve$method == meth, c("gap", "h", "n", "median_rel_err", "p90_abs_rel_err",
                                     "coverage", "width_rel", "fail_rate")]
  s <- s[order(s$gap, s$h), ]
  print(s[seq(1, nrow(s), by = 2), ], row.names = FALSE, digits = 4)
}

cat("\n=== 随包预测窗的位置 ===\n")
cat("随包 fit: 训练 origin 至 2025-01（目标至 2025-06），预测 origin 2026-07\n")
cat("  -> gap = 18 个月；目标 2026-08..12 -> dist = 14..18 个月\n")
cat("2026-08 真值实测：median rel err -0.0096 | p90 |err| 0.0371 | shipped 覆盖 0.9804 | 相对宽 0.0645\n")
for (meth in METHODS) {
  s <- curve[curve$method == meth & curve$gap == 18 & curve$h == 1, ]
  if (nrow(s)) {
    cat(sprintf("折上同位置（gap=18, h=1, %s）：coverage %.4f | median rel err %+.4f | p90 |err| %.4f | 失败率 %.4f\n",
                meth, s$coverage, s$median_rel_err, s$p90_abs_rel_err, s$fail_rate))
  }
}
cat("\nwrote conf_extrap_distance.csv / conf_extrap_curve.csv\n")