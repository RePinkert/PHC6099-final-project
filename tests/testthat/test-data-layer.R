test_that("extdata layer ships readable B1 cache", {
  d <- lifewatt:::.monthly_cache()
  expect_equal(colnames(d), c("state", "period", "price"))
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
