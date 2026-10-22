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
  slim <- lifewatt:::.annual_slim()
  exp_w <- vapply(zs$utilities$eiaid, function(e) {
    rows <- slim[slim$eiaid == e & slim$state == "FL" & is.finite(slim$cus) & slim$cus > 0, ]
    rows$cus[which.max(rows$year)]
  }, numeric(1))
  expect_equal(zs$utilities$cust_weight, unname(exp_w))
  expect_equal(zs$state_share, 1)
  ze <- lifewatt:::.zip_state("32601", weights = "equal")
  expect_equal(ze$weight_scheme, "equal")
  expect_error(lifewatt:::.zip_state("32601", weights = "bogus"), "Unknown weight scheme", fixed = TRUE)
})

test_that("regression: customers weights fall back across data years (year-fallback bug)", {
  slim <- lifewatt:::.annual_slim()
  s <- slim[is.finite(slim$cus) & slim$cus > 0, ]
  pairs <- unique(paste(s$eiaid, s$state, sep = "|"))
  ok <- vapply(pairs, function(p) {
    str <- strsplit(p, "|", fixed = TRUE)[[1L]]
    rows <- s[s$eiaid == str[1L] & s$state == str[2L], ]
    want <- rows$cus[which.max(rows$year)]
    got <- lifewatt:::.annual_customers(str[1L], str[2L])
    is.finite(got) && isTRUE(all.equal(got, want))
  }, logical(1))
  expect_true(all(ok),
              info = paste("latest-year cus not returned for:",
                           paste(utils::head(pairs[!ok], 5L), collapse = ", ")))
  # the historical bug class: pairs present in older years but missing the newest year
  newest <- max(s$year)
  in_newest <- unique(paste(s$eiaid[s$year == newest], s$state[s$year == newest], sep = "|"))
  older_only <- setdiff(pairs, in_newest)
  expect_gt(length(older_only), 0L)
  p <- strsplit(older_only[[1L]], "|", fixed = TRUE)[[1L]]
  rows <- s[s$eiaid == p[1L] & s$state == p[2L], ]
  expect_equal(lifewatt:::.annual_customers(p[1L], p[2L]), rows$cus[which.max(rows$year)])
})

test_that("annual ZIP price equals an independent recompute from the shipped slim tables", {
  map <- lifewatt:::.open_map()
  slim <- lifewatt:::.annual_slim()
  recompute <- function(zip, year) {
    m <- unique(map[map$zip == zip, c("eiaid", "state")])
    s <- slim[slim$year == year & is.finite(slim$price) & slim$price > 0, ]
    j <- merge(m, s[, c("eiaid", "state", "price", "cus")], by = c("eiaid", "state"))
    # 合约：定价权重 = 当年 residential customers（缺失回退等权 1）
    w <- ifelse(is.finite(j$cus) & j$cus > 0, j$cus, 1)
    stats::weighted.mean(j$price, w)
  }
  for (z in c("32601", "28657", "99501", "01002")) {
    for (y in c(2023, 2024, 2025)) {
      got <- lifewatt:::.zip_annual_price(z, y)$price
      expect_equal(got, recompute(z, y), tolerance = 1e-9, label = paste(z, y))
    }
  }
})
