test_that("public functions are exported", {
  expect_true(is.function(electricity_price))
  expect_true(is.function(electricity_price_trend))
  expect_true(is.function(life_expectancy))
  expect_true(is.function(life_expectancy_trend))
})

test_that("placeholders signal that they are not implemented", {
  expect_error(electricity_price("32601"))
  expect_error(electricity_price_trend("32601"))
  expect_error(life_expectancy("32601"))
  expect_error(life_expectancy_trend("32601"))
})
