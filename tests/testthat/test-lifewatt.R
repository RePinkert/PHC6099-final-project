# test-lifewatt.R —— 对外接口面（2026-11-17：zip_to_state() 已删除；health_measure() 是唯一 ZIP 入口）

test_that("public functions are exported", {
  expect_true(is.function(electricity_price))
  expect_true(is.function(electricity_price_trend))
  expect_true(is.function(expected_life_loss))
  expect_true(is.function(my_electricity))
  expect_true(is.function(life_expectancy))
  expect_true(is.function(life_expectancy_trend))
  expect_true(is.function(health_measure))
  expect_setequal(getNamespaceExports("lifewatt"),
                  c("electricity_price", "electricity_price_trend", "expected_life_loss",
                    "health_measure", "life_expectancy", "life_expectancy_trend",
                    "my_electricity"))
})

test_that("electricity_price dispatches to the internal layers", {
  a <- electricity_price(anchor_state_fl, year = 2024)
  expect_equal(a$price, lifewatt:::.state_annual_price(anchor_state_fl, 2024)$price)
  expect_equal(a$regime, "observed")
  m <- electricity_price(anchor_state_fl, period = "mom")
  expect_equal(nrow(m), 43L)
  expect_equal(m$period[nrow(m)], "2026-07")
  expect_equal(m$price[nrow(m)], 15.03)
})

test_that("electricity_price honest errors", {
  expect_error(electricity_price(anchor_state_fl), "Provide either year", fixed = TRUE)
  expect_error(electricity_price(anchor_state_fl, year = 2024, period = "mom"), "not both", fixed = TRUE)
  expect_error(electricity_price(anchor_state_fl, period = "momx"), "Unknown period", fixed = TRUE)
  expect_error(electricity_price(anchor_zip_fl, year = 2024), "looks like a ZIP code", fixed = TRUE)
})

test_that("life_expectancy: synthetic e0 with provenance + declared assumptions (exp#43)", {
  r <- life_expectancy(anchor_state_fl, quarter = "2024Q4")
  expect_equal(r$state, "FL")
  expect_equal(r$e0_synth, r$e0_anchor + r$delta_e1, tolerance = 1e-9)
  expect_equal(r$e0_anchor, 79.0)
  expect_match(r$estimate_type, "synthetic_e0", fixed = TRUE)
  expect_match(r$estimate_type, "not an NCHS-published subnational life expectancy", fixed = TRUE)
  expect_match(r$sensitivity_assumption, "DECLARED assumption", fixed = TRUE)
  expect_provenance_cols(r)
  d <- life_expectancy(anchor_state_fl)  # default = latest shipped quarter
  expect_equal(d$quarter, "2025Q3")
  expect_match(d$notes, "outside D2 anchor table", fixed = TRUE)  # 2025 falls back to 2024 anchor
})

test_that("life_expectancy_trend: yoy/qoq on the quarterly synthesis; mom refused honestly", {
  ty <- life_expectancy_trend(anchor_state_fl, period = "yoy", quarter = "2024Q4")
  expect_equal(ty$from_quarter, "2023Q4")
  expect_equal(ty$e0_change_years, ty$e0_synth_to - ty$e0_synth_from, tolerance = 1e-9)
  tq <- life_expectancy_trend(anchor_state_fl, period = "qoq", quarter = "2024Q4")
  expect_equal(tq$from_quarter, "2024Q3")
  expect_true(tq$provisional)
  expect_error(life_expectancy_trend(anchor_state_fl, period = "mom"), "should be one of")
  expect_provenance_cols(ty)
})

test_that("life_* honest errors", {
  expect_error(life_expectancy("ZZ"), "Unknown state", fixed = TRUE)
  expect_error(life_expectancy(anchor_zip_fl), "looks like a ZIP code", fixed = TRUE)
  expect_error(life_expectancy(anchor_state_fl, quarter = "2024-06"), "Invalid quarter", fixed = TRUE)
  expect_error(life_expectancy(anchor_state_fl, quarter = "2022Q4"), "window 2023Q1..2025Q3", fixed = TRUE)
})

test_that("trend wrappers: yoy uses A1 diffs, mom uses B1 diffs", {
  ty <- electricity_price_trend(anchor_state_fl, period = "yoy")
  expect_equal(ty$year, c(2024L, 2025L))
  p23 <- lifewatt:::.state_annual_price(anchor_state_fl, 2023)$price
  p24 <- lifewatt:::.state_annual_price(anchor_state_fl, 2024)$price
  expect_equal(ty$change[1], p24 - p23, tolerance = 1e-9)
  expect_true("provisional" %in% names(ty))
  expect_false(any(ty$provisional))  # A1 年度两侧均为终值
  expect_true(all(ty$n_utility > 0L))
  expect_provenance_cols(ty)
  tm <- electricity_price_trend(anchor_state_fl, period = "mom")
  expect_equal(nrow(tm), 42L)
  b <- lifewatt:::.mom_series(anchor_state_fl)$price
  expect_equal(tm$change[1], b[2] - b[1], tolerance = 1e-9)
  expect_false(tm$provisional[1])
  expect_true(tm$provisional[nrow(tm)])
  expect_provenance_cols(tm)
  expect_error(electricity_price_trend(anchor_state_fl, period = "q"))
})

test_that("every exported output carries the full provenance contract", {
  expect_provenance_cols(electricity_price(anchor_state_fl, year = 2024))
  expect_provenance_cols(electricity_price(anchor_state_fl, period = "mom"))
  expect_provenance_cols(electricity_price_trend(anchor_state_fl, period = "yoy"))
  expect_provenance_cols(electricity_price_trend(anchor_state_fl, period = "mom"))
  expect_provenance_cols(expected_life_loss(anchor_state_fl, "2026-07"))
  expect_provenance_cols(my_electricity(anchor_state_fl, time = "2026-07"))
  expect_provenance_cols(life_expectancy(anchor_state_fl, quarter = "2024Q4"))
  expect_provenance_cols(life_expectancy_trend(anchor_state_fl, period = "qoq", quarter = "2024Q4"))
})

test_that("no state-level output claims a ZIP-level degradation", {
  rows <- list(
    electricity_price(anchor_state_fl, year = 2024),
    electricity_price(anchor_state_fl, period = "mom"),
    electricity_price_trend(anchor_state_fl, period = "yoy"),
    expected_life_loss(anchor_state_fl, "2026-07"),
    my_electricity(anchor_state_fl, time = "2026-07"),
    life_expectancy(anchor_state_fl, quarter = "2024Q4")
  )
  for (r in rows) {
    expect_true(all(is.na(r$degraded_from)))
    expect_true(all(r$level == "state"))
    expect_false("zip" %in% names(r))
  }
})
