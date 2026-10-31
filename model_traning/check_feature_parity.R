# check_feature_parity.R —— 训练前检查：prepare.R 的特征阵列与服务端 .lstm_feature_window 逐值一致
# 不需要 torch，也不需要权重：用 prepare.R 的变换参数拼一个"只有变换、没有权重"的临时 fit 注入服务端，
#   在若干起点上比较两侧 36 x n_chan 的输入窗。重训前先跑它，避免训练和服务口径悄悄分叉。
# 运行：先 R CMD INSTALL .，再 Rscript model_traning/check_feature_parity.R

source("model_traning/prepare.R")
suppressMessages(library(lifewatt))
ns <- asNamespace("lifewatt")

P <- load_price_wide(".")
annrel <- ann_rel_covariate(P, ".")
tf <- fit_transforms(P, MONTHS, "2025-06")
feat <- build_price_features(P, annrel, tf)
H <- 5L
tt <- fit_target_transform(P, seq(36L, match("2025-06", MONTHS) - H), H)  # 同 train_price_lstm.R 的 origins_train
probe <- list(seq_len = 36L, n_chan = dim(feat$arr)[3], chan_names = feat$chan, h_max = H,
              fit_as_of = "2026-07",
              transforms = list(zpar = feat$zpar, ann_source = ANN_SOURCE,
                                target = list(type = tt$type, mu = unname(tt$mu), sd = unname(tt$sd))))

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

## 目标反变换：训练侧 target_denorm 与服务端 .lstm_denorm 一致，且 target_norm 的逆
set.seed(1)
tdev <- 0
for (o in origins) for (s in STATES) {
  j <- match(o, MONTHS); y <- stats::rnorm(H)
  tdev <- max(tdev, abs(ns$.lstm_denorm(y, s, o) - target_denorm(y, P[s, j], tt)))
  if (j + H <= N_MONTHS) {
    tdev <- max(tdev, abs(target_denorm(target_norm(P, s, j, H, tt), P[s, j], tt) - P[s, j + seq_len(H)]))
  }
}
cat(sprintf("target: %s, max |train - serve| denorm and round-trip: %.2e\n", tt$type, tdev))
stopifnot(tdev < 1e-9)

## 年度通道在训练窗里的覆盖（修复的目的就是让它在整个训练窗都有数据）
tr_last <- match("2025-01", MONTHS)
cov <- mean(annrel$mask[, 36:tr_last])
cat(sprintf("annual channel: mask=1 share over training input months %.3f; first stamp %s\n",
            cov, MONTHS[which(colSums(annrel$mask) > 0)[1]]))
cat("feature parity OK\n")
