# data-raw/assemble_zip_utility_share.R —— 一次性：多 utility ZIP 的 ZIP 内人口份额 -> inst/extdata
#
# 目的：A1 年价原先用 utility 的全州住宅客户数加权，大 utility 只碰到 ZIP 边缘也会主导混合价
#      （32608：Duke 87%）。这里改为 utility 在该 ZCTA 内实际覆盖的 2020 人口份额。
#
# 源（均为公开、免登录）：
#   1. Census 2020 TIGER/Line TABBLOCK20（逐州 zip，只读 .dbf）：GEOID20, POP20, INTPTLAT20, INTPTLON20
#      https://www2.census.gov/geo/tiger/TIGER2020/TABBLOCK20/tl_2020_<FIPS>_tabblock20.zip
#   2. Census 2020 ZCTA5 <-> block 关系表（ZCTA 由 block 拼成，每个 block 至多属于一个 ZCTA）
#      https://www2.census.gov/geo/docs/maps-data/data/rel2020/zcta520/tab20_zcta520_tabblock20_natl.txt
#   3. HIFLD Electric Retail Service Territories（ORNL 维护；字段 ID = EIA utility id）
#      https://services3.arcgis.com/OYP7N6mAJJCyH6hd/arcgis/rest/services/Electric_Retail_Service_Territories_HIFLD/FeatureServer/0
#
# 方法（声明假设）：
#   - 只算 OpenEI 2024 映射里 >1 个 utility 的 ZIP（单 utility ZIP 份额恒为 1，无需算）；ZIP 按同号 ZCTA 处理；
#   - 每个 POP20 > 0 的 block 取内部点，落在哪些 HIFLD 区域内；候选限定为 OpenEI 映射给该 ZIP 的 utility；
#   - 一个 block 同时落在 k 个候选区域内（区域重叠）：主口径归面积最小的区域（HIFLD 的合作社/大 IOU
#     常按整县画，市政区域边界最具体），对照口径 pop_share_equal 等分 1/k；一个都不落的人口记为未分配；
#   - pop_share = utility 分到的人口 / 该 ZIP 已分配人口；assigned_frac = 已分配人口 / ZCTA 总人口；
#     overlap_frac = 已分配人口中落在重叠区的比例（越高，结果越依赖重叠规则）。
#
# 原始文件（约 1.5 GB）不进版本库：缓存在 data-raw/zipshare/（.gitignore）。
# 从包根目录运行：Rscript data-raw/assemble_zip_utility_share.R

library(sf)
sf_use_s2(FALSE)  # 点在面内判断；平面 GEOS 足够且远快于 s2

cache <- "data-raw/zipshare"
dir.create(file.path(cache, "blocks"), showWarnings = FALSE, recursive = TRUE)

fetch <- function(url, dest) {
  if (!file.exists(dest)) {
    message("downloading ", basename(dest))
    utils::download.file(url, dest, mode = "wb", quiet = TRUE)
  }
  dest
}

## 1. 映射：只留多 utility ZIP
m <- unique(read.csv("inst/extdata/openei_zip2state_slim.csv.gz", colClasses = "character")[, c("zip", "eiaid")])
n_u <- table(m$zip)
m <- m[m$zip %in% names(n_u)[n_u > 1L], ]
target_zips <- unique(m$zip)

## 2. block -> ZCTA
rel_path <- fetch("https://www2.census.gov/geo/docs/maps-data/data/rel2020/zcta520/tab20_zcta520_tabblock20_natl.txt",
                  file.path(cache, "zcta_block_rel.txt"))
rel <- utils::read.delim(rel_path, sep = "|", colClasses = "character",
                         fileEncoding = "UTF-8-BOM")[, c("GEOID_ZCTA5_20", "GEOID_TABBLOCK_20")]
rel <- rel[rel$GEOID_ZCTA5_20 %in% target_zips, ]
names(rel) <- c("zip", "block")

## 3. block 人口与内部点（只读 dbf，不要几何）
fips <- c("01", "02", "04", "05", "06", "08", "09", "10", "11", "12", "13", "15", "16", "17", "18", "19",
          "20", "21", "22", "23", "24", "25", "26", "27", "28", "29", "30", "31", "32", "33", "34", "35",
          "36", "37", "38", "39", "40", "41", "42", "44", "45", "46", "47", "48", "49", "50", "51", "53",
          "54", "55", "56", "72")
blocks <- do.call(rbind, lapply(fips, function(f) {
  dbf <- file.path(cache, "blocks", sprintf("tl_2020_%s_tabblock20.dbf", f))
  if (!file.exists(dbf)) {
    z <- fetch(sprintf("https://www2.census.gov/geo/tiger/TIGER2020/TABBLOCK20/tl_2020_%s_tabblock20.zip", f),
               tempfile(fileext = ".zip"))
    utils::unzip(z, files = basename(dbf), exdir = dirname(dbf))
    unlink(z)
  }
  d <- foreign::read.dbf(dbf, as.is = TRUE)
  d <- d[d$POP20 > 0, c("GEOID20", "POP20", "INTPTLAT20", "INTPTLON20")]
  d[d$GEOID20 %in% rel$block, ]
}))
blocks <- merge(blocks, rel, by.x = "GEOID20", by.y = "block")
blocks$lat <- as.numeric(blocks$INTPTLAT20)
blocks$lon <- as.numeric(blocks$INTPTLON20)

## 4. HIFLD 区域：按 OBJECTID 分页取全量 GeoJSON（maxRecordCount 2000；几何简化到 ~0.0005 度 ≈ 50 m，
##    远小于 block 尺度，声明为近似）
hifld <- "https://services3.arcgis.com/OYP7N6mAJJCyH6hd/arcgis/rest/services/Electric_Retail_Service_Territories_HIFLD/FeatureServer/0/query"
terr_path <- file.path(cache, "hifld_territories.gpkg")
if (!file.exists(terr_path)) {
  page <- 50L
  parts <- list()
  offset <- 0L
  repeat {
    q <- paste0(hifld, "?where=1%3D1&outFields=ID,NAME,STATE,SOURCEDATE&outSR=4326",
                "&maxAllowableOffset=0.0005&geometryPrecision=5&orderByFields=OBJECTID",
                "&resultOffset=", offset, "&resultRecordCount=", page, "&f=geojson")
    chunk <- sf::st_read(q, quiet = TRUE)
    if (nrow(chunk) == 0L) break
    parts[[length(parts) + 1L]] <- chunk
    offset <- offset + nrow(chunk)
    message("territories fetched: ", offset)
  }
  terr <- do.call(rbind, parts)
  sf::st_write(terr, terr_path, quiet = TRUE)
}
terr <- sf::st_make_valid(sf::st_read(terr_path, quiet = TRUE))
terr$ID <- as.character(terr$ID)

## 5. 点在面内，候选限定为该 ZIP 的映射 utility（空间匹配约 30 分钟，结果缓存）
hits_path <- file.path(cache, "block_hits.rds")
if (file.exists(hits_path)) {
  hits <- readRDS(hits_path)
} else {
  pts <- sf::st_as_sf(blocks, coords = c("lon", "lat"), crs = 4326)
  hits <- sf::st_intersects(pts, terr)
  saveRDS(hits, hits_path)
}
terr_km2 <- as.numeric(sf::st_area(sf::st_transform(terr, 5070))) / 1e6
hit_df <- data.frame(row = rep(seq_along(hits), lengths(hits)), eiaid = terr$ID[unlist(hits)],
                     km2 = terr_km2[unlist(hits)], stringsAsFactors = FALSE)
hit_df$zip <- blocks$zip[hit_df$row]
hit_df <- merge(hit_df, m, by = c("zip", "eiaid"))
hit_df <- stats::aggregate(km2 ~ zip + eiaid + row, data = hit_df, FUN = min)  # 同一 utility 多块面只记一次
hit_df$pop20 <- blocks$POP20[hit_df$row]
k <- table(hit_df$row)
hit_df$k <- as.numeric(k[as.character(hit_df$row)])

## 重叠处理（声明假设）：HIFLD 中合作社/大型 IOU 常按整县画区域，与边界精确的市政区域重叠。
##   主口径 pop_share：重叠 block 归面积最小的候选区域（最具体的边界）；
##   对照口径 pop_share_equal：重叠 block 人口等分；overlap_frac = 落在重叠区的已分配人口比例。
smallest <- stats::ave(hit_df$km2, hit_df$row, FUN = min)
hit_df$pop_small <- ifelse(hit_df$km2 == smallest, hit_df$pop20, 0)
n_small <- stats::ave(hit_df$pop_small > 0, hit_df$row, FUN = sum)
hit_df$pop_small <- ifelse(n_small > 0, hit_df$pop_small / pmax(n_small, 1), 0)
hit_df$pop_equal <- hit_df$pop20 / hit_df$k

zip_pop <- tapply(blocks$POP20, blocks$zip, sum)
alloc <- stats::aggregate(cbind(pop_small, pop_equal) ~ zip + eiaid, data = hit_df, FUN = sum)
alloc_tot <- tapply(alloc$pop_equal, alloc$zip, sum)
blk <- unique(hit_df[c("zip", "row", "pop20", "k")])
overlap_pop <- tapply(blk$pop20 * (blk$k > 1), blk$zip, sum)

out <- merge(m, alloc, by = c("zip", "eiaid"), all.x = TRUE)
out$pop_small[is.na(out$pop_small)] <- 0
out$pop_equal[is.na(out$pop_equal)] <- 0
out <- out[out$zip %in% names(alloc_tot), ]  # ZIP 内一个 block 都没分配上：不给份额，包内回退客户数加权
tot <- as.numeric(alloc_tot[out$zip])
out$pop_share <- round(out$pop_small / tot, 6)
out$pop_share_equal <- round(out$pop_equal / tot, 6)
out$zcta_pop <- as.numeric(zip_pop[out$zip])
out$assigned_frac <- round(tot / out$zcta_pop, 6)
out$overlap_frac <- round(as.numeric(overlap_pop[out$zip]) / tot, 6)
out <- out[order(out$zip, out$eiaid),
           c("zip", "eiaid", "pop_share", "pop_share_equal", "zcta_pop", "assigned_frac", "overlap_frac")]

con <- gzfile("inst/extdata/zip_utility_share_slim.csv.gz", "wt")
utils::write.csv(out, con, row.names = FALSE)
close(con)

z <- unique(out[c("zip", "assigned_frac", "overlap_frac")])
cat(sprintf(paste0("multi-utility zips %d | with shares %d | rows %d | median assigned_frac %.3f | ",
                   "zips with assigned_frac < 0.5: %d | median overlap_frac %.3f | zips fully in overlap: %d\n"),
            length(target_zips), nrow(z), nrow(out), stats::median(z$assigned_frac),
            sum(z$assigned_frac < 0.5), stats::median(z$overlap_frac), sum(z$overlap_frac >= 0.999)))
