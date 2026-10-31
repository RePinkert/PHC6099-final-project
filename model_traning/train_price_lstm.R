# train_price_lstm.R —— Phase 0：电价 LSTM（替换 triplet 的预测 regime）
# 架构仿 RePinkert/A-demo-of-stock-model-use-case r/stock_prediction.Rmd：
#   自写 LSTMCell(candidate=relu, hidden=128->64)、minmax 仅训练集 fit、逐 epoch 训练；
# 显式偏离（model card 声明）：
#   1) 早停不用 test MSE（参照 demo 的泄漏不照搬），用 walk-forward 验证窗
#      （目标月 2025-07..2026-01）；
#   2) 区间校准用独立留出（目标月 2026-02..2026-07）的相对残差视界分位数
#      （修正 triplet 的 obs_max 选择偏差 / 跨州池化无尺度标准化）；
#   3) seq_len=36（月频年周期），多视界直接输出 h=1..5（2026-08..12 缺口）。
# 产物：inst/extdata/price_lstm_fit.rds（纯数值权重，无 torch 对象）+ 黄金值。

source("model_traning/prepare.R")
suppressMessages(library(torch))

set.seed(20261022)
torch_manual_seed(20261022)

SEQ <- 36L
H <- 5L
HID <- 64L
LR <- 1e-3
BATCH <- 256L
MAX_EPOCHS <- 200L
PATIENCE <- 15L
TRAIN_LAST <- "2025-06"   # 目标月上限（训练窗）
ES_LAST <- "2026-01"      # 早停验证目标月上限
CALIB_FIRST <- "2026-02"  # 区间校准目标月起点

cat("== data ==\n")
P <- load_price_wide(".")
ann <- load_ann_covariate(".")
c1 <- load_c1_covariate(".")
tf <- fit_transforms(P, MONTHS, TRAIN_LAST)
feat <- build_price_features(P, ann, c1, tf)
arr <- feat$arr
cat("price panel:", dim(P), " features:", dim(arr), "\n")

im <- function(m) match(m, MONTHS)
j_train_last <- im(TRAIN_LAST)          # 目标月索引上限
j_val_first <- im("2025-07")
j_es_last <- im(ES_LAST)
j_calib_first <- im(CALIB_FIRST)
j_end <- N_MONTHS

## 样本：origin j0 -> 输入 arr[, (j0-SEQ+1):j0, ]，目标 P[, j0+1:H]
origins_train <- seq(SEQ, j_train_last - H)
origins_val <- seq(j_val_first - 1, j_end - H)   # 2025-06 .. 2026-02，目标 2025-07..2026-07

build_xy <- function(j0s) {
  n <- length(j0s) * 51L
  X <- array(NA_real_, c(n, SEQ, 11))
  Y <- matrix(NA_real_, n, H)
  st <- character(n); o <- integer(n)
  k <- 0L
  for (j0 in j0s) {
    for (s in 1:51) {
      k <- k + 1L
      X[k, , ] <- arr[s, (j0 - SEQ + 1):j0, ]
      Y[k, ] <- mm_price(P[s, (j0 + 1):(j0 + H)], tf$price_minmax[[s]])
      st[k] <- STATES[s]; o[k] <- j0
    }
  }
  list(X = X, Y = Y, state = st, j0 = o)
}

tr <- build_xy(origins_train)
va <- build_xy(origins_val)
cat("train samples:", nrow(tr$Y), " valid origins:", length(origins_val), "\n")

lstm_cell <- nn_module(
  "LSTMCellRelu",
  initialize = function(input_size, hidden_size) {
    self$hidden_size <- hidden_size
    glorot <- function(fan_in, fan_out) {
      b <- sqrt(6 / (fan_in + fan_out))
      torch_empty(c(fan_out, fan_in))$uniform_(-b, b)
    }
    self$w_ih <- nn_parameter(glorot(input_size, 4 * hidden_size))
    self$w_hh <- nn_parameter(glorot(hidden_size, 4 * hidden_size))
    self$b_ih <- nn_parameter(torch_zeros(4 * hidden_size))
    self$b_hh <- nn_parameter(torch_zeros(4 * hidden_size))
  },
  forward = function(x, h, c) {
    gates <- torch_mm(x, self$w_ih$t()) + self$b_ih +
      torch_mm(h, self$w_hh$t()) + self$b_hh
    hs <- self$hidden_size
    i <- torch_sigmoid(gates[, 1:hs])
    f <- torch_sigmoid(gates[, (hs + 1):(2 * hs)])
    g <- nnf_relu(gates[, (2 * hs + 1):(3 * hs)])
    o <- torch_sigmoid(gates[, (3 * hs + 1):(4 * hs)])
    c_new <- f * c + i * g
    list(o * nnf_relu(c_new), c_new)
  }
)

lstm_model <- nn_module(
  "PriceLSTM",
  initialize = function(input_size, hidden_size, h_max) {
    self$cell <- lstm_cell(input_size, hidden_size)
    self$out <- nn_linear(hidden_size, h_max)
  },
  forward = function(x) {
    n <- dim(x)[1]
    h <- torch_zeros(n, self$cell$hidden_size)
    c <- torch_zeros(n, self$cell$hidden_size)
    for (t in seq_len(dim(x)[2])) {
      st <- self$cell(x[, t, ], h, c)
      h <- st[[1]]; c <- st[[2]]
    }
    self$out(h)
  }
)

model <- lstm_model(11L, HID, H)
opt <- optim_adam(model$parameters, lr = LR, weight_decay = 1e-4)
loss_fn <- nn_mse_loss()

Xtr <- torch_tensor(tr$X); Ytr <- torch_tensor(tr$Y)
Xva <- torch_tensor(va$X)

eval_es <- function() {
  model$eval()
  with_no_grad({
    pred <- model(Xva)
    Yv <- torch_tensor(va$Y)
    err <- (pred - Yv)$pow(2)$mean()$item()
    ## 视界三元组级（目标月 <= 早停上限）归一空间 MSE
    ptr <- as_array(pred)
  })
  tgt <- sweep(matrix(rep(va$j0, H), ncol = H), 2, 1:H, "+")
  keep <- tgt <= j_es_last
  list(es = mean((ptr[keep] - va$Y[keep])^2), pred_norm = ptr)
}

cat("== train ==\n")
best <- Inf; best_state <- NULL; wait <- 0L
hist <- list()
for (epoch in 1:MAX_EPOCHS) {
  model$train()
  idx <- sample.int(nrow(tr$Y))
  for (s in seq(1, length(idx), by = BATCH)) {
    b <- idx[s:min(s + BATCH - 1, length(idx))]
    opt$zero_grad()
    loss <- loss_fn(model(Xtr[b]), Ytr[b])
    loss$backward()
    opt$step()
  }
  ev <- eval_es()
  hist[[epoch]] <- c(epoch = epoch, train = loss$item(), es = ev$es)
  cat(sprintf("epoch %3d  train %.6f  valid %.6f\n", epoch, loss$item(), ev$es))
  if (ev$es < best - 1e-7) {
    best <- ev$es; wait <- 0L
    best_state <- lapply(model$state_dict(), function(x) x$detach()$clone())
  } else {
    wait <- wait + 1L
    if (wait >= PATIENCE) { cat("early stop at epoch", epoch, "\n"); break }
  }
}
model$load_state_dict(best_state)
model$eval()

## ---- walk-forward 视界三元组（验证 2025-07..2026-07）----
pv <- eval_es()$pred_norm
tgt_idx <- sweep(matrix(rep(va$j0, H), ncol = H), 2, 1:H, "+")
trip <- data.frame(
  state = rep(va$state, H),
  j0 = rep(va$j0, H),
  h = rep(1:H, each = nrow(va$Y)),
  target = as.vector(tgt_idx),
  pred_norm = as.vector(pv),
  true_norm = as.vector(va$Y),
  stringsAsFactors = FALSE
)
trip$pred <- mapply(function(s, p) {
  mm <- tf$price_minmax[[s]]; (p + 1) / 2 * (mm$max - mm$min) + mm$min
}, trip$state, trip$pred_norm)
trip$pred_raw <- trip$pred
trip$true <- mapply(function(s, p) {
  mm <- tf$price_minmax[[s]]; (p + 1) / 2 * (mm$max - mm$min) + mm$min
}, trip$state, trip$true_norm)
## 基线：季节朴素（t+h-12）与末值（t）——须在子集切分前算好
mm_raw <- P
trip$seas <- mapply(function(s, j0, h) {
  mm_raw[s, if (j0 + h - 12 >= 1) j0 + h - 12 else j0]
}, match(trip$state, STATES), trip$j0, trip$h)
trip$last <- mapply(function(s, j0) mm_raw[s, j0], match(trip$state, STATES), trip$j0)

## 早停窗的视界偏差（相对残差中位数）只作诊断、不再校正点预测：
## 它与校准窗的偏差方向相反（h=1: -2.2% vs +0.9%），校正后校准窗 MSE 2.224 -> 2.274，
## 接缝和"超过本州历史最大值"的比例也没有改善；这一决定参考过校准窗结果，见 NEWS。
es_keep <- trip$target <= j_es_last
es_bias_diagnostic <- vapply(1:H, function(h) {
  d <- trip[es_keep & trip$h == h, ]
  stats::median((d$true - d$pred_raw) / d$pred_raw)
}, numeric(1))
trip$rel <- (trip$true - trip$pred) / trip$pred
es_trips <- trip[es_keep, ]
cal_trips <- trip[trip$target >= j_calib_first, ]
cat("== early-stop window bias (diagnostic only, NOT applied; h=1..5) ==\n")
print(es_bias_diagnostic)

mse <- function(a, b) mean((a - b)^2)
diag <- data.frame(
  model = c("lstm", "seasonal_naive", "last_value"),
  mse_es = c(mse(es_trips$true, es_trips$pred),
             mse(es_trips$true, es_trips$seas),
             mse(es_trips$true, es_trips$last)),
  mse_cal = c(mse(cal_trips$true, cal_trips$pred),
              mse(cal_trips$true, cal_trips$seas),
              mse(cal_trips$true, cal_trips$last)),
  mae_es = c(mean(abs(es_trips$true - es_trips$pred)),
             mean(abs(es_trips$true - es_trips$seas)),
             mean(abs(es_trips$true - es_trips$last)))
)
cat("== baselines ==\n"); print(diag)

## ---- 区间：校准窗相对残差视界分位数（相对预测值，跨州可比）----
qfun <- function(x, pr) unname(stats::quantile(x, pr, na.rm = TRUE))
iv <- do.call(rbind, lapply(1:H, function(h) {
  r <- cal_trips$rel[cal_trips$h == h]
  ar <- abs(r)
  data.frame(
    h = h, n = length(r),
    r_q05 = qfun(r, 0.05), r_q50 = qfun(r, 0.50), r_q95 = qfun(r, 0.95),
    abs_q50 = qfun(ar, 0.50), abs_q85 = qfun(ar, 0.85), abs_q95 = qfun(ar, 0.95),
    stringsAsFactors = FALSE
  )
}))
cov_cal <- sapply(1:H, function(h) {
  r <- cal_trips$rel[cal_trips$h == h]
  mean(abs(r) <= iv$abs_q85[h])
})
cov_transfer <- sapply(1:H, function(h) {
  r <- es_trips$rel[es_trips$h == h]
  mean(abs(r) <= iv$abs_q85[h])
})
cat("== coverage (calib in-sample / transfer to early window) ==\n")
print(rbind(calib = cov_cal, transfer = cov_transfer))

## ---- 2026-08..12 预测（origin 2026-07）----
j0 <- N_MONTHS
FC_MONTHS <- sprintf("%04d-%02d", 2026, 8:12)
Xf <- array(NA_real_, c(51, SEQ, 11))
for (s in 1:51) Xf[s, , ] <- arr[s, (j0 - SEQ + 1):j0, ]
pf_norm <- as_array(with_no_grad(model(torch_tensor(Xf))))
fc <- do.call(rbind, lapply(1:51, function(s) {
  mm <- tf$price_minmax[[s]]
  pr <- (pf_norm[s, ] + 1) / 2 * (mm$max - mm$min) + mm$min
  data.frame(
    state = STATES[s], period = FC_MONTHS, h = 1:H,
    price = pr,
    sd = pr * iv$abs_q85 / stats::qnorm(0.925),
    q_lo = pr * (1 + iv$r_q05), q_hi = pr * (1 + iv$r_q95),
    stringsAsFactors = FALSE
  )
}))
cat("== forecast 2026-08..12 (head) ==\n"); print(head(fc, 6))

## ---- 导出 ----
sd_ <- model$state_dict()
getm <- function(nm) as_array(sd_[[nm]])
imp <- attr(P, "imputed")
imp_cells <- if (any(imp)) {
  w <- which(imp, arr.ind = TRUE)
  data.frame(state = rownames(P)[w[, 1]], period = MONTHS[w[, 2]], stringsAsFactors = FALSE)
} else data.frame(state = character(0), period = character(0))
fit <- list(
  contract = paste0(
    "point = LSTM direct multi-horizon h=1..5, no bias correction (custom LSTMCell, ",
    "candidate relu, hidden=64, seq_len=36, 51-state pooled; minmax per state + zscore fit ",
    "on train window only); ",
    "interval = per-horizon quantiles of relative residuals (true-pred)/pred from the ",
    "held-out calibration window 2026-02..2026-07 (cross-state scale-standardised, no obs_max ",
    "fallback); .sd = price*abs_q85/qnorm(0.925) keeps the downstream Gaussian-scale bridge; ",
    "annual EIA-861 Y value available from Y+1 October, Adjustment eiaid 99999 excluded; ",
    "early stopping on walk-forward valid 2025-07..2026-01, NOT on a test set"
  ),
  fit_as_of = "2026-07",
  forecast_window = "2026-08..2026-12",
  train_window = paste0("price history 2010-01..2026-07; input origins 2012-12..2025-01 ",
                        "(targets through ", TRAIN_LAST, ")"),
  valid_window = paste0("targets 2025-07..", ES_LAST, " (early stop)"),
  calib_window = paste0("targets ", CALIB_FIRST, "..2026-07 (interval quantiles)"),
  seq_len = SEQ, n_hidden = HID, n_chan = 11L, h_max = H,
  chan_names = feat$chan,
  weights = list(
    w_ih = getm("cell.w_ih"), w_hh = getm("cell.w_hh"),
    b_ih = getm("cell.b_ih"), b_hh = getm("cell.b_hh"),
    w_out = getm("out.weight"), b_out = getm("out.bias")
  ),
  transforms = list(price_minmax = tf$price_minmax, zpar = feat$zpar, ann_rng = feat$ann_rng),
  es_bias_diagnostic = es_bias_diagnostic,
  intervals = iv,
  coverage = list(calib_in_sample = cov_cal, transfer_early_window = cov_transfer),
  baselines = diag,
  valid_mse = best,
  forecast = fc,
  imputed_cells = imp_cells,
  golden = fc[fc$state %in% c("FL", "AK", "CA", "DC", "NY", "TX") &
                fc$period %in% c("2026-08", "2026-10", "2026-12"), ],
  seed = 20261022L
)
dir.create("inst/extdata", showWarnings = FALSE, recursive = TRUE)
saveRDS(fit, "inst/extdata/price_lstm_fit.rds")
cat("== saved inst/extdata/price_lstm_fit.rds ==\n")
str(fit$weights, max.level = 1)
print(fit$golden[, c("state", "period", "price", "sd")])
