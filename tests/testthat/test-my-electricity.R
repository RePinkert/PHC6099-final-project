test_that("my_electricity mirrors the shared machinery (bill descriptive)", {
  r <- my_electricity("32601", bill = 180, time = "2026-12")
  expect_s3_class(r, "data.frame")
  expect_equal(r$regime, "predicted")
  expect_equal(r$evidence_regime, "descriptive")
  expect_equal(r$implied_usage_kwh, 180 * 100 / r$price)
  expect_true(is.na(r$price_posterior))
  expect_true(grepl("phaseB triplet", r$notes))
  expect_true(is.na(r$provisional))
})

test_that("my_electricity observed regime keeps provenance (no bill)", {
  r <- my_electricity("32601", time = "2026-07")
  expect_equal(r$regime, "observed")
  expect_equal(r$price, 15.03)
  expect_equal(r$evidence_regime, "none")
  expect_equal(r$source, "EIA retail-sales monthly (B1; inst/extdata cache)")
  expect_false(grepl("LE|life", r$notes))  # energy-side only, no LE leakage
})

test_that("my_electricity bill+usage posterior matches expected_life_loss's evidence", {
  a <- my_electricity("32601", bill = 180, time = "2026-12", usage = 1200, meas_sd = 1)
  b <- expected_life_loss("32601", "2026-12", bill = 180, usage = 1200, meas_sd = 1)
  expect_equal(a$price_posterior, b$price_posterior)
  expect_equal(a$evidence_regime, "posterior")
  expect_equal(a$price, b$price)
})

test_that("my_electricity honest errors (shared validation)", {
  expect_error(my_electricity("32601", bill = -1, time = "2026-07"), "positive", fixed = TRUE)
  expect_error(my_electricity("32601", time = "2026-07", usage = 50), "usage without bill", fixed = TRUE)
  expect_error(my_electricity("32601", time = "2026-07", meas_sd = -2), "meas_sd must be", fixed = TRUE)
})
