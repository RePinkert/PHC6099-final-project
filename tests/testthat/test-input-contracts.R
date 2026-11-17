# test-input-contracts.R —— 输入契约测试：防呆 / 防注入弹药包。
# 原则：任何含糊或恶意输入必须被显式拒绝并给出可行动的报错，绝不静默改写。
# W0 起有两个入口闸门，各自只认自己那一半：
#   .zip5()       —— 5 位数字（只剩 health_measure 用它按 ZCTA 查 CDC PLACES）
#   .state_code() —— 2 字母州码或州全名（价格 / 寿命层），并指名拒绝 ZIP 形状
# 两者都拒绝的输入（注入串）在价格侧报"Unknown state"，在健康侧报"Invalid zip"。

test_that("zip contract: accepted shapes normalize deterministically", {
  expect_equal(lifewatt:::.zip5("32601"), "32601")
  expect_equal(lifewatt:::.zip5(32601), "32601")
  expect_equal(lifewatt:::.zip5(32601L), "32601")
  expect_equal(lifewatt:::.zip5("32601-4401"), "32601")
  expect_equal(lifewatt:::.zip5("326014401"), "32601")
  expect_equal(lifewatt:::.zip5(" 32601 "), "32601")
  expect_equal(lifewatt:::.zip5("01002"), "01002")
  expect_equal(lifewatt:::.zip5(10000), "10000")
})

test_that("zip contract: ambiguous or malformed shapes are refused, never rewritten", {
  expect_error(lifewatt:::.zip5("1002"), "leading zeros required", fixed = TRUE)
  expect_error(lifewatt:::.zip5("3260"), "Invalid zip", fixed = TRUE)
  expect_error(lifewatt:::.zip5("326012"), "Invalid zip", fixed = TRUE)
  expect_error(lifewatt:::.zip5("32601.0"), "Invalid zip", fixed = TRUE)
  expect_error(lifewatt:::.zip5("abcde"), "Invalid zip", fixed = TRUE)
  expect_error(lifewatt:::.zip5(""), "Invalid zip", fixed = TRUE)
  expect_error(lifewatt:::.zip5("   "), "Invalid zip", fixed = TRUE)
  expect_error(lifewatt:::.zip5("32601\n0"), "Invalid zip", fixed = TRUE)
  expect_error(lifewatt:::.zip5("32601 0000"), "Invalid zip", fixed = TRUE)
  expect_error(lifewatt:::.zip5("32601.5"), "Invalid zip", fixed = TRUE)
  expect_error(lifewatt:::.zip5(-32601), "Invalid zip", fixed = TRUE)
  expect_error(lifewatt:::.zip5(32601.5), "Invalid zip", fixed = TRUE)
  expect_error(lifewatt:::.zip5(TRUE), "Invalid zip", fixed = TRUE)
  expect_error(lifewatt:::.zip5(NA), "Invalid zip", fixed = TRUE)
  expect_error(lifewatt:::.zip5(NA_character_), "Invalid zip", fixed = TRUE)
  expect_error(lifewatt:::.zip5(NULL), "Invalid zip", fixed = TRUE)
  expect_error(lifewatt:::.zip5(character(0)), "Invalid zip", fixed = TRUE)
  expect_error(lifewatt:::.zip5(c("32601", "99501")), "Invalid zip", fixed = TRUE)
  expect_error(lifewatt:::.zip5(list("32601")), "Invalid zip", fixed = TRUE)
})

test_that("state contract: the two entry gates are not interchangeable", {
  ## ZIP 形状 -> 价格层：指名拒绝并指路
  expect_error(expected_life_loss(anchor_zip_fl, "2026-07"), "looks like a ZIP code", fixed = TRUE)
  expect_error(my_electricity(anchor_zip_fl, time = "2026-07"), "looks like a ZIP code", fixed = TRUE)
  expect_error(electricity_price(anchor_zip_fl, year = 2024), "looks like a ZIP code", fixed = TRUE)
  expect_error(life_expectancy(anchor_zip_fl), "looks like a ZIP code", fixed = TRUE)
  expect_error(life_expectancy_trend(anchor_zip_fl, period = "yoy"), "looks like a ZIP code", fixed = TRUE)
})

test_that("injection strings die at the entry gate, before any I/O", {
  expect_error(health_measure("32601&$where=1=1"), "Invalid zip", fixed = TRUE)
  expect_error(health_measure("32601'; DROP TABLE"), "Invalid zip", fixed = TRUE)
  expect_error(expected_life_loss("32601<script>", "2026-07"), "Unknown state", fixed = TRUE)
  expect_error(my_electricity("32601&x=1", time = "2026-07"), "Unknown state", fixed = TRUE)
  expect_error(electricity_price("32601|99999", year = 2024), "Unknown state", fixed = TRUE)
  expect_error(life_expectancy("../../etc/passwd"), "Unknown state", fixed = TRUE)
  expect_error(life_expectancy_trend("32601%00", period = "yoy"), "Unknown state", fixed = TRUE)
})

test_that("PLACES URL construction is injection-safe (defense in depth)", {
  u <- lifewatt:::.places_url("32601")
  expect_match(u, "locationname=32601&", fixed = TRUE)
  u2 <- lifewatt:::.places_url("32601&$where=1=1")
  expect_match(u2, "locationname=32601%26", fixed = TRUE)
  expect_false(grepl("locationname=32601&$where", u2, fixed = TRUE))
})

test_that("time contract: the supported window is enforced at the UX layer", {
  expect_error(expected_life_loss(anchor_state_fl, "2035-01"), "outside the supported window", fixed = TRUE)
  expect_error(expected_life_loss(anchor_state_fl, "2027-01"), "outside the supported window", fixed = TRUE)
  expect_error(my_electricity(anchor_state_fl, time = "2035-06"), "outside the supported window", fixed = TRUE)
  expect_s3_class(expected_life_loss(anchor_state_fl, "2026-12"), "data.frame")
  expect_s3_class(expected_life_loss(anchor_state_fl, "2023-01"), "data.frame")
  expect_error(expected_life_loss(anchor_state_fl, "2026-13"), "Invalid month", fixed = TRUE)
  expect_error(expected_life_loss(anchor_state_fl, "foo"), "Invalid time", fixed = TRUE)
  expect_error(expected_life_loss(anchor_state_fl, NA), "time is NA", fixed = TRUE)
  expect_error(expected_life_loss(anchor_state_fl, c("2026-06", "2026-07")), "exactly one", fixed = TRUE)
})

test_that("numeric evidence inputs must be scalar, finite and in-domain", {
  expect_error(expected_life_loss(anchor_state_fl, "2026-07", bill = "180"), "bill must be", fixed = TRUE)
  expect_error(expected_life_loss(anchor_state_fl, "2026-07", bill = c(180, 200)), "bill must be", fixed = TRUE)
  expect_error(expected_life_loss(anchor_state_fl, "2026-07", bill = NA_real_), "bill must be", fixed = TRUE)
  expect_error(expected_life_loss(anchor_state_fl, "2026-07", bill = Inf), "bill must be", fixed = TRUE)
  expect_error(expected_life_loss(anchor_state_fl, "2026-07", bill = 180, usage = c(1200, 1300)),
               "usage must be", fixed = TRUE)
  expect_error(expected_life_loss(anchor_state_fl, "2026-07", bill = 180, usage = "1200"),
               "usage must be", fixed = TRUE)
  expect_error(expected_life_loss(anchor_state_fl, "2026-07", meas_sd = c(1, 1)), "meas_sd must be", fixed = TRUE)
  expect_error(expected_life_loss(anchor_state_fl, "2026-07", meas_sd = "1"), "meas_sd must be", fixed = TRUE)
  expect_error(expected_life_loss(anchor_state_fl, "2026-07", meas_sd = 0), "meas_sd must be", fixed = TRUE)
  expect_error(expected_life_loss(anchor_state_fl, "2026-07", delta_le = c(0.1, 0.2)),
               "finite number of years", fixed = TRUE)
  expect_error(expected_life_loss(anchor_state_fl, "2026-07", delta_le = "0.1"),
               "finite number of years", fixed = TRUE)
  expect_error(expected_life_loss(anchor_state_fl, "2026-07", delta_le = Inf),
               "finite number of years", fixed = TRUE)
  expect_error(expected_life_loss(anchor_state_fl, "2026-07", delta_le = NA_real_),
               "finite number of years", fixed = TRUE)
})

test_that("quarter / year / period contracts refuse shape violations", {
  expect_error(life_expectancy(anchor_state_fl, quarter = "2024Q5"), "Invalid quarter", fixed = TRUE)
  expect_error(life_expectancy(anchor_state_fl, quarter = "2024-06"), "Invalid quarter", fixed = TRUE)
  expect_error(life_expectancy(anchor_state_fl, quarter = "24Q1"), "Invalid quarter", fixed = TRUE)
  expect_error(electricity_price(anchor_state_fl, period = "yoy"), "Unknown period", fixed = TRUE)
  expect_error(electricity_price(anchor_state_fl, year = 2024, period = "mom"), "not both", fixed = TRUE)
  expect_error(life_expectancy_trend(anchor_state_fl, period = "mom"), "quarterly", fixed = TRUE)
})

test_that("state input itself is validated (scalar, known, not NA)", {
  expect_error(electricity_price(c("FL", "GA"), year = 2024), "exactly one value", fixed = TRUE)
  expect_error(electricity_price(NA_character_, year = 2024), "NA", fixed = TRUE)
  expect_error(electricity_price("", year = 2024), "empty", fixed = TRUE)
  expect_error(electricity_price("ZZ", year = 2024), "Unknown state", fixed = TRUE)
  ## 全名与小写都被接受，且解析到同一个州
  a <- electricity_price("florida", year = 2024)
  b <- electricity_price("FL", year = 2024)
  expect_identical(a, b)
})
