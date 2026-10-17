# data-raw/assemble_861_slim.R —— exp#36 一次性：EIA-861 2023/2024/2025 三年下载 → utility×年 RES slim
# URL 依 candidate-list A1：2025 终值 https://www.eia.gov/electricity/data/eia861/zip/f8612025.zip；
# 历年归档 https://www.eia.gov/electricity/data/eia861/archive/zip/f861<YYYY>.zip
# 抽取口径见文件下段（先探查 zip 内表结构）。下载原 zip 留在 data-raw/eia861/（gitignore）。

options(timeout = 900)
dir.create("data-raw/eia861", recursive = TRUE, showWarnings = FALSE)
urls <- c(
  "2025" = "https://www.eia.gov/electricity/data/eia861/zip/f8612025.zip",
  "2024" = "https://www.eia.gov/electricity/data/eia861/archive/zip/f8612024.zip",
  "2023" = "https://www.eia.gov/electricity/data/eia861/archive/zip/f8612023.zip"
)
for (y in names(urls)) {
  dest <- file.path("data-raw/eia861", basename(urls[[y]]))
  if (!file.exists(dest)) {
    download.file(urls[[y]], dest, mode = "wb", quiet = TRUE)
  }
  cat(y, "|", basename(dest), file.info(dest)$size, "bytes\n")
}

## 抽取：Sales_Ult_Cust_<Y>.xlsx \@States，行1/2为表头栏 → 数据自行3。
## 过滤 Service Type=Bundled & Part=A；price(cents/kWh)=100*Revenues(千$)/Sales(MWh)；
## 去重键 (year, eiaid, state)，Data Type=O 优先于 I；res_sales<=0/NA 行剔除（无价可派）。
library(openxlsx)
XTRACT <- function(y) {
  d <- read.xlsx(file.path("data-raw/eia861", y, sprintf("Sales_Ult_Cust_%s.xlsx", y)), sheet = "States")
  names(d) <- c("data_year", "eiaid", "utility_name", "part", "service_type", "data_type",
                "state", "ownership", "ba_code",
                "res_rev", "res_sales", "res_cust",
                "com_rev", "com_sales", "com_cust",
                "ind_rev", "ind_sales", "ind_cust",
                "tra_rev", "tra_sales", "tra_cust",
                "tot_rev", "tot_sales", "tot_cust")
  d <- d[3:nrow(d), ]
  d <- d[d$service_type == "Bundled" & d$part == "A", ]
  d$eiaid <- as.character(d$eiaid)
  d$rev <- suppressWarnings(as.numeric(d$res_rev))
  d$sal <- suppressWarnings(as.numeric(d$res_sales))
  d$cus <- suppressWarnings(as.numeric(d$res_cust))
  d$price <- 100 * d$rev / d$sal
  d <- d[is.finite(d$price) & d$price > 0, c("eiaid", "utility_name", "state", "data_type",
                                             "rev", "sal", "cus", "price")]
  d$type_rank <- ifelse(d$data_type == "O", 0L, 1L)
  d <- d[order(d$eiaid, d$state, d$type_rank, d$rev), ]
  key <- paste(d$eiaid, d$state)
  d <- d[!duplicated(key), ]
  data.frame(year = as.integer(y), d[, c("eiaid", "utility_name", "state", "data_type",
                                         "rev", "sal", "cus", "price")])
}
slim <- do.call(rbind, lapply(c("2023", "2024", "2025"), XTRACT))
slim$src <- "EIA-861 Sales_Ult_Cust (Bundled, Part A); O-preferring dedupe by (year,eiaid,state)"
slim <- slim[order(slim$year, slim$eiaid, slim$state), ]
con <- gzfile("inst/extdata/eia861_annual_slim.csv.gz", "wt")
write.csv(slim, con, row.names = FALSE)
close(con)
cat("slim rows by year:\n"); print(table(slim$year))
cat("states with >=50 priced utilities (2025):\n")
print(head(sort(table(slim$state[slim$year == 2025]), decreasing = TRUE), 12))
cat("customers weight coverage by year (share of rows with customers>0):\n")
print(tapply(slim$cus > 0, slim$year, mean, na.rm = TRUE))
