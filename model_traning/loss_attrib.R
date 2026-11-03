# model_traning/loss_attrib.R —— 预测损失归因（先量后改）
#
# 目的：把"最终输出的精度损失"按层拆开，量化每一层吃掉多少，
#       决定哪些层值得重构（减层 / 复用数据结构 / 去共线）。
#
# 与上一轮 confidence 协议的区别：这里不建新的不确定性代数，
# 而是用已随包数据 + 两个 vintage，把每层的**实际**误差测出来。
#
# 层的定义（与 docs/data-dag.html 的节点对应）：
#   L1  空间替换      ZIP 拿到州价（R/price-at.R:36-39）
#   L2  两面口径差    月度面（EIA-861M 收入/销售之比）vs 年度面（EIA-861 客户加权单价均值）
#   L3  三套州年价    eia861_state_annual（申报，客户加权）/ A1 聚合 / 月度面重建
#   L6  回改          两个 vintage 之间的修订
#   L7  合成层        e0 = 锚 + Δe1（多走一层）
#   L8  权重规则      pop_share（最小面积裁决）vs pop_share_equal（等分）
#   L4/L5 模型与区间  取自随包 fit 的台账与 conf_ledger.csv
#
# 输入：
#   inst/extdata/*.csv.gz            随包冻结物（只读）
#   model_traning/candidates/truth_eia861m_monthly.csv   EIA-861M 工作簿（2026-10-23 版）
#   data-raw/eia_json/*.json          EIA API v2（2026-10-15 抓的第二 vintage）
#
# 输出：
#   model_traning/loss_attrib.csv          汇总（入库）
#   model_traning/candidates/loss_spatial.csv    逐 ZIP-年明细（不入库）
#   model_traning/candidates/loss_revision.csv   逐州-月回改明细（不入库）
#
# 用法：Rscript model_traning/loss_attrib.R

suppressPackageStartupMessages({
  stopifnot(requireNamespace("jsonlite", quietly = TRUE))
  pkgload::load_all(".", quiet = TRUE)
})

OUT <- "model_traning"
CAND <- file.path(OUT, "candidates")
dir.create(CAND, showWarnings = FALSE, recursive = TRUE)

pkgload::load_all(".", quiet = TRUE, export_all = TRUE)
f_zip_annual <- get(".zip_annual_price", envir = asNamespace("lifewatt"))
f_within_sd <- get(".within_state_spread", envir = asNamespace("lifewatt"))

attrib <- list()
add_attrib <- function(layer, metric, variant, n, value, unit, source, note = "") {
  attrib[[length(attrib) + 1L]] <<- data.frame(
    layer = layer, metric = metric, variant = variant, n = n,
    value = value, unit = unit, source = source, note = note,
    stringsAsFactors = FALSE
  )
}
q_of <- function(x, p) unname(stats::quantile(x, p, na.rm = TRUE))

## ---------------------------------------------------------------- 读数据
slim <- utils::read.csv("inst/extdata/eia861_annual_slim.csv.gz",
                         colClasses = c(eiaid = "character"))
opn <- unique(utils::read.csv("inst/extdata/openei_zip2state_slim.csv.gz",
                               colClasses = c(zip = "character", eiaid = "character")))
shr <- utils::read.csv("inst/extdata/zip_utility_share_slim.csv.gz",
                        colClasses = c(zip = "character", eiaid = "character"))
sann <- utils::read.csv("inst/extdata/eia861_state_annual.csv.gz")
b1 <- utils::read.csv("inst/extdata/b1_monthly_cache.csv")
truth <- utils::read.csv(file.path(CAND, "truth_eia861m_monthly.csv"))

years <- sort(unique(slim$year))
cat("A1 years:", paste(years, collapse = "/"), "\n")

## 月度面重建的州年价（口径：100 * sum(rev) / sum(sal)）
truth$year <- substr(truth$period, 1, 4)
mp <- aggregate(cbind(rev, sal) ~ state + year, truth, sum)
mp$price_monthly_plane <- 100 * mp$rev / mp$sal
names(mp)[names(mp) == "year"] <- "year"

## ---------------------------------------------------------------- L1 / L8：空间替换与权重规则
## 与 .zip_annual_price() 同口径的向量化实现（随后对样本做一致性断言）
zip_price_all <- list()
for (y in years) {
  s <- slim[slim$year == y & slim$eiaid != "99999", c("eiaid", "state", "price", "cus")]
  s$price[s$price <= 0] <- NA
  j <- merge(opn, s, by = c("eiaid", "state"), all.x = TRUE, sort = FALSE)
  j <- j[is.finite(j$price), ]
  j$zip_state <- ave(j$state, j$zip, FUN = function(z) z[1])  # 随包的州选择规则：取第一条
  sh <- merge(j[, c("zip", "eiaid", "zip_state", "price", "cus")],
              shr[, c("zip", "eiaid", "pop_share", "pop_share_equal", "assigned_frac", "overlap_frac")],
              by = c("zip", "eiaid"), all.x = TRUE, sort = FALSE)

  ## 三套权重口径（逐 ZIP 归一）
  grp_sum <- function(v, g) {
    r <- rowsum(v, g)
    out <- r[, 1]
    names(out) <- rownames(r)
    out
  }
  norm_w <- function(w) {
    w[is.na(w)] <- 0
    out <- w / grp_sum(w, sh$zip)[sh$zip]
    out[!is.finite(out)] <- NA_real_
    out
  }
  w_mean <- function(w) {
    num <- grp_sum(sh$price * w, sh$zip)[sh$zip]
    den <- grp_sum(w, sh$zip)[sh$zip]
    out <- num / den
    out[!is.finite(out)] <- NA_real_
    out
  }
  ## 口径 1：人口份额（随包主口径）
  sh$w_pop <- norm_w(sh$pop_share)
  ## 口径 2：人口份额的等分对照（同一张表已备好）
  sh$w_equal <- norm_w(sh$pop_share_equal)
  ## 口径 3：全州客户数（随包的回退口径）
  w3 <- sh$cus
  w3[!is.finite(w3) | w3 <= 0] <- NA
  w3[is.na(w3)] <- 1
  sh$w_cus <- w3 / grp_sum(w3, sh$zip)[sh$zip]

  sh$price_pop <- w_mean(sh$w_pop)
  sh$price_equal <- w_mean(sh$w_equal)
  sh$price_cus <- w_mean(sh$w_cus)
  n_p <- table(sh$zip)
  sh$n_priced_utility <- as.integer(n_p[sh$zip])
  ## 随包口径：单 utility ZIP 不查份额表（份额表只覆盖多 utility ZIP），走客户数回退
  pop_tot <- grp_sum(sh$pop_share, sh$zip)[sh$zip]
  sh$use_pop <- sh$n_priced_utility > 1L & is.finite(pop_tot) & pop_tot > 0
  sh$price_main <- ifelse(sh$use_pop, sh$price_pop, sh$price_cus)
  zip_price_all[[as.character(y)]] <- sh
}

## 一致性断言：向量化口径必须与随包 .zip_annual_price() 逐位相同
set.seed(20261103L)
zips_all <- unique(opn$zip)
sample_zip <- sample(zips_all, 200L)
f1 <- numeric(0)
for (y in years) {
  for (z in sample_zip) {
    r <- try(f_zip_annual(z, y), silent = TRUE)
    if (!inherits(r, "try-error")) {
      sh <- zip_price_all[[as.character(y)]]
      row <- sh[sh$zip == z, ]
      mine <- if (nrow(row) == 1L) row$price_main else row$price_main[1]
      f1 <- c(f1, as.numeric(abs(mine - r$price)))
    }
  }
}
cat(sprintf("L1 fidelity: max |vectorised - .zip_annual_price| = %s over %d ZIP-year pairs\n",
            format(max(f1, na.rm = TRUE), digits = 4), length(f1)))
cat("   f1 class:", class(f1), " length:", length(f1), " n_NA:", sum(is.na(f1)),
    " max:", format(max(f1, na.rm = TRUE), digits = 4),
    " passes:", isTRUE(max(f1, na.rm = TRUE) < 1e-9), "\n")
stopifnot(isTRUE(max(f1, na.rm = TRUE) < 1e-9))

## 逐 ZIP-年：ZIP 自有年价 vs 州价（随包月度/预测路径给的就是州价）
sp <- do.call(rbind, lapply(years, function(y) {
  sh <- zip_price_all[[as.character(y)]]
  z <- sh[!duplicated(sh$zip), c("zip", "zip_state", "price_main", "price_pop", "price_equal",
                                 "price_cus", "n_priced_utility", "use_pop",
                                 "assigned_frac", "overlap_frac")]
  z$year <- y
  sf <- sann[sann$year == y, c("state", "price")]
  names(sf)[2] <- "price_state_filed"
  m <- merge(z, sf, by.x = "zip_state", by.y = "state", all.x = TRUE, sort = FALSE)
  m$price_state_monthly_plane <- mp$price_monthly_plane[match(paste(m$zip_state, m$year),
                                                              paste(mp$state, mp$year))]
  m$dev_filed <- (m$price_main - m$price_state_filed) / m$price_state_filed
  m$dev_monthly_plane <- (m$price_main - m$price_state_monthly_plane) / m$price_state_monthly_plane
  m$rule_pop_vs_equal <- ifelse(m$use_pop, (m$price_pop - m$price_equal) / m$price_pop, NA_real_)
  m$rule_pop_vs_cus <- (m$price_main - m$price_cus) / m$price_main
  m
}))
sp <- sp[sp$n_priced_utility >= 1L & is.finite(sp$price_main), ]
utils::write.csv(sp, file.path(CAND, "loss_spatial.csv"), row.names = FALSE)

for (y in years) {
  s <- sp[sp$year == y, ]
  add_attrib("L1", "zip_level_vs_state_annual_rel_dev", sprintf("state=filed_annual;year=%d", y),
             nrow(s), q_of(s$dev_filed, 0.5), "rel", "A1 vs eia861_state_annual",
             sprintf("p90=%.4f max=%.4f", q_of(s$dev_filed, 0.9), max(abs(s$dev_filed), na.rm = TRUE)))
  add_attrib("L1", "zip_level_vs_state_annual_rel_dev", sprintf("state=monthly_plane;year=%d", y),
             nrow(s), q_of(s$dev_monthly_plane, 0.5), "rel", "A1 vs EIA-861M revenue/sales",
             sprintf("p90=%.4f max=%.4f", q_of(s$dev_monthly_plane, 0.9),
                     max(abs(s$dev_monthly_plane), na.rm = TRUE)))
  s8 <- s[is.finite(s$rule_pop_vs_equal), ]
  add_attrib("L8", "weight_rule_spread_rel", sprintf("pop_vs_equal;year=%d", y), nrow(s8),
             q_of(abs(s8$rule_pop_vs_equal), 0.5), "rel", "zip_utility_share_slim",
             sprintf("p90=%.4f max=%.4f", q_of(abs(s8$rule_pop_vs_equal), 0.9),
                     max(abs(s8$rule_pop_vs_equal), na.rm = TRUE)))
  add_attrib("L8", "weight_rule_spread_rel", sprintf("pop_vs_cus_fallback;year=%d", y), nrow(s),
             q_of(abs(s$rule_pop_vs_cus), 0.5), "rel", "A1 cus fallback",
             sprintf("p90=%.4f max=%.4f", q_of(abs(s$rule_pop_vs_cus), 0.9),
                     max(abs(s$rule_pop_vs_cus), na.rm = TRUE)))
}

## L1b：ZIP 自有年价的年际变动 vs 州年价的年际变动（"相对路径可传递"这个假设的代价）
for (y in years[-1]) {
  a <- sp[sp$year == y - 1, c("zip", "price_pop", "price_state_filed", "price_state_monthly_plane")]
  b <- sp[sp$year == y, c("zip", "price_pop", "price_state_filed", "price_state_monthly_plane")]
  names(b)[2:4] <- paste0(names(b)[2:4], "_t")
  m <- merge(a, b, by = "zip", all.x = TRUE, sort = FALSE)
  d_zip <- (m$price_pop_t - m$price_pop) / m$price_pop
  d_filed <- (m$price_state_filed_t - m$price_state_filed) / m$price_state_filed
  d_mp <- (m$price_state_monthly_plane_t - m$price_state_monthly_plane) / m$price_state_monthly_plane
  ok <- is.finite(d_zip) & is.finite(d_filed) & is.finite(d_mp)
  add_attrib("L1b", "zip_annual_change_minus_state_change", sprintf("filed;%d-%d", y - 1, y),
             sum(ok), q_of(abs(d_zip[ok] - d_filed[ok]), 0.5), "rel", "A1 vs eia861_state_annual",
             sprintf("p90=%.4f max=%.4f", q_of(abs(d_zip[ok] - d_filed[ok]), 0.9),
                     max(abs(d_zip[ok] - d_filed[ok]), na.rm = TRUE)))
  add_attrib("L1b", "zip_annual_change_minus_state_change", sprintf("monthly_plane;%d-%d", y - 1, y),
             sum(ok), q_of(abs(d_zip[ok] - d_mp[ok]), 0.5), "rel", "A1 vs EIA-861M revenue/sales",
             sprintf("p90=%.4f max=%.4f", q_of(abs(d_zip[ok] - d_mp[ok]), 0.9),
                     max(abs(d_zip[ok] - d_mp[ok]), na.rm = TRUE)))
}

## ---------------------------------------------------------------- L2 / L3：两面口径差与三套州年价
m2 <- merge(mp[, c("state", "year", "price_monthly_plane")],
            sann[, c("state", "year", "price", "customers")],
            by = c("state", "year"), all.x = TRUE, sort = FALSE)
names(m2)[4] <- "price_state_filed"
m2$rel <- (m2$price_monthly_plane - m2$price_state_filed) / m2$price_state_filed
for (y in years) {
  s <- m2[m2$year == y, ]
  s <- s[is.finite(s$rel), ]
  add_attrib("L2", "monthly_plane_annual_vs_filed_annual_rel_dev", sprintf("year=%d", y), nrow(s),
             q_of(s$rel, 0.5), "rel", "EIA-861M rev/sal vs eia861_state_annual",
             sprintf("p90=%.4f max=%.4f", q_of(s$rel, 0.9), max(abs(s$rel))))
}
## A1 自行聚合的州年价（客户加权）与随包 eia861_state_annual 是否同源一致
for (y in years) {
  s <- slim[slim$year == y & slim$eiaid != "99999" & slim$cus > 0 & is.finite(slim$price) &
              slim$price > 0, ]
  agg <- stats::aggregate(cbind(price, cus) ~ state, s, sum)
  agg$price_cus_weighted <- 100 * sum(s$price * s$cus) / sum(s$cus)  # 占位，下面按州重算
  out <- vapply(split(s, s$state), function(g) {
    w <- g$cus / sum(g$cus); sum(w * g$price)
  }, numeric(1))
  agg$price_cus_weighted <- out[agg$state]
  ref <- sann[sann$year == y, c("state", "price")]
  names(ref)[2] <- "price_state_filed"
  mm <- merge(agg[, c("state", "price_cus_weighted")], ref, by = "state", all.x = TRUE, sort = FALSE)
  mm$rel <- (mm$price_cus_weighted - mm$price_state_filed) / mm$price_state_filed
  mm <- mm[is.finite(mm$rel), ]
  add_attrib("L3", "a1_reaggregation_vs_shipped_state_annual_rel_dev", sprintf("year=%d", y),
             nrow(mm), q_of(mm$rel, 0.5), "rel", "A1 slim vs eia861_state_annual",
             sprintf("p90=%.4f max=%.4f", q_of(mm$rel, 0.9), max(abs(mm$rel))))
}

## ---------------------------------------------------------------- L6：回改（两个 vintage）
jfiles <- list.files("data-raw/eia_json", pattern = "\\.json$", full.names = TRUE)
if (length(jfiles) > 0L) {
  rows <- lapply(jfiles, function(f) {
    j <- jsonlite::fromJSON(f, simplifyDataFrame = TRUE)
    d <- j$response$data
    if (is.null(d) || !nrow(d)) return(NULL)
    data.frame(state = d$stateid, period = d$period,
               price_json = suppressWarnings(as.numeric(d$price)), stringsAsFactors = FALSE)
  })
  jv <- do.call(rbind, rows)
  jv <- jv[is.finite(jv$price_json), ]
  rv <- merge(jv, truth[, c("state", "period", "price", "data_status")],
              by = c("state", "period"), all.x = TRUE, sort = FALSE)
  rv <- rv[is.finite(rv$price) & is.finite(rv$price_json), ]
  rv$abs_diff <- abs(rv$price - rv$price_json)
  rv$rel_diff <- (rv$price - rv$price_json) / rv$price_json
  utils::write.csv(rv, file.path(CAND, "loss_revision.csv"), row.names = FALSE)
  yr <- substr(rv$period, 1, 4)
  for (y in sort(unique(yr))) {
    s <- rv[yr == y, ]
    add_attrib("L6", "revision_abs_cents_per_kwh_json_vs_workbook", sprintf("year=%s", y), nrow(s),
               q_of(s$abs_diff, 0.5), "cents/kWh", "eia_json(2026-10-15) vs EIA-861M(2026-10-23)",
               sprintf("p90=%.4f max=%.4f frac_changed=%.4f", q_of(s$abs_diff, 0.9),
                       max(s$abs_diff), mean(s$abs_diff > 1e-9)))
  }
  add_attrib("L6", "revision_max_abs_cents_per_kwh", "all_months", nrow(rv), max(rv$abs_diff),
             "cents/kWh", "eia_json vs EIA-861M", sprintf("frac_changed=%.4f", mean(rv$abs_diff > 1e-9)))
}

## ---------------------------------------------------------------- L4 / L5：模型与区间（取自随包台账）
fit <- readRDS("inst/extdata/price_lstm_fit.rds")
bl <- fit$baselines
for (i in seq_len(nrow(bl))) {
  add_attrib("L4", "mse_es_baseline", bl$model[i], NA_real_, bl$mse_es[i], "MSE", "price_lstm_fit$baselines",
             sprintf("mse_cal=%.3f mae_es=%.3f", bl$mse_cal[i], bl$mae_es[i]))
}
for (h in seq_len(nrow(fit$intervals))) {
  add_attrib("L5", "shipped_interval_calib_in_sample_coverage", sprintf("h=%d", fit$intervals$h[h]),
             fit$intervals$n[h], fit$coverage$calib_in_sample[h], "coverage", "price_lstm_fit$coverage",
             sprintf("transfer_early_window=%.4f abs_q85=%.4f", fit$coverage$transfer_early_window[h],
                     fit$intervals$abs_q85[h]))
}
if (file.exists(file.path(OUT, "conf_ledger.csv"))) {
  led <- utils::read.csv(file.path(OUT, "conf_ledger.csv"))
  sel <- led[led$method == "bias_scaled_conformal" & led$crit == "mse", ]
  for (y in sort(unique(sel$eval_year))) {
    s <- sel[sel$eval_year == y, ]
    add_attrib("L5", "rolling_origin_out_of_sample_coverage", sprintf("selected_construction;year=%d", y),
               sum(s$n), mean(s$coverage), "coverage", "conf_ledger.csv",
               sprintf("wis=%.3f width_rel=%.3f fail_rate=%.4f", mean(s$wis), mean(s$width_rel),
                       mean(s$fail_rate)))
  }
}

## ---------------------------------------------------------------- 颗粒度损失 vs 预测不确定度
ws <- do.call(rbind, lapply(years, function(y) {
  st <- unique(sann$state)
  out <- vapply(st, function(s) {
    r <- f_within_sd(s, y)
    c(r$sd, r$n_utility)
  }, numeric(2))
  data.frame(state = st, year = y, within_state_sd = out[1, ], n_utility = out[2, ])
}))
h1 <- fit$intervals[fit$intervals$h == 1, ]
band_half_rel <- (h1$r_q95 - h1$r_q05) / 2
for (y in years) {
  s <- ws[ws$year == y, ]
  s <- s[is.finite(s$within_state_sd), ]
  mp_y <- mp[mp$year == y, ]
  lev <- mp_y$price_monthly_plane[match(s$state, mp_y$state)]
  band <- lev * band_half_rel
  ratio <- s$within_state_sd / band
  ok <- is.finite(ratio)
  add_attrib("L10", "granularity_loss_over_h1_band_halfwidth", sprintf("year=%d", y), sum(ok),
             q_of(ratio[ok], 0.5), "ratio", "R/granularity.R vs price_lstm_fit$intervals",
             sprintf("p90=%.2f frac_gt_1=%.3f", q_of(ratio[ok], 0.9), mean(ratio[ok] > 1)))
}

## ---------------------------------------------------------------- 落盘
A <- do.call(rbind, attrib)
A <- A[order(A$layer, A$metric, A$variant), ]
utils::write.csv(A, file.path(OUT, "loss_attrib.csv"), row.names = FALSE)

cat("\n=== loss_attrib.csv ===\n")
print(A, row.names = FALSE)
cat("\nwrote", file.path(OUT, "loss_attrib.csv"), "rows:", nrow(A), "\n")