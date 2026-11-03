# ann_rel_variants.R —— 年值协变量的口径/时点变体（研究侧）
#
# 为什么要有这个文件：
#   随包 v3 的年值通道 ann_rel_z = log(年值 / 发布时点前 12 个月均价)，
#   分子用的是 **EIA-861 申报的州年价**（utility 客户数加权的单价均值），
#   分母与训练目标用的是 **EIA-861M 月度价**（收入/销售之比）。
#   这是**两个不同的口径**：州级年价中位差 -0.3%，p90 1.8-4.0%，TX/MA 最大 13-18%。
#   而 v3 是 **51 州池化、7 通道、没有州身份通道** —— 州相关的口径偏移学不掉，
#   对 TX/MA 来说年值通道就是带系统偏置的噪声（loss_attrib.csv 的 L2/L3）。
#
#   变体（只改协变量，训练/目标/面板都不动）：
#     filed            申报州年价（客户加权），Y+1-10 发布  ← 与随包 v3 同口径（基线）
#     panel_mean       Y 年 12 个月月度价的均值，Y+1-10 发布  ← 只改口径，时点不变
#     panel_mean_early 同上，但 Y+1-01 发布                     ← 只改时点，口径不变
#     workbook_revsal  100*sum(rev)/sum(sal)（EIA-861M 工作簿），Y+1-10 发布
#                      ← 与月度目标完全同定义
#
#   panel_mean 只用随包面板（price_history_slim）即可算，无需新数据；
#   workbook_revsal 需要 model_traning/fetch_eia861m.R 产出的研究侧真值表。
#
# 用法（被 conf_train_folds_serving.R 调用）：
#   ann_rel_variant(P, ".", variant = "panel_mean")

ann_rel_variant <- function(P, root = ".", variant = "filed", release_month = 10L) {
  n <- ncol(P)
  ann <- matrix(NA_real_, length(STATES), n, dimnames = list(STATES, MONTHS))

  if (identical(variant, "filed")) {
    agg <- utils::read.csv(file.path(root, "inst", "extdata", "eia861_state_annual.csv.gz"),
                           stringsAsFactors = FALSE)
    ## 与 prepare.R::ann_rel_covariate 完全一致：Y 年终值在 Y+1-10 发布
    for (i in seq_len(nrow(agg))) {
      si <- match(agg$state[i], STATES)
      j <- match(sprintf("%04d-%02d", agg$year[i] + 1L, release_month), MONTHS)
      if (!is.na(si) && !is.na(j) && j > 12) ann[si, j] <- log(agg$price[i] / mean(P[si, (j - 12):(j - 1)]))
    }
    rel <- ann
  } else if (variant %in% c("panel_mean", "panel_mean_early")) {
    rel_month <- if (identical(variant, "panel_mean_early")) 1L else release_month
    ## 年值 = 该年 12 个月月度价的均值（与月度目标同源、同定义）
    yrs <- unique(substr(MONTHS, 1, 4))
    for (y in yrs) {
      cols <- which(substr(MONTHS, 1, 4) == y)
      if (length(cols) < 12L) next
      yv <- rowMeans(P[, cols, drop = FALSE])
      j <- match(sprintf("%04d-%02d", as.integer(y) + 1L, rel_month), MONTHS)
      if (is.na(j) || j <= 12) next
      ann[, j] <- log(yv / rowMeans(P[, (j - 12):(j - 1), drop = FALSE]))
    }
    rel <- ann
  } else if (identical(variant, "workbook_revsal")) {
    fp <- file.path("model_traning", "candidates", "truth_eia861m_monthly.csv")
    if (!file.exists(fp)) {
      stop("workbook_revsal needs model_traning/candidates/truth_eia861m_monthly.csv; run model_traning/fetch_eia861m.R first.", call. = FALSE)
    }
    tr <- utils::read.csv(fp, stringsAsFactors = FALSE)
    tr$year <- substr(tr$period, 1, 4)
    g <- aggregate(cbind(rev, sal) ~ state + year, tr, sum)
    g$price <- 100 * g$rev / g$sal
    g <- g[is.finite(g$price) & g$price > 0, ]
    for (i in seq_len(nrow(g))) {
      si <- match(g$state[i], STATES)
      j <- match(sprintf("%04d-%02d", as.integer(g$year[i]) + 1L, release_month), MONTHS)
      if (!is.na(si) && !is.na(j) && j > 12) ann[si, j] <- log(g$price[i] / mean(P[si, (j - 12):(j - 1)]))
    }
    rel <- ann
  } else {
    stop("unknown ann_rel variant: ", variant, call. = FALSE)
  }

  ff <- t(apply(rel, 1, function(x) {
    for (k in seq_along(x)) if (is.na(x[k]) && k > 1) x[k] <- x[k - 1]
    x
  }))
  mask <- ifelse(is.na(ff), 0, 1)
  ff[is.na(ff)] <- 0
  age <- t(apply(rel, 1, function(x) {
    last <- NA_real_
    out <- rep(60, length(x))
    for (k in seq_along(x)) {
      if (!is.na(x[k])) last <- k
      if (!is.na(last)) out[k] <- min(k - last, 60)
    }
    out
  }))
  list(value = ff, mask = mask, age = age / 60, variant = variant, release_month = release_month)
}