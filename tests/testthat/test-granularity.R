test_that("multi-utility weighting only selects the state, and the note says so", {
  zs <- lifewatt:::.zip_state(anchor_zip_multi)
  expect_match(zs$note, "selects the state only", fixed = TRUE)
  expect_match(zs$note, "not a zip-weighted blend", fixed = TRUE)
  # customers vs equal weighting resolves the same state: the weights never reach the state value
  map <- lifewatt:::.open_map()
  n_by_zip <- tapply(map$eiaid, map$zip, function(e) length(unique(e)))
  multi <- names(n_by_zip)[n_by_zip > 1L]
  set.seed(6099)
  for (z in sample(multi, 50L)) {
    expect_equal(lifewatt:::.zip_state(z)$state, lifewatt:::.zip_state(z, "equal")$state, label = z)
  }
  r <- lifewatt:::.price_at(anchor_zip_fl, "2026-07")
  d <- lifewatt:::.monthly_cache()
  expect_equal(r$price, d$price[d$state == "FL" & d$period == "2026-07"])
})

test_that("annual multi-utility price reports the utility range, not just a point", {
  r <- lifewatt:::.zip_annual_price(anchor_zip_fl, 2024)
  slim <- lifewatt:::.annual_slim()
  s <- slim[slim$year == 2024 & slim$state == "FL" & slim$eiaid %in% c("3757", "6909"), ]
  expect_equal(r$price_min, min(s$price))
  expect_equal(r$price_max, max(s$price))
  expect_true(r$price_min <= r$price && r$price <= r$price_max)
  expect_match(r$weight_scheme, "not the within-zip share", fixed = TRUE)
  expect_match(r$confidence_tier, "^B:")
  single <- lifewatt:::.zip_annual_price(anchor_zip_single, 2024)
  expect_equal(single$price_min, single$price_max)
  expect_equal(single$price, single$price_min)
  expect_match(single$confidence_tier, "^A:")
})

test_that("within-state spread equals an independent customer-weighted sd", {
  slim <- lifewatt:::.annual_slim()
  s <- slim[slim$year == 2024 & slim$state == "FL" & is.finite(slim$price) & slim$price > 0 &
              is.finite(slim$cus) & slim$cus > 0, ]
  mu <- weighted.mean(s$price, s$cus)
  want <- sqrt(sum(s$cus * (s$price - mu)^2) / sum(s$cus))
  got <- lifewatt:::.within_state_spread("FL", 2024)
  expect_equal(got$sd, want, tolerance = 1e-12)
  expect_equal(got$year, 2024L)
  expect_gt(got$sd, 0)
  # years beyond the final releases fall back to the latest one
  expect_equal(lifewatt:::.within_state_spread("FL", 2026)$year, max(lifewatt:::.annual_years()))
  expect_equal(lifewatt:::.within_state_spread("FL", 2000)$year, min(lifewatt:::.annual_years()))
})

test_that("state-level rows carry the spread and the right tier", {
  obs <- lifewatt:::.price_at(anchor_zip_fl, "2026-07")
  pred <- lifewatt:::.price_at(anchor_zip_fl, "2026-12")
  latest <- max(lifewatt:::.annual_years())
  expect_equal(obs$within_state_sd, lifewatt:::.within_state_spread("FL", 2026)$sd)
  expect_equal(pred$within_state_sd, lifewatt:::.within_state_spread("FL", latest)$sd)
  expect_match(obs$confidence_tier, "^B:")
  expect_match(pred$confidence_tier, "^C:")
  m <- electricity_price(anchor_zip_fl, period = "mom")
  expect_true(all(is.finite(m$within_state_sd)))
  expect_true(all(grepl("^B:", m$confidence_tier)))
  expect_match(expected_life_loss(anchor_zip_fl, "2026-07")$confidence_tier, "^B:")
  expect_match(my_electricity(anchor_zip_fl, time = "2026-12")$confidence_tier, "^C:")
})

test_that("modeled and synthetic outputs are tier C", {
  expect_match(life_expectancy(anchor_zip_fl)$confidence_tier, "^C:")
  expect_match(life_expectancy_trend(anchor_zip_fl, "yoy")$confidence_tier, "^C:")
  expect_true(all(grepl("^B:", electricity_price_trend(anchor_zip_fl, "mom")$confidence_tier)))
  expect_true(all(grepl("^B:", electricity_price_trend(anchor_zip_fl, "yoy")$confidence_tier)))
})

test_that("PLACES rows are tier C (model-based small-area estimates)", {
  local_mocked_bindings(.places_fetch = read_places_fixture)
  h <- health_measure(anchor_zip_fl, measure = "DIABETES")
  expect_match(h$confidence_tier, "^C:")
})
