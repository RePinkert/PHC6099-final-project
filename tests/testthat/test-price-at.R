test_that("observed branch returns cache-verbatim price (anchor: 32601 FL)", {
  r <- lifewatt:::.price_at("32601", "2026-07")
  cache <- lifewatt:::.monthly_cache()
  ref <- cache$price[cache$state == "FL" & cache$period == "2026-07"]
  expect_equal(r$price, ref)
  expect_equal(r$regime, "observed")
  expect_true(r$provisional)
  expect_equal(r$unit, "cents/kWh")
  expect_equal(r$level, "state")
  expect_equal(r$degraded_from, "zip")
  expect_true(grepl("Gainesville Regional", r$utilities))
})

test_that("provisional boundary is 2025-01 (B1 final/provisional two layers)", {
  final_row <- lifewatt:::.price_at("32601", "2024-12")
  provisional_row <- lifewatt:::.price_at("32601", "2025-01")
  expect_false(final_row$provisional)
  expect_true(provisional_row$provisional)
})

test_that("AK 2023-01 pin value from the raw cache (21.73; 99501 -> AK)", {
  expect_equal(lifewatt:::.price_at("99501", "2023-01")$price, 21.73)
  expect_equal(lifewatt:::.price_at("99501", "2023-01")$state, "AK")
})

test_that("Date / YYYY/MM / YYYY-M inputs normalize", {
  expect_equal(lifewatt:::.month_key(as.Date("2026-07-15")), "2026-07")
  expect_equal(lifewatt:::.month_key("2026/7"), "2026-07")
  expect_equal(lifewatt:::.month_key("2026-1"), "2026-01")
})

test_that("beyond-window inputs dispatch to the predicted branch (exp#33)", {
  fut <- lifewatt:::.price_at("32601", "2026-08")
  expect_equal(fut$regime, "predicted")
  expect_true(is.finite(fut$price) && fut$price > 0)
  expect_true(is.finite(fut$price_sd) && fut$price_sd > 0)
  expect_true(is.na(fut$provisional))
  expect_equal(fut$fit_as_of, "2026-07")
  expect_error(lifewatt:::.price_at("32601", "2022-12"), "no record for state FL", fixed = TRUE)
})

test_that("malformed time inputs fail loudly", {
  expect_error(lifewatt:::.price_at("32601", "foo"), "Invalid time", fixed = TRUE)
  expect_error(lifewatt:::.price_at("32601", c("2026-06", "2026-07")), "exactly one", fixed = TRUE)
  expect_error(lifewatt:::.price_at("32601", "2026-13"), "Invalid month", fixed = TRUE)
})
