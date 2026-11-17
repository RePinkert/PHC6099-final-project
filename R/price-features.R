# price-features.R —— 面向用户的「价格特征」与「滞后矩阵」（2026-11-17 解冻）
#
# 这两个函数一直挂在设计稿的"未落地"清单上（candidate-list §包结构「设计稿里没有落地的部分」：
# `price_features()` / `lag_matrix()` 未落地为导出；滚动/滞后统计内联在价格与 LE 两个 LSTM 前向里）。
# 2026-11-17 解冻：算力本来就在包里——`.lstm_predict()` 的 36 月输入窗就是这么拼出来的
# （训练侧同口径见 model_traning/prepare.R）。把同一批计算以**普通用户看得懂的单位**交还给用户：
# 不用懂 z-score / min-max / mask / age，也能拿到"这个州这个月多少钱、最近三个月典型多少、
# 跟去年同月比涨了多少、现在处在年度什么位置"。
#
# 口径纪律（沿用本包一贯做法）：
#   · 全部是**实测**（EIA-861M 零售销售），不是模型输出——预测区间在
#     `expected_life_loss()` / `my_electricity()` 的 `price_lo`/`price_hi` 上，这里不重复给区间；
#   · 单位一律 cents/kWh 与 %，不出现研究口径的字符串；
#   · 每行带 provenance 五列（source/level/degraded_from/mapping_vintage/provisional）；
#   · provisional 逐月随行（EIA 标 Preliminary 的月份），不合并成"总体临时"标签；
#   · 数据窗口 = 随包 price_history_slim（2010-01..2026-07），与 B1 cache 重叠段逐位相同（实测差 0）。

## 州×年客户加权年价（EIA-861 state annual，2010..2025）：用作"这个月处在年度什么位置"的基准
.state_annual_prices <- local({
  cached <- NULL
  function() {
    if (!is.null(cached)) return(cached)
    path <- system.file("extdata", "eia861_state_annual.csv.gz", package = "lifewatt")
    if (!nzchar(path)) {
      stop("state annual table not shipped: inst/extdata/eia861_state_annual.csv.gz missing.",
           call. = FALSE)
    }
    d <- utils::read.csv(path, colClasses = c(state = "character", year = "integer", price = "numeric"))
    sts <- sort(unique(d$state))
    yrs <- sort(unique(d$year))
    m <- matrix(NA_real_, length(sts), length(yrs), dimnames = list(sts, yrs))
    m[cbind(match(d$state, sts), match(d$year, yrs))] <- d$price
    cached <<- m
    m
  }
})

## 某个月的"年度参考价"：该州该年的客户加权年价；2026 年尚未发布 -> NA（不拿邻年顶替）
.annual_price_for <- function(state, period) {
  yr <- as.integer(substr(period, 1L, 4L))
  A <- .state_annual_prices()
  if (!state %in% rownames(A) || !as.character(yr) %in% colnames(A)) return(NA_real_)
  unname(A[state, as.character(yr)])
}

## 尾部均值 / 尾部斜率：只用实测月；窗口不足则 NA（不用更短的窗口悄悄顶替）
.tail_mean <- function(x, k) if (length(x) < k) NA_real_ else mean(x[(length(x) - k + 1L):length(x)])
.tail_slope <- function(x, k) {
  n <- length(x)
  if (n < k) return(NA_real_)
  y <- x[(n - k + 1L):n]
  t <- seq_len(k)
  denom <- sum((t - mean(t))^2)
  if (denom == 0) return(NA_real_)
  sum((t - mean(t)) * (y - mean(y))) / denom
}

#' Recent price history for a state, in plain units
#'
#' Returns what a household would want to know about its state's recent
#' residential electricity prices: the price itself, the typical price over the
#' last 3 / 6 / 12 months, the change against the previous month and against
#' the same month a year earlier, the recent trend, and where the month sits
#' relative to the state's annual average price.
#'
#' Every number is **observed** (EIA-861M retail sales, shipped panel
#' 2010-01..2026-07), not a model output: the forecast and its interval live
#' in [expected_life_loss()] / [my_electricity()] (`price_lo` / `price_hi`).
#' Months EIA marks Preliminary are flagged row by row in `provisional`.
#'
#' The trailing averages, changes and trend are computed from observed months
#' only, and are `NA` when the window is not fully covered by the shipped
#' panel (they are never shortened silently). `annual_price` is the state's
#' customer-weighted EIA-861 annual price and is `NA` for years EIA has not
#' released yet (2026 at the time of writing).
#'
#' @param state A two-letter USPS state code (`"FL"`) or a full state name.
#' @param period A single month (`"YYYY-MM"`); returns one row. Mutually
#'   exclusive with `from`/`to`.
#' @param from,to An optional month range (`"YYYY-MM"`). `from` defaults to
#'   `to` minus 11 months.
#' @return A data.frame with one row per month: `price`, `avg_3m`, `avg_6m`,
#'   `avg_12m`, `change_1m`, `change_1m_pct`, `change_12m`,
#'   `change_12m_pct`, `trend_12m` (cents/kWh per month, straight-line slope
#'   over the trailing 12 months), `annual_price`, `price_vs_annual_pct`
#'   (percent above/below the annual price), the provenance columns
#'   (`source`/`level`/`degraded_from`/`mapping_vintage`/`provisional`) and
#'   `imputed` (TRUE if the assembler filled the cell).
#' @seealso [lag_matrix()], [electricity_price()]
#' @export
#'
#' @examples
#' \dontrun{
#' price_features("FL")                       # the last 12 months
#' price_features("FL", period = "2026-07")   # one month
#' price_features("FL", from = "2024-01", to = "2024-12")
#' }
price_features <- function(state, period = NULL, from = NULL, to = NULL) {
  state <- .state_code(state)
  Ph <- .price_history_wide()
  if (!state %in% rownames(Ph)) {
    stop(sprintf("state %s is outside the shipped price history coverage.", state), call. = FALSE)
  }
  months <- colnames(Ph)
  if (!is.null(period) && (!is.null(from) || !is.null(to))) {
    stop("give either period or a from/to range, not both.", call. = FALSE)
  }
  if (!is.null(period)) {
    per <- .month_key(period)
    if (!per %in% months) {
      stop(sprintf("month %s is outside the shipped price history (%s..%s).", per, months[1], months[length(months)]),
           call. = FALSE)
    }
    sel <- match(per, months)
  } else {
    to_m <- if (is.null(to)) months[length(months)] else .month_key(to)
    if (!to_m %in% months) {
      stop(sprintf("month %s is outside the shipped price history (%s..%s).", to_m, months[1], months[length(months)]),
           call. = FALSE)
    }
    j <- match(to_m, months)
    if (is.null(from)) {
      from_m <- months[max(1L, j - 11L)]
    } else {
      from_m <- .month_key(from)
      if (!from_m %in% months) {
        stop(sprintf("month %s is outside the shipped price history (%s..%s).", from_m, months[1], months[length(months)]),
             call. = FALSE)
      }
    }
    i <- match(from_m, months)
    if (i > j) stop("from must not be after to.", call. = FALSE)
    sel <- i:j
  }
  p <- Ph[state, sel]
  n <- length(sel)
  idx <- sel
  pull <- function(k) {
    v <- rep(NA_real_, n)
    ok <- idx - k >= 1L
    v[ok] <- Ph[state, idx[ok] - k]
    v
  }
  avg3 <- avg6 <- avg12 <- NA_real_
  chg1 <- chg1p <- chg12 <- chg12p <- slope <- NA_real_
  for (i in seq_len(n)) {
    k <- idx[i]
    hist <- Ph[state, 1:k]
    avg3[i] <- .tail_mean(hist, 3)
    avg6[i] <- .tail_mean(hist, 6)
    avg12[i] <- .tail_mean(hist, 12)
    slope[i] <- .tail_slope(hist, 12)
    if (k >= 2L) {
      chg1[i] <- Ph[state, k] - Ph[state, k - 1L]
      chg1p[i] <- chg1[i] / Ph[state, k - 1L] * 100
    }
    if (k >= 13L) {
      chg12[i] <- Ph[state, k] - Ph[state, k - 12L]
      chg12p[i] <- chg12[i] / Ph[state, k - 12L] * 100
    }
  }
  per <- months[sel]
  ann <- vapply(per, function(pp) .annual_price_for(state, pp), numeric(1))
  vsann <- ifelse(is.finite(ann) & ann > 0, (p - ann) / ann * 100, NA_real_)
  fr <- .price_history_frame()
  st <- matrix(NA_character_, nrow(Ph), ncol(Ph), dimnames = dimnames(Ph))
  im <- matrix(NA, nrow(Ph), ncol(Ph), dimnames = dimnames(Ph))
  st[cbind(match(fr$state, rownames(Ph)), match(fr$period, colnames(Ph)))] <- fr$data_status
  im[cbind(match(fr$state, rownames(Ph)), match(fr$period, colnames(Ph)))] <- fr$imputed
  prov <- st[state, sel] == "Preliminary"
  imp <- im[state, sel] == 1L
  note <- ifelse(!is.finite(ann),
                 "no annual reference for this year yet (EIA has not released it); the other columns are unaffected",
                 "")
  data.frame(
    state = state,
    period = per,
    price = p,
    avg_3m = avg3,
    avg_6m = avg6,
    avg_12m = avg12,
    change_1m = chg1,
    change_1m_pct = chg1p,
    change_12m = chg12,
    change_12m_pct = chg12p,
    trend_12m = slope,
    annual_price = ann,
    price_vs_annual_pct = vsann,
    provisional = prov,
    imputed = imp,
    confidence_tier = .confidence_tier("B"),
    source = "EIA-861M retail sales monthly (B1 panel; inst/extdata price history slim)",
    level = "state",
    degraded_from = NA_character_,
    mapping_vintage = NA_character_,
    notes = note,
    stringsAsFactors = FALSE,
    row.names = NULL
  )
}

#' Price history with past months side by side
#'
#' Returns the state's monthly price together with its previous months, one
#' column per lag, so a household (or anyone building their own analysis) can
#' see the shape of the series without re-deriving it: `price_now` is the
#' price of the month itself, `price_1m_ago` the month before it, and so on.
#'
#' All values are **observed** (EIA-861M retail sales, shipped panel
#' 2010-01..2026-07). Months EIA marks Preliminary are flagged row by row in
#' `provisional`. A lag that reaches before the start of the shipped panel is
#' `NA` — it is not filled from another source.
#'
#' @param states Optional vector of state codes or names; default is every
#'   state in the shipped panel.
#' @param from,to An optional month range (`"YYYY-MM"`). `from` defaults to
#'   `to` minus the longest requested lag, so that every lag is populated.
#' @param lags Whole numbers of months to go back; default `0:12`.
#' @return A data.frame with one row per state and month: `price_now` and one
#'   `price_<n>m_ago` column per lag, plus `provisional` and the provenance
#'   columns (`source`/`level`/`degraded_from`/`mapping_vintage`).
#' @seealso [price_features()], [electricity_price()]
#' @export
#'
#' @examples
#' \dontrun{
#' lag_matrix("FL")                                  # last 13 months, 12 lags
#' lag_matrix(c("FL", "NC"), lags = 0:6)
#' lag_matrix("FL", from = "2025-01", to = "2025-12")
#' }
lag_matrix <- function(states = NULL, from = NULL, to = NULL, lags = 0:12) {
  if (!is.numeric(lags) || any(!is.finite(lags)) || any(lags < 0) || any(lags != floor(lags))) {
    stop("lags must be whole numbers of months (0 or more).", call. = FALSE)
  }
  lags <- sort(unique(as.integer(lags)))
  Ph <- .price_history_wide()
  months <- colnames(Ph)
  sts <- if (is.null(states)) rownames(Ph) else vapply(states, function(s) .state_code(s), character(1))
  miss <- setdiff(sts, rownames(Ph))
  if (length(miss)) {
    stop(sprintf("state(s) outside the shipped price history coverage: %s.", paste(miss, collapse = ", ")),
         call. = FALSE)
  }
  to_m <- if (is.null(to)) months[length(months)] else .month_key(to)
  if (!to_m %in% months) {
    stop(sprintf("month %s is outside the shipped price history (%s..%s).", to_m, months[1], months[length(months)]),
         call. = FALSE)
  }
  j <- match(to_m, months)
  if (is.null(from)) {
    from_m <- months[max(1L, j - max(lags))]
  } else {
    from_m <- .month_key(from)
    if (!from_m %in% months) {
      stop(sprintf("month %s is outside the shipped price history (%s..%s).", from_m, months[1], months[length(months)]),
           call. = FALSE)
    }
  }
  i <- match(from_m, months)
  if (i > j) stop("from must not be after to.", call. = FALSE)
  sel <- i:j
  per <- months[sel]
  fr <- .price_history_frame()
  st <- matrix(NA_character_, nrow(Ph), ncol(Ph), dimnames = dimnames(Ph))
  st[cbind(match(fr$state, rownames(Ph)), match(fr$period, colnames(Ph)))] <- fr$data_status
  out <- list()
  for (s in sts) {
    d <- data.frame(state = s, period = per, stringsAsFactors = FALSE)
    for (lag in lags) {
      nm <- if (lag == 0L) "price_now" else sprintf("price_%dm_ago", lag)
      v <- rep(NA_real_, length(sel))
      ok <- sel - lag >= 1L
      v[ok] <- Ph[s, sel[ok] - lag]
      d[[nm]] <- v
    }
    d$provisional <- st[s, sel] == "Preliminary"
    out[[length(out) + 1L]] <- d
  }
  res <- do.call(rbind, out)
  res$source <- "EIA-861M retail sales monthly (B1 panel; inst/extdata price history slim)"
  res$level <- "state"
  res$degraded_from <- NA_character_
  res$mapping_vintage <- NA_character_
  rownames(res) <- NULL
  res
}
