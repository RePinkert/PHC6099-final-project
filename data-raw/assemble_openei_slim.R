# data-raw/assemble_openei_slim.R —— 一次性：A2 OpenEI ZIP→utility 映射 trim 进 inst/extdata
# 源文件（exp#79a24f9 引入，git 跟踪）：data-raw/openei/iou_zipcodes_2024.csv + non_iou_zipcodes_2024.csv
# 依据 candidate-list A2：费率字段仅作合理性校验、不作返回值 → slim 只留映射四列；gz 压缩随包。
# 许可：CC-BY-4.0（NREL/OpenEI），随包分发须保留来源声明（见 reader provenance）。

files <- c("data-raw/openei/iou_zipcodes_2024.csv", "data-raw/openei/non_iou_zipcodes_2024.csv")
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
