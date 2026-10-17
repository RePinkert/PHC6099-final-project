# autoresearch · prepare.R —— READ-ONLY 固件（agent 不得修改）
# 2026-10-16 human 勘误：仅修注释与实装不符处（30/13 时序切分、单次全窗评估 h 1..13、gate 口径）；
# 评估逻辑一行未动。勘误记录见 autoresearch/HANDOVER.md。
#
# LLM 自主研究闭环的固定部分：数据准备、评估基准（ground truth metric）。
# 借鉴 github.com/karpathy/autoresearch 的分工：
#   prepare.R (不修改) + train.R (agent 唯一可改) + program.md (组织章程)。
#
# 任务：州级月度住宅电价的多步预测（valid 单次全窗评估，h 实际 1..13；horizon 分桶仅用于区间校准）。
# 固定指标：MASE(÷季节朴素基线, 越低越好) 与 90% 区间覆盖率(达标区间 [0.85,0.95])。
# 固定预算：单次实验 wall clock ≤ 5 分钟（由 autonomy 循环超时强制，不在本文件计时）。

options(timeout = 300)  # R 内置 curl 默认 60s，EIA v2 逐州响应慢
DATA_DIR   <- "data-raw"
CACHE_FILE <- file.path(DATA_DIR, "b1_monthly_cache.csv")
# mase 账本：2026-10-16 human 决定迁入 autoresearch/ 并随 git 跟踪（append-only，阶段 C 静止；
# 契约见 autoresearch/README.md）。路径必须跟着迁移，否则本脚本会在仓库根另起一份空账本。
RESULTS    <- file.path("autoresearch", "results.tsv")

EIA_ENDPOINT <- "https://api.eia.gov/v2/electricity/retail-sales/data/" # nolint

## ── 数据准备（一次性；EIA key 可选：环境变量 EIA_API_KEY）────────────────
prepare_data <- function() {
  if (file.exists(CACHE_FILE)) {
    message("cache hit: ", CACHE_FILE)
    return(invisible(read.csv(CACHE_FILE)))
  }
  key <- Sys.getenv("EIA_API_KEY")
  stopifnot("`EIA_API_KEY` 未设置且无缓存。请注册 https://www.eia.gov/opendata/register.php 后 export。" = nzchar(key))
  url <- paste0(
    EIA_ENDPOINT,
    "?frequency=monthly&data%5B0%5D=price",
    "&facets%5Bsectorid%5D%5B%5D=RES",
    "&api_key=", key, "&length=5000"
  )
  all_states <- c(state.abb, "DC")
  out <- lapply(all_states, function(invisible_st) NULL)
  results <- list()
  fetch <- function(q, tries = 3) {
    for (i in seq_len(tries)) {
      r <- tryCatch(jsonlite::fromJSON(q), error = function(e) e)
      if (!inherits(r, "error")) return(r)
      Sys.sleep(2 + 3 * i)  # EIA v2 偶发 5xx，退避重试
    }
    stop(r)
  }
  for (st in all_states) {
    q <- paste0(url, "&facets%5Bstateid%5D%5B%5D=", st)
    r <- fetch(q)
    d <- r$response$data
    if (is.null(d) || nrow(d) == 0) next
    keep <- d$period >= "2023-01" & d$period <= "2026-07" & d$sectorid == "RES"
    results[[st]] <- data.frame(
      state = st, period = d$period[keep], price = as.numeric(d$price[keep])
    )
  }
  df <- do.call(rbind, results)
  df$price <- as.numeric(df$price)
  dir.create(DATA_DIR, showWarnings = FALSE, recursive = TRUE)
  write.csv(df, CACHE_FILE, row.names = FALSE)
  message("cached ", nrow(df), " rows -> ", CACHE_FILE)
  invisible(df)
}

## ── 评估固件（ground truth，agent 不得触碰）────────────────────────────
# 协议（2026-11-18 锁定）：
#   阶段A 时序切分 2025-06（30 训练月 / 13 valid 月，≈70/30）：train <= 2025-06，
#       单次全窗评估 valid = 2025-07..2026-07（h 实际 1..13；horizon 分桶仅用于区间；无 per-h walk-forward）
#   阶段B 全量重训: 2023-01..2026-07；一致性 gate（fit_price_forecast.R 计算）：
#       重训 in-sample 尾段残差 MAD(池化) ÷ 阶段A valid 残差 MAD <= 1.5，超标 -> 记 keep_at_risk（gate_pass 落 rds）
# 指标:
#   MASE       = MAE(model) / MAE(seasonal naive, lag 12)，对全部单元×全部评估步合并
#   coverage   = φ⁻¹(0.95)*成比例区间对真实值的覆盖率（模型必须给出 point + sd 列）
#   coverage91 = |coverage - 0.90| （越小越好）

evaluate_model <- function(fit_model_fn, predict_fn, cache = NULL) {
  data <- if (is.null(cache)) prepare_data() else cache
  stopifnot(all(c("state", "period", "price") %in% names(data)))
  data <- data[order(data$state, data$period), ]
  split <- as.Date(paste0("2025-06", "-01"))
  tvals <- as.Date(paste0(data$period, "-01"))
  train <- data[tvals <= split, ]
  test  <- data[tvals >  split, ]
  model <- fit_model_fn(train)
  preds <- predict_fn(model, test)      # 必须返回 state/period/price/.sd
  naive_ratio <- mase_denominator(train, test) # 季节朴素(lag12)的 MAE
  mae <- mean(abs(preds$price - test$price[match(seq_len(nrow(preds)), seq_len(nrow(test)))]))
  coverage <- mean(
    preds$price - stats::qnorm(0.95) * preds$.sd <= test$price &
      preds$price + stats::qnorm(0.95) * preds$.sd >= test$price,
    na.rm = TRUE
  )
  list(
    mase = mae / naive_ratio,
    coverage = coverage,
    n_predict = nrow(preds)
  )
}

# 季节朴素基线：predicted(t) = value(t-12)（月度季节 lag）
mase_denominator <- function(train, test) {
  key <- paste(test$state, test$period)
  lagkey <- paste(test$state,
                  format(as.Date(paste0(test$period, "-01")) - years(1), "%Y-%m"))
  idx <- match(lagkey, paste(train$state, train$period))
  baseline <- train$price[idx]
  keep <- !is.na(baseline)
  mean(abs(test$price[keep] - baseline[keep]))
}

years <- function(n) n * 365.25

## 固定的输出格式（program.md 的 grep 锚点依赖此格式）
report_results <- function(eval) {
  cat(sprintf("mase:       %.6f\nbad_coverage: %.6f\ncoverage:   %.6f\nn_predict:  %d\n",
              eval$mase, abs(eval$coverage - 0.90), eval$coverage, eval$n_predict))
}

run_experiment <- function(...) {
  eval <- evaluate_model(...)
  report_results(eval)
  invisible(eval)
}
