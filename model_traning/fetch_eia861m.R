# model_traning/fetch_eia861m.R —— 取 EIA-861M 月度工作簿（研究侧真值源）
#
# 源：https://www.eia.gov/electricity/data/eia861m/xls/sales_revenue.xlsx
#     sheet "Monthly-States"：Year, Month, State, Data Status, 然后是
#     RESIDENTIAL / COMMERCIAL / INDUSTRIAL 三块，每块 Revenue, Sales, Customers, Price。
#
# 为什么不直接跑 data-raw/assemble_eia861m_monthly.R：
#   那个脚本会把工作簿截到 2026-07 并重写随包的 inst/extdata/b1_monthly_cache.csv。
#   本轮要的是 2026-08..12 的真值（外推段的评估），**不动随包冻结物**，
#   所以这里只落到 gitignored 的研究侧表里。
#
# 产物（均在 .gitignore 内）：
#   data-raw/eia861m/sales_revenue.xlsx      工作簿原件
#   data-raw/eia861m/DOWNLOADED              下载日期 + md5 + 字节数
#   model_traning/candidates/truth_eia861m_monthly.csv   全窗口州级月面（含 rev/sal/cus）
#   model_traning/candidates/truth_extrap_segment.csv     外推段真值（2026-08..12）
#
# 用法：Rscript model_traning/fetch_eia861m.R

suppressPackageStartupMessages({
  stopifnot(requireNamespace("readxl", quietly = TRUE))
})

cache <- "data-raw/eia861m"
dir.create(cache, showWarnings = FALSE, recursive = TRUE)
src <- file.path(cache, "sales_revenue.xlsx")
url <- "https://www.eia.gov/electricity/data/eia861m/xls/sales_revenue.xlsx"

if (!file.exists(src)) {
  utils::download.file(url, src, mode = "wb", quiet = TRUE)
}
writeLines(c(
  sprintf("downloaded: %s", format(Sys.Date())),
  sprintf("url: %s", url),
  sprintf("bytes: %s", file.size(src)),
  sprintf("md5: %s", unname(tools::md5sum(src)))
), file.path(cache, "DOWNLOADED"))

raw <- suppressMessages(readxl::read_excel(
  src, sheet = "Monthly-States", skip = 3, col_names = FALSE,
  col_types = rep("text", 24), .name_repair = "minimal"
))

# 列位（与 data-raw/assemble_eia861m_monthly.R 一致：1=Year 2=Month 3=State 4=Data Status）
# 住宅块：5=Revenue 6=Sales 7=Customers 8=Price
d <- data.frame(
  year = suppressWarnings(as.integer(raw[[1]])),
  month = suppressWarnings(as.integer(raw[[2]])),
  state = raw[[3]],
  data_status = raw[[4]],
  rev = suppressWarnings(as.numeric(raw[[5]])),
  sal = suppressWarnings(as.numeric(raw[[6]])),
  cus = suppressWarnings(as.numeric(raw[[7]])),
  price = suppressWarnings(as.numeric(raw[[8]])),
  stringsAsFactors = FALSE
)
d <- d[!is.na(d$year) & !is.na(d$month), ]
d$period <- sprintf("%04d-%02d", d$year, d$month)
d <- d[order(d$state, d$period), ]

states <- c(state.abb, "DC")
out <- d[d$state %in% states, c("state", "period", "price", "rev", "sal", "cus", "data_status")]
out <- out[!duplicated(out[c("state", "period")]), ]

cat(sprintf("workbook rows(state) %d | months %s..%s | preliminary %d\n",
            nrow(out), min(out$period), max(out$period),
            sum(out$data_status == "Preliminary", na.rm = TRUE)))

dir.create("model_traning/candidates", showWarnings = FALSE, recursive = TRUE)
utils::write.csv(out, "model_traning/candidates/truth_eia861m_monthly.csv", row.names = FALSE)

seg <- out[out$period >= "2026-08" & out$period <= "2026-12", ]
utils::write.csv(seg, "model_traning/candidates/truth_extrap_segment.csv", row.names = FALSE)
cat(sprintf("extrapolation segment rows %d | %s..%s | status %s\n",
            nrow(seg), min(seg$period), max(seg$period),
            paste(unique(seg$data_status), collapse = ",")))