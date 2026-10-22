# check_parity.R —— 纯 R 前向（R/price-lstm.R）与训练期 torch 前向的逐值对账
# 断言：price / .sd 与 price_lstm_fit.rds$forecast（torch float32 原值）在 1e-4 内一致
# （容差 = torch float32 与 R float64 的舍入界；黄金夹具另以纯 R 值 1e-10 钉死）。
# 运行：Rscript model_traning/check_parity.R（需 pkgload）

pkgload::load_all(".", quiet = TRUE)
fit <- lifewatt:::.price_lstm_fit()
fc <- fit$forecast
got <- lifewatt:::.lstm_predict(fc$state, fc$period)
dp <- max(abs(got$price - fc$price))
ds <- max(abs(got$.sd - fc$sd))
cat(sprintf("max |price diff| = %.3e   max |sd diff| = %.3e\n", dp, ds))
stopifnot(dp < 1e-4, ds < 1e-4)
cat("parity OK: pure-R forward reproduces the torch training-time forecast (float32 bound)\n")
