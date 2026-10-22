# mortality-synth.R —— exp#42 寿命指标合成实验（D1b/D2 敏感度合成 × 其他指标）
# 候选口径（同一 VSRR 数据面，单假设各一函数）：
#   a) 率与率趋势（.mortality_rate / .mortality_rate_trend）—— 无假设；
#   b) 合成 e0（.le_synth）—— D1b/D2 敏感度合成：
#      m = 州 age-adjusted 率 / US age-adjusted 率（VSRR 双侧实测）；
#      州年龄模式 = 全国年龄模式 × m（源无州×年龄分解，**声明假设**）；
#      年龄别 mx -> abridged life table（Preston/Chiang 标准法，ax=n/2；85+ 开区间 e=1/m）；
#      Δe1 = e1_state − e1_national，e0_synth = e0_anchor(D2) + Δe1（**Δe1→Δe0 可移植性为声明假设**）；
#   c) 早死指标（.premature_synth）—— 同表派生：YPLL-75 proxy（每千 1 岁存活者）+
#      75 岁前死亡比例（免人口权重，生命表即人口模型）。
# 数据源：inst/extdata/vsrr_state_quarter_slim.csv.gz + vsrr_national_age_slim.csv.gz（exp#41）
#         + nchs_life_tables.csv（D2 锚，exp#34）。
# 出处：方法=Preston, Heuveline, Guillot, Demography (2001) Ch.3 abridged life table；
#       ax/开区间约定为显式声明，非拟合参数。provisional vintage 异质随行（exp#41 注记）。

.age_bands <- c("1-4", "5-14", "15-24", "25-34", "35-44", "45-54", "55-64", "65-74", "75-84", "85+")
.age_widths <- c(4, 10, 10, 10, 10, 10, 10, 10, 10, NA_real_)  # 85+ 开区间
.age_starts <- c(1, 5, 15, 25, 35, 45, 55, 65, 75, 85)

.synth_method_note <- paste0(
  "state age pattern = national age pattern scaled by m (VSRR has no state x age split; DECLARED assumption); ",
  "abridged life table Preston/Chiang (ax = n/2 closed bands, open 85+ e = 1/m); ",
  "delta_e1 applied to D2 national e0 anchor (delta_e1 -> delta_e0 portability DECLARED); ",
  "mortality rates are provisional (VSRR vintage heterogeneity)"
)

## mx 向量 -> abridged life table（l1 = 1e5）；mx 为人年率（率/1e5）
.abridged_table <- function(mx) {
  stopifnot(length(mx) == 10L, all(is.finite(mx)), all(mx > 0))
  n <- .age_widths
  ax <- n / 2
  qx <- (n * mx) / (1 + (n - ax) * mx)
  lx <- numeric(11L)
  lx[1] <- 1e5
  dx <- numeric(10L)
  Lx <- numeric(10L)
  for (i in 1:9L) {
    dx[i] <- lx[i] * qx[i]
    lx[i + 1L] <- lx[i] - dx[i]
    Lx[i] <- n[i] * lx[i + 1L] + ax[i] * dx[i]
  }
  ## 85+ 开区间：q = 1（余者全亡）；e = 1/m（指数尾，声明约定）
  qx[10] <- 1
  e_open <- 1 / mx[10]
  dx[10] <- lx[10]
  Lx[10] <- lx[10] * e_open
  Tx <- rev(cumsum(rev(Lx)))
  ex <- Tx / lx[1:10]
  data.frame(
    age = .age_bands, start = .age_starts, mx = mx, qx = qx,
    lx = lx[1:10], dx = dx, Lx = Lx, Tx = Tx, ex = ex,
    stringsAsFactors = FALSE
  )
}

## 派生指标（免外部人口权重）：YPLL-75 proxy 与 75 前死亡比例
.table_derivs <- function(tab) {
  mids <- tab$start + .age_widths / 2
  mids[10] <- NA_real_  # 85+ 不参与
  w <- ifelse(!is.na(mids) & mids < 75, 75 - mids, 0)
  ypll <- sum(w * tab$dx) / tab$lx[1] * 1000
  prop75 <- sum(tab$dx[!is.na(mids) & mids < 75]) / tab$lx[1]
  list(ypll75_per_1k = ypll, prop_died_before_75 = prop75)
}

## m = 州/US age-adjusted 率比（双侧实测）；rate_period 传 .vsrr_state_rate
.mortality_index <- function(state, quarter, rate_period = c("12m", "3m")) {
  rate_period <- match.arg(rate_period)
  s <- .vsrr_state_rate(state, quarter, rate_period, "age_adjusted")$rate_per_100k
  u <- .vsrr_state_rate("US", quarter, rate_period, "age_adjusted")$rate_per_100k
  list(m = s / u, rate_state = s, rate_us = u)
}

## 候选 b：D1b/D2 敏感度合成 e0
.le_synth <- function(state, quarter, rate_period = c("12m", "3m")) {
  rate_period <- match.arg(rate_period)
  mi <- .mortality_index(state, quarter, rate_period)
  age <- .vsrr_age_pattern(quarter, if (rate_period == "12m") "12m" else "3m")
  mx_nat <- age$rate_per_100k / 1e5
  tab_nat <- .abridged_table(mx_nat)
  tab_st <- .abridged_table(mx_nat * mi$m)
  e1_nat <- tab_nat$ex[1]
  e1_st <- tab_st$ex[1]
  delta_e1 <- e1_st - e1_nat
  yr <- as.integer(substr(quarter, 1L, 4L))
  anchor <- .anchor_for(yr)
  anchor_note <- if (anchor$year != yr) sprintf(
    "quarter year %d outside D2 anchor table; fell back to %d (%s available)", yr, anchor$year,
    if (anchor$year > yr) "earliest" else "latest") else ""
  d <- .table_derivs(tab_st)
  dnat <- .table_derivs(tab_nat)
  data.frame(
    state = state,
    quarter = quarter,
    rate_period = rate_period,
    m_index = mi$m,
    rate_state_per_100k = mi$rate_state,
    rate_us_per_100k = mi$rate_us,
    e1_national = e1_nat,
    e1_synth = e1_st,
    delta_e1 = delta_e1,
    e0_anchor_year = as.integer(anchor$year),
    e0_anchor = anchor$e0,
    e0_synth = anchor$e0 + delta_e1,
    ypll75_per_1k = d$ypll75_per_1k,
    ypll75_per_1k_national = dnat$ypll75_per_1k,
    prop_died_before_75 = d$prop_died_before_75,
    source = "NCHS VSRR 489q-934x (rates) + NCHS life tables (D2 anchor)",
    level = "state",
    provisional = TRUE,
    sensitivity_assumption = .synth_method_note,
    notes = anchor_note,
    stringsAsFactors = FALSE
  )
}

## 候选 a：率与率趋势（无假设）
.mortality_rate <- function(state, quarter, rate_period = c("12m", "3m"),
                            rate_type = c("age_adjusted", "crude")) {
  rate_period <- match.arg(rate_period)
  rate_type <- match.arg(rate_type)
  .vsrr_state_rate(state, quarter, rate_period, rate_type)
}

.mortality_rate_trend <- function(state, from, to, rate_period = c("12m", "3m"),
                                  rate_type = c("age_adjusted", "crude")) {
  rate_period <- match.arg(rate_period)
  rate_type <- match.arg(rate_type)
  a <- .vsrr_state_rate(state, from, rate_period, rate_type)$rate_per_100k
  b <- .vsrr_state_rate(state, to, rate_period, rate_type)$rate_per_100k
  data.frame(
    state = state, from = from, to = to,
    rate_period = rate_period, rate_type = rate_type,
    rate_from = a, rate_to = b,
    change_per_100k = b - a,
    pct_change = (b - a) / a * 100,
    source = "NCHS VSRR Quarterly provisional estimates (data.cdc.gov 489q-934x)",
    provisional = TRUE,
    stringsAsFactors = FALSE
  )
}
