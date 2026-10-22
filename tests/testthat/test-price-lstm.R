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
  ## 残差右偏必须可见（q95 > |q05|），不做对称化
  expect_true(all(fit$intervals$r_q95 > abs(fit$intervals$r_q05)))
})

test_that("package prediction path carries no torch dependency", {
  p <- system.file("DESCRIPTION", package = "lifewatt")
  desc <- if (nzchar(p)) readLines(p) else readLines(test_path("..", "..", "DESCRIPTION"))
  expect_false(any(grepl("torch", desc)))
  ns <- readLines(test_path("..", "..", "NAMESPACE"))
  expect_false(any(grepl("torch", ns)))
})
