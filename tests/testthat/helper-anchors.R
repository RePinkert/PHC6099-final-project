# helper-anchors.R —— 用户场景锚点（testthat 3e 惯例：helper 文件先于所有 test 文件加载）
# 数值锚点由 inst/extdata 数据决定；改 extdata 数据时须同步刷新（见 HANDOVER 第四回合调用留档）。

anchor_zip_fl <- "32601"
anchor_zip_ak <- "99501"
anchor_zip_multi <- "28657"
anchor_zip_single <- "1002"

anchor_price_fl_2026_07 <- 15.03
anchor_price_ak_2023_01 <- 21.73
anchor_e0_2023 <- 78.4
anchor_e0_2024 <- 79.0

# provenance 列契约：每个含数据值的输出行必须携带这四列（HANDOVER 阶段 C 准入标准）
provenance_required <- c("source", "level", "degraded_from", "mapping_vintage")
expect_provenance_cols <- function(df) testthat::expect_contains(names(df), provenance_required)
