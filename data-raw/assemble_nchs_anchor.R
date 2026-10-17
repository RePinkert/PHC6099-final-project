# data-raw/assemble_nchs_anchor.R —— 一次性：D2 全国锚点（NCHS United States Life Tables）随包常量
# 来源（candidate-list D2 节）：
#   2023: e0 = 78.4（NVSR 74/6, 2025-07-15 发布）
#   2024: e0 = 79.0（NVSR 75/5, 2026-08-25 发布）
# 仅全国、总数（sex=total）；窗口内 sub-state 无 LE 数据 —— 这是本包 LE 锚的唯一合法常量。

anchor <- data.frame(
  year = c(2023L, 2024L),
  e0 = c(78.4, 79.0),
  sex = c("total", "total"),
  source = c("NCHS United States Life Tables 2023, NVSR 74/6 (released 2025-07-15)",
             "NCHS United States Life Tables 2024, NVSR 75/5 (released 2026-08-25)")
)
write.csv(anchor, "inst/extdata/nchs_life_tables.csv", row.names = FALSE)
cat("anchor rows:", nrow(anchor), "\n")
