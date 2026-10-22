# helper-anchors.R —— 用户场景锚点（testthat 3e 惯例：helper 文件先于所有 test 文件加载）
# 数值锚点由 inst/extdata 数据决定；改 extdata 数据时须同步刷新（见 HANDOVER 第四回合调用留档）。

anchor_zip_fl <- "32601"
anchor_zip_ak <- "99501"
anchor_zip_multi <- "28657"
anchor_zip_single <- "01002"

anchor_price_fl_2026_07 <- 15.03
anchor_price_ak_2023_01 <- 21.73
anchor_e0_2023 <- 78.4
anchor_e0_2024 <- 79.0

# 健康侧锚点（CDC PLACES 2025 release，ZCTA 原生；2026-10-16 实测 data.cdc.gov qnzd-25i4）
anchor_health_diabetes_value <- 7.7
anchor_health_diabetes_low   <- 6.8
anchor_health_diabetes_high  <- 8.7
anchor_health_bphigh_value   <- 24.0
anchor_health_bphigh_low     <- 21.4
anchor_health_bphigh_high    <- 26.9
anchor_health_n_measures_fl  <- 28L   # 32601 实有项；全国口径上限 35，其余 7 项被该 ZCTA 抑制
anchor_health_n_measures_max <- 35L
# 32601 被抑制的 7 项（社会需求类）：EMOTIONSPT FOODINSECU FOODSTAMP HOUSINSECU
# LACKTRPT LONELINESS SHUTUTILITY —— 含 SHUTUTILITY（公用事业断供风险），不可用。

# health_measure() 是唯一走网络取数的接口：用例测试统一以离线 fixture 替换 .places_fetch
read_places_fixture <- function(zip5) {
  utils::read.csv(testthat::test_path("fixtures", "places_32601.csv"), colClasses = "character")
}

# provenance 列契约：每个含数据值的输出行必须携带这四列（HANDOVER 阶段 C 准入标准）
provenance_required <- c("source", "level", "degraded_from", "mapping_vintage", "provisional")
expect_provenance_cols <- function(df) testthat::expect_contains(names(df), provenance_required)
