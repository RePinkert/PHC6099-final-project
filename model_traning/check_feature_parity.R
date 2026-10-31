# check_feature_parity.R —— 训练前检查：prepare.R 的特征阵列与服务端 .lstm_feature_window 逐值一致
# 不需要 torch，也不需要权重：用 prepare.R 的变换参数拼一个"只有变换、没有权重"的临时 fit 注入服务端，
#   在若干起点上比较两侧 36 x n_chan 的输入窗。重训前先跑它，避免训练和服务口径悄悄分叉。
# 运行：先 R CMD INSTALL .，再 Rscript model_traning/check_feature_parity.R

source("model_traning/prepare.R")
suppressMessages(library(lifewatt))
ns <- asNamespace("lifewatt")

P <- load_price_wide(".")
ann <- load_ann_covariate(".")
tf <- fit_transforms(P, MONTHS, "2025-06")
feat <- build_price_features(P, ann, tf)
probe <- list(seq_len = 36L, n_chan = dim(feat$arr)[3], chan_names = feat$chan,
              transforms = list(price_minmax = tf$price_minmax, zpar = feat$zpar,
                                ann_rng = feat$ann_rng, ann_source = ANN_SOURCE))

real <- ns$.price_lstm_fit
unlockBinding(".price_lstm_fit", ns)
assign(".price_lstm_fit", function() probe, envir = ns)
on.exit({ assign(".price_lstm_fit", real, envir = ns); lockBinding(".price_lstm_fit", ns) })

origins <- c("2012-12", "2015-07", "2020-01", "2024-09", "2024-10", "2025-01", "2025-06", "2026-07")
dev <- 0
for (o in origins) {
  j <- match(o, MONTHS)
  for (s in STATES) {
    w <- ns$.lstm_feature_window(s, o)
    dev <- max(dev, max(abs(w - feat$arr[s, (j - 35):j, ])))
  }
}
cat(sprintf("channels: %s\nmax |train - serve| over %d origins x 51 states: %.2e\n",
            paste(feat$chan, collapse = ", "), length(origins), dev))
stopifnot(dev < 1e-12)

## 年度通道在训练窗里的覆盖（修复的目的就是让它在整个训练窗都有数据）
tr_last <- match("2025-01", MONTHS)
cov <- mean(ann$mask[, 36:tr_last])
cat(sprintf("annual channel: mask=1 share over training input months %.3f; first stamp %s\n",
            cov, MONTHS[which(colSums(ann$mask) > 0)[1]]))
cat("feature parity OK\n")
