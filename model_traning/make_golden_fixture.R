# make_golden_fixture.R —— 生成纯 R 前向黄金值夹具（tests/testthat/fixtures/）
# 黄金值取自 R/price-lstm.R 的纯 R 前向（float64），测试以 1e-10 钉死任何实现漂移；
# torch 对账另见 check_parity.R（float32 界 1e-4）。
# 运行：Rscript model_traning/make_golden_fixture.R（需 pkgload）

pkgload::load_all(".", quiet = TRUE)
st <- c("FL", "AK", "CA", "DC", "NY", "TX", "WY")
pe <- c("2026-08", "2026-10", "2026-12")
g <- expand.grid(period = pe, state = st, stringsAsFactors = FALSE)
g <- g[order(match(g$state, st), match(g$period, pe)), ]
out <- lifewatt:::.lstm_predict(g$state, g$period)
out <- out[, c("state", "period", "h", "price", ".sd", "q_lo", "q_hi")]
dir.create("tests/testthat/fixtures", showWarnings = FALSE, recursive = TRUE)
utils::write.csv(out, "tests/testthat/fixtures/price_lstm_golden.csv", row.names = FALSE)
cat("wrote tests/testthat/fixtures/price_lstm_golden.csv:", nrow(out), "rows\n")
print(out)
