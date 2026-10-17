test_that("triplet predictor regresses 1:1 against autoresearch predict_fn (dev-only anchor)", {
  cand <- c("autoresearch/train.R", file.path("..", "..", "autoresearch", "train.R"))
  path <- cand[file.exists(cand)][1L]
  if (is.na(path)) path <- ""
  skip_if(!nzchar(path), "autoresearch source tree not present (installed-package run)")
  code <- paste(readLines(path), collapse = "\n")
  tailpos <- regexpr("if [(]sys[.]nf", code)[1]
  eval(parse(text = substring(code, 1, tailpos - 1)))  # defines predict_fn (agent source)
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
