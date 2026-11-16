# test-price-at.R —— `.price_at(state, time)` 的双分支契约（W0 起收州）
# 观察分支 = B1 cache 逐位；预测分支 = LSTM + 区间；两者都不再有 zip/degraded_from。

test_that("observed branch returns cache-verbatim price (anchor: FL)", {
  r <- lifewatt:::.price_at(anchor_state_fl, "2026-07")
  cache <- lifewatt:::.monthly_cache()
  ref <- cache$price[cache$state == "FL" & cache$period == "2026-07"]
  expect_equal(r$price, ref)
  expect_equal(r$regime, "observed")
  expect_true(r$provisional)
  expect_equal(r$unit, "cents/kWh")
  expect_equal(r$level, "state")
  ## W0：没有 ZIP 降级可声明，也没有 ZIP 名下的列
  expect_true(is.na(r$degraded_from))
  expect_true(is.na(r$mapping_vintage))
  expect_false("zip" %in% names(r))
  expect_false("utilities" %in% names(r))
  expect_true(r$n_utility > 1L)
})

test_that("provisional follows EIA-861M data status (Final 2025-12 / Preliminary 2026-01)", {
  b1 <- lifewatt:::.monthly_cache()
  expect_setequal(unique(b1$data_status), c("Final", "Preliminary"))
  expect_equal(min(b1$period[b1$data_status == "Preliminary"]), "2026-01")
  expect_false(lifewatt:::.price_at(anchor_state_fl, "2025-12")$provisional)
  expect_true(lifewatt:::.price_at(anchor_state_fl, "2026-01")$provisional)
})

test_that("refreshed cache carries EIA's revisions (MD 2026-03 initial 35.85 -> 22.2)", {
  b1 <- lifewatt:::.monthly_cache()
  expect_equal(b1$price[b1$state == "MD" & b1$period == "2026-03"], 22.2)
})

test_that("AK 2023-01 pin value from the raw cache (21.73)", {
  expect_equal(lifewatt:::.price_at(anchor_state_ak, "2023-01")$price, 21.73)
  expect_equal(lifewatt:::.price_at(anchor_state_ak, "2023-01")$state, "AK")
})

test_that("Date / YYYY/MM / YYYY-M inputs normalize", {
  expect_equal(lifewatt:::.month_key(as.Date("2026-07-15")), "2026-07")
  expect_equal(lifewatt:::.month_key("2026/7"), "2026-07")
  expect_equal(lifewatt:::.month_key("2026-1"), "2026-01")
})

test_that("beyond-window inputs dispatch to the predicted branch (exp#33)", {
  fut <- lifewatt:::.price_at(anchor_state_fl, "2026-08")
  expect_equal(fut$regime, "predicted")
  expect_true(is.finite(fut$price) && fut$price > 0)
  expect_true(is.finite(fut$price_sd) && fut$price_sd > 0)
  expect_true(is.na(fut$provisional))
  expect_equal(fut$fit_as_of, "2026-07")
  expect_error(lifewatt:::.price_at(anchor_state_fl, "2022-12"), "no record for state FL", fixed = TRUE)
})

test_that("malformed time and location inputs fail loudly", {
  expect_error(lifewatt:::.price_at(anchor_state_fl, "foo"), "Invalid time", fixed = TRUE)
  expect_error(lifewatt:::.price_at(anchor_state_fl, c("2026-06", "2026-07")), "exactly one", fixed = TRUE)
  expect_error(lifewatt:::.price_at(anchor_state_fl, "2026-13"), "Invalid month", fixed = TRUE)
  expect_error(lifewatt:::.price_at(anchor_zip_fl, "2026-07"), "looks like a ZIP code", fixed = TRUE)
})
