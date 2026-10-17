# test-user-scenarios.R —— 用户侧回归用例（tidyverse/testthat 3e 惯例）
# 与 HANDOVER「第四回合」8 条真实调用留档一一对应；快照锁定用户可见输出与报错，
# 数值契约用 expect_equal 对账内部层（避免写出两份同一数字）。
# 按对外函数分片落地：每片只带自己那部分的场景，用例标题沿用全量编号。

test_that("scenario 1: 查现在的电价（observed，账单未填）", {
  r <- expected_life_loss(anchor_zip_fl, "2026-07")
  expect_s3_class(r, "data.frame")
  expect_equal(r$price, anchor_price_fl_2026_07)
  expect_equal(r$regime, "observed")
  expect_true(r$provisional)
  expect_equal(r$evidence_regime, "none")
  expect_true(any(grepl("Gainesville Regional", r$utilities)))
  expect_provenance_cols(r)
  expect_snapshot(print(r[, c("zip", "state", "period", "price", "unit", "regime", "provisional")]))
})

test_that("scenario 2: 查下个月的电价（predicted regime）", {
  r <- expected_life_loss(anchor_zip_fl, "2026-12")
  prior <- .triplet_predict("FL", "2026-12")
  expect_equal(r$regime, "predicted")
  expect_equal(r$price, prior$price)
  expect_equal(r$price_sd, prior$.sd)
  expect_equal(r$fit_as_of, "2026-07")
  expect_true(is.na(r$provisional))
  expect_snapshot(print(r[, c("zip", "period", "price", "price_sd", "regime", "fit_as_of")]))
})

test_that("scenario 3: 只有账单 → 描述性证据（隐含用量，不造后验）", {
  r <- expected_life_loss(anchor_zip_fl, "2026-12", bill = 180)
  expect_equal(r$evidence_regime, "descriptive")
  expect_equal(r$implied_usage_kwh, 180 * 100 / r$price)
  expect_true(is.na(r$price_posterior))
  expect_true(grepl("bill alone", r$notes))
})

test_that("scenario 4: 账单+用量 → 贝叶斯后验收紧（inverse-variance）", {
  r <- expected_life_loss(anchor_zip_fl, "2026-12", bill = 180, usage = 1200)
  prior <- .triplet_predict("FL", "2026-12")
  p_meas <- 180 * 100 / 1200
  w_m <- 1 / 1^2
  w_p <- 1 / prior$.sd^2
  expect_equal(r$evidence_regime, "posterior")
  expect_equal(r$price_posterior, (w_m * p_meas + w_p * prior$price) / (w_m + w_p),
               tolerance = 1e-9)
  expect_equal(r$price_posterior_sd, sqrt(1 / (w_m + w_p)), tolerance = 1e-9)
  expect_lt(r$price_posterior_sd, prior$.sd)   # 证据必须收紧先验
})

test_that("scenario 5: 无来源弹性 → delta_le 只能是调用方声明参数", {
  r5a <- expected_life_loss(anchor_zip_fl, "2026-09")
  expect_true(is.na(r5a$le_loss_years))
  expect_match(r5a$sensitivity_assumption, "withheld", fixed = TRUE)
  r5b <- expected_life_loss(anchor_zip_fl, "2026-09", delta_le = 0.01)
  expect_equal(r5b$le_loss_years, 0.01)
  expect_equal(r5b$le_loss_pct_of_anchor, 0.01 / anchor_e0_2024 * 100)
  expect_match(r5b$sensitivity_assumption, "caller-declared sensitivity parameter", fixed = TRUE)
  expect_match(r5b$e0_source, "NVSR 75/5", fixed = TRUE)
  expect_match(r5b$notes, "C1 mechanism not available at 2026-09", fixed = TRUE)
  expect_true(is.na(r5b$c1_disconnections_per_1k))
})

test_that("scenario 6: 年度 ZIP 价与同比（A1 x A2 客户加权）", {
  a <- electricity_price(anchor_zip_fl, year = 2024)
  expect_equal(a$price, .zip_annual_price(anchor_zip_fl, 2024)$price)
  expect_equal(a$regime, "observed")
  expect_false(a$provisional)
  expect_equal(a$mapping_vintage, "2024")
  ty <- electricity_price_trend(anchor_zip_fl, period = "yoy")
  expect_equal(ty$year, c(2024L, 2025L))
  p23 <- .zip_annual_price(anchor_zip_fl, 2023)$price
  p24 <- .zip_annual_price(anchor_zip_fl, 2024)$price
  expect_equal(ty$change[1], p24 - p23, tolerance = 1e-9)
})

test_that("scenario 7: 逐月序列（mom 43 行，provisional 分界 2025-01）", {
  m <- electricity_price(anchor_zip_fl, period = "mom")
  expect_equal(nrow(m), 43L)
  expect_false(m$provisional[1])
  expect_true(m$provisional[nrow(m)])
  expect_equal(m$period[nrow(m)], "2026-07")
  expect_equal(m$price[nrow(m)], anchor_price_fl_2026_07)
  expect_provenance_cols(m)
})

test_that("scenario 8: 多 utility zip、ZIP+4、跨年锚点回退", {
  r <- expected_life_loss(anchor_zip_multi, "2026-09", delta_le = 0.02)
  expect_equal(r$state, "NC")
  expect_equal(r$n_utility, 7L)
  expect_equal(r$le_loss_pct_of_anchor, 0.02 / anchor_e0_2024 * 100)
  r4 <- expected_life_loss(paste0(anchor_zip_fl, "-4401"), "2026-07")
  expect_equal(r4$zip, anchor_zip_fl)
  expect_equal(lifewatt:::.zip5("1002"), "01002")   # 新荷兰传统 4 位写法
})

test_that("scenario 9: 讲不通的输入会被指名拒绝（快照锁定用户可见报错文本）", {
  expect_snapshot(
    tryCatch(expected_life_loss("99999", "2026-07"), error = function(e) e)$message
  )
  expect_snapshot(
    tryCatch(expected_life_loss(anchor_zip_fl, "2026-93"), error = function(e) e)$message
  )
  expect_snapshot(
    tryCatch(expected_life_loss(anchor_zip_fl, "2026-12", bill = -3), error = function(e) e)$message
  )
  expect_snapshot(
    tryCatch(life_expectancy(anchor_zip_fl, quarter = "2024-06"), error = function(e) e)$message
  )
  # 无 year/period 直接调用：mock 意向下必须有指路信息
  expect_snapshot(
    tryCatch(electricity_price(anchor_zip_fl), error = function(e) e)$message
  )
})

test_that("scenario 10: my_electricity 与正门同引擎、能源侧无 LE 列", {
  a <- my_electricity(anchor_zip_fl, bill = 180, time = "2026-12", usage = 1200)
  b <- expected_life_loss(anchor_zip_fl, "2026-12", bill = 180, usage = 1200)
  expect_equal(a$price_posterior, b$price_posterior)
  expect_equal(a$evidence_regime, "posterior")
  expect_false(any(grepl("^le_loss|e0_anchor", names(a))))
  expect_provenance_cols(a)
})