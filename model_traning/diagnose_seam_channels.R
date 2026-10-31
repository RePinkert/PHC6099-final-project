# diagnose_seam_channels.R —— 第二轮接缝诊断：逐通道消融 + 起点输入相对训练分布的位置（纯 R 前向）
# 背景：v2 第一次重训（删 c1、年度通道补到 2010）后跳幅 1.064 -> 1.038，仍未过 A1/A2。
# 训练分布的参照 = 训练样本实际见过的输入：各州、输入月 <= 2025-01（最后一个训练起点）。
# 消融（起点 2026-07，分母为 2026-07 观测值；只改输入窗，不改权重）：
#   typical：每行换成该州训练期同一日历月的中位数（年度通道不分月，用该州训练期中位数）
#   clip   ：截到该州训练期的 [min, max]
#   zero   ：置 0（zscore 通道的训练均值；minmax 通道的区间中点）
#   *_last12：只替换最近 12 个月（2025-08..2026-07），检验 2025-26 的高同比是否是驱动项
# 运行：Rscript model_traning/diagnose_seam_channels.R [输出目录]（需先安装本包）

suppressMessages(library(lifewatt))
ns <- asNamespace("lifewatt")
out_dir <- if (length(commandArgs(TRUE))) commandArgs(TRUE)[1] else "."
fit <- ns$.price_lstm_fit()
ph <- ns$.price_history_wide()
M <- colnames(ph); S <- rownames(ph)
O <- "2026-07"; jo <- match(O, M)
memo <- function(f) { force(f); cache <- list(); function(months, ...) {
  k <- paste(length(months), months[1], months[length(months)], ...)
  if (is.null(cache[[k]])) cache[[k]] <<- f(months, ...)
  cache[[k]]
} }
for (nm in c(".ann_wide", ".c1_wide")) {
  unlockBinding(nm, ns); assign(nm, memo(get(nm, ns)), envir = ns); lockBinding(nm, ns)
}
cn <- fit$chan_names
fwd1 <- function(ws) {
  X <- array(NA_real_, c(length(ws), dim(ws[[1]])))
  for (i in seq_along(ws)) X[i, , ] <- ws[[i]]
  yn <- ns$.lstm_forward_norm(X)
  vapply(seq_along(S), function(i) ns$.lstm_denorm(yn[i, ], S[i])[1], numeric(1))
}

## 每个月的通道值（取以该月为起点的输入窗最后一行），2012-12..2026-07
ser_m <- M[match("2012-12", M):jo]
ser <- array(NA_real_, c(length(S), length(ser_m), length(cn)), dimnames = list(S, ser_m, cn))
for (o in ser_m) for (s in S) ser[s, o, ] <- ns$.lstm_feature_window(s, o)[fit$seq_len, ]
tr <- ser_m <= "2025-01"
mon_of <- as.integer(substr(ser_m, 6, 7))

## 起点（2026-07）相对训练分布的位置
win <- lapply(S, function(s) ns$.lstm_feature_window(s, O)); names(win) <- S
pos <- t(sapply(cn, function(k) {
  pool <- as.vector(ser[, tr, k])
  last <- ser[, O, k]
  lo <- apply(ser[, tr, k], 1, min); hi <- apply(ser[, tr, k], 1, max)
  j <- match(k, cn); wmax <- sapply(S, function(s) max(win[[s]][, j])); wmin <- sapply(S, function(s) min(win[[s]][, j]))
  c(origin_median = median(last), origin_pctile_in_pooled_train = mean(pool <= median(last)),
    states_last_above_own_train_max = mean(last > hi + 1e-12),
    states_last_below_own_train_min = mean(last < lo - 1e-12),
    states_window_outside_own_range = mean(wmax > hi + 1e-12 | wmin < lo - 1e-12),
    train_pooled_q01 = unname(quantile(pool, 0.01)), train_pooled_q99 = unname(quantile(pool, 0.99)))
}))

## 消融
hist_max <- apply(sapply(2015:2025, function(y) ph[, sprintf("%d-08", y)] / ph[, sprintf("%d-07", y)]), 1, max)
wm <- M[(jo - fit$seq_len + 1):jo]; wmon <- as.integer(substr(wm, 6, 7))
last12 <- wm >= "2025-08"
typ <- function(s, k) {  # 该州训练期同月中位数（年度通道不分月）
  x <- ser[s, tr, k]
  if (grepl("^ann", k)) return(rep(median(x), length(wm)))
  vapply(wmon, function(m) median(x[mon_of[tr] == m]), numeric(1))
}
rng <- function(s, k) range(ser[s, tr, k])
mk <- function(chs, mode, rows = rep(TRUE, length(wm))) { force(chs); force(mode); force(rows); function(w, s) {
  for (k in chs) {
    j <- match(k, cn)
    w[rows, j] <- switch(mode,
      typical = typ(s, k)[rows],
      clip = pmin(pmax(w[rows, j], rng(s, k)[1]), rng(s, k)[2]),
      zero = 0)
  }
  w
} }
abl <- list(baseline = function(w, s) w)
for (g in list(price_mm = "price_mm", mom_z = "mom_z", rel12_z = "rel12_z", ann_mm = "ann_mm",
               season = c("sin12", "cos12"))) {
  nm <- paste(g, collapse = "+")
  if (!identical(g, c("sin12", "cos12"))) {
    abl[[paste0(nm, ":clip")]] <- mk(g, "clip")
    abl[[paste0(nm, ":typical")]] <- mk(g, "typical")
    abl[[paste0(nm, ":zero")]] <- mk(g, "zero")
  }
  if (g[1] %in% c("mom_z", "rel12_z")) {
    abl[[paste0(nm, ":typical_last12")]] <- mk(g, "typical", last12)
    abl[[paste0(nm, ":clip_last12")]] <- mk(g, "clip", last12)
  }
}
abl[["season:shift_back_1m"]] <- function(w, s) {
  m <- wmon - 1L; w[, match("sin12", cn)] <- sin(2 * pi * m / 12); w[, match("cos12", cn)] <- cos(2 * pi * m / 12); w }
abl[["ann_mask+age:typical"]] <- mk(c("ann_mask", "ann_age"), "typical")
abl[["mom_z+rel12_z:typical_last12"]] <- mk(c("mom_z", "rel12_z"), "typical", last12)
abl[["price_mm+ann_mm:clip"]] <- mk(c("price_mm", "ann_mm"), "clip")
abl[["price_mm+mom_z+rel12_z+ann_mm:clip"]] <- mk(c("price_mm", "mom_z", "rel12_z", "ann_mm"), "clip")
obs <- ph[, O]
ablation <- t(sapply(abl, function(f) {
  r <- fwd1(lapply(S, function(s) f(win[[s]], s))) / obs
  c(seam_median = median(r), over_hist_max = mean(r > hist_max))
}))

## ann_mm 越界的来源：2024 年值（2025-10 进入）相对各州训练期年度值范围
a <- utils::read.csv(system.file("extdata", "eia861_state_annual.csv.gz", package = "lifewatt"))
ann_src <- data.frame(state = S,
  train_max_value = sapply(S, function(s) max(a$price[a$state == s & a$year <= 2023])),
  value_2024 = sapply(S, function(s) a$price[a$state == s & a$year == 2024]))
ann_src$above <- ann_src$value_2024 > ann_src$train_max_value
ann_src$ann_mm_at_origin <- ser[, O, "ann_mm"]

## 回测：每个起点 h=1 预测/末值 vs 真实（中位数），按年汇总
bt <- utils::read.csv(file.path(out_dir, "seam_backtest_all_origins.csv"), stringsAsFactors = FALSE)
bt$year <- substr(bt$origin, 1, 4); bt$month <- as.integer(substr(bt$origin, 6, 7))
by_year <- do.call(rbind, lapply(split(bt, bt$year), function(d) data.frame(
  year = d$year[1], pred_ratio = median(d$pred_ratio), true_ratio = median(d$true_ratio, na.rm = TRUE),
  excess_median = median(d$excess, na.rm = TRUE),
  excess_jun_aug_origins = median(d$excess[d$month %in% 6:8], na.rm = TRUE))))
by_month <- do.call(rbind, lapply(split(bt[bt$origin <= "2024-12", ], bt$month[bt$origin <= "2024-12"]), function(d)
  data.frame(origin_month = d$month[1], excess_2013_2024 = median(d$excess, na.rm = TRUE))))

res <- list(position_at_origin = pos, ablation = ablation, ann_source = ann_src,
            ann_2024_above_train_max_share = mean(ann_src$above), backtest_by_year = by_year,
            backtest_by_origin_month = by_month)
saveRDS(res, file.path(out_dir, "seam_channels.rds"))
op <- options(digits = 4, width = 140)
for (nm in setdiff(names(res), "ann_source")) { cat("\n==", nm, "==\n"); print(res[[nm]]) }
cat("\n== ann_source (head) ==\n"); print(head(ann_src[order(-ann_src$ann_mm_at_origin), ], 8), row.names = FALSE)
options(op)
