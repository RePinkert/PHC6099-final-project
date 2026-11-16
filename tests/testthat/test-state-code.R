# test-state-code.R —— 州代码入口的契约（W0）
# 三层钉死：①可接受形式的归一化；②ZIP 形状必须指名拒绝并指路；③未知/歧义输入不静默改写。

test_that("state codes normalise from USPS codes and full names", {
  expect_equal(lifewatt:::.state_code("FL"), "FL")
  expect_equal(lifewatt:::.state_code("fl"), "FL")
  expect_equal(lifewatt:::.state_code(" fl "), "FL")
  expect_equal(lifewatt:::.state_code("Florida"), "FL")
  expect_equal(lifewatt:::.state_code("district of columbia"), "DC")
  expect_equal(lifewatt:::.state_code("DC"), "DC")
  ## 51 个实体全部往返一致
  for (s in c(datasets::state.abb, "DC")) {
    expect_equal(lifewatt:::.state_code(s), s, label = s)
    if (s != "DC") {
      expect_equal(lifewatt:::.state_code(datasets::state.name[match(s, datasets::state.abb)]), s)
    }
  }
})

test_that("a ZIP handed to a state argument is refused by name, and points at zip_to_state()", {
  err <- tryCatch(lifewatt:::.state_code("32601"), error = function(e) conditionMessage(e))
  expect_match(err, "looks like a ZIP code", fixed = TRUE)
  expect_match(err, "zip_to_state", fixed = TRUE)
  expect_match(err, "health_measure", fixed = TRUE)
  ## 数值型 ZIP 走同一条路（不能被 as.character 静默变成别的东西）
  expect_error(lifewatt:::.state_code(32601), "looks like a ZIP code", fixed = TRUE)
  ## ZIP+4 与 9 位形式同样指名拒绝
  expect_error(lifewatt:::.state_code("32601-4401"), "looks like a ZIP code", fixed = TRUE)
  expect_error(lifewatt:::.state_code("326014401"), "looks like a ZIP code", fixed = TRUE)
})

test_that("malformed and unknown state input fails loudly", {
  expect_error(lifewatt:::.state_code(NA), "NA", fixed = TRUE)
  expect_error(lifewatt:::.state_code(NULL), "exactly one value", fixed = TRUE)
  expect_error(lifewatt:::.state_code(c("FL", "GA")), "exactly one value", fixed = TRUE)
  expect_error(lifewatt:::.state_code(""), "empty", fixed = TRUE)
  expect_error(lifewatt:::.state_code("ZZ"), "Unknown state", fixed = TRUE)
  expect_error(lifewatt:::.state_code("Florid"), "Unknown state", fixed = TRUE)
  expect_error(lifewatt:::.state_code("FLA"), "Unknown state", fixed = TRUE)
})
