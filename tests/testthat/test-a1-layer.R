test_that("A1 annual price: customer-weighted blend (anchor: 32601 @2024)", {
  r <- lifewatt:::.zip_annual_price("32601", 2024)
  expect_equal(r$state, "FL")
  expect_equal(r$n_mapped, 2L)
  expect_equal(r$n_priced, 2L)
  slim <- lifewatt:::.annual_slim()
  s <- slim[slim$year == 2024 & slim$state == "FL" & slim$eiaid %in% c("3757", "6909"), ]
  expect_equal(r$price, weighted.mean(s$price, s$cus), tolerance = 1e-9)
  expect_equal(r$regime, "observed")
  expect_false(r$provisional)
  expect_equal(r$mapping_vintage, "2024")
  expect_equal(r$equal_fallbacks, 0L)
})

test_that("A1 coverage columns expose missing utilities (anchor: 28657 @2024)", {
  r <- lifewatt:::.zip_annual_price("28657", 2024)
  expect_equal(r$n_mapped, 7L)
  expect_equal(r$n_priced, 6L)
  expect_true(grepl("Tennessee Valley", r$missing_utilities))
  expect_true(r$price > 5 && r$price < 25)
})

test_that("A1 vendor boundary: final years only, 2026 early vintage refused", {
  expect_error(lifewatt:::.zip_annual_price("32601", 2026),
               "2026 early vintage intentionally not vendored", fixed = TRUE)
  expect_error(lifewatt:::.zip_annual_price("32601", 2022), "No vendored EIA-861", fixed = TRUE)
  expect_error(lifewatt:::.zip_annual_price("99999", 2024), "No electric utility record", fixed = TRUE)
})

test_that("zip_state default is customers weighting (exp#36 upgrade)", {
  zs <- lifewatt:::.zip_state("32601")
  expect_equal(zs$state, "FL")
  expect_true(startsWith(zs$weight_scheme, "customers"))
  expect_true(all(zs$utilities$cust_weight > 0))
  expect_equal(zs$state_share, 1)
  ze <- lifewatt:::.zip_state("32601", weights = "equal")
  expect_equal(ze$weight_scheme, "equal")
  expect_error(lifewatt:::.zip_state("32601", weights = "bogus"), "Unknown weight scheme", fixed = TRUE)
})
