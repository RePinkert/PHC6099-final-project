# test-user-facing-fixes.R —— 用户侧测试里发现的问题（2026-11-17）各钉一条，防止回退。

test_that("quarter accepts the documented and the compact spelling, and nothing else", {
  a <- life_expectancy(anchor_state_fl, quarter = "2024Q4")
  expect_equal(life_expectancy(anchor_state_fl, quarter = "2024-Q4")$e0_synth, a$e0_synth)
  expect_equal(life_expectancy(anchor_state_fl, quarter = "2024q4")$quarter, "2024Q4")
  expect_equal(life_expectancy_trend(anchor_state_fl, "qoq", quarter = "2024-Q4")$to_quarter, "2024Q4")
  expect_error(life_expectancy(anchor_state_fl, quarter = "2024Q5"), "such as '2024Q4'", fixed = TRUE)
  expect_error(life_expectancy(anchor_state_fl, quarter = "2024-06"), "such as '2024Q4'", fixed = TRUE)
  expect_error(life_expectancy(anchor_state_fl, quarter = c("2024Q3", "2024Q4")), "exactly one", fixed = TRUE)
})

test_that("ypll75 carries a per-person companion column", {
  r <- life_expectancy(anchor_state_fl)
  expect_equal(r$ypll75_years_per_person, r$ypll75_per_1k / 1000)
})

test_that("a fractional or non-numeric year is refused, not truncated", {
  expect_error(electricity_price(anchor_state_fl, year = 2024.5), "whole year", fixed = TRUE)
  expect_error(electricity_price(anchor_state_fl, year = "abc"), "whole year", fixed = TRUE)
  expect_error(electricity_price(anchor_state_fl, year = Inf), "whole year", fixed = TRUE)
  expect_equal(electricity_price(anchor_state_fl, year = "2024")$year, 2024L)
})

test_that("price_features always offers a same-series baseline", {
  r <- price_features(anchor_state_fl)
  expect_false(anyNA(r$price_vs_avg12m_pct))
  expect_equal(r$price_vs_avg12m_pct, (r$price - r$avg_12m) / r$avg_12m * 100)
  no_ann <- !is.finite(r$annual_price)
  expect_true(any(no_ann))
  expect_true(all(grepl("price_vs_avg12m_pct", r$notes[no_ann], fixed = TRUE)))
  expect_true(is.na(price_features(anchor_state_fl, period = "2010-01")$price_vs_avg12m_pct))
})

test_that("lag_matrix returns each state once even if named twice", {
  r <- lag_matrix(c("fl", "FL", "Florida"), from = "2026-07", lags = 0)
  expect_equal(nrow(r), 1L)
})

test_that("the forecast interval states its level; the observed regime does not", {
  p <- my_electricity(anchor_state_fl, time = "2026-12")
  expect_equal(p$price_interval_level, 0.85)
  expect_match(p$price_interval_basis, "nominal 85% interval", fixed = TRUE)
  expect_false(grepl("model_traning", p$price_interval_basis, fixed = TRUE))
  o <- my_electricity(anchor_state_fl, time = "2026-07")
  expect_true(is.na(o$price_interval_level))
})

test_that("n_utility says which EIA-861 year it comes from", {
  expect_equal(my_electricity(anchor_state_fl, time = "2026-12")$n_utility_year, 2025L)
  expect_equal(my_electricity(anchor_state_fl, time = "2024-06")$n_utility_year, 2024L)
  m <- electricity_price(anchor_state_fl, period = "mom")
  expect_equal(m$n_utility_year[m$period == "2023-01"], 2023L)
})

test_that("user-facing text no longer talks about ZIPs on state rows or a future contract date", {
  r <- expected_life_loss(anchor_state_fl, "2026-07")
  expect_false(grepl("ZIP", r$confidence_tier, fixed = TRUE))
  expect_false(grepl("within_state_sd", price_features(anchor_state_fl, period = "2026-07")$confidence_tier, fixed = TRUE))
  expect_false(grepl("2026-11-18", r$sensitivity_assumption, fixed = TRUE))
})

test_that("delta_le: positive = loss; implausible or negative values are accepted but warned about", {
  expect_warning(expected_life_loss(anchor_state_fl, "2026-12", delta_le = 50), "far outside", fixed = TRUE)
  expect_warning(expected_life_loss(anchor_state_fl, "2026-12", delta_le = -1), "GAIN", fixed = TRUE)
  r <- expect_silent(expected_life_loss(anchor_state_fl, "2026-12", delta_le = 1))
  expect_equal(r$le_loss_years, 1)
  expect_match(r$sensitivity_assumption, "delta_le = 0.7 to 2.7", fixed = TRUE)
  expect_false(grepl("LE -0.7", r$sensitivity_assumption, fixed = TRUE))
})

test_that("life_expectancy_trend: the state change moves opposite to the death-rate change", {
  r <- life_expectancy_trend("MS", "qoq", quarter = "2024Q1")
  expect_gt(r$rate_change_per_100k, 0)
  expect_lt(r$e0_change_years, 0)
  expect_equal(r$e0_synth_diff_years, r$e0_synth_to - r$e0_synth_from)
  expect_match(r$notes, "national anchor changes", fixed = TRUE)
  q <- life_expectancy_trend(anchor_state_fl, "qoq")
  expect_equal(lengths(regmatches(q$notes, gregexpr("outside D2 anchor table", q$notes))), 1L)
  expect_error(life_expectancy_trend(anchor_state_fl, "mom"), "quarterly", fixed = TRUE)
})

test_that("bill evidence far from the state price is flagged in notes", {
  hi <- my_electricity("HI", time = "2026-12", bill = 180, usage = 1200)
  expect_match(hi$notes, "sd away from the state forecast", fixed = TRUE)
  fl <- my_electricity(anchor_state_fl, time = "2026-12", bill = 180, usage = 1200)
  expect_false(grepl("sd away", fl$notes, fixed = TRUE))
  ob <- my_electricity("HI", time = "2026-07", bill = 180, usage = 1200)
  expect_match(ob$notes, "within-state sd", fixed = TRUE)
})

test_that("notes never end with a dangling separator", {
  r <- expected_life_loss(anchor_state_fl, "2026-07")
  expect_false(grepl("\\|\\s*$", r$notes))
})

test_that("error messages name the right argument and point somewhere useful", {
  expect_error(price_features(anchor_state_fl, period = c("2026-06", "2026-07")), "period expects", fixed = TRUE)
  expect_error(life_expectancy("32601"), "its data are state-level", fixed = TRUE)
  expect_error(expected_life_loss(anchor_state_fl, "2027-01"), "price_features()", fixed = TRUE)
  expect_error(electricity_price(anchor_state_fl, year = 2022), "price_features()", fixed = TRUE)
  expect_error(lag_matrix(character(0)), "states is empty", fixed = TRUE)
  expect_error(lag_matrix(anchor_state_fl, lags = integer(0)), "at least one", fixed = TRUE)
  expect_error(health_measure("32601", measure = character(0)), "measure is empty", fixed = TRUE)
})

test_that("round 3: annual vs monthly direction, case-insensitive periods, friendlier windows", {
  ma <- electricity_price_trend("MA", "yoy")
  r25 <- ma[ma$year == 2025, ]
  expect_lt(r25$pct_of_prior, 0)
  expect_gt(r25$monthly_avg_pct_of_prior, 0)
  expect_match(r25$note, "disagree on direction", fixed = TRUE)
  expect_equal(nrow(electricity_price_trend(anchor_state_fl, "MOM")), 42L)
  expect_equal(life_expectancy_trend(anchor_state_fl, "QoQ")$period, "qoq")
  expect_equal(nrow(electricity_price(anchor_state_fl, period = "MOM")), 43L)
  expect_error(electricity_price(anchor_state_fl, year = 2022), 'period = "2022-01")$annual_price', fixed = TRUE)
  expect_error(life_expectancy_trend(anchor_state_fl, "qoq", quarter = "2023Q1"),
               "earliest usable quarter is 2023Q2", fixed = TRUE)
  expect_error(life_expectancy_trend(anchor_state_fl, "yoy", quarter = "2023Q4"),
               "earliest usable quarter is 2024Q1", fixed = TRUE)
})

test_that("round 3: forecast bias is disclosed and silly inputs are caught", {
  b <- my_electricity(anchor_state_fl, time = "2026-09")$price_interval_basis
  expect_match(b, "run LOW in calibration", fixed = TRUE)
  expect_error(expected_life_loss(anchor_state_fl, "2026-12", delta_le = 80), "not possible", fixed = TRUE)
  expect_warning(my_electricity(anchor_state_fl, bill = 1e6, time = "2026-08"), "typical household use", fixed = TRUE)
  expect_silent(my_electricity(anchor_state_fl, bill = 180, time = "2026-08"))
  expect_warning(lag_matrix(anchor_state_fl, lags = c(0, 200)), "200 reach before", fixed = TRUE)
  expect_silent(lag_matrix(anchor_state_fl))
})

test_that("the utility range ignores retailers with a handful of customers", {
  mi <- electricity_price("MI", year = 2023)
  expect_lt(mi$price_max, 100)          # was 285 c/kWh from a 1-customer entity
  nm <- electricity_price("NM", year = 2024)
  expect_gt(nm$price_min, 5)            # was 2.69 c/kWh from a 3-customer entity
  expect_lt(nm$n_utility_in_range, nm$n_utility)
  for (st in c("FL", "DC", "AK", "HI", "TX")) {
    r <- electricity_price(st, year = 2024)
    expect_true(r$price_min <= r$price && r$price <= r$price_max, label = st)
  }
})
