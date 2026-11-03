# conf_report.R —— 最终报告：留出折结论 + "数据外推"段的建议区间 + 数据使用台账
#
# 三块输出：
#   1) 留出折（2025）的覆盖/宽度：选定构造 vs 随包口径；
#   2) 数据外推段：对**随包 v3 的 2026-08..12 预测**，用选定构造在"样本外残差"上重标定，
#      给出建议区间，并与随包区间并列（这是"外推置信度"的可操作产物）；
#   3) 数据使用台账（谁用了哪些月份）——用于人工核对"没有嵌套使用"。
#
# 运行：Rscript model_traning/conf_report.R（需先跑 conf_train_folds.R 与 conf_iterate.R）

source("R/conf-protocol.R")
source("R/conf-harness.R")
source("R/conf-intervals.R")

ROOT <- "."
NOMINAL <- CONF_NOMINAL
sel <- jsonlite::read_json("model_traning/selected_conf.json", simplifyVector = TRUE)
cat("selected:", sel$selected_crit, "/", sel$selected_method, "\n\n")

P <- conf_load_panel(ROOT); ann <- conf_ann_rel(P, ROOT); months <- colnames(P)
mi <- function(s) match(s, months)

## ---------- 1. 留出折（2025）----------
L <- utils::read.csv("model_traning/conf_ledger.csv")
hold <- L[L$eval_year == 2025L, ]
cat("== holdout fold 2025 (never used for selection) ==\n")
sel_h <- hold[hold$crit == sel$selected_crit & hold$method == sel$selected_method, ]
base_h <- hold[hold$crit == sel$selected_crit & hold$method == "shipped", ]
cmp <- merge(sel_h[, c("h", "coverage", "wis", "width_rel", "J")],
             base_h[, c("h", "coverage", "wis", "width_rel", "J")],
             by = "h", suffixes = c("_sel", "_base"))
print(cmp, digits = 4)
cat(sprintf("\nmean coverage: selected %.4f | shipped-style %.4f | nominal %.2f\n",
            mean(sel_h$coverage), mean(base_h$coverage), NOMINAL))
cat(sprintf("mean relative width: selected %.4f | shipped-style %.4f\n",
            mean(sel_h$width_rel), mean(base_h$width_rel)))

## ---------- 2. 四年覆盖画像（选定构造）----------
prof <- aggregate(cbind(coverage, wis, width_rel) ~ eval_year,
                  L[L$crit == sel$selected_crit & L$method == sel$selected_method, ], mean)
cat("\n== 4-year coverage profile (selected configuration) ==\n"); print(prof, digits = 4)

## ---------- 3. 数据外推段：给随包 v3 的 2026-08..12 预测配建议区间 ----------
## 3.1 用 fold-2025 模型（训练<=2022、ES 2023、样本外残差来自 CAL 2024）重标定构造
f25 <- list(train_last = "2022-12", es = "2023-01..2023-12",
            cal_first = "2024-01", cal_last = "2024-12")
fit25_path <- sprintf("model_traning/candidates/conf_fit_y2025_%s.rds", sel$selected_crit)
fit25 <- readRDS(fit25_path)
org25 <- months[(mi("2023-08") - 5L + 1L):(mi("2024-12") - 1L)]
d25 <- conf_replay(fit25, P, ann, org25, verbose = FALSE)
d25 <- conf_add_scale(d25, P)
cal25 <- d25[d25$target >= f25$cal_first & d25$target <= f25$cal_last, ]
pars_sel <- conf_fit_iv(cal25, sel$selected_method, NOMINAL)
pars_base <- conf_fit_iv(cal25, "shipped", NOMINAL)

## 3.2 随包 v3 在 origin 2026-07 的点预测（发货口径）
shipped <- readRDS(file.path(ROOT, "inst", "extdata", "price_lstm_fit.rds"))
X <- conf_feature_batch(shipped, P, ann, rownames(P), shipped$fit_as_of)
yn <- conf_forward_norm(shipped, X)
fc_point <- do.call(rbind, lapply(rownames(P), function(s) {
  pr <- conf_denorm(shipped, yn[match(s, rownames(P)), ], P[s, shipped$fit_as_of])
  data.frame(state = s, h = 1:5, point = pr, stringsAsFactors = FALSE)
}))

## 外推段的逐州尺度：origin 月（2026-07）之前的 12 个月对数变化 sd，归一到中位数 1
vol_at_origin <- function(state) {
  j <- mi(shipped$fit_as_of)
  p <- P[state, (j - 12):j]
  stats::sd(diff(log(p)))
}
scale_fc <- vapply(fc_point$state, vol_at_origin, numeric(1))
scale_fc <- scale_fc / stats::median(scale_fc)

apply_mult <- function(point, pars, scale = NULL) {
  lo <- hi <- numeric(nrow(point))
  for (i in seq_len(nrow(point))) {
    p <- pars$par[[as.character(point$h[i])]]
    base <- point$point[i] * (1 + p$bias)
    if (!is.null(p$state_scale)) {
      s <- p$state_scale[[point$state[i]]]
      if (is.null(s)) s <- 1
    } else if (!is.null(scale)) {
      s <- scale[i]
    } else s <- 1
    lo[i] <- base * (1 + p$lo * s); hi[i] <- base * (1 + p$hi * s)
  }
  data.frame(point = point$point, lo = lo, hi = hi)
}
rec_sel <- apply_mult(fc_point, pars_sel, scale_fc)
rec_base <- apply_mult(fc_point, pars_base, scale_fc)
out <- data.frame(state = fc_point$state, h = fc_point$h,
                  point = round(fc_point$point, 3),
                  sel_lo = round(rec_sel$lo, 3), sel_hi = round(rec_sel$hi, 3),
                  sel_width_rel = round((rec_sel$hi - rec_sel$lo) / fc_point$point, 4),
                  base_lo = round(rec_base$lo, 3), base_hi = round(rec_base$hi, 3),
                  base_width_rel = round((rec_base$hi - rec_base$lo) / fc_point$point, 4),
                  shipped_q_lo = round(shipped$forecast$q_lo[match(
                    paste(fc_point$state, fc_point$h),
                    paste(shipped$forecast$state, shipped$forecast$h))], 3),
                  shipped_q_hi = round(shipped$forecast$q_hi[match(
                    paste(fc_point$state, fc_point$h),
                    paste(shipped$forecast$state, shipped$forecast$h))], 3),
                  stringsAsFactors = FALSE)
cat("\n== extrapolation segment: recommended intervals for the shipped 2026-08..12 forecast ==\n")
cat("(multipliers calibrated on OUT-OF-SAMPLE residuals of the rolling-origin fold-2025 model)\n\n")
print(head(out[out$state %in% c("FL", "CA", "AK", "TX", "MS"), ], 12), digits = 4)
cat("\nmean relative width by horizon (selected vs shipped-style vs shipped artifact):\n")
agg <- aggregate(cbind(sel_width_rel, base_width_rel) ~ h, out, mean)
sf <- shipped$forecast
sf$w_rel <- (sf$q_hi - sf$q_lo) / sf$price
shipped_w <- aggregate(w_rel ~ h, sf, mean)
names(shipped_w) <- c("h", "shipped_width_rel")
print(merge(agg, shipped_w), digits = 4)
utils::write.csv(out, "model_traning/conf_extrapolation_intervals.csv", row.names = FALSE)

## ---------- 4. 数据使用台账 ----------
cat("\n== data-usage ledger (who used which target months) ==\n")
ledger <- data.frame(
  role = c("FIT", "ES", "CAL", "EVAL(dev)", "EVAL(holdout)"),
  target_months = c("<=2019-12 (fold 2022) .. <=2022-12 (fold 2025)", "per fold: y-2", "per fold: y-1",
                    "2022-01..2024-12", "2025-01..2025-12"),
  used_for = c("weights (per fold, rolling origin)", "early stopping (epoch choice)",
               "interval parameters (quantiles/bias/scale)", "selection of the construction",
               "final report only"),
  nested = c("no", "no", "no", "no", "no"),
  stringsAsFactors = FALSE)
print(ledger, row.names = FALSE)
utils::write.csv(ledger, "model_traning/conf_data_usage_ledger.csv", row.names = FALSE)

cat("\n== 结论摘要 ==\n")
cat(sprintf("选定构造：%s / %s\n", sel$selected_crit, sel$selected_method))
cat(sprintf("留出折 2025：覆盖 %.4f（名义 %.2f），随包口径 %.4f；相对宽度 %.4f vs %.4f\n",
            mean(sel_h$coverage), NOMINAL, mean(base_h$coverage),
            mean(sel_h$width_rel), mean(base_h$width_rel)))
cat(sprintf("四年画像（2022..2025）覆盖：%s\n",
            paste(sprintf("%d:%.3f", prof$eval_year, prof$coverage), collapse = "  ")))
