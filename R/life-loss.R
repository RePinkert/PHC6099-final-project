# expected_life_loss() —— UX 契约正门（exp#34 MVP）
# 2026-10-16 mock 意向：time 给出对应时点的预估电费（实测 B1 <= 2026-07 / LSTM 预测 > 2026-07），
# bill 是贝叶斯证据，默认不填充。诚实契约（HANDOVER 2026-11-18 隔离记录）：
#   delta_le 在弹性来源核实之前只能以调用方显式敏感度参数存在（输出带 sensitivity_assumption 列）；
#   EIA-112 (C1) 机制列 exp#39 已接线（State Total 口径 per-1k；覆盖 2024，窗口外 NA + 注记）。
#   exp#40 弹性核实结论：无美国 ZIP 级"电价->ΔLE"直接弹性；sensitivity_assumption 附文献区间引注：
#     Richardson E, McCartney G, Taulbut M, et al. BMJ Public Health 2023;1:e000097
#       （苏格兰生活成本冲击情景建模：LE -0.7..-1.6y 全人群 / -1.0..-2.7y 最贫困五分位；
#         口径=能源价格通胀冲击，非单位电价弹性）
#     Chirakijja J, Jayachandran S, Ong P. NBER WP 25681 (2019), doi:10.3386/w25681
#       （美国供暖价->冬季死亡方向一致证据，量级=年避 1.1 万冬季死亡；非 LE 换算）

.nchs_anchor <- function() {
  path <- system.file("extdata", "nchs_life_tables.csv", package = "lifewatt")
  if (!nzchar(path)) {
    stop("NCHS anchor not shipped: inst/extdata/nchs_life_tables.csv missing.", call. = FALSE)
  }
  utils::read.csv(path, colClasses = c(year = "integer", e0 = "numeric", sex = "character",
                                       source = "character"))
}

## D2 锚路由：取 <= 目标年的最新全国 e0；目标年早于表首则退回表首行（调用方须见 fallback 注记）
.anchor_for <- function(year) {
  a <- .nchs_anchor()
  hit <- a[a$sex == "total" & a$year <= year, ]
  if (nrow(hit) == 0L) hit <- a[a$sex == "total", ][1L, ]
  hit[which.max(hit$year), ]
}

## bill 证据合成（exp#34 假设：bill+usage = 局部测量 -> 反方差合成后验；bill 单独 = 描述性证据）
.bill_evidence <- function(price, price_sd, bill, usage, meas_sd = 1) {
  if (!is.numeric(price) || length(price) != 1L || !is.finite(price) || price <= 0) {
    stop("price must be a positive finite number (cents/kWh) before evidence can be combined.",
         call. = FALSE)
  }
  has_bill <- !is.null(bill)
  has_usage <- !is.null(usage)
  if (!has_bill && !has_usage) {
    return(list(regime = "none", price_meas = NA_real_, posterior = NULL,
                posterior_sd = NULL, implied_usage = NA_real_, note = ""))
  }
  if (has_usage && !has_bill) {
    stop("usage without bill is not evidence: rerun with bill (USD/month) supplied.", call. = FALSE)
  }
  if (!is.numeric(bill) || length(bill) != 1L || !is.finite(bill) || bill <= 0) {
    stop("bill must be a positive number (USD/month).", call. = FALSE)
  }
  if (has_usage && (!is.numeric(usage) || length(usage) != 1L || !is.finite(usage) || usage <= 0)) {
    stop("usage must be a positive number (kWh/month).", call. = FALSE)
  }
  implied <- bill * 100 / price
  if (!has_usage) {
    return(list(regime = "descriptive", price_meas = NA_real_, posterior = NULL,
                posterior_sd = NULL, implied_usage = implied,
                note = "bill alone: implied usage only, no posterior (declared contract)"))
  }
  p_meas <- bill * 100 / usage
  # 合理性：美国住宅电价（EIA-861 utility 年价）几乎全在 1..100 cents/kWh；
  # 超出 [1, 150] 的局部测量多半是单位或位数错误，拒绝而不是把它当证据
  if (p_meas < 1 || p_meas > 150) {
    stop(sprintf(paste0("bill / usage implies %.1f cents/kWh, outside the plausible 1..150 range; ",
                        "check units (bill in USD per month, usage in kWh per month)."), p_meas),
         call. = FALSE)
  }
  if (is.finite(price_sd)) {
    w_m <- 1 / meas_sd^2
    w_p <- 1 / price_sd^2
    pm <- (w_m * p_meas + w_p * price) / (w_m + w_p)
    ps <- sqrt(1 / (w_m + w_p))
    list(regime = "posterior", price_meas = p_meas, posterior = pm, posterior_sd = ps,
         implied_usage = implied,
         note = sprintf("inverse-variance blend, declared meas_sd=%.4f cents/kWh", meas_sd))
  } else {
    # 实测月份没有先验 sd，无从合成：本地测量只放 price_meas，后验列留空，免得把用户自报值叫"后验"
    list(regime = "measured_local", price_meas = p_meas, posterior = NULL,
         posterior_sd = NULL, implied_usage = implied,
         note = paste0("observed regime: no posterior (the measured state price has no prior sd); ",
                       "the local measurement is in price_meas"))
  }
}

#' Expected life expectancy loss for a ZIP code at a month
#'
#' Returns the electricity-price estimate at a time point (observed B1 state price for
#' months up to 2026-07, LSTM forecast afterwards), combined with the user
#' bill as Bayesian evidence and (optionally) a life-expectancy loss estimate.
#' Without `delta_le` the loss columns are withheld: no sourced US ZIP-level
#' price-to-life-expectancy elasticity exists yet (HANDOVER quarantine contract,
#' 2026-11-18; exp#40 literature check). The `sensitivity_assumption` column
#' carries the closest sourced context: Richardson et al. (BMJ Public Health
#' 2023;1:e000097) energy-cost-shock LE scenario band (-0.7 to -1.6 years
#' population / -1.0 to -2.7 most deprived) and Chirakijja et al. (NBER WP
#' 25681, 2019) US heating-price winter-mortality direction evidence.
#'
#' @param zipcode A character or numeric US ZIP code.
#' @param time A month ("YYYY-MM", "YYYY/M", "YYYY/MM" or Date); exactly one value.
#' @param bill Optional monthly electricity bill in USD; Bayesian evidence (default: unset).
#' @param usage Optional monthly usage in kWh; together with `bill` it forms a local
#'   price measurement that is inverse-variance blended into a posterior (predicted
#'   regime) or reported as a local measurement (observed regime).
#' @param delta_le Optional declared life-expectancy shift in years (caller-supplied
#'   sensitivity parameter; negative = gain). Not sourced yet.
#' @param meas_sd Declared sd of the local price measurement (cents/kWh).
#' @return A one-row data.frame with price/implied-usage/bill-evidence columns, the
#'   NCHS national anchor, provenance columns (source/level/degraded_from/
#'   mapping_vintage/provisional), C1 disconnection mechanism columns
#'   (per-1k rates, Form EIA-112 2024 State Total; NA outside 2024) and a
#'   `sensitivity_assumption` declaration column.
#' @export
#'
#' @examples
#' \dontrun{
#' expected_life_loss("32601", "2026-07")
#' expected_life_loss("32601", "2026-12", bill = 180, usage = 1200)
#' expected_life_loss("32601", "2026-12", delta_le = 0.01)
#' }
expected_life_loss <- function(zipcode, time, bill = NULL, usage = NULL,
                               delta_le = NULL, meas_sd = 1) {
  base <- .price_at(zipcode, time)
  if (!is.numeric(meas_sd) || length(meas_sd) != 1L || !is.finite(meas_sd) || meas_sd <= 0) {
    stop("meas_sd must be a positive number (declared measurement sd, cents/kWh).", call. = FALSE)
  }
  ev <- .bill_evidence(base$price, base$price_sd, bill, usage, meas_sd)

  if (!is.null(delta_le) && (!is.numeric(delta_le) || length(delta_le) != 1L || !is.finite(delta_le))) {
    stop("delta_le must be a finite number of years (caller-declared sensitivity parameter).",
         call. = FALSE)
  }
  yr <- as.integer(substr(base$period, 1L, 4L))
  anchor <- .anchor_for(yr)
  anchor_note <- if (anchor$year != yr) sprintf(
    "time year %d outside anchor table; fell back to %d (%s available)", yr, anchor$year,
    if (anchor$year > yr) "earliest" else "latest") else ""

  if (is.null(delta_le)) {
    le_years <- NA_real_
    le_pct <- NA_real_
    assumption <- paste0(
      "delta_le not supplied: LE-loss columns withheld (no sourced elasticity yet; declared 2026-11-18 contract). ",
      "Literature band (context only, not a price elasticity): LE -0.7 to -1.6 years population / -1.0 to -2.7 most deprived ",
      "under an energy-cost inflation shock (Richardson et al., BMJ Public Health 2023;1:e000097); ",
      "US heating-price winter-mortality direction evidence: Chirakijja et al., NBER WP 25681 (2019)"
    )
  } else {
    le_years <- delta_le
    le_pct <- delta_le / anchor$e0 * 100
    assumption <- sprintf(
      paste0(
        "delta_le = %.4f years is a caller-declared sensitivity parameter (not a sourced elasticity); negative = gain. ",
        "Literature band (context only): LE -0.7 to -1.6 years population / -1.0 to -2.7 most deprived under an energy-cost ",
        "inflation shock (Richardson et al., BMJ Public Health 2023;1:e000097); ",
        "US heating-price winter-mortality direction evidence: Chirakijja et al., NBER WP 25681 (2019)"
      ),
      delta_le
    )
  }

  notes <- c(
    .c1_note(base$state, base$period),
    if (nzchar(anchor_note)) anchor_note else character(0),
    ev$note
  )

  out <- base
  out$bill <- if (is.null(bill)) NA_real_ else bill
  out$usage_kwh <- if (is.null(usage)) NA_real_ else usage
  out$price_meas <- ev$price_meas
  out$evidence_regime <- ev$regime
  out$price_posterior <- if (is.null(ev$posterior)) NA_real_ else ev$posterior
  out$price_posterior_sd <- if (is.null(ev$posterior_sd)) NA_real_ else ev$posterior_sd
  out$implied_usage_kwh <- ev$implied_usage
  out$e0_anchor_year <- as.integer(anchor$year)
  out$e0_anchor <- anchor$e0
  out$e0_source <- anchor$source
  out$le_loss_years <- le_years
  out$le_loss_pct_of_anchor <- le_pct
  out$sensitivity_assumption <- assumption
  c1 <- .c1_at(base$state, base$period)
  out$c1_final_notices_per_1k <- c1$c1_final_notices_per_1k
  out$c1_disconnections_per_1k <- c1$c1_disconnections_per_1k
  out$c1_reconnections_per_1k <- c1$c1_reconnections_per_1k
  out$c1_res_customers <- c1$c1_res_customers
  out$c1_source <- c1$c1_source
  out$notes <- paste(notes, collapse = " | ")
  row.names(out) <- NULL
  out
}
