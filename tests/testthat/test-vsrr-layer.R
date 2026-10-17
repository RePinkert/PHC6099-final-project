# test-vsrr-layer.R —— VSRR（D1b 程序化替代源）数据层契约（exp#41）
# 来源：NCHS VSRR Quarterly provisional estimates（data.cdc.gov 489q-934x，USGOV_WORKS）。
# 锚值来自源 CSV 抽验；改 extdata 须同步刷新。

test_that("VSRR state slim: 51 states + US row x 11 quarters x 2 period x 2 rate types", {
  s <- lifewatt:::.vsrr_state_cache()
  expect_equal(nrow(s), 2288L)
  expect_equal(length(unique(s$state)), 52L)
  expect_true("US" %in% s$state)  # national row = denominator for the synthesis index m
  expect_true(all(sort(unique(s$quarter)) ==
                    sprintf("%dQ%d", rep(2023:2025, each = 4), rep(1:4, 3))[1:11]))
  expect_true(all(s$provisional))
  expect_true(all(grepl("489q-934x", s$source)))
})

test_that("VSRR state rate anchors (source spot-checks)", {
  fl <- lifewatt:::.vsrr_state_rate("FL", "2023Q1", period_type = "3m", rate_type = "age_adjusted")
  expect_equal(fl$rate_per_100k, 705.9, tolerance = 1e-9)
  nat <- lifewatt:::.vsrr_state_rate("FL", "2023Q1", period_type = "3m", rate_type = "crude")
  expect_gt(nat$rate_per_100k, fl$rate_per_100k)  # crude > age-adjusted for FL 2023Q1
  r12 <- lifewatt:::.vsrr_state_rate("WY", "2025Q3", period_type = "12m", rate_type = "age_adjusted")
  expect_true(is.finite(r12$rate_per_100k))
})

test_that("VSRR national age pattern: 10 bands, ordered, declared-assumption note", {
  a <- lifewatt:::.vsrr_age_pattern("2023Q1", period_type = "12m")
  expect_equal(nrow(a), 10L)
  expect_equal(a$age_band, c("1-4", "5-14", "15-24", "25-34", "35-44", "45-54",
                             "55-64", "65-74", "75-84", "85+"))
  expect_equal(a$rate_per_100k[a$age_band == "1-4"], 28.4, tolerance = 1e-9)
  expect_true(all(grepl("DECLARED assumption", a$coverage_note)))
  expect_true(all(a$provisional))
})

test_that("VSRR honest errors outside the window / unknown state", {
  expect_error(lifewatt:::.vsrr_state_rate("FL", "2026Q1"), "window 2023Q1..2025Q3", fixed = TRUE)
  expect_error(lifewatt:::.vsrr_state_rate("XX", "2023Q1"), "window 2023Q1..2025Q3", fixed = TRUE)
  expect_error(lifewatt:::.vsrr_age_pattern("2026Q1"), "incomplete", fixed = TRUE)
})
