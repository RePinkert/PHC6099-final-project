# test-mortality-synth.R —— exp#42 寿命指标合成契约（D1b/D2 敏感度合成 × 率口径 × 早死指标）
# 方法：abridged life table（Preston/Chiang，ax=n/2，85+ e=1/m）；全部假设以 sensitivity_assumption 声明。

test_that("abridged life table sanity: positive, monotone lx, US e1 plausible", {
  age <- lifewatt:::.vsrr_age_pattern("2024Q4", "12m")
  tab <- lifewatt:::.abridged_table(age$rate_per_100k / 1e5)
  expect_equal(nrow(tab), 10L)
  expect_true(all(tab$qx[1:9] > 0 & tab$qx[1:9] < 1))  # closed bands
  expect_equal(tab$qx[10], 1)                            # open interval: all remaining die
  expect_true(all(diff(tab$lx) <= 0))          # lx non-increasing
  expect_gt(tab$ex[1], 70)                       # e1 at age 1 in plausible band
  expect_lt(tab$ex[1], 85)
  expect_gt(tab$ex[10], 3)                       # open-interval e85 = 1/m
})

test_that("L1 self-check: US row m=1 -> delta_e1 = 0 -> e0_synth = D2 anchor exactly", {
  us <- lifewatt:::.le_synth("US", "2024Q4", "12m")
  expect_equal(us$m_index, 1, tolerance = 1e-12)
  expect_equal(us$delta_e1, 0, tolerance = 1e-9)
  expect_equal(us$e0_synth, us$e0_anchor, tolerance = 1e-9)
  expect_equal(us$e0_anchor, 79.0)
  us23 <- lifewatt:::.le_synth("US", "2023Q2", "12m")
  expect_equal(us23$e0_synth, 78.4, tolerance = 1e-9)
})

test_that("synth direction + magnitude anchors (state mortality index drives delta_e1)", {
  fl <- lifewatt:::.le_synth("FL", "2024Q4", "12m")
  expect_lt(fl$m_index, 1)                       # FL age-adjusted mortality below US
  expect_gt(fl$delta_e1, 0)
  expect_equal(fl$e0_synth, fl$e0_anchor + fl$delta_e1, tolerance = 1e-9)
  ms <- lifewatt:::.le_synth("MS", "2024Q4", "12m")
  expect_gt(ms$m_index, 1.2)
  expect_lt(ms$delta_e1, -2)
  expect_lt(ms$e0_synth, fl$e0_synth)
  # 51-state range finite and inside a plausible LE band
  states <- setdiff(unique(lifewatt:::.vsrr_state_cache()$state), "US")
  e0s <- vapply(states, function(s) lifewatt:::.le_synth(s, "2024Q4", "12m")$e0_synth, numeric(1))
  expect_equal(length(e0s), 51L)
  expect_true(all(is.finite(e0s)))
  expect_gt(min(e0s), 70)
  expect_lt(max(e0s), 86)
})

test_that("other longevity indicators (candidate a/c): trend + premature metrics", {
  t1 <- lifewatt:::.mortality_rate_trend("FL", "2023Q1", "2024Q1")
  expect_equal(t1$rate_from, 688.6, tolerance = 1e-9)
  expect_equal(t1$change_per_100k, 669.5 - 688.6, tolerance = 1e-9)
  expect_true(t1$provisional)
  r <- lifewatt:::.mortality_rate("MS", "2024Q4", "3m", "crude")
  expect_true(is.finite(r$rate_per_100k))
  us <- lifewatt:::.le_synth("US", "2024Q4", "12m")
  expect_gt(us$ypll75_per_1k, 1000)
  expect_lt(us$ypll75_per_1k, 10000)
  expect_gt(us$prop_died_before_75, 0.1)
  expect_lt(us$prop_died_before_75, 0.5)
  ms <- lifewatt:::.le_synth("MS", "2024Q4", "12m")
  expect_gt(ms$ypll75_per_1k, us$ypll75_per_1k)   # high-mortality state loses more YPLL
})

test_that("declared assumptions and provenance travel with every synthesis row", {
  fl <- lifewatt:::.le_synth("FL", "2024Q4", "12m")
  expect_match(fl$sensitivity_assumption, "DECLARED assumption", fixed = TRUE)
  expect_match(fl$sensitivity_assumption, "Preston/Chiang", fixed = TRUE)
  expect_match(fl$sensitivity_assumption, "delta_e1 -> delta_e0 portability DECLARED", fixed = TRUE)
  expect_match(fl$source, "489q-934x", fixed = TRUE)
  expect_match(fl$source, "D2 anchor", fixed = TRUE)
  expect_true(fl$provisional)
  # anchor fallback note for 2025 quarters (D2 table ends 2024)
  q25 <- lifewatt:::.le_synth("FL", "2025Q3", "12m")
  expect_equal(q25$e0_anchor_year, 2024L)
  expect_match(q25$notes, "outside D2 anchor table", fixed = TRUE)
})

test_that("honest errors outside VSRR window / unknown state", {
  expect_error(lifewatt:::.le_synth("FL", "2022Q4"), "window 2023Q1..2025Q3", fixed = TRUE)
  expect_error(lifewatt:::.mortality_index("ZZ", "2024Q4"), "window 2023Q1..2025Q3", fixed = TRUE)
})
