# check_ann_variants.R —— 年值协变量变体的诊断（口径/时点差多少）
#
# 问题：v3 的年值通道分子用的是 EIA-861 申报州年价（utility 客户数加权的单价均值），
#       分母与训练目标是 EIA-861M 月度价（收入/销售之比）—— 两个口径。
#       州级年价中位差 -0.3%、p90 1.8-4.0%、TX/MA 最大 13-18%；
#       而模型是 51 州池化、**没有州身份通道** → 州相关的偏移学不掉。
# 这里量的是：各变体下 ann_rel_z 通道上，各州相对训练总体分布的偏移（= 模型看到的多余噪声）。
#
# 用法：Rscript model_traning/check_ann_variants.R

source("model_traning/prepare.R")
source("model_traning/ann_rel_variants.R")

P <- load_price_wide(".")
tf <- fit_transforms(P, MONTHS, "2023-12")
tr <- MONTHS <= tf$train_last

res <- list()
for (v in c("filed", "panel_mean", "panel_mean_early", "workbook_revsal")) {
  a <- ann_rel_variant(P, ".", variant = v)
  f <- build_price_features(P, a, tf)
  z <- f$arr[, , "ann_rel_z"]
  ## 训练窗内、mask=1 的格上的州级偏移（相对全体均值）
  sel <- tr & a$mask == 1
  per_state <- tapply(z[sel], rep(rownames(z), each = ncol(z))[sel], mean)
  per_state <- per_state[order(per_state)]
  res[[v]] <- data.frame(
    variant = v,
    months_masked = sum(a$mask == 1),
    mean_age_months = mean(a$age[tr] * 60),
    ann_z_sd = sd(z[sel]),
    state_offset_min = min(per_state),
    state_offset_max = max(per_state),
    state_offset_p90 = unname(stats::quantile(per_state, 0.9)),
    offset_TX = unname(per_state["TX"]),
    offset_MA = unname(per_state["MA"]),
    offset_CA = unname(per_state["CA"]),
    offset_FL = unname(per_state["FL"]),
    offset_NY = unname(per_state["NY"]),
    stringsAsFactors = FALSE)
}
R <- do.call(rbind, res)
cat("=== 年值协变量变体诊断（训练窗 <= 2023-12）===\n")
print(R, row.names = FALSE, digits = 4)

cat("\n=== 口径差（申报年价 vs 月度面年均）在各州上的幅度 ===\n")
tr_tab <- utils::read.csv("model_traning/candidates/truth_eia861m_monthly.csv", stringsAsFactors = FALSE)
tr_tab$year <- substr(tr_tab$period, 1, 4)
mp <- aggregate(cbind(rev, sal) ~ state + year, tr_tab, sum)
mp$price_monthly_plane <- 100 * mp$rev / mp$sal
filed <- utils::read.csv("inst/extdata/eia861_state_annual.csv.gz", stringsAsFactors = FALSE)
m <- merge(mp[, c("state", "year", "price_monthly_plane")],
           filed[, c("state", "year", "price")], by = c("state", "year"), all.x = TRUE)
names(m)[4] <- "price_filed"
m$rel <- (m$price_filed - m$price_monthly_plane) / m$price_monthly_plane
m <- m[is.finite(m$rel), ]
cat(sprintf("state-year n=%d | median %+.3f%% | p90 %+.3f%% | max %+.3f%%\n",
            nrow(m), 100 * stats::median(m$rel), 100 * stats::quantile(m$rel, 0.9),
            100 * max(abs(m$rel))))
worst <- m[order(-abs(m$rel)), c("state", "year", "price_filed", "price_monthly_plane", "rel")]
print(head(worst, 8), row.names = FALSE)
cat("\n各州的最大 |口径差|（跨年）：\n")
st <- tapply(abs(m$rel), m$state, max)
print(head(sort(st, decreasing = TRUE), 10))