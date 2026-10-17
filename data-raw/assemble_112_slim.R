# assemble_112_slim.R —— C1 (Form EIA-112) 机制列的一次性组装脚本（exp#39）
# 来源：https://www.eia.gov/analysis/requests/residential/utility/
#       xls/112 electric utility level data 2024.xlsx（2026-04-14 发布，2024 全年逐月）
# 口径：每州取 EIA 官方 "State Total" 行（= utility 报告值 + State Adjustment，见 About sheet）；
#       4 个指标 sheet：Final notices / Disconnections / Reconnections / Number of customers。
# 产物：inst/extdata/eia112_state_month_slim.csv.gz（51 州 x 12 月 = 612 行，含 per-1k 率）
# 再分发许可：美国政府公作（与 EIA-861/B1 同），风险登记 #5 关闭。
# 运行期包代码只读 inst/extdata；本脚本仅在数据缺失/刷新时人工运行。

src <- "data-raw/eia112/112_electric_utility_2024.xlsx"
if (!file.exists(src)) {
  dir.create(dirname(src), showWarnings = FALSE, recursive = TRUE)
  utils::download.file(
    "https://www.eia.gov/analysis/requests/residential/utility/xls/112%20electric%20utility%20level%20data%202024.xlsx",
    src, mode = "wb"
  )
}

if (!requireNamespace("readxl", quietly = TRUE)) {
  stop("readxl is required for this one-time assembly step (not a package dependency).")
}

months <- c("January", "February", "March", "April", "May", "June", "July",
            "August", "September", "October", "November", "December")
periods <- sprintf("2024-%02d", 1:12)

read_sheet <- function(sheet) {
  d <- as.data.frame(readxl::read_excel(src, sheet = sheet, skip = 3),
                     stringsAsFactors = FALSE)
  st <- d[!is.na(d[["Utility name"]]) & d[["Utility name"]] == "State Total", ]
  stopifnot(nrow(st) == 51L)
  m <- as.matrix(st[, months])
  stopifnot(!anyNA(m))
  data.frame(
    state = rep(st[["State abbreviation"]], each = 12L),
    value = as.numeric(t(m)),
    stringsAsFactors = FALSE
  )
}

fn <- read_sheet("Final notices")
dc <- read_sheet("Disconnections")
rc <- read_sheet("Reconnections")
cu <- read_sheet("Number of customers")

out <- data.frame(
  state = fn$state,
  period = rep(periods, times = 51L),
  final_notices = fn$value,
  disconnections = dc$value,
  reconnections = rc$value,
  res_customers = cu$value,
  stringsAsFactors = FALSE
)
stopifnot(nrow(out) == 612L, all(fn$state == dc$state), all(dc$state == rc$state),
          all(rc$state == cu$state))

out$final_notices_per_1k <- out$final_notices / out$res_customers * 1000
out$disconnections_per_1k <- out$disconnections / out$res_customers * 1000
out$reconnections_per_1k <- out$reconnections / out$res_customers * 1000
out$source <- "Form EIA-112 State Total (2024; utilities + State Adjustment)"
out$level <- "state"
out$provisional <- FALSE
out$coverage_note <- "EIA-112 covers calendar 2024 only (survey not extended)"

dir.create("inst/extdata", showWarnings = FALSE, recursive = TRUE)
utils::write.csv(out, gzfile("inst/extdata/eia112_state_month_slim.csv.gz"),
                 row.names = FALSE)

cat(sprintf("saved inst/extdata/eia112_state_month_slim.csv.gz | rows: %d | states: %d | NA rates: %d\n",
            nrow(out), length(unique(out$state)),
            sum(!is.finite(out$disconnections_per_1k))))
