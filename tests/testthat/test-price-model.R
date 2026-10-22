test_that("triplet predictor regresses 1:1 against the frozen reference predict_fn", {
  path <- test_path("fixtures", "predict_fn_reference.R")
  expect_true(file.exists(path),
              info = "frozen predict_fn fixture must ship with the suite; its absence must fail loudly")
  eval(parse(text = readLines(path, warn = FALSE)), envir = environment())
  fit <- lifewatt:::.price_fit()
  cache <- lifewatt:::.monthly_cache()
  model <- list(params = fit$params, train = cache, hw = fit$hw)
  st <- c("FL", "WY", "AK", "DC", "TX", "CA")
  mo <- c("2026-08", "2026-12", "2027-06", "2028-01")
  test_df <- data.frame(
    state = rep(st, each = length(mo)),
    period = rep(mo, times = length(st)),
    price = 0
  )
  ref <- predict_fn(model, test_df)
  got <- lifewatt:::.triplet_predict(test_df$state, test_df$period)
  expect_equal(got$price, ref$price, tolerance = 1e-10)
  expect_equal(got$.sd, ref$.sd, tolerance = 1e-10)
})
