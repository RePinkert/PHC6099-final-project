# diagnose_seam.R —— 诊断 2026-08 接缝跳幅（纯 R 前向；不重训、不改 shipped 模型）
# 现象：2026-08 预测 / 2026-07 观测 的跨州中位数 1.064，历史 Aug/Jul 中位数约 1.0035。
# 四项：
#   1. 真实值对照：EIA-861M 批量表的 2026-08（训练和服务都没用到；只做事后评估，不用于调参）
#   2. 归一化越界：起点 2026-07 的 36 个月输入在训练窗变换下超出范围的程度，及其与跳幅的相关
#   3. 回测：每年 7 月起点的 h=1 Aug/Jul 比值（2016..2024 目标在训练窗内，是样本内；2025 在早停窗），
#      以及所有起点 h=1 预测/末值 比值随时间的走势（减去真实比值）
#   4. 消融：在 2026-07 起点上逐一替换输入，看跳幅中位数如何变化
# 注意：价格历史是现行数据版本（含 EIA 回改），不是当时的实时版本；年度通道按发布日期入模，是因果的。
# 运行：Rscript model_traning/diagnose_seam.R [输出目录]（需先安装本包，需 data-raw/eia861m/sales_revenue.xlsx）

suppressMessages(library(lifewatt))
ns <- asNamespace("lifewatt")
out_dir <- if (length(commandArgs(TRUE))) commandArgs(TRUE)[1] else "."
fit <- ns$.price_lstm_fit()
ph <- ns$.price_history_wide()
M <- colnames(ph)
S <- rownames(ph)
O <- "2026-07"
jo <- match(O, M)
## 旧拟合（11 通道）含 EIA-112 c1；重训后（8 通道）没有，c1 相关的分析自动跳过
has_c1 <- "c1_age" %in% fit$chan_names

## 只为提速：.lstm_feature_window 每次都重读年度/断供表，这里在本进程内缓存（结果不变）
memo <- function(f) { force(f); cache <- list(); function(months, ...) {
  k <- paste(length(months), months[1], months[length(months)], ...)
  if (is.null(cache[[k]])) cache[[k]] <<- f(months, ...)
  cache[[k]]
} }
for (nm in c(".ann_wide", ".c1_wide")) {
  unlockBinding(nm, ns); assign(nm, memo(get(nm, ns)), envir = ns); lockBinding(nm, ns)
}

fwd <- function(ws, states) {  # ws: list of 36x11 windows -> denormalised h=1..5 matrix
  X <- array(NA_real_, c(length(ws), dim(ws[[1]])))
  for (i in seq_along(ws)) X[i, , ] <- ws[[i]]
  yn <- ns$.lstm_forward_norm(X)
  t(vapply(seq_along(states), function(i) ns$.lstm_denorm(yn[i, ], states[i]), numeric(fit$h_max)))
}
win <- lapply(S, function(s) ns$.lstm_feature_window(s, O))
names(win) <- S
base <- fwd(win, S)[, 1]
obs_jul <- ph[, O]
jump <- base / obs_jul
stopifnot(max(abs(base - ns$.lstm_predict(S, rep("2026-08", length(S)))$price)) < 1e-10)

hist_r <- sapply(2015:2025, function(y) ph[, sprintf("%d-08", y)] / ph[, sprintf("%d-07", y)])
hist_max <- apply(hist_r, 1, max)
summ <- function(r) c(median = median(r), over_hist_max = mean(r > hist_max))
res <- list()

## ---- 1. 真实 2026-08 ----
raw <- readxl::read_excel("data-raw/eia861m/sales_revenue.xlsx", sheet = "Monthly-States", skip = 3,
                          col_names = FALSE, col_types = "text", .name_repair = "minimal")
ym <- sprintf("%s-%02d", raw[[1]], suppressWarnings(as.integer(raw[[2]])))
tr <- suppressWarnings(as.numeric(raw[[8]]))
true_aug <- setNames(tr[ym == "2026-08"], raw[[3]][ym == "2026-08"])[S]
true_jul_x <- setNames(tr[ym == "2026-07"], raw[[3]][ym == "2026-07"])[S]
stopifnot(all(is.finite(true_aug)), max(abs(true_jul_x - obs_jul)) < 1e-9)
true_r <- true_aug / obs_jul
res$truth <- rbind(predicted = summ(jump), true = summ(true_r))
res$truth_extra <- c(
  cor_pearson = cor(jump, true_r), cor_spearman = cor(jump, true_r, method = "spearman"),
  mse_lstm = mean((base - true_aug)^2), mse_last = mean((obs_jul - true_aug)^2),
  mse_seas = mean((ph[, "2025-08"] / ph[, "2025-07"] * obs_jul - true_aug)^2),
  median_rel_err = median((true_aug - base) / base),
  share_pred_above_true = mean(base > true_aug))
per_state <- data.frame(state = S, obs_jul = obs_jul, pred_aug = base, true_aug = true_aug,
                        pred_ratio = jump, true_ratio = true_r, hist_max = hist_max)

## ---- 2. 归一化越界（起点 2026-07 的输入窗）----
oor <- function(w) c(
  price_frac_gt1 = mean(abs(w[, 1]) > 1), price_max = max(w[, 1]), price_last = w[36, 1],
  ann_frac_gt1 = mean(abs(w[, 6]) > 1), ann_max = max(w[, 6]), ann_last = w[36, 6],
  mom_absz_max = max(abs(w[, 2])), rel12_absz_max = max(abs(w[, 3])), c1_absz_max = if (has_c1) max(abs(w[, 9])) else NA_real_)
oor_now <- t(sapply(win, oor))
per_state <- cbind(per_state, oor_now)
## 对照：训练/早停期起点的同一指标（训练窗最后一个起点 2025-01、早停窗起点 2025-06）
oor_ref <- sapply(c("2024-07", "2025-01", "2025-06", "2026-01", "2026-07"), function(o) {
  z <- t(sapply(S, function(s) oor(ns$.lstm_feature_window(s, o))))
  c(price_last_median = median(z[, "price_last"]), price_states_last_gt1 = mean(z[, "price_last"] > 1),
    ann_last_median = median(z[, "ann_last"]), ann_states_last_gt1 = mean(z[, "ann_last"] > 1))
})
res$oor_ref <- oor_ref
res$oor_cor <- sapply(c("price_last", "price_frac_gt1", "ann_last", "ann_frac_gt1", "rel12_absz_max"),
                      function(v) cor(per_state[[v]], jump - true_r, method = "spearman"))
res$oor_cor_jump <- sapply(c("price_last", "price_frac_gt1", "ann_last", "ann_frac_gt1", "rel12_absz_max"),
                           function(v) cor(per_state[[v]], jump, method = "spearman"))

## ---- 3. 回测 ----
origins <- M[match("2012-12", M):jo]
bt <- do.call(rbind, lapply(origins, function(o) {
  j <- match(o, M)
  p1 <- fwd(lapply(S, function(s) ns$.lstm_feature_window(s, o)), S)[, 1]
  data.frame(origin = o, pred_ratio = median(p1 / ph[, j]),
             true_ratio = if (j < length(M)) median(ph[, j + 1] / ph[, j]) else NA_real_,
             excess = if (j < length(M)) median(p1 / ph[, j] - ph[, j + 1] / ph[, j]) else NA_real_,
             share_over_hist_max = if (substr(o, 6, 7) == "07") mean(p1 / ph[, j] > hist_max) else NA_real_)
}))
bt$excess[bt$origin == O] <- median(jump - true_r)
bt$true_ratio[bt$origin == O] <- median(true_r)
utils::write.csv(bt, file.path(out_dir, "seam_backtest_all_origins.csv"), row.names = FALSE)
res$july <- bt[substr(bt$origin, 6, 7) == "07", ]
bt$year <- substr(bt$origin, 1, 4)
res$excess_by_year <- tapply(bt$excess, bt$year, median, na.rm = TRUE)
res$pred_ratio_by_year <- tapply(bt$pred_ratio, bt$year, median)

## ---- 4. 消融（起点 2026-07，分母固定为 2026-07 观测值）----
## 年度通道在各起点最后一行的 mask=1 行数（训练窗内最多几行）
res$ann_mask_rows <- sapply(c("2024-09", "2024-12", "2025-01", "2025-06", "2026-07"),
                            function(o) sum(ns$.lstm_feature_window("FL", o)[, 7]))
if (has_c1) {
win_2501 <- lapply(S, function(s) ns$.lstm_feature_window(s, "2025-01")); names(win_2501) <- S
## 训练起点上见过的最大 age（只看有数据的行；无数据行的 age 是哨兵值 60/60）
c1_age_train_max <- max(vapply(win_2501, function(w) max(w[w[, 10] == 1, 11]), numeric(1)))
stopifnot(abs(c1_age_train_max - 1 / 60) < 1e-12)
## 超额跳幅与 c1 age 的走势：2024-01 起每个起点的 age（各州相同）和 excess
bt$c1_age_months <- vapply(bt$origin, function(o) ns$.lstm_feature_window("FL", o)[36, 11] * 60, numeric(1))
res$excess_vs_c1_age <- bt[bt$origin >= "2024-01", c("origin", "c1_age_months", "pred_ratio", "true_ratio", "excess")]
res$cor_excess_c1_age_2024on <- with(bt[bt$origin >= "2024-01" & is.finite(bt$excess), ],
                                     cor(excess, c1_age_months, method = "spearman"))
}
pz <- fit$transforms$zpar
mm_of <- function(s) fit$transforms$price_minmax[[s]]
set_last_price <- function(w, s, p_new) {  # 只改最后一行的价格及其衍生通道（mom、rel12 只依赖到当月）
  p <- ph[s, ]; p[jo] <- p_new
  mm <- mm_of(s)
  w[36, 1] <- 2 * (p_new - mm$min) / (mm$max - mm$min) - 1
  w[36, 2] <- (p[jo] / p[jo - 1] - 1 - pz$mom[1]) / pz$mom[2]
  w[36, 3] <- (p[jo] / mean(p[(jo - 11):jo]) - 1 - pz$rel12[1]) / pz$rel12[2]
  w
}
ann_prev <- function(w) {  # 2025-10 起的 2024 年值换回上一次发布（2023 年值），age 顺延
  k <- which(M[(jo - 35):jo] >= "2025-10")
  w[k, 6] <- w[min(k) - 1, 6]
  w[k, 8] <- pmin(w[min(k) - 1, 8] + seq_along(k) / 60, 1)
  w
}
abl <- list(
  baseline = function(w, s) w,
  ann_prev_release = function(w, s) ann_prev(w),
  ann_clip_pm1 = function(w, s) { w[, 6] <- pmin(pmax(w[, 6], -1), 1); w },
  ann_zero = function(w, s) { w[, 6] <- 0; w },
  price_clip_pm1 = function(w, s) { w[, 1] <- pmin(pmax(w[, 1], -1), 1); w },
  price_jul_eq_jun = function(w, s) set_last_price(w, s, ph[s, jo - 1]),
  price_jul_eq_yoy = function(w, s) set_last_price(w, s, ph[s, "2025-07"] * ph[s, "2026-06"] / ph[s, "2025-06"]),
  mom_rel12_last_zero = function(w, s) { w[36, 2:3] <- 0; w },
  season_shift_back_1m = function(w, s) {  # 假装窗口晚一个月结束前的季节相位（只换 sin/cos）
    mon <- as.integer(substr(M[(jo - 35):jo], 6, 7)) - 1L
    w[, 4] <- sin(2 * pi * mon / 12); w[, 5] <- cos(2 * pi * mon / 12); w
  },
  c1_zero = function(w, s) { w[, 9:11] <- 0; w },
  price_and_ann_clip = function(w, s) { w[, 1] <- pmin(pmax(w[, 1], -1), 1); w[, 6] <- pmin(pmax(w[, 6], -1), 1); w },
  ## EIA-112 只有 2024 年，此后向前填充、age 单调增长；训练最后一个起点 2025-01 的 age 只有 1 个月
  c1_age_cap_train = function(w, s) { k <- w[, 10] == 1; w[k, 11] <- pmin(w[k, 11], c1_age_train_max); w },
  c1_frozen_at_2025_01 = function(w, s) { w[, 9:11] <- win_2501[[s]][, 9:11]; w },
  ## eia861_annual_slim 只有 2023..2025 年：按发布日期，首个值 2024-10 才进入，训练窗里几乎全是"无数据"
  ann_as_no_data = function(w, s) { w[, 6] <- 0; w[, 7] <- 0; w[, 8] <- 1; w },
  ann_no_data_and_c1_age_cap = function(w, s) {
    w[, 6] <- 0; w[, 7] <- 0; w[, 8] <- 1; k <- w[, 10] == 1; w[k, 11] <- pmin(w[k, 11], c1_age_train_max); w },
  ann_no_data_c1_age_cap_price_clip = function(w, s) {
    w[, 6] <- 0; w[, 7] <- 0; w[, 8] <- 1; k <- w[, 10] == 1; w[k, 11] <- pmin(w[k, 11], c1_age_train_max)
    w[, 1] <- pmin(pmax(w[, 1], -1), 1); w },
  c1_age_cap_and_price_clip = function(w, s) {
    k <- w[, 10] == 1; w[k, 11] <- pmin(w[k, 11], c1_age_train_max); w[, 1] <- pmin(pmax(w[, 1], -1), 1); w }
)
if (!has_c1) abl <- abl[!grepl("c1", names(abl))]
res$ablation <- t(sapply(abl, function(f) {
  p1 <- fwd(lapply(S, function(s) f(win[[s]], s)), S)[, 1]
  r <- p1 / obs_jul
  c(summ(r), median_err_vs_true = median(r - true_r), mse_vs_true_aug = mean((p1 - true_aug)^2))
}))

utils::write.csv(per_state, file.path(out_dir, "seam_per_state.csv"), row.names = FALSE)
saveRDS(res, file.path(out_dir, "seam_diagnosis.rds"))
op <- options(digits = 4)
for (nm in names(res)) { cat("\n==", nm, "==\n"); print(res[[nm]]) }
options(op)

## ---- 4b. 同一截断用于 2024-01 以来每个起点：超额跳幅的时间趋势是否消失（仅旧拟合）----
if (has_c1) {
fix_w <- function(w) { k <- w[, 10] == 1; w[k, 11] <- pmin(w[k, 11], c1_age_train_max)
  w[, 1] <- pmin(pmax(w[, 1], -1), 1); w }
cap_age <- function(w) { k <- w[, 10] == 1; w[k, 11] <- pmin(w[k, 11], c1_age_train_max); w }
bt2 <- do.call(rbind, lapply(M[match("2024-01", M):jo], function(o) {
  j <- match(o, M)
  ws <- lapply(S, function(s) ns$.lstm_feature_window(s, o))
  tr1 <- if (o == O) true_aug else ph[, j + 1]
  r0 <- fwd(ws, S)[, 1] / ph[, j]; r1 <- fwd(lapply(ws, cap_age), S)[, 1] / ph[, j]
  r2 <- fwd(lapply(ws, fix_w), S)[, 1] / ph[, j]; rt <- tr1 / ph[, j]
  data.frame(origin = o, excess_shipped = median(r0 - rt), excess_age_cap = median(r1 - rt),
             excess_age_cap_price_clip = median(r2 - rt))
}))
bt2$period <- ifelse(bt2$origin <= "2025-01", "2024-01..2025-01 (age<=1)", "2025-02..2026-07 (age 2..19)")
res$backtest_capped <- aggregate(cbind(excess_shipped, excess_age_cap, excess_age_cap_price_clip) ~ period,
                                 data = bt2, FUN = function(x) mean(abs(x)))
res$backtest_capped_median <- aggregate(cbind(excess_shipped, excess_age_cap, excess_age_cap_price_clip) ~ period,
                                        data = bt2, FUN = median)
utils::write.csv(bt2, file.path(out_dir, "seam_backtest_capped.csv"), row.names = FALSE)
saveRDS(res, file.path(out_dir, "seam_diagnosis.rds"))
cat("\n== backtest_capped (mean |excess|) ==\n"); print(res$backtest_capped, digits = 3)
cat("\n== backtest_capped (median excess) ==\n"); print(res$backtest_capped_median, digits = 3)
}
