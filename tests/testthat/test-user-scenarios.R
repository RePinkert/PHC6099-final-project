# test-user-scenarios.R —— 用户侧回归用例（tidyverse/testthat 3e 惯例）
# 与 HANDOVER「第四回合」8 条真实调用留档一一对应；快照锁定用户可见输出与报错，
# 数值契约用 expect_equal 对账内部层（避免写出两份同一数字）。
# 按对外函数分片落地：每片只带自己那部分的场景，用例标题沿用全量编号。

test_that("scenario 6: 年度 ZIP 价（A1 x A2 客户加权）", {
  a <- electricity_price(anchor_zip_fl, year = 2024)
  expect_equal(a$price, .zip_annual_price(anchor_zip_fl, 2024)$price)
  expect_equal(a$regime, "observed")
  expect_false(a$provisional)
  expect_equal(a$mapping_vintage, "2024")
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

test_that("scenario 9: 讲不通的输入会被指名拒绝（快照锁定用户可见报错文本）", {
  # 无 year/period 直接调用：mock 意向下必须有指路信息
  expect_snapshot(
    tryCatch(electricity_price(anchor_zip_fl), error = function(e) e)$message
  )
})