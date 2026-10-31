# test-price-lstm.R —— LSTM 预测 regime 的冻结契约
# 三层钉死：①黄金值 1e-10（纯 R 前向 vs 冻结夹具，防实现漂移）
#           ②独立朴素前向对拍（测试内重算，防两侧同错）
#           ③窗口契约（h=1..5 供给、越界诚实拒绝）

test_that("lstm predictor reproduces the frozen golden values (1e-10)", {
  path <- test_path("fixtures", "price_lstm_golden.csv")
  expect_true(file.exists(path),
              info = "golden fixture must ship with the suite; its absence must fail loudly")
  g <- utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  got <- lifewatt:::.lstm_predict(g$state, g$period)
  expect_equal(got$price, g$price, tolerance = 1e-10)
  expect_equal(got[[".sd"]], g[[".sd"]], tolerance = 1e-10)
  expect_equal(got$q_lo, g$q_lo, tolerance = 1e-10)
  expect_equal(got$q_hi, g$q_hi, tolerance = 1e-10)
})

test_that("lstm forward recomputes independently (naive loop, in-test reference)", {
  fit <- lifewatt:::.price_lstm_fit()
  W <- fit$weights
  hs <- fit$n_hidden
  w <- lifewatt:::.lstm_feature_window("FL", fit$fit_as_of)
  ## 朴素逐步重算：显式循环 + 门展开（与 R/price-lstm.R 向量化实现不同路径）
  h <- rep(0, hs); cc <- rep(0, hs)
  for (t in seq_len(nrow(w))) {
    x <- w[t, ]
    gates <- rep(0, 4 * hs)
    for (j in seq_len(4 * hs)) {
      s1 <- 0
      for (k in seq_len(ncol(w))) s1 <- s1 + W$w_ih[j, k] * x[k]
      s2 <- 0
      for (k in seq_len(hs)) s2 <- s2 + W$w_hh[j, k] * h[k]
      gates[j] <- s1 + W$b_ih[j] + s2 + W$b_hh[j]
    }
    i <- 1 / (1 + exp(-gates[1:hs]))
    f <- 1 / (1 + exp(-gates[(hs + 1):(2 * hs)]))
    g <- pmax(gates[(2 * hs + 1):(3 * hs)], 0)
    o <- 1 / (1 + exp(-gates[(3 * hs + 1):(4 * hs)]))
    cc <- f * cc + i * g
    h <- o * pmax(cc, 0)
  }
  yn <- rep(0, fit$h_max)
  for (j in seq_len(fit$h_max)) {
    s <- W$b_out[j]
    for (k in seq_len(hs)) s <- s + W$w_out[j, k] * h[k]
    yn[j] <- s
  }
  got <- lifewatt:::.lstm_forward_norm(array(w, c(1, nrow(w), ncol(w))))
  expect_equal(as.numeric(got[1, ]), yn, tolerance = 1e-12)
})

test_that("lstm window contract: horizons 1..5 only, refusals are honest", {
  expect_error(lifewatt:::.lstm_predict("FL", "2026-07"), "horizons 1..5")
  expect_error(lifewatt:::.lstm_predict("FL", "2027-01"), "horizons 1..5")
  expect_error(lifewatt:::.lstm_predict(c("FL", "FL"), "2026-12"), "aligned")
  expect_error(lifewatt:::.lstm_predict("ZZ", "2026-12"), "outside the LSTM fit coverage")
  expect_error(expected_life_loss("32601", "2027-01"), "outside the supported window")
})

test_that("price_at predicted branch serves the LSTM source for the gap months", {
  r <- lifewatt:::.price_at("32601", "2026-10")
  expect_equal(r$regime, "predicted")
  expect_match(r$source, "LSTM price forecast", fixed = TRUE)
  expect_true(is.finite(r$price_sd) && r$price_sd > 0)
  ## 4 年窗口闭合：2026-08..12 全部由拟合数据供给
  for (p in sprintf("2026-%02d", 8:12)) {
    rr <- lifewatt:::.price_at("32601", p)
    expect_equal(rr$regime, "predicted")
    expect_true(is.finite(rr$price) && rr$price > 0)
  }
})

test_that("lstm fit contract ledger is intact", {
  fit <- lifewatt:::.price_lstm_fit()
  expect_equal(fit$fit_as_of, "2026-07")
  expect_equal(fit$forecast_window, "2026-08..2026-12")
  expect_equal(fit$h_max, 5L)
  expect_equal(nrow(fit$forecast), 51L * 5L)
  expect_true(all(is.finite(fit$forecast$price)))
  expect_true(all(fit$forecast$q_lo < fit$forecast$price &
                    fit$forecast$price < fit$forecast$q_hi))
  ## 85% 区间覆盖率台账在验收带 [0.85, 0.95]（校准口径）
  expect_true(all(fit$coverage$calib_in_sample >= 0.80))
  ## 区间直接取残差的 5%/95% 分位，不做对称化（偏斜方向随 h 变化：h=1..4 右偏，h=5 左偏）
  expect_true(all(abs(fit$intervals$r_q95 + fit$intervals$r_q05) > 1e-6))
  ## 去掉偏差校正后不再携带 point_bias；早停窗偏差只作诊断
  expect_null(fit$point_bias)
  expect_length(fit$es_bias_diagnostic, fit$h_max)
})

test_that("package prediction path carries no torch dependency", {
  p <- system.file("DESCRIPTION", package = "lifewatt")
  desc <- if (nzchar(p)) readLines(p) else readLines(test_path("..", "..", "DESCRIPTION"))
  expect_false(any(grepl("torch", desc)))
  # 安装态（R CMD check）没有 ../../NAMESPACE；用运行时已加载的导入表，两种模式都成立
  expect_false("torch" %in% names(getNamespaceImports("lifewatt")))
  lifewatt:::.lstm_predict("FL", "2026-12")
  expect_false("torch" %in% loadedNamespaces())
})

test_that(".sd is the Gaussian scale implied by the 85% absolute-residual quantile", {
  iv <- lifewatt:::.price_lstm_fit()$intervals
  p <- lifewatt:::.lstm_predict(rep("FL", 5), sprintf("2026-%02d", 8:12))
  # P(|e| <= abs_q85) = 0.85 under N(0, sd) => abs_q85 = sd * qnorm(0.925)
  expect_equal(p$.sd, p$price * iv$abs_q85[p$h] / qnorm(0.925), tolerance = 1e-12)
  z <- iv$abs_q85[p$h] * p$price / p$.sd
  expect_equal(2 * pnorm(z) - 1, rep(0.85, 5), tolerance = 1e-12)
})

test_that("frozen calibration quantiles reproduce from the shipped weights and data", {
  skip_on_cran()  # ~25 s: 459 forward passes (origins 2025-06..2026-02 x 51 states)
  ns <- asNamespace("lifewatt")
  fit <- ns$.price_lstm_fit()
  ph <- ns$.price_history_wide()
  months <- colnames(ph)
  rel <- list()
  for (o in months[match("2025-06", months):match("2026-02", months)]) {
    j0 <- match(o, months)
    for (s in rownames(ph)) {
      w <- ns$.lstm_feature_window(s, o)
      y <- ns$.lstm_denorm(ns$.lstm_forward_norm(array(w, c(1, dim(w))))[1, ], s)
      for (h in seq_len(fit$h_max)) {
        if (j0 + h <= length(months) && months[j0 + h] >= "2026-02") {
          rel[[length(rel) + 1L]] <- c(h = h, r = (ph[s, j0 + h] - y[h]) / y[h])
        }
      }
    }
  }
  rel <- as.data.frame(do.call(rbind, rel))
  q <- function(x, p) unname(stats::quantile(x, p))
  for (h in seq_len(fit$h_max)) {
    r <- rel$r[rel$h == h]
    expect_equal(length(r), fit$intervals$n[h])
    expect_equal(q(r, 0.05), fit$intervals$r_q05[h], tolerance = 1e-6)
    expect_equal(q(r, 0.95), fit$intervals$r_q95[h], tolerance = 1e-6)
    expect_equal(q(abs(r), 0.85), fit$intervals$abs_q85[h], tolerance = 1e-6)
  }
})
