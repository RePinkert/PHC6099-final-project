# prepare.R —— model_traning 分支：LSTM 训练数据装配（价格面板 + 异频协变量通道）
# 数据源（全部树内、离线可复现）：
#   data-raw/eia_json/*.json           州级住宅月度电价 2001-01..2026-07（307 月 x 51 州）
#   inst/extdata/eia861_annual_slim.csv.gz    EIA-861 州年客户加权价（2023/2024/2025）
#   inst/extdata/eia112_state_month_slim.csv.gz   EIA-112 断供机制（仅 2024-01..12）
#   inst/extdata/vsrr_state_quarter_slim.csv.gz   VSRR 州季死亡率（2023Q1..2025Q3）
# 声明窗口 2023-01..2026-12 不变；训练窗允许回溯（用户 2026-10-22 决定）。
# 异频协变量通道设计（弥合"数据源时间窗口不统一"）：每个辅助源带
#   value + mask（该时点是否已有观测）+ age（距上次观测月数，截断归一）
# 陈旧源的可信度由模型自learn，不靠人工对齐。

# 运行方式：在包根目录下 Rscript model_traning/<script>.R（root = "."）
stopifnot(requireNamespace("jsonlite", quietly = TRUE))

MONTHS <- sprintf("%04d-%02d", rep(2001:2026, each = 12), rep(1:12, 26))
MONTHS <- MONTHS[MONTHS <= "2026-07"]
N_MONTHS <- length(MONTHS)

STATES <- c(state.abb, "DC")

load_price_wide <- function(root = ".") {
  files <- file.path(root, "data-raw", "eia_json", paste0(STATES, ".json"))
  stopifnot(all(file.exists(files)))
  P <- matrix(NA_real_, nrow = length(STATES), ncol = N_MONTHS,
              dimnames = list(STATES, MONTHS))
  for (i in seq_along(files)) {
    j <- jsonlite::fromJSON(files[i], simplifyVector = TRUE)
    d <- j$response$data
    idx <- match(d$period, MONTHS)
    ok <- !is.na(idx) & !is.na(suppressWarnings(as.numeric(d$price)))
    P[i, idx[ok]] <- suppressWarnings(as.numeric(d$price))[ok]
  }
  ## 短缺口（内部 <=3 月）线性插补并留痕；长缺口/端点缺口拒绝
  imputed <- matrix(FALSE, nrow(P), N_MONTHS, dimnames = dimnames(P))
  for (i in seq_len(nrow(P))) {
    x <- P[i, ]
    if (all(is.finite(x))) next
    na <- which(!is.finite(x))
    fin <- which(is.finite(x))
    runs <- split(na, cumsum(c(1, diff(na) != 1)))
    for (r in runs) {
      if (length(r) > 3 || min(r) < min(fin) || max(r) > max(fin)) {
        stop(sprintf("unfillable price gap for %s at %s", rownames(P)[i],
                     paste(MONTHS[r], collapse = ",")))
      }
      x[r] <- stats::approx(fin, x[fin], xout = r)$y
      imputed[i, r] <- TRUE
    }
    P[i, ] <- x
  }
  stopifnot(all(is.finite(P)))
  attr(P, "imputed") <- imputed
  P
}

## EIA-861 州年客户加权价（2023/24/25），盖章于 Y-01 并向前填充；2023 前 mask=0
load_ann_covariate <- function(root = ".") {
  a <- utils::read.csv(file.path(root, "inst", "extdata", "eia861_annual_slim.csv.gz"),
                       stringsAsFactors = FALSE)
  agg <- aggregate(cbind(rev = a$rev * 0 + a$price * a$cus, cus = a$cus),
                   by = list(state = a$state, year = a$year), sum, na.rm = TRUE)
  agg$price_w <- agg$rev / agg$cus
  V <- matrix(NA_real_, length(STATES), N_MONTHS, dimnames = list(STATES, MONTHS))
  for (i in seq_len(nrow(agg))) {
    si <- match(agg$state[i], STATES)
    stamp <- sprintf("%04d-01", agg$year[i])
    if (!is.na(si) && stamp %in% MONTHS) V[si, match(stamp, MONTHS)] <- agg$price_w[i]
  }
  ff <- t(apply(V, 1, function(x) {
    for (k in seq_along(x)) if (is.na(x[k]) && k > 1) x[k] <- x[k - 1]
    x
  }))
  mask <- ifelse(is.na(ff), 0, 1)
  ff[is.na(ff)] <- 0
  age <- t(apply(V, 1, function(x) {
    last <- NA_real_
    out <- rep(60, length(x))
    for (k in seq_along(x)) {
      if (!is.na(x[k])) last <- k
      if (!is.na(last)) out[k] <- min(k - last, 60)
    }
    out
  }))
  list(value = ff, mask = mask, age = age / 60, years = sort(unique(agg$year)))
}

## EIA-112 断供 per-1k（仅 2024-01..12），向前填充；2024 前 mask=0
load_c1_covariate <- function(root = ".") {
  c1 <- utils::read.csv(file.path(root, "inst", "extdata", "eia112_state_month_slim.csv.gz"),
                        stringsAsFactors = FALSE)
  V <- matrix(NA_real_, length(STATES), N_MONTHS, dimnames = list(STATES, MONTHS))
  for (i in seq_len(nrow(c1))) {
    si <- match(c1$state[i], STATES)
    if (!is.na(si) && c1$period[i] %in% MONTHS) {
      V[si, match(c1$period[i], MONTHS)] <- c1$disconnections_per_1k[i]
    }
  }
  ff <- t(apply(V, 1, function(x) {
    for (k in seq_along(x)) if (is.na(x[k]) && k > 1) x[k] <- x[k - 1]
    x
  }))
  mask <- ifelse(is.na(ff), 0, 1)
  ff[is.na(ff)] <- 0
  age <- t(apply(V, 1, function(x) {
    last <- NA_real_
    out <- rep(60, length(x))
    for (k in seq_along(x)) {
      if (!is.na(x[k])) last <- k
      if (!is.na(last)) out[k] <- min(k - last, 60)
    }
    out
  }))
  list(value = ff, mask = mask, age = age / 60)
}

## VSRR 州季 log(m)，m = 州率 / US 率（12m 与 3m 两种口径都用作训练目标）
load_vsrr_logm <- function(root = ".") {
  v <- utils::read.csv(file.path(root, "inst", "extdata", "vsrr_state_quarter_slim.csv.gz"),
                       stringsAsFactors = FALSE)
  v <- v[v$rate_type == "age_adjusted", ]
  us <- v[v$state == "US", ]
  st <- v[v$state != "US", ]
  us_key <- paste(us$quarter, us$period_type)
  m <- st$rate_per_100k / us$rate_per_100k[match(paste(st$quarter, st$period_type), us_key)]
  data.frame(state = st$state, quarter = st$quarter, period_type = st$period_type,
             logm = log(m), m = m, stringsAsFactors = FALSE)
}

## 归一化参数：训练窗内拟合（与参照 demo 一致"仅训练集 fit"）
fit_transforms <- function(P, MONTHS, train_last = "2025-06") {
  tr <- MONTHS <= train_last
  price_minmax <- lapply(seq_len(nrow(P)), function(i) {
    x <- P[i, tr]
    list(min = min(x), max = max(x))
  })
  names(price_minmax) <- rownames(P)
  list(price_minmax = price_minmax, train_last = train_last)
}

mm_price <- function(x, mm) 2 * (x - mm$min) / (mm$max - mm$min) - 1

zscore <- function(x, mu, sd) (x - mu) / sd

## 价格特征阵列 [51, 307, nch]；通道名随阵列返回
build_price_features <- function(P, ann, c1, transforms) {
  n <- N_MONTHS
  mom <- P[, -1, drop = FALSE] / P[, -n, drop = FALSE] - 1
  mom <- cbind(NA_real_, mom)
  roll12 <- t(apply(P, 1, function(x) {
    out <- rep(NA_real_, length(x))
    for (k in 12:length(x)) out[k] <- x[k] / mean(x[(k - 11):k]) - 1
    out
  }))
  tr <- MONTHS <= transforms$train_last
  ok_m <- is.finite(mom) & matrix(tr, 51, n, byrow = TRUE)
  ok_r <- is.finite(roll12) & matrix(tr, 51, n, byrow = TRUE)
  ok_c <- c1$mask == 1 & matrix(tr, 51, n, byrow = TRUE)
  mu_mom <- mean(mom[ok_m]); sd_mom <- sd(mom[ok_m])
  mu_r12 <- mean(roll12[ok_r]); sd_r12 <- sd(roll12[ok_r])
  mu_c1 <- mean(c1$value[ok_c]); sd_c1 <- sd(c1$value[ok_c])
  if (!is.finite(sd_mom) || sd_mom == 0) sd_mom <- 1
  if (!is.finite(sd_r12) || sd_r12 == 0) sd_r12 <- 1
  if (!is.finite(sd_c1) || sd_c1 == 0) sd_c1 <- 1
  ## 缺测/掩码格填训练均值 -> z=0（中性），掩码通道另行告知
  mom[!is.finite(mom)] <- mu_mom
  roll12[!is.finite(roll12)] <- mu_r12
  c1_z <- c1$value
  c1_z[c1$mask == 0] <- mu_c1

  mm <- matrix(NA_real_, 51, n)
  ann_mm <- matrix(NA_real_, 51, n)
  ann_rng <- matrix(NA_real_, 51, 2, dimnames = list(STATES, NULL))
  for (i in 1:51) {
    mm[i, ] <- mm_price(P[i, ], transforms$price_minmax[[i]])
    av <- ann$value[i, ]; am <- av[ann$mask[i, ] == 1]
    rng <- if (length(am)) range(am) else c(0, 1)
    if (diff(rng) == 0) rng <- rng + c(-0.5, 0.5)
    ann_rng[i, ] <- rng
    ann_mm[i, ] <- 2 * (av - rng[1]) / (rng[2] - rng[1]) - 1
    ann_mm[i, ann$mask[i, ] == 0] <- 0
  }
  mon <- as.integer(substr(MONTHS, 6, 7))
  sin12 <- matrix(rep(sin(2 * pi * mon / 12), each = 51), 51, n)
  cos12 <- matrix(rep(cos(2 * pi * mon / 12), each = 51), 51, n)

  arr <- array(NA_real_, dim = c(51, n, 11),
               dimnames = list(STATES, MONTHS, NULL))
  arr[, , 1] <- mm
  arr[, , 2] <- zscore(mom, mu_mom, sd_mom)
  arr[, , 3] <- zscore(roll12, mu_r12, sd_r12)
  arr[, , 4] <- sin12
  arr[, , 5] <- cos12
  arr[, , 6] <- ann_mm
  arr[, , 7] <- ann$mask
  arr[, , 8] <- ann$age
  arr[, , 9] <- zscore(c1_z, mu_c1, sd_c1)
  arr[, , 10] <- c1$mask
  arr[, , 11] <- c1$age
  dimnames(arr)[[3]] <- c("price_mm", "mom_z", "rel12_z", "sin12", "cos12",
                          "ann_mm", "ann_mask", "ann_age", "c1_z", "c1_mask", "c1_age")
  list(arr = arr,
       zpar = list(mom = c(mu_mom, sd_mom), rel12 = c(mu_r12, sd_r12), c1 = c(mu_c1, sd_c1)),
       ann_rng = ann_rng,
       chan = dimnames(arr)[[3]])
}
