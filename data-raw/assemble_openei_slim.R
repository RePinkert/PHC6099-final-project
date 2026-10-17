# data-raw/assemble_openei_slim.R —— 一次性：A2 OpenEI ZIP→utility 映射 trim 进 inst/extdata
#
# 源：OpenEI / NREL「U.S. Electric Utility Companies and Rates: Look-up by Zip Code」
#     2024 版入口 https://data.openei.org/submissions/8563
#     （编制人 Jay Huggins；许可 CC-BY-4.0，随包分发须保留来源声明，见 reader provenance）
# 依据 candidate-list A2：费率字段仅作合理性校验、不作返回值 → slim 只留映射四列；gz 压缩随包。
#
# 两张源 CSV 合计约 8.9 MB，**不进版本库**（data-raw/openei/ 已在 .gitignore）：
# 脚本按下面的 URL 下载到本地缓存，再用哈希钉住 2024 vintage。哈希不符即失败 ——
# 源站若改版，宁可报错也不静默换数据（换版应连带重跑 tests + 更新 NEWS 的滞后声明）。
#
# 钉住的副本（2026-10-16 实测）：
#   iou_zipcodes_2024.csv      md5 1d46f5c0bc4b933fdd66b8c09cd7d8b3
#                              sha256 e5ed44abe4b22189b3c5c3ead297096aed90c81858b3a350c030cbf171434477
#   non_iou_zipcodes_2024.csv  md5 2366912d3bdc2049160642f80b5cfe76
#                              sha256 0681adf5cec7cfc05e6352e9ec295e686f58bf4e818fefb0f3f58958f9418121
# 产出的 inst/extdata/openei_zip2state_slim.csv.gz 由函数体末尾的三行统计与包内 tests 对账。

sources <- c(
  iou_zipcodes_2024.csv     = "https://data.openei.org/files/8563/iou_zipcodes_2024.csv",
  non_iou_zipcodes_2024.csv = "https://data.openei.org/files/8563/non_iou_zipcodes_2024.csv"
)
pinned_md5 <- c(
  iou_zipcodes_2024.csv     = "1d46f5c0bc4b933fdd66b8c09cd7d8b3",
  non_iou_zipcodes_2024.csv = "2366912d3bdc2049160642f80b5cfe76"
)

fetch_verified <- function(name, url, want, dir = "data-raw/openei") {
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  dest <- file.path(dir, name)
  if (!file.exists(dest) || !identical(unname(tools::md5sum(dest)), want)) {
    message("downloading ", name, " from ", url)
    utils::download.file(url, dest, mode = "wb", quiet = TRUE)
  }
  got <- unname(tools::md5sum(dest))
  if (!identical(got, want)) {
    stop(sprintf(
      "checksum mismatch for %s: got %s, pinned %s -- the OpenEI 2024 vintage changed; re-verify the slim output, the tests and the NEWS staleness note before re-pinning.",
      name, got, want), call. = FALSE)
  }
  dest
}

files <- vapply(names(sources), function(n) fetch_verified(n, sources[[n]], pinned_md5[[n]]),
                character(1))
m <- lapply(files, function(f) {
  d <- read.csv(f, colClasses = "character")
  d[, c("zip", "eiaid", "utility_name", "state")]
})
df <- do.call(rbind, m)
df <- df[order(df$zip, df$eiaid), ]
con <- gzfile("inst/extdata/openei_zip2state_slim.csv.gz", "wt")
write.csv(df, con, row.names = FALSE)
close(con)
u <- unique(df[c("zip", "eiaid")])
n_zip <- length(unique(u$zip))
cat(sprintf("slim rows %d | zip+eiaid pairs %d | zips %d | multi-utility zips %d\n",
            nrow(df), nrow(u), n_zip, sum(table(u$zip) > 1)))
