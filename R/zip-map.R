# A2 (OpenEI 2024 vintage, CC-BY-4.0) ZIP -> state resolver.
#
# W0 起（2026-11）：**州是这个文件唯一被使用的产物**。
# v1 的 `.zip_state()` 还做了一件额外的事——用客户数（或等权）在 ZIP 的多个 utility 间
# 加权，用来"选州"。但 A2 2024 中不存在跨州多 utility 的 ZIP（实测 15,331 个多 utility ZIP
# 全部同州），所以这套权重从未改变过任何下游数值；它只增加了三样东西：一份需要随包的
# 人口份额表、一个从未被验证的重叠裁决规则、以及一个会让读者以为"ZIP 级加权"存在的列。
# 这些在 W0 一并删除，ZIP 只剩"查州"一个用途，对外入口是 `zip_to_state()`。

.open_map <- local({
  m <- NULL
  function() {
    if (is.null(m)) {
      path <- system.file("extdata", "openei_zip2state_slim.csv.gz", package = "lifewatt")
      if (!nzchar(path)) {
        stop("OpenEI mapping not shipped: inst/extdata/openei_zip2state_slim.csv.gz missing.", call. = FALSE)
      }
      m <<- unique(utils::read.csv(path, colClasses = "character"))
    }
    m
  }
})

## 严格归一化：5 位数字（前导零必须显式）或 ZIP+4；歧义形状拒绝，不静默改写
.zip5 <- function(zip) {
  if (is.null(zip) || is.list(zip) || length(zip) != 1L) {
    stop("Invalid zip: expects exactly one value (5-digit ZIP or ZIP+4).", call. = FALSE)
  }
  if (is.na(zip)) {
    stop("Invalid zip: NA is not a ZIP code.", call. = FALSE)
  }
  z <- if (is.numeric(zip)) {
    if (!is.finite(zip) || zip != trunc(zip)) {
      stop(sprintf("Invalid zip: %s (numeric zip must be a whole number).", format(zip)), call. = FALSE)
    }
    format(zip, scientific = FALSE, trim = TRUE)
  } else {
    trimws(as.character(zip))
  }
  if (grepl("^[0-9]{5}-[0-9]{4}$", z) || grepl("^[0-9]{9}$", z)) z <- substr(z, 1L, 5L)
  if (!grepl("^[0-9]{5}$", z)) {
    stop(sprintf("Invalid zip '%s': expected 5 digits (leading zeros required, e.g. '01002') or ZIP+4.", z),
         call. = FALSE)
  }
  z
}

## ZIP -> 该 ZIP 的 utility 记录（OpenEI 2024）；州与 utility 名都来自这里
.zip_lookup <- function(zip) {
  m <- .open_map()
  hit <- m[m$zip == .zip5(zip), ]
  if (nrow(hit) == 0L) {
    stop(sprintf("No electric utility record for zip %s (OpenEI 2024 mapping).", zip),
         call. = FALSE)
  }
  hit[order(hit$eiaid, hit$utility_name), ]
}

## 解析结果（内部）：州 + 该 ZIP 的 utility 记录。不做任何加权。
.zip_resolve <- function(zip) {
  hit <- .zip_lookup(zip)
  st <- unique(hit$state)
  if (length(st) != 1L) {
    stop(sprintf("ZIP %s maps to %d states in the OpenEI 2024 mapping; refusing to pick one.",
                 .zip5(zip), length(st)), call. = FALSE)
  }
  list(zip = .zip5(zip), state = st, n_utility = nrow(hit),
       utilities = hit, mapping_vintage = "2024")
}

#' State of a US ZIP code
#'
#' `lifewatt` prices and life-expectancy estimates are state-level: the only
#' free, nationally complete residential electricity price data are published by
#' utility (EIA-861) and by state (EIA-861M), and no source publishes a realised
#' average price per ZIP code. `zip_to_state()` is therefore the only ZIP-facing
#' entry point of the price layer: it maps a ZIP to the state that serves it, and
#' every function that reports a price takes that state directly.
#'
#' This is a lookup, not an estimate. No price, no interval and no weighting
#' depends on the ZIP: every ZIP in a state returns identical state-level values.
#' The returned `n_utility` is the number of utilities the OpenEI 2024 mapping
#' assigns to the ZIP, reported because it is the only ZIP-specific fact the
#' mapping carries.
#'
#' @param zip A character or numeric US ZIP code. Five digits are required
#'   (leading zeros must be written out, `"01002"`); ZIP+4 and 9-digit forms are
#'   accepted and truncated, and ambiguous shapes are refused.
#' @return A one-row data.frame with `zip` (normalised five digits), `state`
#'   (two-letter USPS code), `mapping_vintage` (OpenEI release, `"2024"`) and
#'   `n_utility` (utilities assigned to the ZIP by that mapping).
#' @seealso [electricity_price()], [expected_life_loss()], [health_measure()]
#'   (the one function that still takes a ZIP, because CDC PLACES publishes by
#'   ZCTA).
#' @export
#'
#' @examples
#' \dontrun{
#' zip_to_state("32601")
#' electricity_price(zip_to_state("32601")$state, year = 2024)
#' }
zip_to_state <- function(zip) {
  r <- .zip_resolve(zip)
  data.frame(
    zip = r$zip,
    state = r$state,
    mapping_vintage = r$mapping_vintage,
    n_utility = r$n_utility,
    stringsAsFactors = FALSE,
    row.names = NULL
  )
}
