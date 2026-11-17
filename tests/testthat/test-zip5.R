# test-zip5.R —— ZIP 归一化契约（2026-11-17 起包内只剩这一件事）
# zip_to_state() 与 A2 OpenEI 映射（openei_zip2state_slim.csv.gz）一并删除：
# 价格/寿命层是州级的，受访者知道自己的州，所以 ZIP->州 映射没有用户价值。
# health_measure() 仍按 ZCTA 查 CDC PLACES，因此只剩"把用户写的 ZIP 归一化成 5 位"。

test_that("zip input is normalized (numeric, ZIP+4, 9-digit) then strictly validated", {
  expect_equal(lifewatt:::.zip5(32601), "32601")
  expect_equal(lifewatt:::.zip5("32601-4401"), "32601")
  expect_equal(lifewatt:::.zip5("326014401"), "32601")
  expect_equal(lifewatt:::.zip5(" 32601 "), "32601")
  expect_equal(lifewatt:::.zip5("01002"), "01002")
  expect_error(lifewatt:::.zip5("1002"), "leading zeros required", fixed = TRUE)
  expect_error(lifewatt:::.zip5("3260"), "Invalid zip", fixed = TRUE)
})

test_that("no ZIP-to-state mapping ships any more", {
  expect_false("zip_to_state" %in% getNamespaceExports("lifewatt"))
})
