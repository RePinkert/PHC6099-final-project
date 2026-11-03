# conf_train_folds_serving.R —— "服务 regime"折：把滚动起点的留出压到 12 个月
#
# 为什么需要它：conf_extrap_distance.R 量出
#   * 折上评估的 gap（预测 origin 距最后一个训练 origin）= 25..40 个月；
#   * 随包实际服务时 gap = 18 个月（训练 origin 至 2025-01，预测 origin 2026-07）；
#   * 随包区间标定窗（目标 2026-02..07）落在 gap ≈ 12 的"新鲜"端。
#   => 四年画像刻画的是**比实际服务更难**的 regime；在这个 regime 上选出的区间构造，
#      直接换到服务 regime 只会更宽（2026-08 实测：随包 h=1 覆盖 0.9804，
#      研究分支的建议区间覆盖 0.9608 但宽 3 倍）。
#
# 本折的做法：把 ES + CAL 从 24 个月压到 12 个月（ES 6 + CAL 6），评估窗整体前移，
# 使评估 origin 落在距最后一个训练 origin 18 个月处 —— 与随包服务 regime 对齐。
#
# 折（评估年 y=2026）的角色划分（全部按**目标月**）：
#   FIT   目标月 <= Dec(2023-12)          -> 只学权重
#   ES    目标月 2024-01..2024-06          -> 早停（ES-A <= 2024-03 定区间参数，ES-B 打分）
#   CAL   目标月 2024-07..2024-12          -> 只定区间构造
#   EVAL  目标月 2025-02..2026-01          -> 只量一次（评估 origin = 2025-01..2025-12）
#
# 与 conf_train_folds.R 的差别只有三处：折定义、ES origin 的取法（并把 ES 行限制在 ES 窗内）、
# 以及评估 origin 由 conf_serving_eval.R 用同样的规则枚举。
#
# 运行：Rscript model_traning/conf_train_folds_serving.R

source("model_traning/prepare.R")
source("model_traning/ann_rel_variants.R")
source("R/conf-protocol.R")
source("R/conf-intervals.R")
suppressMessages(library(torch))

SEQ <- 36L; H <- 5L; HID <- 64L
LR <- 1e-3; BATCH <- 512L; MAX_EPOCHS <- 240L; PATIENCE <- 60L
NOMINAL <- CONF_NOMINAL

## ---- 可调参数（环境变量；默认值 = 已发布的那次训练）----
## SERVING_ANN    年值协变量口径：filed | panel_mean | panel_mean_early | workbook_revsal
## SERVING_CRIT   早停准则（逗号分隔）：mse | wis
## SERVING_STOP   早停方式：patience | fixed（fixed = 固定训练 N 个 epoch，把"准则"与"停在哪"解耦）
## SERVING_PATIENCE / SERVING_EPOCHS
## SERVING_FOLDS  评估年（逗号分隔）：2026 | 2027
## SERVING_TAG    文件名后缀（留空 = 与已发布的候选文件同名）
ANN_VARIANT <- Sys.getenv("SERVING_ANN", "filed")
CRITS <- strsplit(Sys.getenv("SERVING_CRIT", "mse,wis"), ",", fixed = TRUE)[[1]]
STOP_MODE <- Sys.getenv("SERVING_STOP", "patience")
PATIENCE <- as.integer(Sys.getenv("SERVING_PATIENCE", "60"))
FIXED_EPOCHS <- as.integer(Sys.getenv("SERVING_EPOCHS", "90"))
MIN_EPOCH <- as.integer(Sys.getenv("SERVING_MIN_EPOCH", "0"))
EVAL_YEARS <- as.integer(strsplit(Sys.getenv("SERVING_FOLDS", "2026"), ",", fixed = TRUE)[[1]])
TAG <- Sys.getenv("SERVING_TAG", "")
SEED_BASE <- as.integer(Sys.getenv("SERVING_SEED", "20261103"))
cat(sprintf("== serving fits: ann=%s crit=%s stop=%s patience=%d fixed_epochs=%d min_epoch=%d folds=%s tag=%s seed_base=%d ==\n",
            ANN_VARIANT, paste(CRITS, collapse = "/"), STOP_MODE, PATIENCE, FIXED_EPOCHS, MIN_EPOCH,
            paste(EVAL_YEARS, collapse = "/"), TAG, SEED_BASE))

## 折定义（服务 regime：留出 12 个月，评估 origin 距最后一个训练 origin 18 个月）
conf_fold <- function(y) {
  list(eval_year = y,
       train_last = sprintf("%04d-12", y - 3L),
       es_first = sprintf("%04d-01", y - 2L), es_last = sprintf("%04d-06", y - 2L),
       es_a_last = sprintf("%04d-03", y - 2L),      # ES-A 定区间参数
       cal_first = sprintf("%04d-07", y - 2L), cal_last = sprintf("%04d-12", y - 2L),
       eval_first = sprintf("%04d-02", y - 1L), eval_last = sprintf("%04d-01", y))
}

P <- load_price_wide(".")
im <- function(m) match(m, MONTHS)

lstm_cell <- nn_module(
  "LSTMCellRelu",
  initialize = function(input_size, hidden_size) {
    self$hidden_size <- hidden_size
    glorot <- function(fan_in, fan_out) {
      b <- sqrt(6 / (fan_in + fan_out)); torch_empty(c(fan_out, fan_in))$uniform_(-b, b)
    }
    self$w_ih <- nn_parameter(glorot(input_size, 4 * hidden_size))
    self$w_hh <- nn_parameter(glorot(hidden_size, 4 * hidden_size))
    self$b_ih <- nn_parameter(torch_zeros(4 * hidden_size))
    self$b_hh <- nn_parameter(torch_zeros(4 * hidden_size))
  },
  forward = function(x, h, c) {
    gates <- torch_mm(x, self$w_ih$t()) + self$b_ih + torch_mm(h, self$w_hh$t()) + self$b_hh
    hs <- self$hidden_size
    i <- torch_sigmoid(gates[, 1:hs]); f <- torch_sigmoid(gates[, (hs + 1):(2 * hs)])
    g <- nnf_relu(gates[, (2 * hs + 1):(3 * hs)]); o <- torch_sigmoid(gates[, (3 * hs + 1):(4 * hs)])
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
    h <- torch_zeros(n, self$cell$hidden_size); c <- torch_zeros(n, self$cell$hidden_size)
    for (t in seq_len(dim(x)[2])) { st <- self$cell(x[, t, ], h, c); h <- st[[1]]; c <- st[[2]] }
    self$out(h)
  }
)

conf_train_one <- function(fold, crit = "mse", seed = 20261103L) {
  set.seed(seed); torch_manual_seed(seed)
  tf <- fit_transforms(P, MONTHS, fold$train_last)
  annrel <- ann_rel_variant(P, ".", variant = ANN_VARIANT)
  feat <- build_price_features(P, annrel, tf)
  arr <- feat$arr; NCH <- dim(arr)[3]
  j_fit_last <- im(fold$train_last); j_es_first <- im(fold$es_first); j_es_last <- im(fold$es_last)
  origins_train <- seq(SEQ, j_fit_last - H)
  ## ES origin：目标月落在 ES 窗内的那些 origin（h=1..5 都要有），并把 ES 行限制在 ES 窗内
  origins_es <- seq(max(SEQ, j_es_first - H), j_es_last - 1)
  tt <- fit_target_transform(P, origins_train, H)
  build_xy <- function(j0s) {
    n <- length(j0s) * 51L
    X <- array(NA_real_, c(n, SEQ, NCH)); Y <- matrix(NA_real_, n, H)
    st <- character(n); o <- integer(n); k <- 0L
    for (j0 in j0s) for (s in 1:51) {
      k <- k + 1L
      X[k, , ] <- arr[s, (j0 - SEQ + 1):j0, ]
      Y[k, ] <- target_norm(P, s, j0, H, tt)
      st[k] <- STATES[s]; o[k] <- j0
    }
    list(X = X, Y = Y, state = st, j0 = o)
  }
  tr <- build_xy(origins_train); es <- build_xy(origins_es)
  model <- lstm_model(NCH, HID, H)
  opt <- optim_adam(model$parameters, lr = LR, weight_decay = 1e-4)
  loss_fn <- nn_mse_loss()
  Xtr <- torch_tensor(tr$X); Ytr <- torch_tensor(tr$Y); Xes <- torch_tensor(es$X)
  es_eval <- function() {
    model$eval()
    ptr <- as_array(with_no_grad(model(Xes)))
    tgt_idx <- sweep(matrix(rep(es$j0, H), ncol = H), 2, 1:H, "+")
    p0 <- P[cbind(match(es$state, STATES), es$j0)]
    pr <- p0 * exp(sweep(sweep(ptr, 2, tt$mu, "+"), 2, tt$sd, "*"))
    true <- P[cbind(match(es$state, STATES), as.vector(tgt_idx))]
    d <- data.frame(state = rep(es$state, H), j0 = rep(es$j0, H), h = rep(1:H, each = nrow(es$Y)),
                    target = as.vector(tgt_idx), pred = as.vector(pr), true = as.vector(true),
                    stringsAsFactors = FALSE)
    d$rel <- (d$true - d$pred) / d$pred
    d$target_month <- MONTHS[d$target]
    ## 只保留 ES 窗内的行（origin 取法变了，ES 行的目标月可能落在窗外）
    d <- d[d$target_month >= fold$es_first & d$target_month <= fold$es_last, ]
    a <- d[d$target_month <= fold$es_a_last, ]; b <- d[d$target_month > fold$es_a_last, ]
    alpha <- 1 - NOMINAL
    wis_sum <- 0; n_b <- 0; cov_sum <- 0; nh <- 0
    for (h in 1:H) {
      ra <- a$rel[a$h == h]; rb <- b[b$h == h, ]
      if (length(ra) < 30 || nrow(rb) < 30) next
      lo <- rb$pred * (1 + conf_q_empirical(ra, alpha / 2))
      hi <- rb$pred * (1 + conf_q_empirical(ra, 1 - alpha / 2))
      wis_sum <- wis_sum + sum(conf_wis(rb$true, lo, hi, alpha)); n_b <- n_b + nrow(rb)
      cov_sum <- cov_sum + mean(rb$true >= lo & rb$true <= hi); nh <- nh + 1
    }
    list(mse = mean((d$true - d$pred)^2),
         wis = if (n_b > 0) wis_sum / n_b else NA_real_,
         cov = if (nh > 0) cov_sum / nh else NA_real_, d = d)
  }
  score_of <- function(ev) {
    lastv <- P[cbind(match(ev$d$state, STATES), ev$d$j0)]
    mse_n <- ev$mse / (mean((ev$d$true - lastv)^2) + 1e-9)
    wis_n <- ev$wis / (mean(abs(ev$d$true - lastv)) + 1e-9)
    switch(crit, mse = ev$mse, wis = wis_n + 5 * abs(ev$cov - NOMINAL),
           stop("unknown crit"))
  }
  best <- list(score = Inf); wait <- 0L; prev <- Inf; ep_tab <- list()
  for (epoch in 1:MAX_EPOCHS) {
    model$train()
    idx <- sample.int(nrow(tr$Y))
    for (s in seq(1, length(idx), by = BATCH)) {
      b <- idx[s:min(s + BATCH - 1, length(idx))]
      opt$zero_grad(); loss <- loss_fn(model(Xtr[b]), Ytr[b]); loss$backward(); opt$step()
    }
    ev <- es_eval()
    ep_tab[[epoch]] <- data.frame(epoch = epoch, mse = ev$mse, wis = ev$wis, cov = ev$cov)
    if (epoch %% 20 == 0) cat(sprintf("   epoch %3d es_mse %.4f es_wis %.4f es_cov %.3f\n",
                                      epoch, ev$mse, ev$wis, ev$cov))
    sc <- score_of(ev)
    ## 早停下限：早于 MIN_EPOCH 的 epoch 不参与"选权重"（fold 2025 的 wis 准则停在 epoch 3，
    ## 那次"更稳"是**没训练**的副产品，不是置信度目标的功劳）
    eligible <- epoch >= MIN_EPOCH
    if (eligible && is.finite(sc) && sc < best$score - 1e-9) {
      best <- list(score = sc, epoch = epoch,
                   state = lapply(model$state_dict(), function(x) x$detach()$clone()))
      wait <- 0L
    } else if (eligible) {
      wait <- wait + 1L
      if (STOP_MODE == "patience" && wait >= PATIENCE) {
        cat("   early stop at epoch", epoch, "\n"); break
      }
    }
    if (STOP_MODE == "fixed" && epoch >= FIXED_EPOCHS) {
      best <- list(score = sc, epoch = epoch,
                   state = lapply(model$state_dict(), function(x) x$detach()$clone()))
      cat("   fixed budget reached at epoch", epoch, "\n"); break
    }
  }
  model$load_state_dict(best$state); model$eval()
  sd_ <- model$state_dict(); getm <- function(nm) as_array(sd_[[nm]])
  fit <- list(
    contract = paste0("rolling-origin candidate (confidence-objective experiment, NOT shipped). ",
                      "fold eval year ", fold$eval_year, "; early-stop criterion ", crit,
                      "; best epoch ", best$epoch, "; score ", round(best$score, 5),
                      "; stop mode ", STOP_MODE, "; min epoch ", MIN_EPOCH,
                      "; ann covariate ", ANN_VARIANT, ". ",
                      "FIT targets <= ", fold$train_last, "; ES ", fold$es_first, "..", fold$es_last,
                      " (ES-A <= ", fold$es_a_last, " sets interval params, ES-B scores them); ",
                      "CAL ", fold$cal_first, "..", fold$cal_last, "; EVAL ", fold$eval_first,
                      "..", fold$eval_last, " (untouched here). Same architecture/channels/target as shipped v3."),
    fit_as_of = "2026-07", forecast_window = "2026-08..2026-12",
    train_window = paste0("targets <= ", fold$train_last),
    valid_window = paste0("targets ", fold$es_first, "..", fold$es_last, " (early stop)"),
    calib_window = paste0("targets ", fold$cal_first, "..", fold$cal_last),
    eval_window = paste0("targets ", fold$eval_first, "..", fold$eval_last),
    fold = fold, early_stop = list(criterion = crit, epoch = best$epoch, score = best$score),
    seq_len = SEQ, n_hidden = HID, n_chan = as.integer(NCH), h_max = H,
    chan_names = feat$chan,
    weights = list(w_ih = getm("cell.w_ih"), w_hh = getm("cell.w_hh"),
                   b_ih = getm("cell.b_ih"), b_hh = getm("cell.b_hh"),
                   w_out = getm("out.weight"), b_out = getm("out.bias")),
    transforms = list(zpar = feat$zpar, ann_source = ANN_SOURCE,
                      target = list(type = tt$type, mu = unname(tt$mu), sd = unname(tt$sd))),
    epochs = do.call(rbind, ep_tab), seed = seed)
  fit
}

dir.create("model_traning/candidates", showWarnings = FALSE, recursive = TRUE)
cat("== rolling-origin fits ==\n")
for (y in EVAL_YEARS) {
  f <- conf_fold(y)
  for (crit in CRITS) {
    cat(sprintf("-- fold %d (%s): train<=%s es=%s..%s cal=%s..%s eval=%s..%s crit=%s\n",
                y, crit, f$train_last, f$es_first, f$es_last, f$cal_first, f$cal_last,
                f$eval_first, f$eval_last, crit))
    t0 <- Sys.time()
    fit <- conf_train_one(f, crit, seed = SEED_BASE + y)
    fp <- sprintf("model_traning/candidates/conf_fit_serving_y%d_%s%s.rds", y, crit,
                  if (nzchar(TAG)) paste0("_", TAG) else "")
    saveRDS(fit, fp)
    cat(sprintf("   saved %s (epoch %d, score %.5f, %.0fs)\n", fp, fit$early_stop$epoch,
                fit$early_stop$score, as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  }
}
cat("== done ==\n")
