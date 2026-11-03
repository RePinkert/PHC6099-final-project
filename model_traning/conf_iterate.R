# conf_iterate.R —— 自主迭代（折版）：在四年窗口上比较区间构造与早停准则，选出置信度最好的配置
#
# 折（评估年 y）= rolling-origin 模型 + 三段严格分离的月份：
#   FIT(<=y-3) / ES(y-2) / CAL(y-1) / EVAL(y)
#   -> 区间参数只由 CAL(y-1) 决定；EVAL(y) 只用来读覆盖。
# 选择纪律：开发折 2022-2024 用来**选**构造与早停准则；留出折 2025 只在最后读一次。
#
# 输出：conf_ledger.csv（逐折/h）、conf_dev_summary.csv（开发折汇总）、
#       conf_holdout.csv（留出折）、candidates/selected_conf.json

source("R/conf-protocol.R")
source("R/conf-harness.R")
source("R/conf-intervals.R")

ROOT <- "."
EVAL_YEARS <- c(2022L, 2023L, 2024L, 2025L)
DEV_YEARS  <- c(2022L, 2023L, 2024L)
HOLD_YEAR   <- 2025L
CRITS  <- c("mse", "wis")
METHODS <- c("shipped", "conformal_asym", "conformal_sym", "scaled_conformal",
             "bias_conformal", "bias_scaled_conformal", "shrunk_state")
NOMINAL <- CONF_NOMINAL

P <- conf_load_panel(ROOT); ann <- conf_ann_rel(P, ROOT); months <- colnames(P)
mi <- function(s) match(s, months)

fold_of <- function(y) list(
  eval_year = y,
  train_last = sprintf("%04d-12", y - 3L),
  es_first = sprintf("%04d-01", y - 2L), es_last = sprintf("%04d-12", y - 2L),
  cal_first = sprintf("%04d-01", y - 1L), cal_last = sprintf("%04d-12", y - 1L),
  eval_first = sprintf("%04d-01", y), eval_last = sprintf("%04d-12", y))

origins_for_fold <- function(y) {
  lo <- mi(sprintf("%04d-01", y - 1L)) - 5L + 1L
  hi <- mi(sprintf("%04d-12", y)) - 1L
  months[lo:hi]
}

## ---------- 1. 逐折重放 + 逐构造评估 ----------
ledger <- list(); kk <- 0L
fold_data <- list()
for (y in EVAL_YEARS) {
  f <- fold_of(y)
  org <- origins_for_fold(y)
  for (crit in CRITS) {
    fp <- sprintf("model_traning/candidates/conf_fit_y%d_%s.rds", y, crit)
    if (!file.exists(fp)) { cat("missing candidate:", fp, "\n"); next }
    fit <- readRDS(fp)
    d <- conf_replay(fit, P, ann, org, verbose = FALSE)
    d <- conf_add_scale(d, P)
    cal <- d[d$target >= f$cal_first & d$target <= f$cal_last, ]
    ev  <- d[d$target >= f$eval_first & d$target <= f$eval_last, ]
    fold_data[[sprintf("%d_%s", y, crit)]] <- list(fit = fit, cal = cal, ev = ev, fold = f)
    cat(sprintf("fold %d %-3s: cal rows %d, eval rows %d\n", y, crit, nrow(cal), nrow(ev)))
    for (meth in METHODS) {
      pars <- conf_fit_iv(cal, meth, NOMINAL)
      e2 <- conf_apply_iv(pars, ev)
      for (h in sort(unique(e2$h))) {
        s <- e2[e2$h == h, ]
        ## 失败（预测非有限/越界）按"未覆盖"计入：诚实优先
        fail_rate <- mean(!s$ok)
        good <- s[s$ok, ]
        sc <- if (nrow(good) > 0) mean(abs(good$true - good$last)) + 1e-9 else NA_real_
        cov <- mean(s$ok & s$true >= s$lo & s$true <= s$hi)
        wis <- if (nrow(good) > 0) mean(conf_wis(good$true, good$lo, good$hi, 1 - NOMINAL)) else NA_real_
        width_rel <- if (nrow(good) > 0) mean((good$hi - good$lo) / good$true) else NA_real_
        kk <- kk + 1L
        ledger[[kk]] <- data.frame(
          eval_year = y, crit = crit, method = meth, h = h, n = nrow(s),
          n_ok = nrow(good), fail_rate = fail_rate,
          coverage = cov, cov_err = cov - NOMINAL,
          wis = wis, width = if (nrow(good) > 0) mean(good$hi - good$lo) else NA_real_,
          width_rel = width_rel,
          bias = if (nrow(good) > 0) mean((good$true - good$pred) / good$pred) else NA_real_,
          scale = sc,
          J = (if (is.finite(wis)) wis / sc else 1e6) + 5 * abs(cov - NOMINAL) + 50 * fail_rate,
          stringsAsFactors = FALSE)
      }
    }
  }
}
L <- do.call(rbind, ledger)

## ---------- 2. 开发折汇总（选择只在这里做）----------
dev <- L[L$eval_year %in% DEV_YEARS, ]
agg <- aggregate(cbind(coverage, wis, width_rel, fail_rate, J) ~ crit + method, dev, mean)
agg$cov_err <- agg$coverage - NOMINAL
agg <- agg[order(agg$J), c("crit","method","coverage","cov_err","wis","width_rel","fail_rate","J")]
cat("\n== dev folds (2022-2024) summary, ranked by J ==\n"); print(agg, digits = 4)

best <- agg[1, ]
cat("\nselected on dev folds:", best$crit, "/", best$method,
    sprintf(" | coverage %.4f (target %.2f) | width_rel %.4f | J %.4f\n",
            best$coverage, NOMINAL, best$width_rel, best$J))

## ---------- 3. 留出折 2025（只读一次）----------
hold <- L[L$eval_year == HOLD_YEAR, ]
cat("\n== holdout fold 2025 (never used for selection) ==\n")
hs <- hold[order(hold$J), ]
print(hs[, c("crit","method","h","n","coverage","wis","width_rel","J")], digits = 4)
sel_hold <- hold[hold$crit == best$crit & hold$method == best$method, ]
base_hold <- hold[hold$crit == best$crit & hold$method == "shipped", ]
cat(sprintf("\nselected  on 2025: coverage %s | WIS %s | rel width %s\n",
            paste(round(mean(sel_hold$coverage), 4), collapse = ","),
            paste(round(mean(sel_hold$wis), 3), collapse = ","),
            paste(round(mean(sel_hold$width_rel), 4), collapse = ",")))
cat(sprintf("shipped-style on 2025: coverage %s | WIS %s | rel width %s\n",
            paste(round(mean(base_hold$coverage), 4), collapse = ","),
            paste(round(mean(base_hold$wis), 3), collapse = ","),
            paste(round(mean(base_hold$width_rel), 4), collapse = ",")))

## ---------- 4. 四年覆盖画像（选定构造，逐折）----------
cat("\n== 4-year coverage profile of the selected configuration ==\n")
prof <- L[L$crit == best$crit & L$method == best$method, ]
print(aggregate(cbind(coverage, wis, width_rel, bias) ~ eval_year, prof, mean)[, c("eval_year","coverage","wis","width_rel","bias")], digits = 4)

## ---------- 5. 落盘 ----------
utils::write.csv(L, "model_traning/conf_ledger.csv", row.names = FALSE)
utils::write.csv(agg, "model_traning/conf_dev_summary.csv", row.names = FALSE)
utils::write.csv(hold, "model_traning/conf_holdout.csv", row.names = FALSE)
dir.create("model_traning/candidates", showWarnings = FALSE, recursive = TRUE)
sel <- list(selected_crit = best$crit, selected_method = best$method,
            nominal = NOMINAL,
            dev_years = DEV_YEARS, holdout_year = HOLD_YEAR,
            dev_summary = agg, holdout = sel_hold, holdout_shipped_style = base_hold,
            four_year_profile = aggregate(cbind(coverage, wis, width_rel) ~ eval_year, prof, mean),
            generated = format(Sys.Date()))
jsonlite::write_json(sel, "model_traning/selected_conf.json", auto_unbox = TRUE, pretty = TRUE)
cat("\nwrote conf_ledger.csv / conf_dev_summary.csv / conf_holdout.csv / candidates/selected_conf.json\n")
