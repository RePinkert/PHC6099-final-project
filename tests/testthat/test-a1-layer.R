# test-a1-layer.R —— A1 年度层：州年价（W0 起不再有 ZIP 混合）
# 契约：price 与 price_min/max/n_utility 必须取自**同一个** utility 集合（该州的居民 utility，
# 排除 EIA 的 99999 调整伪 utility），否则"州值 vs 州内范围"不可比。

test_that("A1 state annual price is the customer-weighted mean of the state's utilities", {
  r <- lifewatt:::.state_annual_price("FL", 2024)
  expect_equal(r$state, "FL")
  expect_equal(r$year, 2024L)
  s <- lifewatt:::.state_utility_rows("FL", 2024)
  expect_gt(nrow(s), 2L)
  expect_equal(r$price, stats::weighted.mean(s$price, s$cus), tolerance = 1e-9)
  expect_equal(r$price_min, min(s$price))
  expect_equal(r$price_max, max(s$price))
  expect_equal(r$n_utility, nrow(s))
  ## 不变量：客户加权均值必落在 min/max 之间（W0 的 A3 判据，单州版本）
  expect_true(r$price_min <= r$price && r$price <= r$price_max)
  expect_equal(r$regime, "observed")
  expect_false(r$provisional)
  expect_true(is.na(r$degraded_from))     # 不再有 ZIP 降级可声明
  expect_true(is.na(r$mapping_vintage))   # 州年价不经过任何映射
  expect_match(r$confidence_tier, "^B:")
})

test_that("A1 state price reproduces the shipped state annual table", {
  agg <- utils::read.csv(system.file("extdata", "eia861_state_annual.csv.gz", package = "lifewatt"),
                         stringsAsFactors = FALSE)
  for (y in c(2023L, 2024L, 2025L)) {
    for (st in c("FL", "CA", "TX", "DC", "MA", "AK", "NC")) {
      got <- lifewatt:::.state_annual_price(st, y)$price
      want <- agg$price[agg$state == st & agg$year == y]
      expect_equal(got, want, tolerance = 1e-9, label = paste(st, y))
    }
  }
})

test_that("A1 vendor boundary: final years only, 2026 early vintage refused", {
  expect_error(lifewatt:::.state_annual_price("FL", 2026),
               "only final EIA releases are shipped, so not 2026", fixed = TRUE)
  expect_error(lifewatt:::.state_annual_price("FL", 2022), "No utility-level EIA-861 annual price for 2022", fixed = TRUE)
  expect_error(lifewatt:::.state_annual_price("ZZ", 2024), "Unknown state", fixed = TRUE)
  expect_error(lifewatt:::.state_annual_price("FL", c(2024, 2025)), "exactly one", fixed = TRUE)
  ## ZIP 形状在 A1 层同样被指名拒绝
  expect_error(lifewatt:::.state_annual_price("32601", 2024), "looks like a ZIP code", fixed = TRUE)
})

test_that("the EIA state-adjustment pseudo-utility never enters price, min, max or n_utility", {
  slim <- lifewatt:::.annual_slim()
  adj <- slim[slim$eiaid == "99999", ]
  expect_gt(nrow(adj), 0L)
  checked <- 0L
  for (st in unique(adj$state)) {
    for (y in c(2023L, 2024L, 2025L)) {
      if (!nrow(adj[adj$state == st & adj$year == y, ])) next
      s <- lifewatt:::.state_utility_rows(st, y)
      if (nrow(s) == 0L) next
      expect_false("99999" %in% s$eiaid, label = paste(st, y))
      checked <- checked + 1L
    }
  }
  expect_gt(checked, 0L)
})
