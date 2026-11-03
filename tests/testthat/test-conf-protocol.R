# test-conf-protocol.R —— 置信度协议与评分库的硬约束（钉住"不嵌套"这条纪律）
#
# 这些测试是本次改造的护栏：任何让"同一批月份既用来估参数又用来量覆盖"的改动都会在这里失败。
# 运行：Rscript -e 'testthat::test_file("tests/testthat/test-conf-protocol.R")'

library(testthat)

## 协议/区间/重放器都是包内函数（内部，未导出）：在 test_check() 下直接可见。
## 单独跑本文件时（testthat::test_file）用 lifewatt 的命名空间补上。
if (!exists("conf_protocol")) {
  ns <- asNamespace("lifewatt")
  for (nm in ls(ns, all.names = TRUE)) {
    if (grepl("^conf_", nm)) assign(nm, get(nm, ns))
  }
}

test_that("协议角色两两不相交，且四年窗口是四年", {
  p <- conf_protocol()
  sp <- p$spans
  keys <- names(sp)
  for (i in seq_along(sp)) for (j in seq_along(sp)) if (i < j) {
    expect_false(sp[[i]][2] >= sp[[j]][1] && sp[[j]][2] >= sp[[i]][1])
  }
  yrs <- as.integer(substr(p$w4, 1, 4))
  expect_equal(yrs[2] - yrs[1] + 1, 4L)
})

test_that("角色重叠会被直接拒绝（构造一个嵌套划分）", {
  bad <- list(fit = c("2010-01", "2019-12"), es = c("2020-01", "2021-12"),
              cal = c("2021-06", "2024-12"), eval = c("2025-01", "2025-12"))
  expect_error(conf_protocol(bad), "nested data use")
})

test_that("前向链每一折的参考窗口都严格早于其评估窗口", {
  p <- conf_protocol()
  for (f in p$folds) {
    expect_true(f$ref_to < f$eval_from)
    expect_true(f$eval_from <= f$eval_to)
  }
  ## 折的评估年份必须递增且互不重叠
  ey <- vapply(p$folds, function(f) f$year, integer(1))
  expect_equal(ey, sort(ey))
  expect_equal(anyDuplicated(ey), 0L)
})

test_that("运行期嵌套核查会抓到跨角色使用", {
  p <- conf_protocol()
  ok_usage <- data.frame(target_month = c("2015-01", "2018-01"),
                         used_for = c("fit", "fit"))
  expect_true(conf_assert_no_nesting(p, ok_usage))
  bad_usage <- data.frame(target_month = c("2023-05"), used_for = c("fit"))
  expect_error(conf_assert_no_nesting(p, bad_usage), "nested data use")
})

test_that("conformal 有限样本秩：位置正确、样本不足时返回 NA", {
  expect_equal(conf_conformal_rank(19, 0.95), 19L)
  expect_equal(conf_conformal_rank(100, 0.95), 96L)
  expect_true(is.infinite(conf_conformal_rank(10, 0.95)))
  x <- 1:20
  expect_equal(conf_finite_quantile(x, 0.95), 20)      # rank = ceil(21*0.95) = 20 -> 第 20 个顺序统计量
  expect_true(is.na(conf_finite_quantile(1:5, 0.95)))   # n 太小 -> 不给数字
})

test_that("Winkler 评分：区间内等于宽度，界外按 2/alpha 罚", {
  lo <- 0; hi <- 10; alpha <- 0.1
  expect_equal(conf_wis(5, lo, hi, alpha), 10)
  expect_equal(conf_wis(-5, lo, hi, alpha), 10 + (2 / alpha) * 5)
  expect_equal(conf_wis(15, lo, hi, alpha), 10 + (2 / alpha) * 5)
})

test_that("conformal 区间在可交换样本上覆盖不低于名义值（模拟检验）", {
  set.seed(1)
  n <- 400
  x <- rnorm(n)                      # 参考集：相对残差
  y <- rnorm(200)                    # 评价集：相对残差（真值 = 1 + r，pred = 1）
  pars <- conf_fit_iv(data.frame(h = 1L, rel = x, true = x, pred = 1,
                                 state = "AL", scale_vol12 = 1),
                      "conformal_asym", nominal = 0.9)
  ev <- data.frame(h = 1L, rel = y, true = 1 + y, pred = 1, state = "AL", scale_vol12 = 1)
  ev2 <- conf_apply_iv(pars, ev)
  expect_gte(conf_coverage(ev2$true, ev2$lo, ev2$hi), 0.85)
})

test_that("随包 v3 权重的重放能复现其分位数（口径一致性）", {
  skip_on_cran()
  r <- conf_check_parity(".")
  expect_true(r$ok)
  expect_lt(r$drift, 1e-6)
  ## 随包校准窗的 h=1 只有 2 个目标月（102 个残差）——四年窗口的意义正在于此
  expect_equal(r$rep_iv$n[r$rep_iv$h == 1], 102L)
})
