# assemble_price_history_slim.R —— 价格 LSTM 特征所需的历史电价面（2020-01..2026-07）
# 来源：data-raw/eia_json/*.json（EIA API 住宅月度价，51 州，2001-01 起）
# 产物：inst/extdata/price_history_slim.csv.gz (state, period, price, imputed)
# 用途：仅供 R/price-lstm.R 特征构造（观测供给契约不变：served observed = 2023-01..2026-07
#       的 b1_monthly_cache）；声明窗口 2023-01..2026-12 不因此扩展。
# imputed=1 为源缺口线性插补格（训练侧 prepare.R 同口径）。

states <- c(state.abb, "DC")
months <- sprintf("%04d-%02d", rep(2001:2026, each = 12), rep(1:12, 26))
months <- months[months <= "2026-07"]

P <- matrix(NA_real_, length(states), length(months), dimnames = list(states, months))
for (i in seq_along(states)) {
  j <- jsonlite::fromJSON(file.path("data-raw", "eia_json", paste0(states[i], ".json")))
  d <- j$response$data
  idx <- match(d$period, months)
  pv <- suppressWarnings(as.numeric(d$price))
  ok <- !is.na(idx) & is.finite(pv)
  P[i, idx[ok]] <- pv[ok]
}

imputed <- matrix(FALSE, nrow(P), ncol(P), dimnames = dimnames(P))
for (i in seq_len(nrow(P))) {
  x <- P[i, ]
  if (all(is.finite(x))) next
  na <- which(!is.finite(x))
  fin <- which(is.finite(x))
  runs <- split(na, cumsum(c(1, diff(na) != 1)))
  for (r in runs) {
    if (length(r) > 3 || min(r) < min(fin) || max(r) > max(fin)) {
      stop(sprintf("unfillable price gap for %s at %s", states[i], paste(months[r], collapse = ",")))
    }
    x[r] <- stats::approx(fin, x[fin], xout = r)$y
    imputed[i, r] <- TRUE
  }
  P[i, ] <- x
}
stopifnot(all(is.finite(P)))

keep <- months >= "2020-01"
out <- data.frame(
  state = rep(states, each = sum(keep)),
  period = rep(months[keep], times = length(states)),
  price = as.numeric(t(P[, keep])),
  imputed = as.integer(t(imputed[, keep])),
  stringsAsFactors = FALSE
)
utils::write.csv(out, gzfile("inst/extdata/price_history_slim.csv.gz"), row.names = FALSE)
cat("wrote inst/extdata/price_history_slim.csv.gz:", nrow(out), "rows",
    sum(out$imputed), "imputed cells\n")
