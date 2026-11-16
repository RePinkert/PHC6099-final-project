test_that("A1 annual price: population-share blend (anchor: 32601 @2024)", {
  r <- lifewatt:::.zip_annual_price("32601", 2024)
  expect_equal(r$state, "FL")
  expect_equal(r$n_mapped, 2L)
  expect_equal(r$n_priced, 2L)
  expect_equal(r$weight_basis, "population_share")
  slim <- lifewatt:::.annual_slim()
  s <- slim[slim$year == 2024 & slim$state == "FL" & slim$eiaid %in% c("3757", "6909"), ]
  sh <- lifewatt:::.zip_shares("32601")
  w <- sh$pop_share[match(s$eiaid, sh$eiaid)]
  expect_equal(r$price, weighted.mean(s$price, w), tolerance = 1e-9)
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

test_that("annual ZIP price equals an independent recompute from the shipped slim tables", {
  map <- lifewatt:::.open_map()
  slim <- lifewatt:::.annual_slim()
  share <- utils::read.csv(system.file("extdata", "zip_utility_share_slim.csv.gz", package = "lifewatt"),
                           colClasses = c(zip = "character", eiaid = "character"))
  recompute <- function(zip, year) {
    m <- unique(map[map$zip == zip, c("eiaid", "state")])
    s <- slim[slim$year == year & is.finite(slim$price) & slim$price > 0, ]
    j <- merge(m, s[, c("eiaid", "state", "price", "cus")], by = c("eiaid", "state"))
    # 合约：多 utility 时首选 ZIP 内人口份额（在已定价 utility 间归一），
    # 无份额或份额全 0 时回退当年 residential customers（缺失回退等权 1）
    sh <- share[share$zip == zip, ]
    w <- if (nrow(j) > 1L && nrow(sh) > 0L) sh$pop_share[match(j$eiaid, sh$eiaid)] else NULL
    if (!is.null(w)) w[is.na(w)] <- 0
    if (is.null(w) || sum(w) == 0) w <- ifelse(is.finite(j$cus) & j$cus > 0, j$cus, 1)
    stats::weighted.mean(j$price, w)
  }
  for (z in c("32601", "28657", "99501", "01002")) {
    for (y in c(2023, 2024, 2025)) {
      got <- lifewatt:::.zip_annual_price(z, y)$price
      expect_equal(got, recompute(z, y), tolerance = 1e-9, label = paste(z, y))
    }
  }
})
