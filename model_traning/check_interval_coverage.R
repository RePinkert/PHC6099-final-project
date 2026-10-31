# check_interval_coverage.R —— 区间覆盖复核（纯 R，无需 torch，约 30 秒）
# 用包内冻结权重 + 随包数据重放 walk-forward 验证三元组（origin 2025-06..2026-02，h=1..5），
#   ① 先对账：重算的校准窗分位数须与 price_lstm_fit.rds$intervals 一致（float32 界内）；
#   ② 再报覆盖：
#      - calib_in_sample：同一批残差定分位、同一批量覆盖（按构造≈名义值，不是证据）；
#      - early_stop_window：早停选模型的窗口，不独立；
#      - leave-one-month-out：校准窗内每次留出一个目标月，用其余月份定分位、在留出月量覆盖，
#        这是唯一不复用同一批残差的检验（样本小：h=1 只有 2 个目标月）。
# 运行：Rscript model_traning/check_interval_coverage.R（需先安装本包）

suppressMessages(library(lifewatt))
ns <- asNamespace("lifewatt")
fit <- ns$.price_lstm_fit()
ph <- ns$.price_history_wide()
months <- colnames(ph)
H <- fit$h_max

trips <- list()
for (o in months[match("2025-06", months):match("2026-02", months)]) {
  j0 <- match(o, months)
  for (s in rownames(ph)) {
    w <- ns$.lstm_feature_window(s, o)
    y <- ns$.lstm_denorm(ns$.lstm_forward_norm(array(w, c(1, dim(w))))[1, ], s)
    for (h in seq_len(H)) {
      if (j0 + h <= length(months)) {
        trips[[length(trips) + 1L]] <- data.frame(state = s, origin = o, h = h, target = months[j0 + h],
                                                  pred = y[h], true = ph[s, j0 + h])
      }
    }
  }
}
trips <- do.call(rbind, trips)
trips$rel <- (trips$true - trips$pred) / trips$pred
cal <- trips[trips$target >= "2026-02", ]
es <- trips[trips$target <= "2026-01", ]
q <- function(x, p) unname(stats::quantile(x, p))
iv <- fit$intervals

rep_iv <- do.call(rbind, lapply(seq_len(H), function(h) {
  r <- cal$rel[cal$h == h]
  data.frame(h = h, n = length(r), r_q05 = q(r, 0.05), r_q95 = q(r, 0.95), abs_q85 = q(abs(r), 0.85))
}))
drift <- max(abs(as.matrix(rep_iv[, c("r_q05", "r_q95", "abs_q85")]) -
                 as.matrix(iv[, c("r_q05", "r_q95", "abs_q85")])))
stopifnot(identical(as.integer(rep_iv$n), as.integer(iv$n)), drift < 1e-6)
cat(sprintf("reproduction: n identical, max quantile drift %.1e\n\n", drift))

asym <- function(r, h) r >= iv$r_q05[h] & r <= iv$r_q95[h]
sym <- function(r, h) abs(r) <= iv$abs_q85[h]
by_h <- function(d, f) vapply(seq_len(H), function(h) mean(f(d$rel[d$h == h], h)), numeric(1))
lomo <- function(type) vapply(seq_len(H), function(h) {
  d <- cal[cal$h == h, ]
  hit <- unlist(lapply(unique(d$target), function(m) {
    fit_r <- d$rel[d$target != m]
    te <- d$rel[d$target == m]
    if (type == "asym") te >= q(fit_r, 0.05) & te <= q(fit_r, 0.95) else abs(te) <= q(abs(fit_r), 0.85)
  }))
  mean(hit)
}, numeric(1))

out <- rbind(
  `q_lo/q_hi (90%) calib_in_sample` = by_h(cal, asym),
  `q_lo/q_hi (90%) early_stop_window` = by_h(es, asym),
  `q_lo/q_hi (90%) leave-one-month-out` = lomo("asym"),
  `abs_q85 / .sd (85%) leave-one-month-out` = lomo("sym")
)
colnames(out) <- paste0("h", seq_len(H))
print(round(out, 3))
cat("\ncalibration target months per h:",
    vapply(seq_len(H), function(h) length(unique(cal$target[cal$h == h])), integer(1)), "\n")
cat("median relative residual per h (positive = forecast too low):",
    round(vapply(seq_len(H), function(h) stats::median(cal$rel[cal$h == h]), numeric(1)), 4), "\n")
