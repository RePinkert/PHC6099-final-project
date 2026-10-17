source("autoresearch/prepare.R")
code <- paste(readLines("autoresearch/train.R"), collapse = "\n")
tailpos <- regexpr("if [(]sys[.]nf", code)[1]
eval(parse(text = substring(code, 1, tailpos - 1)))
data <- prepare_data()
data <- data[order(data$state, data$period), ]  # evaluate_model 同款排序：州序 × 月序
model <- fit_model_fn(data)
hist <- model$train
params <- model$params
pb <- structure(params$b, names = params$state)
pv <- structure(params$v0, names = params$state)
pt <- structure(params$t0, names = params$state)
tt <- as.numeric(as.Date(paste0(hist$period, "-01")))
prev12 <- format(as.Date(paste0(hist$period, "-01")) - 365.25, "%Y-%m")
lagv <- structure(hist$price, names = paste(hist$state, hist$period))[paste(hist$state, prev12)]
tlag <- as.numeric(as.Date(paste0(prev12, "-01")))
drift_pred <- lagv + pb[hist$state] * (tt - tlag)                        # 成员1: lag12 + 12m 窗漂移（exp#19）
anchor_pred <- pv[hist$state] + pb[hist$state] * (tt - pt[hist$state])   # 成员2: 末端水平 + 漂移
## 成员3: HW(additive) 的 in-sample fitted.values，按 ts 起点与该州序列逐月对齐。
## 2026-10-16 勘误：旧实现 fitted(f)[1] 对每行取同一首行值 -> HW 成员退化为每州常量。
## R 源码事实（stats:::HoltWinters）：fitted 为 3 列 mts(col1=xhat=level+trend+season)，
## ts 起点 = lag(x, k = 1 - start.time) => 行 k ↔ 月份 12+k（前 12 月为季节初始化窗，不被覆盖），
## 行数 = n - 12（实测 AK 等 51 州全部 31 = 43-12）。
hwp <- rep(NA_real_, nrow(hist))
for (st in unique(hist$state)) {
  idx <- which(hist$state == st)
  f <- model$hw[[st]]
  if (is.null(f)) next
  fv <- stats::fitted(f)
  if (is.matrix(fv)) fv <- fv[, 1]
  fv <- as.numeric(fv)
  off <- length(idx) - length(fv)   # 季节初始化覆盖数（月频 12 时恒为 12）
  stopifnot(off == 12)
  hwp[idx[(off + 1):length(idx)]] <- unname(fv)
}
## 阶段A v2 契约 = 三体均值（exp#24），不是旧实现的二成员 blend
m3 <- cbind(drift_pred, anchor_pred, hwp)
n_ok <- rowSums(!is.na(m3))
blend_full <- rowMeans(m3, na.rm = TRUE)
blend_full[n_ok == 0] <- drift_pred[n_ok == 0]
resid_full <- abs(hist$price - blend_full)

## 一致性 gate（program.md 口径，2026-10-16 勘误统一）：
##   分子 = 全量重训 in-sample 残差 MAD（2025-07..2026-07，51 州池化，三体均值口径）
##   分母 = 阶段A 模型 valid 残差 MAD（train<=2025-06 拟合 + predict_fn 盲区预测，与 mase .5966 同管线）
##   比值 <= 1.5 -> 重训未漂移；超标 -> keep_at_risk（不 stop，flag 落 rds，下游裁决）
## 旧 .606 作废：旧分子/分母是 head12/tail12 各取 12 行，落在单一州的数据块上，且二成员口径。
in_win <- hist$period >= "2025-07" & hist$period <= "2026-07"
m_num <- stats::mad(resid_full[in_win], na.rm = TRUE)
split <- as.Date("2025-06-01")
tvals <- as.Date(paste0(hist$period, "-01"))
model_a <- fit_model_fn(hist[tvals <= split, ])
pred_a <- predict_fn(model_a, hist[tvals >  split, ])   # valid 残差，与阶段A mase 的分子同源
m_den <- stats::mad(abs(pred_a$price - hist$price[tvals > split]), na.rm = TRUE)
ratio <- m_num / m_den
gate_pass <- is.finite(ratio) && ratio <= 1.5
cat(sprintf("consistency_tail_ratio: %.4f (gate <= 1.5; numerator in-sample 2025-07..2026-07 pooled)\n", ratio))
cat(sprintf("m_num=%.4f | m_den(phaseA valid MAD)=%.4f cents/kWh | gate_pass=%s\n", m_num, m_den, gate_pass))
if (!gate_pass) cat("keep_at_risk: full-refit is at-risk; downstream must label price_draws accordingly\n")

save_data <- list(
  fit_as_of = "2026-07",
  fit_protocol = "ts-split 2025-06 (30 train / 13 valid months, phaseA exp#2..#27) + full-refit 2023-01..2026-07 (phaseB)",
  phase_a_split = "2025-06",
  valid_window = "2025-07..2026-07",
  contract = "point = triplet mean {lag12+12m drift, v0+b*h, HW additive}; interval = drift-member origin-sim horizon-binned q85 (train.R::predict_fn)",
  params = params, hw = model$hw, states = sort(unique(data$state)),
  consistency_tail_ratio = ratio,
  consistency_note = "phaseB in-sample |resid| MAD (2025-07..2026-07, all states pooled, triplet blend) / phaseA valid |resid| MAD (same pipeline as mase .5966)",
  gate_pass = gate_pass
)
saveRDS(save_data, "data-raw/price_forecast_fit.rds")
cat("saved data-raw/price_forecast_fit.rds | blended in-sample MAE:",
    sprintf("%.4f cents/kWh\n", mean(resid_full, na.rm = TRUE)))
