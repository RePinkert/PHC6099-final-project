# exp#26 · MASE 的 block-bootstrap CI（按州重抽，保空间相关；1000 次）
# 只读 train.R 与缓存，不修改模型 —— 产出报告用数字。
source("autoresearch/prepare.R")
code <- paste(readLines("autoresearch/train.R"), collapse = "\n")
tailpos <- regexpr("if [(]sys[.]nf", code)[1]
eval(parse(text = substring(code, 1, tailpos - 1)))

cache <- prepare_data()
cache <- cache[order(cache$state, cache$period), ]
tv <- as.Date(paste0(cache$period, "-01"))
train <- cache[tv <= as.Date("2025-06-01"), ]
test  <- cache[tv >  as.Date("2025-06-01"), ]
m <- fit_model_fn(train)
preds <- predict_fn(m, test)
# 显式对齐（prepare 的匹配是行号假设）
stopifnot(nrow(preds) == nrow(test))
naive_num <- mase_denominator(train, test)

states_unique <- sort(unique(test$state))
set.seed(2026)
B <- 1000
bs_mase <- numeric(B)
for (b in seq_len(B)) {
  samp <- sample(states_unique, size = length(states_unique), replace = TRUE)
  idx  <- unlist(lapply(seq_along(samp), function(i) {
    w <- which(test$state == samp[i])
    w + (i - 1) * 0 # 保持州内序列
    # 对重复州直接重复 idx
    w
  }))
  # 州重抽后按州首查 test 行（重复州重复计入，集群 bootstrap）
  idx_list <- lapply(samp, function(st) which(test$state == st))
  idx <- do.call(c, idx_list)
  # naive 分母也按相同重抽口径
  idx_tr <- unlist(lapply(samp, function(st) which(train$state == st)))
  mn <- mase_denominator(train[idx_tr, ], test[idx, ])
  mae_b <- mean(abs(preds$price[idx] - test$price[idx]), na.rm = TRUE)
  bs_mase[b] <- mae_b / (if (is.finite(mn) && mn > 0) mn else naive_num)
}
q <- stats::quantile(bs_mase, probs = c(0.025, 0.25, 0.5, 0.75, 0.975))
point <- mean(abs(preds$price - test$price), na.rm = TRUE) / naive_num
cat(sprintf("mase point: %.4f\nmase CI95: [%.4f, %.4f]\nmase IQR:  [%.4f, %.4f]\nmedian: %.4f\n",
            point, q[1], q[5], q[2], q[4], q[3]))
