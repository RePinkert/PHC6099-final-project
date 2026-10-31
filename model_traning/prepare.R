# prepare.R —— model_traning 分支：LSTM 训练数据装配（价格面板 + 异频协变量通道）
# 数据源（全部树内、离线可复现）：
#   inst/extdata/price_history_slim.csv.gz  EIA-861M 州级住宅月度电价 2010-01..2026-07
#   inst/extdata/eia861_state_annual.csv.gz   EIA-861 州年客户加权价 2010..2025（assemble_861_state_annual.R）
#   inst/extdata/vsrr_state_quarter_slim.csv.gz   VSRR 州季死亡率（2023Q1..2025Q3）
# 接缝修复的历次改动（诊断见 model_traning/diagnose_seam.R、diagnose_seam_channels.R）：
#   v2：删掉 EIA-112 断供（仅 2024 年，向前填充后 age 外推出训练分布）；年度通道从 2023..2025 补到 2010。
#   v3（第二次重训尝试）：价格水平和年度值都改成相对量，目标改成 log(P_{t+h}/P_t)；
#       v2 的第一次重训里，按州 minmax 的 price_mm、ann_mm 在样本末端越界（65% / 71% 的州）。
# 声明窗口 2023-01..2026-12 不变；训练窗允许回溯（用户 2026-10-22 决定）。
# 异频协变量通道设计（弥合"数据源时间窗口不统一"）：每个辅助源带
#   value + mask（该时点是否已有观测）+ age（距上次观测月数，截断归一）
# 陈旧源的可信度由模型自learn，不靠人工对齐。

# 运行方式：在包根目录下 Rscript model_traning/<script>.R（root = "."）
MONTHS <- sprintf("%04d-%02d", rep(2010:2026, each = 12), rep(1:12, 17))
MONTHS <- MONTHS[MONTHS <= "2026-07"]
N_MONTHS <- length(MONTHS)

STATES <- c(state.abb, "DC")

load_price_wide <- function(root = ".") {
  d <- utils::read.csv(file.path(root, "inst", "extdata", "price_history_slim.csv.gz"),
                       stringsAsFactors = FALSE)
  P <- matrix(NA_real_, nrow = length(STATES), ncol = N_MONTHS,
              dimnames = list(STATES, MONTHS))
  ok <- d$state %in% STATES & d$period %in% MONTHS & is.finite(d$price)
  P[cbind(match(d$state[ok], STATES), match(d$period[ok], MONTHS))] <- d$price[ok]
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

## 年度通道来源（州×年表，已排除 Adjustment 伪 utility）；Y 年终值按 Y+1 年 10 月发布，见 ann_rel_covariate()
ANN_SOURCE <- "eia861_state_annual"

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

## 归一化参数只在训练窗内拟合（与参照 demo 一致"仅训练集 fit"）
fit_transforms <- function(P, MONTHS, train_last = "2025-06") list(train_last = train_last)

zscore <- function(x, mu, sd) (x - mu) / sd

## v3（第二次尝试）：所有价格类输入和目标都用相对量，避免按州 minmax 的水平通道在样本末端越界
## （接缝诊断第二轮：attempt 1 的 price_mm、ann_mm 在 2026-07 起点 65% / 71% 的州超出训练期范围）。
## 通道（7）：
##   lrel12_z  = log(P_t / 过去 12 个月均值，含当月)            —— 取代 price_mm（和 rel12_z）
##   mom_z     = P_t / P_{t-1} - 1
##   sin12 / cos12
##   ann_rel_z = log(Y 年年度值 / 发布时点（Y+1 年 10 月）前 12 个月的月度均价)，向前填充；无数据时为 0
##   ann_mask / ann_age
## zscore 参数只用训练窗（月份 <= train_last；ann_rel 只用 mask=1 的格）。
TARGET_TYPE <- "logratio"

## Y 年年度值相对发布前 12 个月月度均价的 log 比（Y+1 年 10 月起可用），向前填充 + mask/age
ann_rel_covariate <- function(P, root = ".") {
  agg <- utils::read.csv(file.path(root, "inst", "extdata", "eia861_state_annual.csv.gz"),
                         stringsAsFactors = FALSE)
  V <- matrix(NA_real_, length(STATES), N_MONTHS, dimnames = list(STATES, MONTHS))
  for (i in seq_len(nrow(agg))) {
    si <- match(agg$state[i], STATES)
    j <- match(sprintf("%04d-10", agg$year[i] + 1L), MONTHS)
    if (!is.na(si) && !is.na(j) && j > 12) V[si, j] <- log(agg$price[i] / mean(P[si, (j - 12):(j - 1)]))
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

## 价格特征阵列 [51, n_months, 7]；通道名随阵列返回
build_price_features <- function(P, annrel, transforms) {
  n <- N_MONTHS
  mom <- cbind(NA_real_, P[, -1, drop = FALSE] / P[, -n, drop = FALSE] - 1)
  lrel12 <- t(apply(P, 1, function(x) {
    out <- rep(NA_real_, length(x))
    for (k in 12:length(x)) out[k] <- log(x[k] / mean(x[(k - 11):k]))
    out
  }))
  tr <- matrix(MONTHS <= transforms$train_last, 51, n, byrow = TRUE)
  par_of <- function(x, ok) {
    v <- c(mean(x[ok]), sd(x[ok]))
    if (!is.finite(v[2]) || v[2] == 0) v[2] <- 1
    v
  }
  p_mom <- par_of(mom, is.finite(mom) & tr)
  p_lr <- par_of(lrel12, is.finite(lrel12) & tr)
  p_ann <- par_of(annrel$value, annrel$mask == 1 & tr)
  ## 缺测格填训练均值 -> z=0（中性）；年度通道无数据时也置 0，mask 另行告知
  mom[!is.finite(mom)] <- p_mom[1]
  lrel12[!is.finite(lrel12)] <- p_lr[1]
  ann_z <- zscore(annrel$value, p_ann[1], p_ann[2])
  ann_z[annrel$mask == 0] <- 0

  mon <- as.integer(substr(MONTHS, 6, 7))
  chan <- c("lrel12_z", "mom_z", "sin12", "cos12", "ann_rel_z", "ann_mask", "ann_age")
  arr <- array(NA_real_, dim = c(51, n, length(chan)), dimnames = list(STATES, MONTHS, chan))
  arr[, , "lrel12_z"] <- zscore(lrel12, p_lr[1], p_lr[2])
  arr[, , "mom_z"] <- zscore(mom, p_mom[1], p_mom[2])
  arr[, , "sin12"] <- matrix(rep(sin(2 * pi * mon / 12), each = 51), 51, n)
  arr[, , "cos12"] <- matrix(rep(cos(2 * pi * mon / 12), each = 51), 51, n)
  arr[, , "ann_rel_z"] <- ann_z
  arr[, , "ann_mask"] <- annrel$mask
  arr[, , "ann_age"] <- annrel$age
  list(arr = arr, zpar = list(mom = p_mom, lrel12 = p_lr, ann_rel = p_ann), chan = chan)
}

## 目标：每个 h 的 log(P_{t+h} / P_t)，用训练样本（origins_train）的均值/标准差标准化
fit_target_transform <- function(P, origins, H) {
  r <- do.call(rbind, lapply(origins, function(j0) log(P[, j0 + seq_len(H), drop = FALSE] / P[, j0])))
  list(type = TARGET_TYPE, mu = colMeans(r), sd = apply(r, 2, sd))
}
target_norm <- function(P, s, j0, H, tt) (log(P[s, j0 + seq_len(H)] / P[s, j0]) - tt$mu) / tt$sd
target_denorm <- function(y_norm, p0, tt) p0 * exp(tt$mu + tt$sd * y_norm)
