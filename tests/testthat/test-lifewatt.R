test_that("public functions are exported", {
  expect_true(is.function(electricity_price))
  expect_true(is.function(electricity_price_trend))
  expect_true(is.function(expected_life_loss))
  expect_true(is.function(life_expectancy))
  expect_true(is.function(life_expectancy_trend))
})

test_that("placeholders signal that they are not implemented", {
  expect_error(life_expectancy("32601"))
  expect_error(life_expectancy_trend("32601"))
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

test_that("trend wrappers: yoy uses A1 diffs, mom uses B1 diffs", {
  ty <- electricity_price_trend("32601", period = "yoy")
  expect_equal(ty$year, c(2024L, 2025L))
  p23 <- lifewatt:::.zip_annual_price("32601", 2023)$price
  p24 <- lifewatt:::.zip_annual_price("32601", 2024)$price
  expect_equal(ty$change[1], p24 - p23, tolerance = 1e-9)
  tm <- electricity_price_trend("32601", period = "mom")
  expect_equal(nrow(tm), 42L)
  b <- lifewatt:::.mom_series("32601")$price
  expect_equal(tm$change[1], b[2] - b[1], tolerance = 1e-9)
  expect_false(tm$provisional[1])
  expect_true(tm$provisional[nrow(tm)])
  expect_error(electricity_price_trend("32601", period = "q"))
})