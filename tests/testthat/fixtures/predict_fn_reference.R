# Dev-only reference implementation of the phase-B triplet predictor.
#
# Contract this file pins (tests/testthat/test-price-model.R):
#   .triplet_predict() must regress 1:1 against this function -- same point
#   estimate, same .sd -- within 1e-10, on the six-state / four-horizon probe.
#
# Provenance: extracted verbatim from autoresearch/train.R version 15
# (= exp#24 triple-mean: mean{lag12 + 12-month drift, v0 + b*h,
# HoltWinters(additive seasonal)}; interval = drift-origin simulation,
# horizon-binned, pooled across states, q85 with the n < 40 fallback).
# The research tree is not part of this repository; this frozen copy is the
# only one the suite needs, so the anchor survives the tree being moved out.
predict_fn <- function(model, test) {
  params <- model$params
  hist <- model$train
  pv <- structure(params$v0, names = params$state)
  pb <- structure(params$b, names = params$state)
  pt <- structure(params$t0, names = params$state)

  prev12 <- format(as.Date(paste0(test$period, "-01")) - 365.25, "%Y-%m")
  key <- paste(hist$state, hist$period)
  base <- structure(hist$price, names = key)

  out <- test[, c("state", "period", "price")]
  tlag <- as.numeric(as.Date(paste0(prev12, "-01")))
  tnow <- as.numeric(as.Date(paste0(out$period, "-01")))
  basev <- base[paste(out$state, prev12)]
  drift_pred <- basev + pb[out$state] * (tnow - tlag)
  ## exp#24: 三体均值 {lag12+漂移, 末端水平+漂移, HW}
  h_num <- (tnow - pt[out$state]) / 30.44
  last_anchor <- pv[out$state] + pb[out$state] * (tnow - pt[out$state])
  hw_pred <- sapply(seq_along(out$state), function(i) {
    f <- model$hw[[out$state[i]]]
    if (is.null(f)) return(NA_real_)
    unname(tryCatch(stats::predict(f, n.ahead = max(1, round(h_num[i])))[1],
                    error = function(e) NA_real_))
  })
  mats24 <- cbind(drift_pred, last_anchor, hw_pred)
  n_ok24 <- rowSums(!is.na(mats24))
  blended <- rowMeans(mats24, na.rm = TRUE)
  blended[n_ok24 == 0] <- drift_pred[n_ok24 == 0]
  out$price <- blended

  need <- is.na(out$price)
  if (any(need)) out$price[need] <- pv[out$state[need]] +
    pb[out$state[need]] * (tnow[need] - pt[out$state[need]])

  ## horizon-aware 池化 conformal
  t0_map <- structure(params$t0, names = params$state)
  h_test <- (tnow - t0_map[out$state]) / 30.44

  sim_raw <- lapply(split(hist, hist$state), function(g) {
    g <- g[order(g$period), ]
    n <- nrow(g)
    if (n < 26) return(NULL)
    dates <- as.numeric(as.Date(paste0(g$period, "-01")))
    b_s <- pb[[g$state[1]]]
    rows <- list()
    for (o in 25:min(n, n - 2)) {
      for (h in 1:13) {
        j <- o + h
        if (j > n) break
        lag_p <- format(as.Date(dates[j], origin = "1970-01-01") - 365.25, "%Y-%m")
        lag_idx <- match(paste(g$state[o], lag_p), paste(g$state, g$period))
        if (is.na(lag_idx)) next
        pred <- g$price[lag_idx] + b_s * (dates[j] - dates[lag_idx])
        rows[[length(rows) + 1]] <-
          data.frame(state = g$state[1], h = h, resid = abs(g$price[j] - pred))
      }
    }
    do.call(rbind, rows)
  })
  sim <- do.call(rbind, Filter(is.data.frame, sim_raw))
  if (is.null(sim) || nrow(sim) == 0) stop("horizon sim empty")

  h_bin <- pmin(ceiling(h_test), 13)
  q_h <- tapply(sim$resid, sim$h, stats::quantile, probs = 0.85, na.rm = TRUE)
  n_h <- as.integer(table(sim$h))
  names(n_h) <- names(q_h)
  obs_max <- unname(max(q_h, na.rm = TRUE))
  qv <- unname(q_h[as.character(h_bin)])
  qv[is.na(qv)] <- obs_max
  for (i in seq_along(h_bin)) {
    hb <- as.character(h_bin[i])
    if (!hb %in% names(n_h) || n_h[[hb]] < 40) qv[i] <- obs_max
  }
  qq <- stats::qnorm(0.95)
  out$.sd <- qv / qq
  out
}
