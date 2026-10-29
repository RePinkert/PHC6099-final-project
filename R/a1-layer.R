# A1 (EIA-861) 年度层内部 API（exp#36）。
# slim 组装：data-raw/assemble_861_slim.R（一次性下载 + Bundled/Part A + O 优先去重）。
# A1 角色（candidate-list）：ZIP 级年度价格数值的唯一来源；A2 提供映射，mapping_vintage=2024 必须随行声明。
# 加权：residential customers（缺省回退等权并把数量记进 note/coverage 列）。

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

.annual_customers <- local({
  cch <- NULL
  function(eiaid, state) {
    if (is.null(cch)) {
      s <- .annual_slim()
      s <- s[s$cus > 0 & is.finite(s$cus), ]
      s <- s[order(s$year), ]
      cch <<- structure(s$cus, names = paste(s$year, s$eiaid, s$state, sep = "|"))
    }
    # 目标 utility 在该州的最新可得客户数；缺名回落 NA 并继续尝试更早年份（不中断循环）
    yr <- .annual_years()
    hit <- NA_real_
    for (y in rev(yr)) {
      v <- unname(cch[paste(y, eiaid, state, sep = "|")])
      if (length(v) == 1L && !is.na(v)) {
        hit <- v
        break
      }
    }
    hit
  }
})

.zip_annual_price <- function(zip, year) {
  year <- as.integer(year)
  if (length(year) != 1L || is.na(year)) stop("year expects exactly one integer year.", call. = FALSE)
  avail <- .annual_years()
  if (!year %in% avail) {
    stop(sprintf(
      "No vendored EIA-861 annual table for %d (available: %s). 2026 early vintage intentionally not vendored; candidate-list prescribes final releases.",
      year, paste(avail, collapse = "/")), call. = FALSE)
  }
  zl <- .zip_lookup(zip)
  slim <- .annual_slim()[.annual_slim()$year == year, ]
  j <- merge(zl, slim[, c("eiaid", "state", "price", "cus")],
             by = c("eiaid", "state"), all.x = TRUE, sort = FALSE)
  j$price[j$price <= 0] <- NA
  priced <- j[is.finite(j$price), ]
  priced$weight <- ifelse(is.finite(priced$cus) & priced$cus > 0, priced$cus, NA)
  n_equal_fallback <- sum(is.na(priced$weight))
  priced$weight[is.na(priced$weight)] <- 1
  if (nrow(priced) == 0L) {
    stop(sprintf("No priced EIA-861 utility covers zip %s in %d (mapped utilities all lack annual price rows).",
                 .zip5(zip), year), call. = FALSE)
  }
  miss <- zl$utility_name[!zl$eiaid %in% priced$eiaid]
  data.frame(
    zip = .zip5(zip),
    state = zl$state[1],
    year = year,
    price = stats::weighted.mean(priced$price, priced$weight),
    price_min = min(priced$price),
    price_max = max(priced$price),
    unit = "cents/kWh",
    regime = "observed",
    provisional = FALSE,
    n_mapped = nrow(zl),
    n_priced = nrow(priced),
    weight_scheme = paste0("residential customers, utility system-wide in state -- not the within-zip share, ",
                           "which no public source publishes (equal fallback where missing)"),
    min_weight = min(priced$weight),
    max_weight = max(priced$weight),
    equal_fallbacks = n_equal_fallback + (nrow(zl) - nrow(priced)),
    missing_utilities = if (length(miss)) paste(miss, collapse = "; ") else NA_character_,
    source = "EIA-861 annual (Bundled/Part A, O-preferring; inst/extdata slim)",
    level = "utility (customer-weighted to zip)",
    degraded_from = "zip",
    mapping_vintage = "2024",
    confidence_tier = .confidence_tier(if (nrow(priced) == 1L) "A" else "B"),
    stringsAsFactors = FALSE,
    row.names = NULL
  )
}
