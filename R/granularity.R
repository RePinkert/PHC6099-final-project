# 颗粒度与置信度声明层：每个含数值的输出行带 confidence_tier，州级行另带州内离散度。
# 口径：
#   A = 在声明颗粒度上实测（单 utility ZIP 的 EIA-861 年价）；
#   B = 实测，但比 ZIP 粗（州级月价；多 utility ZIP 的年价混合——权重是 utility 全州客户数，
#       不是 ZIP 内份额，公开数据没有后者）；
#   C = 模型或合成（LSTM 预测、合成 e0、PLACES 模型估计）。
# 州内离散度 = 同州各 utility EIA-861 年价的客户加权 sd：州值落到某个 ZIP 时可能偏离的典型幅度，
# 它是颗粒度损失的量化，不是抽样误差。

.tier_label <- c(
  A = "A: observed at the reported granularity",
  B = "B: observed, but coarser than the ZIP (state value, or a multi-utility blend weighted by system-wide customers)",
  C = "C: modeled or synthetic estimate"
)

.confidence_tier <- function(tier) {
  stopifnot(all(tier %in% names(.tier_label)))
  unname(.tier_label[tier])
}

## 同州 utility 年价的客户加权 sd（cents/kWh）；年份取 <= year 的最新终版，早于表首退回表首年
.within_state_spread <- function(state, year) {
  slim <- .annual_slim()
  yrs <- .annual_years()
  y <- if (any(yrs <= year)) max(yrs[yrs <= year]) else min(yrs)
  s <- slim[slim$year == y & slim$state == state &
              is.finite(slim$price) & slim$price > 0 &
              is.finite(slim$cus) & slim$cus > 0, ]
  if (nrow(s) < 2L) {
    return(list(sd = NA_real_, n_utility = nrow(s), year = as.integer(y)))
  }
  w <- s$cus / sum(s$cus)
  mu <- sum(w * s$price)
  list(sd = sqrt(sum(w * (s$price - mu)^2)), n_utility = nrow(s), year = as.integer(y))
}
