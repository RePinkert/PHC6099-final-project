# data-raw/assemble_eia861m_monthly.R —— B1 州级住宅月价缓存，改由 EIA-861M 批量文件组装
#
# 源：EIA-861M「Sales and revenue」月度州表（无需 API key，www.eia.gov 直接下载）
#     https://www.eia.gov/electricity/data/eia861m/xls/sales_revenue.xlsx
#     sheet Monthly-States：Year, Month, State, Data Status, RESIDENTIAL Revenue/Sales/Customers/Price ...
# 与原 EIA API（retail-sales）同源：2025 年以前与旧缓存逐格一致；差异只来自 EIA 对 2025+ 的回改
# （例：MD 2026-03 旧缓存 35.85 为初值，现值 22.2）。
#
# 产物：inst/extdata/b1_monthly_cache.csv (state, period, price, data_status)
#   - 窗口仍为声明的 2023-01..2026-07（预测 regime 的 fit_as_of 不因新月份到达而移动；
#     重训时再一起前移）；
#   - data_status 取源表的 Final / Preliminary，下游 provisional 由它决定，而不是按日期猜。
# 源文件缓存在 data-raw/eia861m/（.gitignore），下载日期写进 data-raw/eia861m/DOWNLOADED。
# 从包根目录运行：Rscript data-raw/assemble_eia861m_monthly.R

cache <- "data-raw/eia861m"
dir.create(cache, showWarnings = FALSE, recursive = TRUE)
src <- file.path(cache, "sales_revenue.xlsx")
if (!file.exists(src)) {
  utils::download.file("https://www.eia.gov/electricity/data/eia861m/xls/sales_revenue.xlsx",
                       src, mode = "wb", quiet = TRUE)
  writeLines(format(Sys.Date()), file.path(cache, "DOWNLOADED"))
}

raw <- readxl::read_excel(src, sheet = "Monthly-States", skip = 3, col_names = FALSE,
                          col_types = "text", .name_repair = "minimal")
d <- data.frame(
  year = suppressWarnings(as.integer(raw[[1]])), month = suppressWarnings(as.integer(raw[[2]])),
  state = raw[[3]],
  data_status = raw[[4]], price = suppressWarnings(as.numeric(raw[[8]])),
  stringsAsFactors = FALSE
)
d <- d[!is.na(d$year) & !is.na(d$month), ]
d$period <- sprintf("%04d-%02d", d$year, d$month)

states <- c(state.abb, "DC")
out <- d[d$state %in% states & d$period >= "2023-01" & d$period <= "2026-07",
         c("state", "period", "price", "data_status")]
out <- out[order(out$state, out$period), ]

stopifnot(
  nrow(out) == length(states) * 43L,
  all(is.finite(out$price) & out$price > 0),
  all(out$data_status %in% c("Final", "Preliminary"))
)
utils::write.csv(out, "inst/extdata/b1_monthly_cache.csv", row.names = FALSE)
cat(sprintf("b1 rows %d | states %d | months %d | preliminary %d (%s..%s)\n",
            nrow(out), length(unique(out$state)), length(unique(out$period)),
            sum(out$data_status == "Preliminary"),
            min(out$period[out$data_status == "Preliminary"]),
            max(out$period[out$data_status == "Preliminary"])))
