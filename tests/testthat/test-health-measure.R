# Offline tests use a saved copy of the CDC PLACES response for ZIP 32601
# (tests/testthat/fixtures/places_32601.csv, downloaded 2026-10-16).

fake_fetch <- function(zip5) {
  utils::read.csv(test_path("fixtures", "places_32601.csv"), colClasses = "character")
}

test_that("returns only BRFSS 2023 measures with provenance", {
  local_mocked_bindings(.places_fetch = fake_fetch)
  r <- health_measure("32601")
  expect_equal(nrow(r), 28L)
  expect_true(all(r$brfss_year == 2023L))
  expect_false(any(c("SLEEP", "DENTAL", "COLON_SCREEN", "MAMMOUSE", "TEETHLOST") %in% r$measure_id))
  expect_equal(unique(r$level), "zcta")
  expect_provenance_cols(r)
  # PLACES 2025 is a published cross-section, so nothing is provisional
  expect_false(any(r$provisional))
})

test_that("diabetes value matches the CDC website (anchor: 32601 = 7.7%)", {
  local_mocked_bindings(.places_fetch = fake_fetch)
  r <- health_measure(32601, measure = "diabetes")
  expect_equal(nrow(r), 1L)
  expect_equal(r$value, 7.7)
  expect_equal(r$low_ci, 6.8)
  expect_equal(r$high_ci, 8.7)
})

test_that("several measures can be requested at once", {
  local_mocked_bindings(.places_fetch = fake_fetch)
  r <- health_measure("32601", measure = c("DIABETES", "BPHIGH"))
  expect_setequal(r$measure_id, c("DIABETES", "BPHIGH"))
})

test_that("unknown or excluded measures fail loudly", {
  local_mocked_bindings(.places_fetch = fake_fetch)
  expect_error(health_measure("32601", measure = "NOPE"), "not available", fixed = TRUE)
  expect_error(health_measure("32601", measure = "SLEEP"), "not available", fixed = TRUE)
})

test_that("schema drift fails loudly instead of blaming the ZIP", {
  local_mocked_bindings(.places_fetch = function(zip5) data.frame(foo = "bar"))
  expect_error(health_measure("32601"), "schema unexpected", fixed = TRUE)
})

test_that("age-adjusted rows are dropped (crude-only contract)", {
  local_mocked_bindings(.places_fetch = function(zip5) {
    d <- read_places_fixture(zip5)
    adj <- d[1:3, ]
    adj$data_value_type <- "Age-adjusted prevalence"
    rbind(d, adj)
  })
  r <- health_measure("32601")
  expect_true(all(r$value_type == "Crude prevalence"))
  expect_equal(anyDuplicated(r$measure_id), 0L)
  expect_equal(nrow(r), 28L)
})

test_that("other-vintage-only responses are distinguished from no-coverage", {
  local_mocked_bindings(.places_fetch = function(zip5) {
    d <- read_places_fixture(zip5)
    d[d$year == "2022", , drop = FALSE]
  })
  expect_error(health_measure("32601"), "other vintages", fixed = TRUE)
})

test_that("ZIPs without PLACES data and malformed ZIPs fail loudly", {
  local_mocked_bindings(.places_fetch = function(zip5) fake_fetch(zip5)[0, ])
  expect_error(health_measure("32601"), "No CDC PLACES estimates", fixed = TRUE)
  expect_error(health_measure("abcde"), "Invalid zip", fixed = TRUE)
})

test_that("live download from data.cdc.gov works", {
  skip_on_cran()
  skip_if_offline("data.cdc.gov")
  r <- health_measure("32601", measure = "DIABETES")
  expect_equal(nrow(r), 1L)
  expect_true(is.numeric(r$value) && r$value > 0 && r$value < 100)
})
