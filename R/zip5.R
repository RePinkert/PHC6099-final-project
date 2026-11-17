# zip5.R —— ZIP 归一化（只服务 health_measure()）
#
# 2026-11-17 决定：面向用户的 zip_to_state() 删除——受访者知道自己的州，而价格/寿命层
# 本来就是州级的（任何 ZIP 都只会拿到同一个州级数字），所以 ZIP→州 映射没有用户价值。
# 随之退场：A2 OpenEI 映射（inst/extdata/openei_zip2state_slim.csv.gz，232 KB）与
# data-raw/assemble_openei_slim.R。包内不再保留任何 ZIP→州 的映射。
#
# 本文件只剩一件事：把用户写的 ZIP 归一化成 5 位数字，供 CDC PLACES 按 ZCTA 查询。
# 归一化规则不变：前导零必须显式写出、ZIP+4 截断、歧义形状拒绝、不静默改写。

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
