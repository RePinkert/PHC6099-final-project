# rebuild_fit_without_bias.R —— 一次性：从已冻结的权重重算去掉偏差校正后的台账（纯 R，无需 torch）
# 背景：b02e8fc 的重训在早停窗估计了每个 h 的偏差并乘到点预测上。复核发现它与校准窗方向相反、
#   校准窗 MSE 反而变差（2.224 -> 2.274），于是撤掉校正。权重不变（训练本身不依赖校正），
#   只需重放 walk-forward 三元组（origin 2025-06..2026-02，与 train_price_lstm.R 的 origins_val 相同），
#   按 train_price_lstm.R 同一公式重算 intervals / coverage / baselines / forecast / golden。
# 重新运行 train_price_lstm.R（已改为只报告、不应用偏差）会得到同一结果。
# 运行：先 R CMD INSTALL .（服务端已不乘 point_bias），再 Rscript model_traning/rebuild_fit_without_bias.R

suppressMessages(library(lifewatt))
ns <- asNamespace("lifewatt")
path <- "inst/extdata/price_lstm_fit.rds"
fit <- readRDS(path)
stopifnot(!is.null(fit$point_bias))  # 只在仍带校正的旧台账上运行一次
ph <- ns$.price_history_wide()
months <- colnames(ph)
H <- fit$h_max

trip <- list()
for (o in months[match("2025-06", months):match("2026-02", months)]) {
  j0 <- match(o, months)
  for (s in rownames(ph)) {
    w <- ns$.lstm_feature_window(s, o)
    y <- ns$.lstm_denorm(ns$.lstm_forward_norm(array(w, c(1, dim(w))))[1, ], s)
    for (h in seq_len(H)) {
      trip[[length(trip) + 1L]] <- data.frame(
        state = s, h = h, target = months[j0 + h], pred = y[h], true = ph[s, j0 + h],
        seas = ph[s, if (j0 + h - 12 >= 1) j0 + h - 12 else j0], last = ph[s, j0],
        stringsAsFactors = FALSE)
    }
  }
}
trip <- do.call(rbind, trip)
trip$rel <- (trip$true - trip$pred) / trip$pred
es_trips <- trip[trip$target <= "2026-01", ]
cal_trips <- trip[trip$target >= "2026-02", ]
es_bias_diagnostic <- vapply(seq_len(H), function(h) stats::median(es_trips$rel[es_trips$h == h]), numeric(1))
## 对账：重放出的早停窗偏差须与旧台账里训练时估计的 point_bias 一致
stopifnot(max(abs(es_bias_diagnostic - fit$point_bias)) < 1e-6)

mse <- function(a, b) mean((a - b)^2)
diag <- data.frame(
  model = c("lstm", "seasonal_naive", "last_value"),
  mse_es = c(mse(es_trips$true, es_trips$pred), mse(es_trips$true, es_trips$seas),
             mse(es_trips$true, es_trips$last)),
  mse_cal = c(mse(cal_trips$true, cal_trips$pred), mse(cal_trips$true, cal_trips$seas),
              mse(cal_trips$true, cal_trips$last)),
  mae_es = c(mean(abs(es_trips$true - es_trips$pred)), mean(abs(es_trips$true - es_trips$seas)),
             mean(abs(es_trips$true - es_trips$last)))
)
stopifnot(max(abs(diag$mse_cal[2:3] - fit$baselines$mse_cal[2:3])) < 1e-9)  # 基线不受影响

qfun <- function(x, pr) unname(stats::quantile(x, pr, na.rm = TRUE))
iv <- do.call(rbind, lapply(seq_len(H), function(h) {
  r <- cal_trips$rel[cal_trips$h == h]
  ar <- abs(r)
  data.frame(h = h, n = length(r),
             r_q05 = qfun(r, 0.05), r_q50 = qfun(r, 0.50), r_q95 = qfun(r, 0.95),
             abs_q50 = qfun(ar, 0.50), abs_q85 = qfun(ar, 0.85), abs_q95 = qfun(ar, 0.95),
             stringsAsFactors = FALSE)
}))
cov_cal <- sapply(seq_len(H), function(h) mean(abs(cal_trips$rel[cal_trips$h == h]) <= iv$abs_q85[h]))
cov_transfer <- sapply(seq_len(H), function(h) mean(abs(es_trips$rel[es_trips$h == h]) <= iv$abs_q85[h]))

states <- rownames(ph)
fc <- do.call(rbind, lapply(states, function(s) {
  w <- ns$.lstm_feature_window(s, fit$fit_as_of)
  pr <- ns$.lstm_denorm(ns$.lstm_forward_norm(array(w, c(1, dim(w))))[1, ], s)
  data.frame(state = s, period = sprintf("2026-%02d", 8:12), h = seq_len(H), price = pr,
             sd = pr * iv$abs_q85 / stats::qnorm(0.925),
             q_lo = pr * (1 + iv$r_q05), q_hi = pr * (1 + iv$r_q95), stringsAsFactors = FALSE)
}))
row.names(fc) <- NULL

fit$contract <- sub(
  "point = bias-corrected LSTM direct multi-horizon h=1..5 (per-h relative residual median estimated on early-stop window only; ",
  "point = LSTM direct multi-horizon h=1..5, no bias correction (",
  fit$contract, fixed = TRUE)
stopifnot(grepl("no bias correction", fit$contract, fixed = TRUE))
fit$point_bias <- NULL
fit$es_bias_diagnostic <- es_bias_diagnostic
fit$intervals <- iv
fit$coverage <- list(calib_in_sample = cov_cal, transfer_early_window = cov_transfer)
fit$baselines <- diag
fit$forecast <- fc
fit$golden <- fc[fc$state %in% c("FL", "AK", "CA", "DC", "NY", "TX") &
                   fc$period %in% c("2026-08", "2026-10", "2026-12"), ]
saveRDS(fit, path)
cat("== rebuilt", path, "without bias correction ==\n")
print(diag); print(iv)
print(rbind(calib = cov_cal, transfer = cov_transfer))
