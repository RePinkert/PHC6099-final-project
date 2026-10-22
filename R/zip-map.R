# A2 (OpenEI 2024 vintage, CC-BY-4.0) ZIP -> utility -> state resolver.
# 阶段C exp#31 假设：等权；exp#36 起 customers 加权为默认（A1 客户数优先、缺失回退等权并记 note）。
# cross-state 事实：A2 2024 数据中不存在跨州多 utility 的 zip（实测 15331 个多 utility zip 全部同州）。

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

.zip5 <- function(zip) {
  if (is.null(zip) || length(zip) != 1L) {
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

.zip_lookup <- function(zip) {
  m <- .open_map()
  hit <- m[m$zip == .zip5(zip), ]
  if (nrow(hit) == 0L) {
    stop(sprintf("No electric utility record for zip %s (OpenEI 2024 mapping).", zip),
         call. = FALSE)
  }
  hit[order(hit$eiaid, hit$utility_name), ]
}

.zip_state <- function(zip, weights = "customers") {
  hit <- .zip_lookup(zip)
  tb_raw <- table(hit$state)
  if (identical(weights, "customers")) {
    hit$cust_weight <- vapply(seq_len(nrow(hit)), function(i) {
      w <- tryCatch(.annual_customers(hit$eiaid[i], hit$state[i]), error = function(e) NA_real_)
      if (is.finite(w) && w > 0) w else NA_real_
    }, numeric(1))
    n_fallback <- sum(is.na(hit$cust_weight))
    hit$cust_weight[is.na(hit$cust_weight)] <- 1
    scheme <- sprintf("customers (%d equal fallback)", n_fallback)
  } else if (identical(weights, "equal")) {
    hit$cust_weight <- rep(1, nrow(hit))
    scheme <- "equal"
  } else {
    stop(sprintf("Unknown weight scheme: %s (expects 'customers' or 'equal').", weights), call. = FALSE)
  }
  wt <- tapply(hit$cust_weight, hit$state, sum)
  st <- names(wt)[which.max(wt)]
  list(
    state = st,
    utilities = hit,
    n_utility = nrow(hit),
    weight_scheme = scheme,
    state_share = as.numeric(wt[st]) / sum(wt),
    mapping_vintage = "2024",
    note = if (nrow(hit) > 1L) {
      sprintf("multi-utility zip; %s weighting", scheme)
    } else {
      ""
    }
  )
}
