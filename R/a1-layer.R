# A1 (EIA-861) 年度层内部 API（exp#36；W0 起只答州）。
# slim 组装：data-raw/assemble_861_slim.R（一次性下载 + Bundled/Part A + O 优先去重）。
#
# 口径（W0，2026-11）：
#   price      = 该州全部居民 utility 的客户加权均价（= eia861_state_annual 的同一定义）
#   price_min  = 该州最便宜的居民 utility 年价（只看居民客户 >= 100 户的 utility）
#   price_max  = 该州最贵的居民 utility 年价（同上）
#   n_utility  = 参与 price 的 utility 行数；n_utility_in_range = 参与 min/max 的行数
# 2026-11-17：min/max 曾被个位数客户的实体带偏（MI 2023 Sunnova 1 户 285 c/kWh，
# NM 2024 Tesla 3 户 2.69），所以范围只取 >= .range_customer_floor 户的 utility；
# 客户加权均价不受影响（这些实体的权重本来就可忽略），仍用全部行。
# 后三者是**描述性**的：它们声明"州值离某个 ZIP 的真实价可能有多远"，不参与任何加权。
# ZIP 内的人口份额混合（v1 的 .zip_shares / weight_basis / share_overlap_frac）已删除：
# 见 docs/confidence-plan.md 的 D1。

.annual_slim <- local({
  m <- NULL
  function() {
    if (is.null(m)) {
      path <- system.file("extdata", "eia861_annual_slim.csv.gz", package = "lifewatt")
      if (!nzchar(path)) {
        stop("EIA-861 annual slim not shipped: inst/extdata/eia861_annual_slim.csv.gz missing.", call. = FALSE)
      }
      m <<- utils::read.csv(path, colClasses = c(eiaid = "character"))
    }
    m
  }
})

.annual_years <- function() sort(unique(.annual_slim()$year))

## 该州某年的居民 utility 行（排除 EIA 的 "Adjustment YYYY" 伪 utility 99999，
## 以及价格/客户数不可用的行）——price 与 min/max 必须取自同一个集合，否则两者不可比
.range_customer_floor <- 100L

.state_utility_rows <- function(state, year) {
  slim <- .annual_slim()
  s <- slim[slim$year == year & slim$state == state & slim$eiaid != "99999" &
              is.finite(slim$price) & slim$price > 0, ]
  s[is.finite(s$cus) & s$cus > 0, ]
}

.state_annual_price <- function(state, year) {
  state <- .state_code(state)
  if (length(year) != 1L) stop("year expects exactly one integer year.", call. = FALSE)
  y_num <- suppressWarnings(as.numeric(year))
  if (!is.finite(y_num) || y_num != trunc(y_num)) {
    stop(sprintf("year expects a whole year such as 2024 (got %s).", format(year)), call. = FALSE)
  }
  year <- as.integer(y_num)
  avail <- .annual_years()
  if (!year %in% avail) {
    hint <- if (year >= 2010L && year <= max(avail)) sprintf(paste0(
      " The state annual price alone is available as price_features(\"%s\", period = \"%d-01\")$annual_price."),
      state, year) else ""
    stop(sprintf(
      "No utility-level EIA-861 annual price for %d (available: %s; only final EIA releases are shipped, so not 2026).%s Monthly prices back to 2010 are in price_features().",
      year, paste(avail, collapse = "/"), hint), call. = FALSE)
  }
  s <- .state_utility_rows(state, year)
  if (nrow(s) == 0L) {
    stop(sprintf("No priced EIA-861 utility in %s for %d.", state, year), call. = FALSE)
  }
  r <- s[s$cus >= .range_customer_floor, ]
  if (nrow(r) == 0L) r <- s
  data.frame(
    state = state,
    year = year,
    price = stats::weighted.mean(s$price, s$cus),
    price_min = min(r$price),
    price_max = max(r$price),
    n_utility = nrow(s),
    n_utility_in_range = nrow(r),
    unit = "cents/kWh",
    regime = "observed",
    provisional = FALSE,
    weight_scheme = "residential customers, utility system-wide in the state",
    source = "EIA-861 annual (Bundled/Part A, O-preferring; inst/extdata slim)",
    level = "state",
    degraded_from = NA_character_,
    mapping_vintage = NA_character_,
    confidence_tier = .confidence_tier("B"),
    stringsAsFactors = FALSE,
    row.names = NULL
  )
}
