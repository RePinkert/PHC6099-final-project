# model_traning/loss_extrap.R —— 外推段实测 + "ZIP 自有水平 x 州相对路径"变体对照（实验，不改随包行为）
#
# 两件事：
# (A) 外推段实测。EIA-861M 工作簿（2026-10-23 版）已含 2026-08 真值（51 州），
#     于是外推窗的第一个月**第一次有真值**：直接测随包预测在真实外推段上的误差与覆盖，
#     同时对比研究分支给的建议区间（conf_extrapolation_intervals.csv）。
# (B) 变体对照（研究侧）。当前随包口径给 ZIP 的是**州价**（空间替换）；
#     变体给 ZIP 的是"自有年价 x 州相对路径"。两者的差别在年度层可直接测，
#     在预测层可分解为"被消掉的水平项"与"新增的路径转移项"。
#
# 输出：
#   model_traning/loss_extrap.csv          2026-08 逐州（随包 vs 研究分支区间）
#   model_traning/loss_extrap_summary.csv   外推段汇总
#   model_traning/candidates/loss_variant_zip.csv   变体逐 ZIP-年对照
#   model_traning/loss_posterior_bias.csv   bill 证据后验继承水平偏差的敏感度
#
# 用法：Rscript model_traning/loss_extrap.R

suppressPackageStartupMessages({
  pkgload::load_all(".", quiet = TRUE, export_all = TRUE)
})

CAND <- "model_traning/candidates"
truth <- utils::read.csv(file.path(CAND, "truth_eia861m_monthly.csv"))
truth$year <- substr(truth$period, 1, 4)
mp <- aggregate(cbind(rev, sal) ~ state + year, truth, sum)
mp$price_monthly_plane <- 100 * mp$rev / mp$sal
sp <- utils::read.csv(file.path(CAND, "loss_spatial.csv"))
fit <- readRDS("inst/extdata/price_lstm_fit.rds")
fc <- fit$forecast

## ---------------------------------------------------------------- (A) 外推段实测
seg <- truth[truth$period == "2026-08", c("state", "period", "price", "data_status")]
names(seg)[3] <- "truth"
h1 <- fc[fc$h == 1 & fc$period == "2026-08", c("state", "period", "h", "price", "sd", "q_lo", "q_hi")]
names(h1)[4] <- "pred"
ex <- merge(seg, h1, by = c("state", "period"), all.x = TRUE, sort = FALSE)
ex$rel_err <- (ex$pred - ex$truth) / ex$truth
ex$cover_shipped <- ex$truth >= ex$q_lo & ex$truth <= ex$q_hi
ex$band_half_rel <- (ex$q_hi - ex$q_lo) / (2 * ex$pred)

rec <- utils::read.csv("model_traning/conf_extrapolation_intervals.csv")
rec <- rec[rec$h == 1, c("state", "sel_lo", "sel_hi", "sel_width_rel", "shipped_q_lo", "shipped_q_hi")]
ex <- merge(ex, rec, by = "state", all.x = TRUE, sort = FALSE)
ex$cover_recommended <- ex$truth >= ex$sel_lo & ex$truth <= ex$sel_hi
ex$cover_shipped_csv <- ex$truth >= ex$shipped_q_lo & ex$truth <= ex$shipped_q_hi
utils::write.csv(ex, "model_traning/loss_extrap.csv", row.names = FALSE)

q_of <- function(x, p) unname(stats::quantile(x, p, na.rm = TRUE))
smry <- data.frame(
  metric = c("n_states", "median_rel_err", "p90_abs_rel_err", "max_abs_rel_err",
             "shipped_band_half_rel_median", "shipped_coverage", "shipped_coverage_csv",
             "recommended_coverage", "recommended_width_rel_median",
             "shipped_width_rel_median"),
  value = c(nrow(ex), q_of(ex$rel_err, 0.5), q_of(abs(ex$rel_err), 0.9), max(abs(ex$rel_err), na.rm = TRUE),
            q_of(ex$band_half_rel, 0.5), mean(ex$cover_shipped), mean(ex$cover_shipped_csv),
            mean(ex$cover_recommended), q_of(ex$sel_width_rel, 0.5), q_of(ex$band_half_rel, 0.5)),
  stringsAsFactors = FALSE
)
utils::write.csv(smry, "model_traning/loss_extrap_summary.csv", row.names = FALSE)

cat("=== 外推段实测：2026-08（51 州，随包预测窗的第一个月）===\n")
cat(sprintf("truth status: %s\n", paste(unique(ex$data_status), collapse = ",")))
cat(sprintf("median rel err %+.4f | p90 |err| %.4f | max |err| %.4f\n",
            q_of(ex$rel_err, 0.5), q_of(abs(ex$rel_err), 0.9), max(abs(ex$rel_err), na.rm = TRUE)))
cat(sprintf("shipped band coverage %.4f (csv %.4f) | recommended coverage %.4f\n",
            mean(ex$cover_shipped), mean(ex$cover_shipped_csv), mean(ex$cover_recommended)))
cat(sprintf("shipped width(rel) %.4f | recommended width(rel) %.4f\n",
            q_of(ex$band_half_rel, 0.5), q_of(ex$sel_width_rel, 0.5)))
cat("\n--- 误差最大的 8 个州 ---\n")
print(head(ex[order(-abs(ex$rel_err)), c("state", "truth", "pred", "rel_err", "q_lo", "q_hi",
                                         "cover_shipped", "cover_recommended")], 8), row.names = FALSE)

## ---------------------------------------------------------------- (B) 变体对照
## 变体：ZIP 自有年价 x 州相对路径；随包：州价（水平替换）
sp25 <- sp[sp$year == 2025, c("zip", "zip_state", "price_main", "price_state_filed",
                              "dev_filed", "n_priced_utility")]
sp25 <- sp25[is.finite(sp25$price_main) & is.finite(sp25$price_state_filed), ]
sp25$err_current <- sp25$price_state_filed - sp25$price_main     # 随包给的是州价
sp25$err_variant <- 0                                            # 变体给的是自有年价
sp25$level_term_removed <- abs(sp25$err_current) / sp25$price_main

## 预测层分解：变体相对随包省掉水平项，保留路径转移项（由 L1b 实测）
cat("\n=== 年度层：随包 vs 变体（逐 ZIP，2025）===\n")
cat(sprintf("n ZIP %d\n", nrow(sp25)))
cat(sprintf("current  |err| median %.4f  p90 %.4f  max %.4f\n",
            q_of(abs(sp25$err_current) / sp25$price_main, 0.5),
            q_of(abs(sp25$err_current) / sp25$price_main, 0.9),
            max(abs(sp25$err_current) / sp25$price_main)))
cat(sprintf("variant  |err| median %.4f  p90 %.4f  max %.4f  (水平项按构造为 0)\n", 0, 0, 0))
cat(sprintf("保留的路径转移项 L1b: median %.4f  p90 %.4f\n",
            0.0263, 0.0942))
utils::write.csv(sp25, file.path(CAND, "loss_variant_zip.csv"), row.names = FALSE)

## ---------------------------------------------------------------- (C) bill 证据后验的偏差继承
## 随包 .bill_evidence()：先验 = 州价（price_sd 来自预测），观测 = bill/usage；
## 反方差合成 -> 后验。后验里先验的权重 = (1/price_sd^2) / (1/price_sd^2 + 1/meas_sd^2)。
## 州价的水平偏差会按这个权重原样进到后验里。
cat("\n=== bill 证据后验：水平偏差继承比例 ===\n")
out <- do.call(rbind, lapply(c(0.5, 1, 2, 5, 10), function(ms) {
  w <- 1 / (1 + (ms / 1.44)^2)   # price_sd ~ band_half/1.44 量级；ms=1 cents
  data.frame(meas_sd = ms, prior_weight = w,
             inherited_bias_median = w * q_of(sp25$err_current / sp25$price_main, 0.5),
             inherited_bias_p90 = w * q_of(sp25$err_current / sp25$price_main, 0.9))
}))
print(out, row.names = FALSE)
utils::write.csv(out, "model_traning/loss_posterior_bias.csv", row.names = FALSE)

cat("\nwrote model_traning/loss_extrap.csv, loss_extrap_summary.csv, loss_posterior_bias.csv\n")