# data-raw/assemble_861_state_annual.R —— LSTM 年度通道：EIA-861 州×年客户加权住宅价 2010..2025
#
# 为什么单独一张表：eia861_annual_slim.csv.gz（utility×年，2023..2025）同时供 ZIP 年度价使用，
#   不在那里扩年份；LSTM 只需要州级聚合，所以这里另出一张小表。
# 为什么要补到 2010：接缝诊断（model_traning/diagnose_seam.R）发现年度通道只有 2023..2025，
#   按发布日期 2024-10 才首次进入，训练窗里几乎全是"无数据"，模型学不到它的含义。
#
# 源：EIA-861 年度归档（无需 API key）
#   2010、2011：archive/zip/f86110.zip、f86111.zip 里的 file2_<Y>.xls（同一张"Sales to Ultimate Customers"表）
#   2012..2022：archive/zip/f861<Y>.zip 里的 Sales_Ult_Cust_<Y>.xls[x]
#   2023..2025：直接取 inst/extdata/eia861_annual_slim.csv.gz（assemble_861_slim.R 的产物），保证数值不变
# 口径与 assemble_861_slim.R 相同：sheet States；Service Type = Bundled 且 Part = A；
#   price = 100 * 住宅收入(千$) / 住宅售电(MWh)；(year, eiaid, state) 去重，Data Type O 优先于 I；
#   只保留 price 有限且 > 0 的行。
# 聚合与服务端 .ann_wide 相同：排除 Adjustment 伪 utility（eiaid 99999）和 customers <= 0，
#   price = sum(price * cus) / sum(cus)。
# 产物：inst/extdata/eia861_state_annual.csv.gz (state, year, price, customers, n_utilities)
# 原始 zip 缓存在 data-raw/eia861/（.gitignore）。从包根目录运行：Rscript data-raw/assemble_861_state_annual.R

options(timeout = 900)
cache <- "data-raw/eia861"
dir.create(cache, showWarnings = FALSE, recursive = TRUE)
STATES <- c(state.abb, "DC")
base <- "https://www.eia.gov/electricity/data/eia861/archive/zip/"

src_of <- function(y) {
  if (y <= 2011) {
    list(zip = sprintf("f861%02d.zip", y %% 100), member = sprintf("file2_%d.xls", y))
  } else {
    list(zip = sprintf("f861%d.zip", y), member = NA_character_)
  }
}

extract_year <- function(y) {
  s <- src_of(y)
  z <- file.path(cache, s$zip)
  if (!file.exists(z)) utils::download.file(paste0(base, s$zip), z, mode = "wb", quiet = TRUE)
  members <- utils::unzip(z, list = TRUE)$Name
  m <- if (is.na(s$member)) grep(sprintf("^Sales_Ult_Cust_%d\\.xlsx?$", y), members, value = TRUE) else s$member
  stopifnot(length(m) == 1, m %in% members)
  dir <- file.path(cache, y)
  dir.create(dir, showWarnings = FALSE)
  f <- utils::unzip(z, files = m, exdir = dir, junkpaths = TRUE)
  raw <- suppressMessages(readxl::read_excel(f, sheet = "States", col_names = FALSE, col_types = "text",
                                             .name_repair = "minimal"))
  ## 表头：第 1 行是分组（RESIDENTIAL ...），第 3 行是字段名；2013 起多一列 BA Code，按名字定位
  h1 <- as.character(unlist(raw[1, ])); h3 <- tolower(gsub("\\s+", " ", as.character(unlist(raw[3, ]))))
  col <- function(pat) { k <- grep(pat, h3); stopifnot(length(k) >= 1); k[1] }
  res <- which(h1 == "RESIDENTIAL")
  stopifnot(length(res) == 1)
  d <- data.frame(
    year = y,
    eiaid = raw[[col("^utility number")]], state = raw[[col("^state$")]],
    part = raw[[col("^part$")]], service_type = raw[[col("^service.type")]],
    data_type = substr(raw[[col("^data type")]], 1, 1),
    rev = suppressWarnings(as.numeric(raw[[res]])), sal = suppressWarnings(as.numeric(raw[[res + 1]])),
    cus = suppressWarnings(as.numeric(raw[[res + 2]])), stringsAsFactors = FALSE)
  d <- d[-(1:3), ]
  d <- d[d$service_type == "Bundled" & d$part == "A", ]
  d$price <- 100 * d$rev / d$sal
  d <- d[is.finite(d$price) & d$price > 0, ]
  d$type_rank <- ifelse(d$data_type == "O", 0L, 1L)
  d <- d[order(d$eiaid, d$state, d$type_rank, d$rev), ]
  d[!duplicated(paste(d$eiaid, d$state)), c("year", "eiaid", "state", "rev", "sal", "cus", "price")]
}

old <- do.call(rbind, lapply(2010:2022, extract_year))
new <- utils::read.csv("inst/extdata/eia861_annual_slim.csv.gz", stringsAsFactors = FALSE,
                       colClasses = c(eiaid = "character"))
stopifnot(identical(sort(unique(new$year)), 2023:2025))
u <- rbind(old, new[, names(old)])
u <- u[u$state %in% STATES & u$eiaid != "99999" & is.finite(u$cus) & u$cus > 0, ]
agg <- stats::aggregate(cbind(wsum = u$price * u$cus, customers = u$cus, n_utilities = 1),
                        by = list(state = u$state, year = u$year), sum)
agg$price <- agg$wsum / agg$customers
out <- agg[order(agg$state, agg$year), c("state", "year", "price", "customers", "n_utilities")]

## 覆盖与合理性：每个州 2010..2025 都要有值，价格在 1..100 美分/kWh
cover <- table(factor(out$state, STATES), factor(out$year, 2010:2025))
if (any(cover == 0)) {
  miss <- which(cover == 0, arr.ind = TRUE)
  print(data.frame(state = rownames(cover)[miss[, 1]], year = colnames(cover)[miss[, 2]]))
  stop("state-years missing from the annual covariate (see above)")
}
stopifnot(all(out$price > 1 & out$price < 100), all(cover == 1))

con <- gzfile("inst/extdata/eia861_state_annual.csv.gz", "wt")
utils::write.csv(out, con, row.names = FALSE)
close(con)
cat(sprintf("eia861_state_annual: %d rows | %d states | years %d..%d\n", nrow(out),
            length(unique(out$state)), min(out$year), max(out$year)))
print(stats::aggregate(cbind(median_price = price, median_utilities = n_utilities) ~ year, out, median))
