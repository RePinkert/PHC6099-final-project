# test-c1-layer.R —— C1 (Form EIA-112) 机制列契约（exp#39）
# 锚值来自 inst/extdata/eia112_state_month_slim.csv.gz（State Total 口径）；
# 源文件 data-raw/eia112/112_electric_utility_2024.xlsx 由 assemble_112_slim.R 一次性组装。

test_that("C1 slim coverage: 51 states x 12 months of 2024", {
  d <- lifewatt:::.c1_cache()
  expect_equal(nrow(d), 612L)
  expect_equal(length(unique(d$state)), 51L)
  expect_true(all(d$period >= "2024-01" & d$period <= "2024-12"))
  expect_false(anyNA(d$disconnections_per_1k))
  expect_true(all(grepl("Form EIA-112 State Total", d$source)))
})

test_that("C1 state-month anchors (State Total incl. State Adjustment)", {
  a <- lifewatt:::.c1_at("AK", "2024-01")
  expect_equal(a$c1_disconnections_per_1k, 706.1 / 298371 * 1000, tolerance = 1e-9)
  expect_equal(a$c1_res_customers, 298371)
  fl <- lifewatt:::.c1_at("FL", "2024-06")
  expect_equal(fl$c1_disconnections_per_1k, 16.54101247, tolerance = 1e-6)
  expect_equal(fl$c1_final_notices_per_1k, 87.10294454, tolerance = 1e-6)
  nc <- lifewatt:::.c1_at("NC", "2024-12")
  expect_equal(nc$c1_disconnections_per_1k, 5.345701795, tolerance = 1e-6)
})

test_that("C1 outside 2024 returns NA row + honest note (survey not extended)", {
  a <- lifewatt:::.c1_at("FL", "2026-07")
  expect_true(is.na(a$c1_disconnections_per_1k))
  expect_true(is.na(a$c1_source))
  n <- lifewatt:::.c1_note("FL", "2026-07")
  expect_match(n, "EIA-112 covers 2024 only", fixed = TRUE)
  expect_match(n, "not extended", fixed = TRUE)
})

test_that("expected_life_loss wires C1 columns in-window (observed 2024)", {
  r <- expected_life_loss("32601", "2024-06")
  expect_equal(r$c1_disconnections_per_1k, 16.54101247, tolerance = 1e-6)
  expect_equal(r$c1_final_notices_per_1k, 87.10294454, tolerance = 1e-6)
  expect_true(grepl("Form EIA-112 State Total", r$c1_source))
  expect_match(r$notes, "C1 mechanism (Form EIA-112 State Total, 2024)", fixed = TRUE)
  expect_provenance_cols(r)
})

test_that("expected_life_loss wires C1 NA outside 2024 with note", {
  r <- expected_life_loss("32601", "2026-07")
  expect_true(is.na(r$c1_disconnections_per_1k))
  expect_match(r$notes, "C1 mechanism not available at 2026-07", fixed = TRUE)
})

test_that("my_electricity mirrors the C1 wiring (energy-side sibling)", {
  r <- my_electricity("32601", bill = 150, time = "2024-06")
  expect_equal(r$c1_disconnections_per_1k, 16.54101247, tolerance = 1e-6)
  expect_true(grepl("Form EIA-112 State Total", r$c1_source))
  expect_false(grepl("LE|life", r$notes))
  r2 <- my_electricity("32601", time = "2026-12")
  expect_true(is.na(r2$c1_disconnections_per_1k))
  expect_match(r2$notes, "C1 mechanism not available at 2026-12", fixed = TRUE)
})
