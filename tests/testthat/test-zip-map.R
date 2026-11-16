# test-zip-map.R —— ZIP → 州 的查询契约（W0）
# 不再是"ZIP 级加权"：ZIP 只用来选州。这里钉住 ①州解析的确定性 ②返回形状 ③坏输入的指名拒绝。

test_that("zip_to_state resolves the state and reports the mapping vintage", {
  r <- zip_to_state("32601")
  expect_equal(names(r), c("zip", "state", "mapping_vintage", "n_utility"))
  expect_equal(r$zip, "32601")
  expect_equal(r$state, "FL")
  expect_equal(r$mapping_vintage, "2024")
  expect_equal(nrow(r), 1L)
})

test_that("every ZIP in a state resolves to the same state (anchor set)", {
  expect_equal(zip_to_state("01002")$state, "MA")
  expect_equal(zip_to_state("28657")$state, "NC")
  expect_equal(zip_to_state("99501")$state, "AK")
  ## 多 utility ZIP 与单 utility ZIP 走同一条路：只有州是产物
  expect_equal(lifewatt:::.zip_resolve("01002")$n_utility, 1L)
  expect_equal(lifewatt:::.zip_resolve("32601")$n_utility, 2L)
  expect_equal(lifewatt:::.zip_resolve("28657")$n_utility, 7L)
})

test_that("zip input is normalized (numeric, ZIP+4, 9-digit) then strictly validated", {
  expect_equal(lifewatt:::.zip5(32601), "32601")
  expect_equal(lifewatt:::.zip5("32601-4401"), "32601")
  expect_equal(lifewatt:::.zip5("326014401"), "32601")
  expect_equal(lifewatt:::.zip5(" 32601 "), "32601")
  expect_equal(lifewatt:::.zip5("01002"), "01002")
  expect_error(lifewatt:::.zip5("1002"), "leading zeros required", fixed = TRUE)
  expect_error(lifewatt:::.zip5("3260"), "Invalid zip", fixed = TRUE)
  ## 归一化在 zip_to_state 上也成立
  expect_equal(zip_to_state("32601-4401")$zip, "32601")
})

test_that("unknown and malformed zips fail loudly", {
  expect_error(zip_to_state("99999"), "No electric utility record", fixed = TRUE)
  expect_error(zip_to_state("abcde"), "Invalid zip", fixed = TRUE)
  expect_error(zip_to_state("12"), "Invalid zip", fixed = TRUE)
  expect_error(zip_to_state("1234567"), "Invalid zip", fixed = TRUE)
  expect_error(zip_to_state(NA), "Invalid zip", fixed = TRUE)
})

test_that("a state code handed to zip_to_state is refused (the two entry points are not interchangeable)", {
  expect_error(zip_to_state("FL"), "Invalid zip", fixed = TRUE)
})
