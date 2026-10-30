test_that("extdata layer ships readable B1 cache", {
  d <- lifewatt:::.monthly_cache()
  expect_equal(colnames(d), c("state", "period", "price", "data_status"))
  expect_setequal(unique(d$state), c(state.abb, "DC"))
  expect_equal(nrow(d), 2193L)
  expect_equal(min(d$period), "2023-01")
  expect_equal(max(d$period), "2026-07")
})

test_that("extdata layer ships phaseB fit with passing gate", {
  fit <- lifewatt:::.price_fit()
  expect_true(isTRUE(fit$gate_pass))
  expect_equal(fit$fit_as_of, "2026-07")
  expect_setequal(unique(fit$states), c(state.abb, "DC"))
  expect_true(fit$consistency_tail_ratio <= 1.5)
})

test_that("all data planes agree on the 51-state universe (no silent divergence)", {
  cache <- lifewatt:::.monthly_cache()
  fit <- lifewatt:::.price_fit()
  map <- lifewatt:::.open_map()
  vsrr <- utils::read.csv(system.file("extdata", "vsrr_state_quarter_slim.csv.gz", package = "lifewatt"),
                          colClasses = c(state = "character"))
  states <- unique(cache$state)
  expect_setequal(fit$states, states)
  expect_true(all(unique(map$state) %in% states))
  expect_true(all(states %in% unique(vsrr$state)))
  c1 <- utils::read.csv(system.file("extdata", "eia112_state_month_slim.csv.gz", package = "lifewatt"),
                        colClasses = c(state = "character"))
  expect_setequal(unique(c1$state), states)
})
