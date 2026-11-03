# conf_serving_eval.R —— 服务 regime 折上的区间构造评估（gap 18 起）
#
# 与 conf_iterate.R 同一套评分口径（WIS / 覆盖 / 失败率 / 相对宽度 / J），
# 但折的留出被压到 12 个月（ES 6 + CAL 6），评估 origin 从 2025-01 起
# —— 距最后一个训练 origin（2023-07）正好 18 个月，与随包服务 regime 对齐。
#
# 输出：
#   model_traning/conf_serving_ledger.csv   逐 (crit, method, h)
#   model_traning/conf_serving_distance.csv  逐 gap/dist/h
#
# 用法：Rscript model_traning/conf_serving_eval.R

source("R/conf-protocol.R")
source("R/conf-harness.R")
source("R/conf-intervals.R")

ROOT <- "."
CRITS <- c("mse", "wis")
METHODS <- c("shipped", "conformal_asym", "conformal_sym", "scaled_conformal",
             "bias_conformal", "bias_scaled_conformal", "shrunk_state")
NOMINAL <- CONF_NOMINAL

P <- conf_load_panel(ROOT); ann <- conf_ann_rel(P, ROOT); months <- colnames(P)
mi <- function(s) match(s, months)

fold <- list(eval_year = 2026L,
             train_last = "2023-12",
             es_first = "2024-01", es_last = "2024-06", es_a_last = "2024-03",
             cal_first = "2024-07", cal_last = "2024-12",
             eval_first = "2025-02", eval_last = "2026-01")

## CAL 的 origin：目标月落在 2024-07..12 的那些（h=1..5 都要有）
cal_origins <- months[seq(mi(fold$cal_first) - 5L, mi(fold$cal_last) - 1L)]
## EVAL 的 origin：目标月落在 2025-02..2026-01 的那些
eval_origins <- months[seq(mi(fold$eval_first) - 5L, mi(fold$eval_last) - 1L)]
j_last <- mi(fold$train_last)
cat(sprintf("CAL origins %s..%s | EVAL origins %s..%s\n",
            min(cal_origins), max(cal_origins), min(eval_origins), max(eval_origins)))
cat(sprintf("last training origin %s -> first eval origin %s | gap %d months\n",
            months[j_last - 5L], min(eval_origins), mi(min(eval_origins)) - (j_last - 5L)))

ledger <- list(); dd <- list(); kk <- 0L; kd <- 0L
for (crit in CRITS) {
  fp <- sprintf("model_traning/candidates/conf_fit_serving_y%d_%s.rds", fold$eval_year, crit)
  if (!file.exists(fp)) { cat("missing:", fp, "\n"); next }
  fit <- readRDS(fp)
  cat(sprintf("-- serving fold %d %s: train<=%s es=%s..%s cal=%s..%s eval=%s..%s | best epoch %d\n",
              fold$eval_year, crit, fit$fold$train_last, fit$fold$es_first, fit$fold$es_last,
              fit$fold$cal_first, fit$fold$cal_last, fit$fold$eval_first, fit$fold$eval_last,
              fit$early_stop$epoch))

  cal_all <- conf_replay(fit, P, ann, cal_origins, verbose = FALSE)
  ev_all <- conf_replay(fit, P, ann, eval_origins, verbose = FALSE)
  ## 尺度列必须在 CAL+EVAL 的**同一个**集合上归一（否则参数与目标不同标尺），与 conf_iterate.R 同口径
  d_all <- conf_add_scale(rbind(cal_all, ev_all), P)
  cal <- d_all[d_all$target >= fold$cal_first & d_all$target <= fold$cal_last, ]
  ev <- d_all[d_all$target >= fold$eval_first & d_all$target <= fold$eval_last, ]
  ev$gap <- mi(ev$origin) - (j_last - 5L)
  ev$dist <- mi(ev$target) - j_last
  cat(sprintf("   cal rows %d | eval rows %d | gap %d..%d | dist %d..%d\n",
              nrow(cal), nrow(ev), min(ev$gap), max(ev$gap), min(ev$dist), max(ev$dist)))

  for (meth in METHODS) {
    pars <- conf_fit_iv(cal, meth, NOMINAL)
    e2 <- conf_apply_iv(pars, ev)
    for (h in sort(unique(e2$h))) {
      s <- e2[e2$h == h, ]
      fail_rate <- mean(!s$ok)
      good <- s[s$ok, ]
      sc <- if (nrow(good) > 0) mean(abs(good$true - good$last)) + 1e-9 else NA_real_
      cov <- mean(s$ok & s$true >= s$lo & s$true <= s$hi)
      wis <- if (nrow(good) > 0) mean(conf_wis(good$true, good$lo, good$hi, 1 - NOMINAL)) else NA_real_
      width_rel <- if (nrow(good) > 0) mean((good$hi - good$lo) / good$true) else NA_real_
      kk <- kk + 1L
      ledger[[kk]] <- data.frame(
        eval_year = fold$eval_year, crit = crit, method = meth, h = h, n = nrow(s),
        n_ok = nrow(good), fail_rate = fail_rate, coverage = cov, cov_err = cov - NOMINAL,
        wis = wis, width_rel = width_rel,
        bias = if (nrow(good) > 0) mean((good$true - good$pred) / good$pred) else NA_real_,
        scale = sc,
        J = (if (is.finite(wis)) wis / sc else 1e6) + 5 * abs(cov - NOMINAL) + 50 * fail_rate,
        stringsAsFactors = FALSE)
    }
  }
  ## gap / dist 曲线（shipped 口径与选定构造）
  for (meth in c("shipped", "bias_scaled_conformal")) {
    pars <- conf_fit_iv(cal, meth, NOMINAL)
    e2 <- conf_apply_iv(pars, ev)
    for (g in sort(unique(e2$gap))) {
      s <- e2[e2$gap == g, ]
      good <- s[s$ok, ]
      kd <- kd + 1L
      dd[[kd]] <- data.frame(
        crit = crit, method = meth, gap = g, n = nrow(s),
        fail_rate = mean(!s$ok),
        coverage = mean(s$ok & s$true >= s$lo & s$true <= s$hi),
        median_rel_err = if (nrow(good)) stats::median((good$true - good$pred) / good$pred) else NA_real_,
        p90_abs_rel_err = if (nrow(good)) unname(stats::quantile(abs((good$true - good$pred) / good$pred), 0.9)) else NA_real_,
        width_rel = if (nrow(good)) mean((good$hi - good$lo) / good$true) else NA_real_,
        stringsAsFactors = FALSE)
    }
  }
}

L <- do.call(rbind, ledger)
utils::write.csv(L, "model_traning/conf_serving_ledger.csv", row.names = FALSE)
D <- do.call(rbind, dd)
utils::write.csv(D, "model_traning/conf_serving_distance.csv", row.names = FALSE)

cat("\n=== 服务 regime 折：逐 (准则, 构造, h) ===\n")
print(L[order(L$crit, L$method, L$h), c("crit", "method", "h", "n", "coverage", "wis", "width_rel",
                                         "fail_rate", "bias", "J")], row.names = FALSE, digits = 4)

cat("\n=== 服务 regime 折：按 gap ===\n")
print(D[order(D$crit, D$method, D$gap), ], row.names = FALSE, digits = 4)

cat("\n=== 汇总（每构造跨 h 平均）===\n")
agg <- aggregate(cbind(coverage, wis, width_rel, fail_rate, J) ~ crit + method, L, mean)
agg$cov_err <- agg$coverage - NOMINAL
print(agg[order(agg$crit, agg$J), ], row.names = FALSE, digits = 4)

cat("\n=== 对照：四年折（gap 25..40）上同一口径 ===\n")
led <- utils::read.csv("model_traning/conf_ledger.csv")
old <- led[led$method %in% c("shipped", "bias_scaled_conformal"), ]
oldagg <- aggregate(cbind(coverage, wis, width_rel, fail_rate) ~ crit + method, old, mean)
print(oldagg, row.names = FALSE, digits = 4)

cat("\nwrote conf_serving_ledger.csv / conf_serving_distance.csv\n")