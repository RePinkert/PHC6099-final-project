# assemble_vsrr_slim.R —— D1b 程序化替代源（exp#41）
# 来源：NCHS VSRR Quarterly provisional estimates for selected indicators of mortality
#       data.cdc.gov dataset 489q-934x（Socrata rows.csv，免人工表单；USGOV_WORKS 许可）
# 覆盖：2023Q1..2025Q3（11 季）；51 州全因死亡率（crude/age-adjusted x 3m/12m 滚动）；
#       全国全因年龄组率（crude only —— 年龄组列无州级分解，合成所需"州年龄模式=全国"为声明假设）。
# 产物：
#   inst/extdata/vsrr_state_quarter_slim.csv.gz   (51 x 11 x 2 x 2 = 2244 行)
#   inst/extdata/vsrr_national_age_slim.csv.gz    (11 x 2 x 10 = 220 行)
# vintage：provisional 全行 TRUE（VSRR 会被终值替换；vintage 异质见 candidate-list 风险 #15/#16）。
# 运行期包代码只读 inst/extdata；本脚本为一次性/刷新步骤。

src_dir <- "data-raw/vsrr"
src <- file.path(src_dir, "vsrr_quarterly.csv")
if (!file.exists(src)) {
  dir.create(src_dir, showWarnings = FALSE, recursive = TRUE)
  utils::download.file(
    "https://data.cdc.gov/api/views/489q-934x/rows.csv?accessType=DOWNLOAD",
    src, mode = "wb"
  )
}

d <- utils::read.csv(src, stringsAsFactors = FALSE)

quarter_of <- function(x) gsub(" ", "", x)  # "2023 Q1" -> "2023Q1"
state_abbrev <- function(col) {
  nm <- gsub("\\.", " ", sub("^Rate\\.", "", col))
  if (nm == "District of Columbia") return("DC")
  hit <- match(nm, state.name)
  stopifnot(!is.na(hit))
  state.abb[hit]
}

period_map <- c("3-month period" = "3m", "12 months ending with quarter" = "12m")
type_map <- c("Crude" = "crude", "Age-adjusted" = "age_adjusted")

## ---- 州级全因序列（+ US 全国行 = m 分母，exp#42）-------------------------
ac <- d[d$Cause.of.Death == "All causes", ]
state_cols <- grep("^Rate\\.", names(d), value = TRUE)
state_cols <- state_cols[!grepl("Age|Sex|Type|^Rate\\.[0-9]", state_cols)]
stopifnot(length(state_cols) == 51L)

rows <- list()
k <- 0L
for (i in seq_len(nrow(ac))) {
  for (cc in state_cols) {
    v <- ac[[cc]][i]
    if (is.na(v)) next
    k <- k + 1L
    rows[[k]] <- data.frame(
      state = state_abbrev(cc),
      quarter = quarter_of(ac$Year.and.Quarter[i]),
      period_type = unname(period_map[ac$Time.Period[i]]),
      rate_type = unname(type_map[ac$Rate.Type[i]]),
      rate_per_100k = as.numeric(v),
      stringsAsFactors = FALSE
    )
  }
  ## US 全国行：Overall.Rate = 全国率（合成层 m = state_adj / us_adj 的分母）
  kv <- ac$Overall.Rate[i]
  if (!is.na(kv)) {
    k <- k + 1L
    rows[[k]] <- data.frame(
      state = "US",
      quarter = quarter_of(ac$Year.and.Quarter[i]),
      period_type = unname(period_map[ac$Time.Period[i]]),
      rate_type = unname(type_map[ac$Rate.Type[i]]),
      rate_per_100k = as.numeric(kv),
      stringsAsFactors = FALSE
    )
  }
}
state_slim <- do.call(rbind, rows)
stopifnot(nrow(state_slim) == 52L * 11L * 2L * 2L)
state_slim$unit <- "deaths per 100,000"
state_slim$source <- "NCHS VSRR Quarterly provisional estimates (data.cdc.gov 489q-934x)"
state_slim$level <- ifelse(state_slim$state == "US", "national", "state")
state_slim$provisional <- TRUE
state_slim$coverage_note <- "provisional estimates; replaced by final vintage in later releases"

## ---- 全国年龄组模式（crude only，All causes）----------------------------
age_map <- c(
  "Rate.Age.1.4" = "1-4", "Rate.Age.5.14" = "5-14", "Rate.Age.15.24" = "15-24",
  "Rate.Age.25.34" = "25-34", "Rate.Age.35.44" = "35-44", "Rate.Age.45.54" = "45-54",
  "Rate.Age.55.64" = "55-64", "Rate.65.74" = "65-74", "Rate.Age.75.84" = "75-84",
  "Rate.Age.85.plus" = "85+"
)
ac_crude <- ac[ac$Rate.Type == "Crude", ]
rows2 <- list()
k <- 0L
for (i in seq_len(nrow(ac_crude))) {
  for (cc in names(age_map)) {
    v <- ac_crude[[cc]][i]
    if (is.na(v)) next
    k <- k + 1L
    rows2[[k]] <- data.frame(
      quarter = quarter_of(ac_crude$Year.and.Quarter[i]),
      period_type = unname(period_map[ac_crude$Time.Period[i]]),
      age_band = unname(age_map[cc]),
      rate_per_100k = as.numeric(v),
      stringsAsFactors = FALSE
    )
  }
}
age_slim <- do.call(rbind, rows2)
stopifnot(nrow(age_slim) == 11L * 2L * 10L)
age_slim$unit <- "deaths per 100,000"
age_slim$source <- "NCHS VSRR Quarterly provisional estimates (data.cdc.gov 489q-934x)"
age_slim$level <- "national"
age_slim$provisional <- TRUE
age_slim$coverage_note <- "national crude age pattern only (no state x age split in source); state age pattern = national is a DECLARED assumption downstream"

dir.create("inst/extdata", showWarnings = FALSE, recursive = TRUE)
utils::write.csv(state_slim, gzfile("inst/extdata/vsrr_state_quarter_slim.csv.gz"), row.names = FALSE)
utils::write.csv(age_slim, gzfile("inst/extdata/vsrr_national_age_slim.csv.gz"), row.names = FALSE)

cat(sprintf("saved vsrr_state_quarter_slim.csv.gz (%d rows) + vsrr_national_age_slim.csv.gz (%d rows)\n",
            nrow(state_slim), nrow(age_slim)))
