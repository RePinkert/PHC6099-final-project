test_that("observed regime, no bill: pure price + withheld loss columns", {
  r <- expected_life_loss("32601", "2026-07")
  expect_equal(r$regime, "observed")
  expect_equal(r$evidence_regime, "none")
  expect_true(is.na(r$implied_usage_kwh))
  expect_match(r$sensitivity_assumption, "delta_le not supplied: LE-loss columns withheld", fixed = TRUE)
  expect_match(r$sensitivity_assumption, "BMJ Public Health 2023;1:e000097", fixed = TRUE)
  expect_match(r$sensitivity_assumption, "NBER WP 25681", fixed = TRUE)
  expect_equal(r$e0_anchor_year, 2024L)
  expect_equal(r$e0_anchor, 79.0)
  expect_true(grepl("NVSR 75/5", r$e0_source))
})

test_that("predicted regime, bill only: descriptive implied usage, no posterior", {
  r <- expected_life_loss("32601", "2026-12", bill = 180)
  expect_equal(r$regime, "predicted")
  expect_equal(r$evidence_regime, "descriptive")
  expect_equal(r$implied_usage_kwh, 180 * 100 / r$price)
  expect_true(is.na(r$price_posterior))
})

test_that("predicted regime, bill+usage: posterior equals inverse-variance blend", {
  r <- expected_life_loss("32601", "2026-12", bill = 180, usage = 1200, meas_sd = 1)
  expect_equal(r$evidence_regime, "posterior")
  prior <- lifewatt:::.lstm_predict("FL", "2026-12")
  p_meas <- 180 * 100 / 1200
  w_m <- 1 / 1^2
  w_p <- 1 / unname(prior$.sd)^2
  expect_equal(r$price_meas, p_meas)
  expect_equal(unname(r$price_posterior), (w_m * p_meas + w_p * prior$price) / (w_m + w_p), tolerance = 1e-9)
  expect_equal(unname(r$price_posterior_sd), sqrt(1 / (w_m + w_p)), tolerance = 1e-9)
  expect_true(is.na(r$le_loss_years))
})

test_that("observed regime, bill+usage: local measurement alongside measured state price", {
  r <- expected_life_loss("32601", "2026-07", bill = 150, usage = 1000)
  expect_equal(r$evidence_regime, "measured_local")
  expect_equal(r$price_posterior, 150 * 100 / 1000)
  expect_true(is.na(r$price_sd))  # observed has no prior sd
})

test_that("delta_le supplied: loss columns computed against the anchor", {
  r <- expected_life_loss("32601", "2026-09", delta_le = 0.01)
  expect_equal(r$le_loss_years, 0.01)
  expect_equal(r$le_loss_pct_of_anchor, 0.01 / 79.0 * 100)
  expect_true(grepl("caller-declared sensitivity parameter", r$sensitivity_assumption))
  expect_match(r$sensitivity_assumption, "BMJ Public Health 2023;1:e000097", fixed = TRUE)
  expect_match(r$sensitivity_assumption, "NBER WP 25681", fixed = TRUE)
  expect_true(is.na(r$price_posterior))  # no bill, posterior untouched
})

test_that("anchor routing (D2 2023/2024, fallback declared for pre-2023 years)", {
  r <- expected_life_loss("32601", "2023-01")
  expect_equal(r$e0_anchor_year, 2023L)
  expect_equal(r$e0_anchor, 78.4)
  expect_false(grepl("outside anchor table", r$notes))
  a <- lifewatt:::.anchor_for(2026L)
  expect_equal(a$year, 2024L)
  a2 <- lifewatt:::.anchor_for(2022L)
  expect_equal(a2$year, 2023L)
})

test_that("honest errors", {
  expect_error(expected_life_loss("32601", "2026-07", bill = -5), "positive", fixed = TRUE)
  expect_error(expected_life_loss("32601", "2026-07", usage = 50), "usage without bill", fixed = TRUE)
  expect_error(expected_life_loss("32601", "2026-07", bill = 100, usage = -1), "usage must be", fixed = TRUE)
  expect_error(expected_life_loss("32601", "2026-07", delta_le = NA_real_), "finite", fixed = TRUE)
  expect_error(expected_life_loss("32601", "2026-07", meas_sd = 0), "meas_sd must be a positive number", fixed = TRUE)
})
