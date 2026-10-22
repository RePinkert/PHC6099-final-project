test_that("public functions are exported", {
  expect_true(is.function(electricity_price))
  expect_true(is.function(electricity_price_trend))
  expect_true(is.function(expected_life_loss))
  expect_true(is.function(my_electricity))
  expect_true(is.function(life_expectancy))
  expect_true(is.function(life_expectancy_trend))
  expect_true(is.function(health_measure))
})

test_that("electricity_price dispatches to the internal layers", {
  a <- electricity_price("32601", year = 2024)
  expect_equal(a$price, lifewatt:::.zip_annual_price("32601", 2024)$price)
  expect_equal(a$regime, "observed")
  m <- electricity_price("32601", period = "mom")
  expect_equal(nrow(m), 43L)
  expect_equal(m$period[nrow(m)], "2026-07")
  expect_equal(m$price[nrow(m)], 15.03)
})

test_that("electricity_price honest errors", {
  expect_error(electricity_price("32601"), "Provide either year", fixed = TRUE)
  expect_error(electricity_price("32601", year = 2024, period = "mom"), "not both", fixed = TRUE)
  expect_error(electricity_price("32601", period = "momx"), "Unknown period", fixed = TRUE)
})

test_that("life_expectancy: synthetic e0 with provenance + declared assumptions (exp#43)", {
  r <- life_expectancy("32601", quarter = "2024Q4")
  expect_equal(r$state, "FL")
  expect_equal(r$e0_synth, r$e0_anchor + r$delta_e1, tolerance = 1e-9)
  expect_equal(r$e0_anchor, 79.0)
  expect_match(r$estimate_type, "synthetic_e0", fixed = TRUE)
  expect_match(r$estimate_type, "not an NCHS-published subnational life expectancy", fixed = TRUE)
  expect_match(r$sensitivity_assumption, "DECLARED assumption", fixed = TRUE)
  expect_provenance_cols(r)
  d <- life_expectancy("32601")  # default = latest shipped quarter
  expect_equal(d$quarter, "2025Q3")
  expect_match(d$notes, "outside D2 anchor table", fixed = TRUE)  # 2025 falls back to 2024 anchor
})

test_that("life_expectancy_trend: yoy/qoq on the quarterly synthesis; mom refused honestly", {
  ty <- life_expectancy_trend("32601", period = "yoy", quarter = "2024Q4")
  expect_equal(ty$from_quarter, "2023Q4")
  expect_equal(ty$e0_change_years, ty$e0_synth_to - ty$e0_synth_from, tolerance = 1e-9)
  tq <- life_expectancy_trend("32601", period = "qoq", quarter = "2024Q4")
  expect_equal(tq$from_quarter, "2024Q3")
  expect_true(tq$provisional)
  expect_error(life_expectancy_trend("32601", period = "mom"), "should be one of")
  expect_provenance_cols(ty)
})

test_that("life_* honest errors", {
  expect_error(life_expectancy("99999"), "No electric utility record", fixed = TRUE)
  expect_error(life_expectancy("32601", quarter = "2024-06"), "Invalid quarter", fixed = TRUE)
  expect_error(life_expectancy("32601", quarter = "2022Q4"), "window 2023Q1..2025Q3", fixed = TRUE)
})

test_that("trend wrappers: yoy uses A1 diffs, mom uses B1 diffs", {
  ty <- electricity_price_trend("32601", period = "yoy")
  expect_equal(ty$year, c(2024L, 2025L))
  p23 <- lifewatt:::.zip_annual_price("32601", 2023)$price
  p24 <- lifewatt:::.zip_annual_price("32601", 2024)$price
  expect_equal(ty$change[1], p24 - p23, tolerance = 1e-9)
  expect_true("provisional" %in% names(ty))
  expect_false(any(ty$provisional))  # A1 年度两侧均为终值
  expect_provenance_cols(ty)
  tm <- electricity_price_trend("32601", period = "mom")
  expect_equal(nrow(tm), 42L)
  b <- lifewatt:::.mom_series("32601")$price
  expect_equal(tm$change[1], b[2] - b[1], tolerance = 1e-9)
  expect_false(tm$provisional[1])
  expect_true(tm$provisional[nrow(tm)])
  expect_provenance_cols(tm)
  expect_error(electricity_price_trend("32601", period = "q"))
})

test_that("every exported output carries the full provenance contract", {
  expect_provenance_cols(electricity_price("32601", year = 2024))
  expect_provenance_cols(electricity_price("32601", period = "mom"))
  expect_provenance_cols(electricity_price_trend("32601", period = "yoy"))
  expect_provenance_cols(electricity_price_trend("32601", period = "mom"))
  expect_provenance_cols(expected_life_loss("32601", "2026-07"))
  expect_provenance_cols(my_electricity("32601", time = "2026-07"))
  expect_provenance_cols(life_expectancy("32601", quarter = "2024Q4"))
  expect_provenance_cols(life_expectancy_trend("32601", period = "qoq", quarter = "2024Q4"))
})