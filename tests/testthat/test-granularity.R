# test-granularity.R —— 颗粒度与置信度声明层（W0 起：州是唯一颗粒度）
# 钉住：①州是唯一颗粒度（ZIP 不再参与任何数值） ②州年价带 min/max 且自洽 ③within_state_sd 是独立可复算的
# ④tier 只按"观测 / 模型"分，不再有 ZIP 级 A

test_that("the state value is the whole answer, and no ZIP is weighted anywhere", {
  ## 2026-11-17 起包内没有 ZIP->州 映射：同州不同 ZIP 不再产生任何差异
  a <- lifewatt:::.price_at(anchor_state_fl, "2026-07")
  b <- lifewatt:::.price_at("fl", "2026-07")
  expect_identical(a, b)
  d <- lifewatt:::.monthly_cache()
  expect_equal(a$price, d$price[d$state == "FL" & d$period == "2026-07"])
})

test_that("annual state price reports the utility range, not just a point", {
  r <- lifewatt:::.state_annual_price("FL", 2024)
  s <- lifewatt:::.state_utility_rows("FL", 2024)
  expect_equal(r$price_min, min(s$price))
  expect_equal(r$price_max, max(s$price))
  expect_true(r$price_min < r$price_max)
  expect_true(r$price_min <= r$price && r$price <= r$price_max)
  expect_match(r$confidence_tier, "^B:")
})

test_that("within-state spread equals an independent customer-weighted sd", {
  slim <- lifewatt:::.annual_slim()
  s <- slim[slim$year == 2024 & slim$state == "FL" & slim$eiaid != "99999" &
              is.finite(slim$price) & slim$price > 0 & is.finite(slim$cus) & slim$cus > 0, ]
  mu <- stats::weighted.mean(s$price, s$cus)
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
  obs <- lifewatt:::.price_at(anchor_state_fl, "2026-07")
  pred <- lifewatt:::.price_at(anchor_state_fl, "2026-12")
  latest <- max(lifewatt:::.annual_years())
  expect_equal(obs$within_state_sd, lifewatt:::.within_state_spread("FL", 2026)$sd)
  expect_equal(pred$within_state_sd, lifewatt:::.within_state_spread("FL", latest)$sd)
  expect_match(obs$confidence_tier, "^B:")
  expect_match(pred$confidence_tier, "^C:")
  m <- electricity_price(anchor_state_fl, period = "mom")
  expect_true(all(is.finite(m$within_state_sd)))
  expect_true(all(m$n_utility > 0L))
  expect_true(all(grepl("^B:", m$confidence_tier)))
  expect_match(expected_life_loss(anchor_state_fl, "2026-07")$confidence_tier, "^B:")
  expect_match(my_electricity(anchor_state_fl, time = "2026-12")$confidence_tier, "^C:")
})

test_that("modeled and synthetic outputs are tier C", {
  expect_match(life_expectancy(anchor_state_fl)$confidence_tier, "^C:")
  expect_match(life_expectancy_trend(anchor_state_fl, "yoy")$confidence_tier, "^C:")
  expect_true(all(grepl("^B:", electricity_price_trend(anchor_state_fl, "mom")$confidence_tier)))
  expect_true(all(grepl("^B:", electricity_price_trend(anchor_state_fl, "yoy")$confidence_tier)))
})

test_that("PLACES rows are tier C (model-based small-area estimates)", {
  local_mocked_bindings(.places_fetch = read_places_fixture)
  h <- health_measure(anchor_zip_fl, measure = "DIABETES")
  expect_match(h$confidence_tier, "^C:")
})

test_that("within-state spread ignores EIA state-adjustment pseudo-utilities", {
  slim <- lifewatt:::.annual_slim()
  adj <- slim[slim$eiaid == "99999" & slim$year == 2023 & slim$state == "AL", ]
  expect_equal(nrow(adj), 1L)
  expect_gt(adj$cus, 0)  # positive customers, so only the eiaid filter keeps it out
  s <- slim[slim$year == 2023 & slim$state == "AL" & slim$eiaid != "99999" & slim$cus > 0, ]
  mu <- stats::weighted.mean(s$price, s$cus)
  want <- sqrt(sum(s$cus * (s$price - mu)^2) / sum(s$cus))
  expect_equal(lifewatt:::.within_state_spread("AL", 2023)$sd, want, tolerance = 1e-12)
})
