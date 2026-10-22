test_that("single-utility zip resolves deterministically (anchor: 01002, MA)", {
  r <- lifewatt:::.zip_state("01002")
  expect_equal(r$state, "MA")
  expect_equal(r$n_utility, 1L)
  expect_equal(r$state_share, 1)
  expect_true(startsWith(r$weight_scheme, "customers"))
  expect_equal(r$mapping_vintage, "2024")
  expect_equal(r$utilities$utility_name, "Massachusetts Electric Co")
})

test_that("multi-utility zip reports all entities (anchor: 32601, 28657)", {
  r <- lifewatt:::.zip_state("32601")
  expect_equal(r$state, "FL")
  expect_equal(r$n_utility, 2L)
  expect_true(any(grepl("Gainesville Regional", r$utilities$utility_name)))
  r2 <- lifewatt:::.zip_state("28657")
  expect_equal(r2$state, "NC")
  expect_equal(r2$n_utility, 7L)
  expect_equal(r2$state_share, 1)
  expect_true(grepl("customers", r2$note))
})

test_that("zip input is normalized (numeric, ZIP+4, 9-digit) then strictly validated", {
  expect_equal(lifewatt:::.zip5(32601), "32601")
  expect_equal(lifewatt:::.zip5("32601-4401"), "32601")
  expect_equal(lifewatt:::.zip5("326014401"), "32601")
  expect_equal(lifewatt:::.zip5(" 32601 "), "32601")
  expect_equal(lifewatt:::.zip5("01002"), "01002")
  expect_error(lifewatt:::.zip5("1002"), "leading zeros required", fixed = TRUE)
  expect_error(lifewatt:::.zip5("3260"), "Invalid zip", fixed = TRUE)
})

test_that("unknown and malformed zips fail loudly", {
  expect_error(lifewatt:::.zip_state("99999"), "No electric utility record", fixed = TRUE)
  expect_error(lifewatt:::.zip_state("abcde"), "Invalid zip", fixed = TRUE)
  expect_error(lifewatt:::.zip_state("12"), "Invalid zip", fixed = TRUE)
  expect_error(lifewatt:::.zip_state("1234567"), "Invalid zip", fixed = TRUE)
})
