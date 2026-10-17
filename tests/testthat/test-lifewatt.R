test_that("public functions are exported", {
  expect_true(is.function(electricity_price))
  expect_true(is.function(electricity_price_trend))
  expect_true(is.function(life_expectancy))
  expect_true(is.function(life_expectancy_trend))
})

test_that("placeholders signal that they are not implemented", {
  expect_error(electricity_price_trend("32601"))
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