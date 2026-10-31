# assemble_price_history_slim.R —— 价格 LSTM 特征所需的历史电价面（2010-01..2026-07）
# 来源：EIA-861M bulk workbook, Monthly-States sheet（无需 API key）
#   https://www.eia.gov/electricity/data/eia861m/xls/sales_revenue.xlsx
# 第 4 列为 Data Status，第 8 列为住宅电价（cents/kWh）。即使源文件已有
# 2026-08，仍按冻结预测契约截在 fit_as_of = 2026-07。
# 产物：inst/extdata/price_history_slim.csv.gz

stopifnot(requireNamespace("readxl", quietly = TRUE))

url <- "https://www.eia.gov/electricity/data/eia861m/xls/sales_revenue.xlsx"
xlsx <- tempfile(fileext = ".xlsx")
on.exit(unlink(xlsx), add = TRUE)
utils::download.file(url, xlsx, mode = "wb", quiet = TRUE)

raw <- suppressMessages(readxl::read_excel(
  xlsx, sheet = "Monthly-States", skip = 3, col_names = FALSE,
  col_types = rep("text", 24)
))
states <- c(state.abb, "DC")
out <- data.frame(
  state = raw[[3]],
  period = sprintf("%04d-%02d", as.integer(raw[[1]]), as.integer(raw[[2]])),
  price = suppressWarnings(as.numeric(raw[[8]])),
  data_status = raw[[4]],
  stringsAsFactors = FALSE
)
out <- out[out$state %in% states & out$period >= "2010-01" &
             out$period <= "2026-07" & is.finite(out$price), ]
out <- out[order(match(out$state, states), out$period), ]
stopifnot(!anyDuplicated(out[c("state", "period")]))

months <- sprintf("%04d-%02d", rep(2010:2026, each = 12), rep(1:12, 17))
months <- months[months <= "2026-07"]
expected <- expand.grid(state = states, period = months, stringsAsFactors = FALSE)
stopifnot(nrow(out) == nrow(expected),
          setequal(paste(out$state, out$period), paste(expected$state, expected$period)))
out$imputed <- 0L
out <- out[c("state", "period", "price", "imputed", "data_status")]

utils::write.csv(out, gzfile("inst/extdata/price_history_slim.csv.gz"), row.names = FALSE)
cat("wrote inst/extdata/price_history_slim.csv.gz:", nrow(out), "rows;",
    min(out$period), "through", max(out$period), "; statuses:",
    paste(names(table(out$data_status)), table(out$data_status), collapse = ", "), "\n")
