# 输入契约测试：防呆 / 防注入弹药包。
# 原则：任何含糊或恶意输入必须被显式拒绝并给出可行动的报错，绝不静默改写；
# 正则白名单（.zip5）是 ZIP 的唯一通路，URL 拼接再做纵深编码。
# 这些断言故意不依赖任何锚点数值——它们锁的是“拒绝行为”本身。

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

test_that("injection strings die at the zip gate, before any I/O", {
  expect_error(health_measure("32601&$where=1=1"), "Invalid zip", fixed = TRUE)
  expect_error(health_measure("32601'; DROP TABLE"), "Invalid zip", fixed = TRUE)
  expect_error(expected_life_loss("32601<script>", "2026-07"), "Invalid zip", fixed = TRUE)
  expect_error(my_electricity("32601&x=1", time = "2026-07"), "Invalid zip", fixed = TRUE)
  expect_error(electricity_price("32601|99999", year = 2024), "Invalid zip", fixed = TRUE)
  expect_error(life_expectancy("../../etc/passwd"), "Invalid zip", fixed = TRUE)
  expect_error(life_expectancy_trend("32601%00", period = "yoy"), "Invalid zip", fixed = TRUE)
})

test_that("PLACES URL construction is injection-safe (defense in depth)", {
  u <- lifewatt:::.places_url("32601")
  expect_match(u, "locationname=32601&", fixed = TRUE)
  u2 <- lifewatt:::.places_url("32601&$where=1=1")
  expect_match(u2, "locationname=32601%26", fixed = TRUE)
  expect_false(grepl("locationname=32601&$where", u2, fixed = TRUE))
})

test_that("time contract: the supported window is enforced at the UX layer", {
  expect_error(expected_life_loss("32601", "2035-01"), "outside the supported window", fixed = TRUE)
  expect_error(expected_life_loss("32601", "2027-01"), "outside the supported window", fixed = TRUE)
  expect_error(my_electricity("32601", time = "2035-06"), "outside the supported window", fixed = TRUE)
  expect_s3_class(expected_life_loss("32601", "2026-12"), "data.frame")
  expect_s3_class(expected_life_loss("32601", "2023-01"), "data.frame")
  expect_error(expected_life_loss("32601", "2026-13"), "Invalid month", fixed = TRUE)
  expect_error(expected_life_loss("32601", "foo"), "Invalid time", fixed = TRUE)
  expect_error(expected_life_loss("32601", NA), "Invalid time", fixed = TRUE)
  expect_error(expected_life_loss("32601", c("2026-06", "2026-07")), "exactly one", fixed = TRUE)
})

test_that("numeric evidence inputs must be scalar, finite and in-domain", {
  expect_error(expected_life_loss("32601", "2026-07", bill = "180"), "bill must be", fixed = TRUE)
  expect_error(expected_life_loss("32601", "2026-07", bill = c(180, 200)), "bill must be", fixed = TRUE)
  expect_error(expected_life_loss("32601", "2026-07", bill = NA_real_), "bill must be", fixed = TRUE)
  expect_error(expected_life_loss("32601", "2026-07", bill = Inf), "bill must be", fixed = TRUE)
  expect_error(expected_life_loss("32601", "2026-07", bill = 180, usage = c(1200, 1300)),
               "usage must be", fixed = TRUE)
  expect_error(expected_life_loss("32601", "2026-07", bill = 180, usage = "1200"),
               "usage must be", fixed = TRUE)
  expect_error(expected_life_loss("32601", "2026-07", meas_sd = c(1, 1)), "meas_sd must be", fixed = TRUE)
  expect_error(expected_life_loss("32601", "2026-07", meas_sd = "1"), "meas_sd must be", fixed = TRUE)
  expect_error(expected_life_loss("32601", "2026-07", meas_sd = 0), "meas_sd must be", fixed = TRUE)
  expect_error(expected_life_loss("32601", "2026-07", delta_le = c(0.1, 0.2)),
               "finite number of years", fixed = TRUE)
  expect_error(expected_life_loss("32601", "2026-07", delta_le = "0.1"),
               "finite number of years", fixed = TRUE)
  expect_error(expected_life_loss("32601", "2026-07", delta_le = Inf),
               "finite number of years", fixed = TRUE)
  expect_error(expected_life_loss("32601", "2026-07", delta_le = NA_real_),
               "finite number of years", fixed = TRUE)
})

test_that("quarter / year / period contracts refuse shape violations", {
  expect_error(life_expectancy("32601", quarter = "2024Q5"), "Invalid quarter", fixed = TRUE)
  expect_error(life_expectancy("32601", quarter = "2024-06"), "Invalid quarter", fixed = TRUE)
  expect_error(life_expectancy("32601", quarter = "24Q1"), "Invalid quarter", fixed = TRUE)
  expect_error(electricity_price("32601", period = "yoy"), "Unknown period", fixed = TRUE)
  expect_error(electricity_price("32601", year = 2024, period = "mom"), "not both", fixed = TRUE)
  expect_error(life_expectancy_trend("32601", period = "mom"), "should be one of")
})
