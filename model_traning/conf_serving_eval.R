# conf_serving_eval.R —— 服务 regime 折上的统一评估：口径变体 / 早停准则 / 种子 / 第二个折 / 模型集合
#
# 评估对象（全部是研究侧候选，不进随包）：
#   filed_mse / filed_wis        基线（协变量=申报州年价，早停=patience60）
#   seed1/seed2/seed3/seedw1     同折换随机种子（量"种子噪声"）
#   annpanel                     协变量改为月度面 12 月均价（口径同源，发布时点不变）
#   annwbrev                     协变量改为月度面 100*sum(rev)/sum(sal)（与目标完全同定义）
#   min30mse / min30wis          早停加"不得早于 epoch 30 选权重"的下限
#   fold2027                     第二个服务 regime 折（评估年 2027，真值到 2026-08）
#   ensemble                     上面 6 个成员的稳健集合（区间参数在集合残差上标定）
#
# 输出：
#   model_traning/conf_serving_ledger.csv    逐 (fit, method, h)
#   model_traning/conf_serving_state.csv     逐 (fit, method, h, state_group)
#   model_traning/conf_serving_distance.csv  逐 (fit, method, gap)
#   model_traning/conf_serving_seedband.csv  种子带的覆盖（逐 h 的 min/中位/max）
#   model_traning/conf_ensemble.csv          集合 vs 单模型
#
# 用法：Rscript model_traning/conf_serving_eval.R

source("R/conf-protocol.R")
source("R/conf-harness.R")
source("R/conf-intervals.R")

ROOT <- "."
METHODS <- c("shipped", "conformal_asym", "conformal_sym", "scaled_conformal",
             "bias_conformal", "bias_scaled_conformal", "shrunk_state")
NOMINAL <- CONF_NOMINAL
H <- 5L
BIG_GAP <- c("MA", "TX", "DC", "ME", "NY")   # 申报年价 vs 月度面口径差最大的州

P <- conf_load_panel(ROOT); ann <- conf_ann_rel(P, ROOT); months <- colnames(P)

## 研究侧真值表把面板延伸一个月（2026-08），这样 y=2027 折也能评到 2026-08
ext_fp <- "model_traning/candidates/truth_eia861m_monthly.csv"
if (file.exists(ext_fp)) {
  ext <- utils::read.csv(ext_fp, stringsAsFactors = FALSE)
  new_m <- sort(setdiff(ext$period, colnames(P)))
  if (length(new_m) > 0L) {
    P <- cbind(P, matrix(NA_real_, nrow(P), length(new_m), dimnames = list(rownames(P), new_m)))
    for (i in seq_len(nrow(ext))) {
      s <- match(ext$state[i], rownames(P)); j <- match(ext$period[i], colnames(P))
      if (!is.na(s) && !is.na(j)) P[s, j] <- ext$price[i]
    }
    months <- colnames(P)
    cat("panel extended with:", paste(new_m, collapse = ","), "\n")
  }
}
mi <- function(s) match(s, months)

FIT_REG <- list(
  list(tag = "filed_mse", file = "model_traning/candidates/conf_fit_serving_y2026_mse.rds",          ens = TRUE),
  list(tag = "seed1",    file = "model_traning/candidates/conf_fit_serving_y2026_mse_seed1.rds",     ens = TRUE),
  list(tag = "seed2",    file = "model_traning/candidates/conf_fit_serving_y2026_mse_seed2.rds",     ens = TRUE),
  list(tag = "seed3",    file = "model_traning/candidates/conf_fit_serving_y2026_mse_seed3.rds",     ens = TRUE),
  list(tag = "filed_wis", file = "model_traning/candidates/conf_fit_serving_y2026_wis.rds",          ens = TRUE),
  list(tag = "seedw1",   file = "model_traning/candidates/conf_fit_serving_y2026_wis_seedw1.rds",     ens = TRUE),
  list(tag = "annpanel", file = "model_traning/candidates/conf_fit_serving_y2026_mse_annpanel.rds", ens = FALSE),
  list(tag = "annwbrev", file = "model_traning/candidates/conf_fit_serving_y2026_mse_annwbrev.rds", ens = FALSE),
  list(tag = "min30mse", file = "model_traning/candidates/conf_fit_serving_y2026_mse_min30mse.rds", ens = FALSE),
  list(tag = "min30wis", file = "model_traning/candidates/conf_fit_serving_y2026_wis_min30wis.rds", ens = FALSE),
  list(tag = "fold2027", file = "model_traning/candidates/conf_fit_serving_y2027_mse_fold2027.rds", ens = FALSE)
)

## ---- 通用：一个 (cal, ev) 对在某组构造上的评分 ----
## cal_rows / ev_rows 是"并集 origin"回放出来的行；目标窗与尺度都在这里统一切/归一，
## 保证 CAL 与 EVAL 用同一把尺（与 conf_iterate.R 同口径）。
score_block <- function(tag, cal_rows, ev_rows, f, j_last, cal_last_eff, eval_last_eff) {
  d <- conf_add_scale(rbind(cal_rows, ev_rows), P)
  cal <- d[d$target >= f$cal_first & d$target <= cal_last_eff, ]
  ev <- d[d$target >= f$eval_first & d$target <= eval_last_eff, ]
  ev$gap <- mi(ev$origin) - (j_last - H)
  ev$dist <- mi(ev$target) - j_last
  led <- list(); stt <- list(); dst <- list()
  for (meth in METHODS) {
    pars <- conf_fit_iv(cal, meth, NOMINAL)
    e2 <- conf_apply_iv(pars, ev)
    for (h in sort(unique(e2$h))) {
      s <- e2[e2$h == h, ]
      fail_rate <- mean(!s$ok); good <- s[s$ok, ]
      sc <- if (nrow(good) > 0) mean(abs(good$true - good$last)) + 1e-9 else NA_real_
      cov <- mean(s$ok & s$true >= s$lo & s$hi)
      wis <- if (nrow(good) > 0) mean(conf_wis(good$true, good$lo, good$hi, 1 - NOMINAL)) else NA_real_
      width_rel <- if (nrow(good) > 0) mean((good$hi - good$lo) / good$true) else NA_real_
      led[[length(led) + 1L]] <- data.frame(
        fit = tag, eval_year = f$eval_year, method = meth, h = h, n = nrow(s), n_ok = nrow(good),
        fail_rate = fail_rate, coverage = cov, cov_err = cov - NOMINAL, wis = wis,
        width_rel = width_rel,
        bias = if (nrow(good) > 0) mean((good$true - good$pred) / good$pred) else NA_real_,
        mse = if (nrow(good) > 0) mean((good$true - good$pred)^2) else NA_real_,
        scale = sc,
        J = (if (is.finite(wis)) wis / sc else 1e6) + 5 * abs(cov - NOMINAL) + 50 * fail_rate,
        stringsAsFactors = FALSE)
      for (grp in c("gap_big", "rest")) {
        ss <- s[s$state %in% (if (grp == "gap_big") BIG_GAP else setdiff(rownames(P), BIG_GAP)), ]
        gg <- ss[ss$ok, ]
        stt[[length(stt) + 1L]] <- data.frame(
          fit = tag, method = meth, h = h, group = grp, n = nrow(ss), n_ok = nrow(gg),
          fail_rate = mean(!ss$ok),
          coverage = mean(ss$ok & ss$true >= ss$lo & ss$hi),
          mse = if (nrow(gg) > 0) mean((gg$true - gg$pred)^2) else NA_real_,
          mae = if (nrow(gg) > 0) mean(abs(gg$true - gg$pred)) else NA_real_,
          bias = if (nrow(gg) > 0) mean((gg$true - gg$pred) / gg$pred) else NA_real_,
          width_rel = if (nrow(gg) > 0) mean((gg$hi - gg$lo) / gg$true) else NA_real_,
          stringsAsFactors = FALSE)
      }
    }
  }
  for (meth in c("shipped", "bias_scaled_conformal")) {
    pars <- conf_fit_iv(cal, meth, NOMINAL)
    e2 <- conf_apply_iv(pars, ev)
    for (g in sort(unique(e2$gap))) {
      s <- e2[e2$gap == g, ]; good <- s[s$ok, ]
      dst[[length(dst) + 1L]] <- data.frame(
        fit = tag, method = meth, gap = g, n = nrow(s), fail_rate = mean(!s$ok),
        coverage = mean(s$ok & s$true >= s$lo & s$hi),
        median_rel_err = if (nrow(good)) stats::median((good$true - good$pred) / good$pred) else NA_real_,
        p90_abs_rel_err = if (nrow(good)) unname(stats::quantile(abs((good$true - good$pred) / good$pred), 0.9)) else NA_real_,
        width_rel = if (nrow(good)) mean((good$hi - good$lo) / good$true) else NA_real_,
        stringsAsFactors = FALSE)
    }
  }
  ## 逐行区间（shipped 口径）→ 联合覆盖用
  pars_s <- conf_fit_iv(cal, "shipped", NOMINAL)
  e2s <- conf_apply_iv(pars_s, ev)
  rows_shipped <- e2s[, c("state", "origin", "h", "target", "true", "pred", "lo", "hi", "ok")]

  list(ledger = do.call(rbind, led), state = do.call(rbind, stt), dist = do.call(rbind, dst),
       rows = rows_shipped)
}

## ---- 稳健集合：逐行取可用成员的均值（每个成员过稳定性闸门）----
ens_mean <- function(dfs) {
  key <- function(d) paste(d$state, d$origin, d$h, sep = "|")
  k0 <- key(dfs[[1]])
  M <- vapply(dfs, function(d) d$pred[match(k0, key(d))], numeric(length(k0)))
  lastv <- dfs[[1]]$last[match(k0, key(dfs[[1]]))]
  okm <- is.finite(M) & is.finite(lastv) & abs(M / lastv - 1) <= 0.5
  okm[is.na(okm)] <- FALSE
  M[!okm] <- NA_real_
  out <- dfs[[1]]
  out$pred <- suppressWarnings(rowMeans(M, na.rm = TRUE))
  out$ok <- rowSums(okm) >= 2L & is.finite(out$pred)
  out$n_members <- rowSums(okm)
  out$ens_sd <- apply(M, 1, function(v) if (sum(is.finite(v)) >= 2L) stats::sd(v, na.rm = TRUE) else NA_real_)
  out$rel <- (out$true - out$pred) / out$pred
  out
}

led_all <- list(); stt_all <- list(); dst_all <- list()
pred_list <- list(); cal_list <- list(); ev_list <- list()

for (fr in FIT_REG) {
  if (!file.exists(fr$file)) { cat("missing:", fr$file, "\n"); next }
  fit <- readRDS(fr$file)
  f <- fit$fold
  j_last <- mi(f$train_last)
  cal_last_eff <- min(f$cal_last, max(months)); eval_last_eff <- min(f$eval_last, max(months))
  cal_origins <- months[seq(mi(f$cal_first) - H, mi(cal_last_eff) - 1L)]
  eval_origins <- months[seq(mi(f$eval_first) - H, mi(eval_last_eff) - 1L)]
  union_origins <- sort(unique(c(cal_origins, eval_origins)))
  cal_rows <- conf_replay(fit, P, ann, union_origins, verbose = FALSE)
  ev_rows <- cal_rows
  cat(sprintf("-- %-10s fold %d | es_score %.4f | best epoch %d | origins %s..%s | gap %d..%d\n",
              fr$tag, f$eval_year, fit$early_stop$score, fit$early_stop$epoch,
              min(union_origins), max(union_origins),
              min(mi(eval_origins)) - (j_last - H), max(mi(eval_origins)) - (j_last - H)))
  res <- score_block(fr$tag, cal_rows, ev_rows, f, j_last, cal_last_eff, eval_last_eff)
  led_all[[fr$tag]] <- res$ledger; stt_all[[fr$tag]] <- res$state; dst_all[[fr$tag]] <- res$dist
  pred_list[[fr$tag]] <- ev_rows[, c("state", "origin", "h", "target", "pred", "true", "last", "ok")]
  cal_list[[fr$tag]] <- cal_rows[, c("state", "origin", "h", "target", "pred", "true", "last", "ok")]
  ev_list[[fr$tag]] <- ev_rows
}

## ---- 集合作为第 12 个"fit"：区间参数在集合的 CAL 残差上标定 ----
ens_idx <- vapply(FIT_REG, function(x) isTRUE(x$ens), logical(1))
ens_tags <- vapply(FIT_REG[ens_idx], function(x) x$tag, character(1))
ens_tags <- ens_tags[vapply(ens_tags, function(tg) !is.null(pred_list[[tg]]), logical(1))]
if (length(ens_tags) >= 2L) {
  f0 <- readRDS(FIT_REG[[1]]$file)$fold
  j0 <- mi(f0$train_last)
  ens_cal <- ens_mean(lapply(ens_tags, function(tg) cal_list[[tg]]))
  ens_ev <- ens_mean(lapply(ens_tags, function(tg) ev_list[[tg]]))
  cat(sprintf("-- ensemble (%s): cal %d eval %d | members/row median %d\n",
              paste(ens_tags, collapse = "+"), nrow(ens_cal), nrow(ens_ev),
              median(ens_ev$n_members)))
  res <- score_block("ensemble", ens_cal, ens_ev, f0, j0,
                     min(f0$cal_last, max(months)), min(f0$eval_last, max(months)))
  led_all[["ensemble"]] <- res$ledger; stt_all[["ensemble"]] <- res$state; dst_all[["ensemble"]] <- res$dist
  utils::write.csv(ens_ev, "model_traning/candidates/conf_ensemble_rows.csv", row.names = FALSE)

  ## ---- 联合覆盖：一次调用（同一 state+origin）里 5 个 horizon 同时落界内 ----
  rs <- res$rows
  rs$cov <- rs$true >= rs$lo & rs$hi
  jc <- aggregate(cov ~ state + origin, rs, function(v) all(v))
  marg <- mean(rs$cov)
  cat(sprintf("\n=== 联合覆盖（集合，shipped 口径）===\n边际覆盖 %.4f | 5 个 horizon 同时落界内 %.4f | 独立预期(Šidák) %.4f | Bonferroni 下界 %.4f\n",
              marg, mean(jc$cov), marg^5, 1 - 5 * (1 - marg)))
  utils::write.csv(data.frame(marginal = marg, joint5 = mean(jc$cov), sidak = marg^5,
                               bonferroni = 1 - 5 * (1 - marg), n_calls = nrow(jc)),
                    "model_traning/conf_serving_joint.csv", row.names = FALSE)
}

L <- do.call(rbind, led_all); S <- do.call(rbind, stt_all); D <- do.call(rbind, dst_all)
utils::write.csv(L, "model_traning/conf_serving_ledger.csv", row.names = FALSE)
utils::write.csv(S, "model_traning/conf_serving_state.csv", row.names = FALSE)
utils::write.csv(D, "model_traning/conf_serving_distance.csv", row.names = FALSE)

## ---- 种子带：逐 h 的覆盖在几个种子上的分布 ----
seed_tags <- c("filed_mse", "seed1", "seed2", "seed3", "filed_wis", "seedw1")
band <- do.call(rbind, lapply(seed_tags, function(tg) {
  s <- L[L$fit == tg & L$method == "shipped", ]
  if (!nrow(s)) return(NULL)
  data.frame(fit = tg, h = s$h, coverage = s$coverage, mse = s$mse, fail_rate = s$fail_rate,
             width_rel = s$width_rel, stringsAsFactors = FALSE)
}))
if (!is.null(band)) {
  utils::write.csv(band, "model_traning/conf_serving_seedband.csv", row.names = FALSE)
  cat("\n=== 种子带（shipped 口径，逐 h）===\n")
  agg <- aggregate(cbind(coverage, mse, fail_rate, width_rel) ~ h, band, function(v) {
    c(min = min(v, na.rm = TRUE), median = stats::median(v, na.rm = TRUE), max = max(v, na.rm = TRUE))
  })
  print(agg, row.names = FALSE, digits = 4)
  cat(sprintf("\n种子带宽度（max-min 覆盖）：h1 %.3f h2 %.3f h3 %.3f h4 %.3f h5 %.3f | 跨 h 平均 %.3f\n",
              max(band$coverage[band$h == 1]) - min(band$coverage[band$h == 1]),
              max(band$coverage[band$h == 2]) - min(band$coverage[band$h == 2]),
              max(band$coverage[band$h == 3]) - min(band$coverage[band$h == 3]),
              max(band$coverage[band$h == 4]) - min(band$coverage[band$h == 4]),
              max(band$coverage[band$h == 5]) - min(band$coverage[band$h == 5]),
              max(aggregate(coverage ~ h, band, max)$coverage) -
                min(aggregate(coverage ~ h, band, min)$coverage)))
}

cat("\n=== 逐 fit：shipped 口径逐 h ===\n")
print(L[L$method == "shipped", c("fit", "eval_year", "h", "n", "coverage", "width_rel", "fail_rate", "mse", "bias")],
      row.names = FALSE, digits = 4)

cat("\n=== 逐 fit：跨 h 平均（shipped 口径）===\n")
print(aggregate(cbind(coverage, wis, width_rel, fail_rate, mse, bias) ~ fit + eval_year,
                 L[L$method == "shipped", ], mean), row.names = FALSE, digits = 4)

cat("\n=== 协变量变体：分州组 MSE（shipped 口径，跨 h 平均）===\n")
print(aggregate(cbind(mse, mae, coverage, fail_rate) ~ fit + group, S[S$method == "shipped", ], mean),
      row.names = FALSE, digits = 4)

cat("\n=== 集合 vs 单模型 ===\n")
rows <- list()
for (tg in ens_tags) {
  p <- pred_list[[tg]]; rel <- (p$true - p$pred) / p$pred; good <- is.finite(rel) & p$ok
  rows[[tg]] <- data.frame(member = tg, n = sum(good), mse = mean((p$true[good] - p$pred[good])^2),
                            mae = mean(abs(p$true[good] - p$pred[good])), bias = mean(rel[good]),
                            p90_abs_rel = unname(stats::quantile(abs(rel[good]), 0.9)), stringsAsFactors = FALSE)
}
if (!is.null(ens_ev)) {
  rel <- (ens_ev$true - ens_ev$pred) / ens_ev$pred; good <- is.finite(rel) & ens_ev$ok
  rows[["ensemble"]] <- data.frame(member = "ensemble", n = sum(good),
                                   mse = mean((ens_ev$true[good] - ens_ev$pred[good])^2),
                                   mae = mean(abs(ens_ev$true[good] - ens_ev$pred[good])),
                                   bias = mean(rel[good]),
                                   p90_abs_rel = unname(stats::quantile(abs(rel[good]), 0.9)),
                                   stringsAsFactors = FALSE)
}
E <- do.call(rbind, rows)
utils::write.csv(E, "model_traning/conf_ensemble.csv", row.names = FALSE)
print(E, row.names = FALSE, digits = 4)

if (!is.null(ens_ev)) {
  sub <- ens_ev[ens_ev$ok & is.finite(ens_ev$ens_sd), ]
  q <- stats::quantile(sub$ens_sd, c(0, 1 / 3, 2 / 3, 1), na.rm = TRUE)
  grp <- cut(sub$ens_sd, breaks = q, include.lowest = TRUE, labels = c("sd_low", "sd_mid", "sd_high"))
  cat("\n--- 集合离散度 vs 实际误差（分位三分层）---\n")
  print(data.frame(
    stratum = levels(grp), n = as.integer(table(grp)),
    ens_sd_median = as.numeric(tapply(sub$ens_sd, grp, function(v) stats::median(v, na.rm = TRUE))),
    abs_rel_err_median = as.numeric(tapply(abs((sub$true - sub$pred) / sub$pred), grp,
                                            function(v) stats::median(v, na.rm = TRUE))),
    abs_rel_err_p90 = as.numeric(tapply(abs((sub$true - sub$pred) / sub$pred), grp,
                                         function(v) unname(stats::quantile(v, 0.9, na.rm = TRUE)))),
    stringsAsFactors = FALSE), row.names = FALSE, digits = 4)
  cat(sprintf("Spearman(ens_sd, |rel err|) = %.3f\n",
              suppressWarnings(stats::cor(sub$ens_sd, abs((sub$true - sub$pred) / sub$pred),
                                          method = "spearman"))))
  cover2 <- abs((sub$true - sub$pred) / sub$pred) <= 2 * sub$ens_sd / sub$pred
  cat(sprintf("用 2*集合离散度当区间：覆盖 %.4f（名义 0.90）| 平均相对宽 %.4f\n",
              mean(cover2), mean(2 * sub$ens_sd / sub$pred)))
}

cat("\nwrote conf_serving_ledger.csv / conf_serving_state.csv / conf_serving_distance.csv / conf_serving_seedband.csv / conf_ensemble.csv\n")