# life_expectancy() —— exp#43 双桩收口定案（life_expectancy_trend() 独立成
# R/life-expectancy-trend.R 按函数分片落地）。
# 证据（exp#42）：D1b/D2 敏感度合成 e0 通过 L1 自检（US m=1 -> Δe1=0 -> e0=锚值精确）且
# 51 州量级合理 -> 按计划实装为**合成估计**（estimate_type 明示，非 NCHS 发布的州级 e0）。
# §E1 命名冲突由此了结：来源是死亡率（VSRR）+生命表（D2），不是患病率冒充 LE。
# 全部合成假设以 sensitivity_assumption 声明（见 mortality-synth.R .synth_method_note）。
# 数据窗口：VSRR 2023Q1..2025Q3（provisional）；D2 锚 2023/2024（2025 回退 2024 + 注记）。

.vsrr_latest_quarter <- function() {
  max(.vsrr_state_cache()$quarter)
}

.quarter_shift <- function(quarter, k) {
  if (!grepl("^[0-9]{4}Q[1-4]$", quarter)) {
    stop(sprintf("Invalid quarter: %s (expects YYYY-Qn).", quarter), call. = FALSE)
  }
  y <- as.integer(substr(quarter, 1L, 4L))
  n <- as.integer(substr(quarter, 6L, 6L))
  t <- y * 4L + (n - 1L) + k
  sprintf("%dQ%d", t %/% 4L, t %% 4L + 1L)
}

#' Synthetic life expectancy for a ZIP code
#'
#' Returns a **synthetic** life-expectancy estimate for the state the ZIP belongs
#' to: the D1b/D2 sensitivity synthesis (internal mortality-synth layer) — the
#' state's mortality index (VSRR age-adjusted rate vs US) applied to the national
#' age pattern, converted through an abridged life table and anchored to the
#' published NCHS national e0. This is a declared-assumption estimate, **not** an
#' NCHS-published subnational life expectancy; every assumption travels in the
#' `sensitivity_assumption` column (estimate_type says "synthetic_e0").
#'
#' @param zip A character or numeric US ZIP code.
#' @param quarter A quarter ("YYYY-Qn"); default: the latest VSRR quarter shipped.
#' @return A one-row data.frame with `e0_synth`, `e0_anchor` (NCHS national),
#'   `delta_e1`, the state mortality index `m_index`, premature-mortality metrics
#'   (`ypll75_per_1k`, `prop_died_before_75`), an `estimate_type` label and full
#'   provenance columns (source/level/degraded_from/mapping_vintage/provisional)
#'   plus the `sensitivity_assumption` declaration.
#' @export
#'
#' @examples
#' \dontrun{
#' life_expectancy("32601")
#' life_expectancy("32601", quarter = "2024Q4")
#' }
life_expectancy <- function(zip, quarter = NULL) {
  if (is.null(quarter)) quarter <- .vsrr_latest_quarter()
  if (!grepl("^[0-9]{4}Q[1-4]$", as.character(quarter))) {
    stop(sprintf("Invalid quarter: %s (expects YYYY-Qn).", quarter), call. = FALSE)
  }
  zs <- .zip_state(zip)
  s <- .le_synth(zs$state, as.character(quarter), "12m")
  data.frame(
    zip = .zip5(zip),
    state = s$state,
    quarter = s$quarter,
    e0_synth = s$e0_synth,
    e0_anchor = s$e0_anchor,
    e0_anchor_year = s$e0_anchor_year,
    delta_e1 = s$delta_e1,
    m_index = s$m_index,
    rate_state_per_100k = s$rate_state_per_100k,
    ypll75_per_1k = s$ypll75_per_1k,
    prop_died_before_75 = s$prop_died_before_75,
    estimate_type = "synthetic_e0 (mortality-based D1b/D2 sensitivity synthesis; not an NCHS-published subnational life expectancy)",
    source = s$source,
    level = s$level,
    degraded_from = "zip",
    mapping_vintage = zs$mapping_vintage,
    provisional = s$provisional,
    sensitivity_assumption = s$sensitivity_assumption,
    notes = paste(c(if (nzchar(s$notes)) s$notes else character(0),
                    if (nzchar(zs$note)) zs$note else character(0)), collapse = " | "),
    stringsAsFactors = FALSE,
    row.names = NULL
  )
}
