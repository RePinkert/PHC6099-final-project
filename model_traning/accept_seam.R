# accept_seam.R —— 重训验收（标准在重训前固定，2026-10-31；重训后不得修改）
# 背景：接缝诊断（diagnose_seam.R）发现 2026-08 跳幅来自只在训练末尾出现的稀疏协变量。
#   修复：删掉 EIA-112 c1 通道；年度 EIA-861 通道补齐 2010..2025。架构、种子、fit_as_of = 2026-07、
#   训练/早停/校准窗都不变。
# 判定（三条都过才算通过，不依赖 2026-08 真值）：
#   A1 第一个预测月：2026-08 预测 / 2026-07 观测 的跨州中位数在 [0.99, 1.015]
#   A2 超过本州 2015..2025 最大 Aug/Jul 比值的州 <= 15%
#   A3 校准窗（目标 2026-02..07）MSE 低于末值基线（用随包权重重放计算，并与 fit$baselines 对账）
# 另报（不参与判定）：2026-08 单月 MSE 对末值 / 季节朴素。2026-08 已在接缝诊断中看过，
#   所以这一项不是干净的样本外检验，只作参考。
# 运行：先 R CMD INSTALL .，再 Rscript model_traning/accept_seam.R；不通过时退出码为 1

suppressMessages(library(lifewatt))
ns <- asNamespace("lifewatt")
fit <- ns$.price_lstm_fit()
ph <- ns$.price_history_wide()
M <- colnames(ph)
S <- rownames(ph)
fwd1 <- function(o) {
  X <- array(NA_real_, c(length(S), fit$seq_len, fit$n_chan))
  for (i in seq_along(S)) X[i, , ] <- ns$.lstm_feature_window(S[i], o)
  yn <- ns$.lstm_forward_norm(X)
  t(vapply(seq_along(S), function(i) ns$.lstm_denorm(yn[i, ], S[i], o), numeric(fit$h_max)))
}
cat("fit channels:", paste(fit$chan_names, collapse = ", "), "\n")

## A1 / A2
aug <- ns$.lstm_predict(S, rep("2026-08", length(S)))$price
ratio <- aug / ph[, "2026-07"]
hist_max <- apply(sapply(2015:2025, function(y) ph[, sprintf("%d-08", y)] / ph[, sprintf("%d-07", y)]), 1, max)
a1 <- median(ratio)
a2 <- mean(ratio > hist_max)

## A3：重放校准窗三元组（origin 2025-06..2026-02）
trip <- list()
for (o in M[match("2025-06", M):match("2026-02", M)]) {
  j0 <- match(o, M); y <- fwd1(o)
  for (h in seq_len(fit$h_max)) {
    if (M[j0 + h] >= "2026-02") {
      trip[[length(trip) + 1L]] <- data.frame(pred = y[, h], true = ph[, j0 + h], last = ph[, j0])
    }
  }
}
trip <- do.call(rbind, trip)
mse_lstm <- mean((trip$true - trip$pred)^2)
mse_last <- mean((trip$true - trip$last)^2)
bl <- fit$baselines
stopifnot(abs(mse_lstm - bl$mse_cal[bl$model == "lstm"]) < 1e-4,
          abs(mse_last - bl$mse_cal[bl$model == "last_value"]) < 1e-9)

verdict <- data.frame(
  criterion = c("A1 seam median 2026-08/07 in [0.99, 1.015]",
                "A2 states above own Aug/Jul max <= 15%",
                "A3 calibration MSE < last value"),
  value = c(sprintf("%.4f", a1), sprintf("%.1f%%", 100 * a2),
            sprintf("%.3f vs %.3f", mse_lstm, mse_last)),
  pass = c(a1 >= 0.99 && a1 <= 1.015, a2 <= 0.15, mse_lstm < mse_last))
print(verdict, row.names = FALSE)

## 另报：2026-08 单月（需要 data-raw/eia861m/sales_revenue.xlsx；不参与判定）
src <- "data-raw/eia861m/sales_revenue.xlsx"
if (file.exists(src)) {
  raw <- readxl::read_excel(src, sheet = "Monthly-States", skip = 3, col_names = FALSE,
                            col_types = "text", .name_repair = "minimal")
  ym <- sprintf("%s-%02d", raw[[1]], suppressWarnings(as.integer(raw[[2]])))
  k <- ym == "2026-08"
  tru <- setNames(suppressWarnings(as.numeric(raw[[8]][k])), raw[[3]][k])[S]
  if (all(is.finite(tru))) {
    seas <- ph[, "2025-08"] / ph[, "2025-07"] * ph[, "2026-07"]
    cat(sprintf(paste0("\n[report only; 2026-08 was seen in the seam diagnosis] 2026-08 MSE: ",
                       "lstm %.3f | last value %.3f | seasonal ratio (2025 Aug/Jul x 2026-07) %.3f | true Aug/Jul median %.4f\n"),
                mean((aug - tru)^2), mean((ph[, "2026-07"] - tru)^2), mean((seas - tru)^2),
                median(tru / ph[, "2026-07"])))
  }
}
if (!all(verdict$pass)) {
  cat("\nACCEPTANCE: FAIL\n")
  quit(status = 1)
}
cat("\nACCEPTANCE: PASS\n")
