# test-price-features.R —— 面向用户的 price_features() / lag_matrix()（2026-11-17 解冻）
# 钉住：①窗口语义（默认 12 个月 / 单月 / 区间）②单位与列名是"普通用户"能读懂的
# ③窗口不足一律 NA（不悄悄缩短）④与包内价格面板逐位一致 ⑤坏输入指名拒绝。

test_that("price_features defaults to the last 12 months of the shipped panel", {
  r <- price_features(anchor_state_fl)
  expect_s3_class(r, "data.frame")
  expect_equal(nrow(r), 12L)
  expect_equal(r$period[1], "2025-08")
  expect_equal(r$period[nrow(r)], "2026-07")
  expect_true(all(r$state == anchor_state_fl))
  expect_provenance_cols(r)
})

test_that("price_features matches the panel it is derived from (FL anchors)", {
  r <- price_features(anchor_state_fl, period = "2026-07")
  expect_equal(nrow(r), 1L)
  expect_equal(r$price, anchor_price_fl_2026_07)
  Ph <- lifewatt:::.price_history_wide()
  expect_equal(r$avg_3m, mean(Ph["FL", match("2026-05", colnames(Ph)):match("2026-07", colnames(Ph))]))
  expect_equal(r$avg_12m, mean(Ph["FL", match("2025-08", colnames(Ph)):match("2026-07", colnames(Ph))]))
  expect_equal(r$change_1m, Ph["FL", match("2026-07", colnames(Ph))] - Ph["FL", match("2026-06", colnames(Ph))])
  expect_equal(r$change_12m, Ph["FL", match("2026-07", colnames(Ph))] - Ph["FL", match("2025-07", colnames(Ph))])
  expect_equal(r$change_12m_pct,
               (Ph["FL", match("2026-07", colnames(Ph))] - Ph["FL", match("2025-07", colnames(Ph))]) /
                 Ph["FL", match("2025-07", colnames(Ph))] * 100)
})

test_that("price_features columns are plain-language, and the interval stays where it belongs", {
  r <- price_features(anchor_state_fl)
  ## 用户能读懂的列名（没有 z-score / min-max / mask / age 这类研究口径字符串）
  expect_true(all(c("price", "avg_3m", "avg_6m", "avg_12m", "change_1m", "change_1m_pct",
                    "change_12m", "change_12m_pct", "trend_12m", "annual_price",
                    "price_vs_annual_pct", "provisional", "imputed") %in% names(r)))
  expect_false(any(c("price_mm", "mom_z", "rel12_z", "lrel12_z", "sin12", "cos12",
                     "ann_mm", "ann_rel_z", "ann_mask", "ann_age", "c1_z") %in% names(r)))
  ## 区间不在这张表里（它在 expected_life_loss()/my_electricity() 的 price_lo/price_hi）
  expect_false(any(c("price_lo", "price_hi", "price_interval_basis") %in% names(r)))
  ## 列集合固定：读取方不会因为列漂移而崩
  expect_equal(nrow(r), 12L)
  expect_match(r$confidence_tier[1], "^B:")
})

test_that("price_features never shortens a window silently: short history -> NA", {
  r <- price_features(anchor_state_fl, from = "2010-01", to = "2010-03")
  expect_equal(nrow(r), 3L)
  expect_true(is.na(r$avg_3m[1]))
  expect_false(is.na(r$avg_3m[3]))
  expect_true(is.na(r$change_12m[1]))
  expect_true(is.na(r$change_12m_pct[1]))
  expect_true(is.na(r$trend_12m[1]))
})

test_that("price_features marks provisional months row by row and keeps the annual reference honest", {
  r <- price_features(anchor_state_fl, from = "2025-06", to = "2026-07")
  expect_true(any(r$provisional))
  expect_false(any(r$provisional[r$period <= "2025-12"]))
  ## EIA-861 2026 年价尚未发布 -> NA（不拿 2025 顶替）
  expect_true(all(is.na(r$annual_price[r$period >= "2026-01"])))
  expect_true(all(is.na(r$price_vs_annual_pct[r$period >= "2026-01"])))
  ## 2025 及以前有州年价，且与该州年价表一致
  A <- lifewatt:::.state_annual_prices()
  y <- 2025
  expect_equal(r$annual_price[r$period == "2025-07"], unname(A["FL", as.character(y)]))
  expect_equal(r$price_vs_annual_pct[r$period == "2025-07"],
               (r$price[r$period == "2025-07"] - A["FL", as.character(y)]) / A["FL", as.character(y)] * 100)
})

test_that("price_features refuses inputs it cannot answer", {
  expect_error(price_features(anchor_zip_fl), "looks like a ZIP code", fixed = TRUE)
  expect_error(price_features(anchor_state_fl, period = "2026-12"), "outside the shipped price history", fixed = TRUE)
  expect_error(price_features(anchor_state_fl, period = "2026-07", from = "2026-01"),
               "not both", fixed = TRUE)
  expect_error(price_features(anchor_state_fl, from = "2026-05", to = "2026-01"),
               "from must not be after to", fixed = TRUE)
})

test_that("lag_matrix lays the previous months side by side with plain column names", {
  r <- lag_matrix(anchor_state_fl)
  expect_s3_class(r, "data.frame")
  expect_equal(nrow(r), 13L)                       # 12 个滞后都填满所需的月份数
  expect_equal(names(r)[1:3], c("state", "period", "price_now"))
  expect_true(all(c("price_1m_ago", "price_6m_ago", "price_12m_ago") %in% names(r)))
  expect_false(any(grepl("^lag[0-9]$", names(r))))
  Ph <- lifewatt:::.price_history_wide()
  k <- match("2026-07", colnames(Ph))
  row <- r[r$period == "2026-07", ]
  expect_equal(row$price_now, Ph["FL", k])
  expect_equal(row$price_1m_ago, Ph["FL", k - 1L])
  expect_equal(row$price_12m_ago, Ph["FL", k - 12L])
  expect_provenance_cols(r)
})

test_that("lag_matrix covers every state by default and flags provisional rows", {
  r <- lag_matrix()
  expect_equal(length(unique(r$state)), 51L)
  expect_equal(nrow(r), 51L * 13L)
  expect_true(any(r$provisional))
  expect_false(any(r$provisional[r$period == "2025-07"]))
})

test_that("lag_matrix leaves NA where a lag reaches before the shipped panel", {
  r <- lag_matrix(anchor_state_fl, from = "2010-01", to = "2010-03", lags = 0:2)
  expect_equal(nrow(r), 3L)
  expect_true(is.na(r$price_1m_ago[1]))
  expect_true(is.na(r$price_2m_ago[1]))
  expect_false(is.na(r$price_2m_ago[3]))
})

test_that("lag_matrix refuses inputs it cannot answer", {
  expect_error(lag_matrix(anchor_state_fl, lags = c(0, -1)), "whole numbers of months", fixed = TRUE)
  expect_error(lag_matrix(anchor_state_fl, lags = c(0, 1.5)), "whole numbers of months", fixed = TRUE)
  expect_error(lag_matrix(anchor_state_fl, to = "2026-12"), "outside the shipped price history", fixed = TRUE)
  expect_error(lag_matrix(anchor_state_fl, from = "2026-05", to = "2026-01"),
               "from must not be after to", fixed = TRUE)
})
