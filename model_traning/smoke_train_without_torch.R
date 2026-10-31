# smoke_train_without_torch.R —— 不装 torch 时检查 train_price_lstm.R 训练之外的全部步骤能跑通
# 做法：把 train_price_lstm.R 里 torch 训练那一段（lstm_cell 定义 .. model$eval()）换成"随机权重的纯 R LSTM"，
#   其余代码（数据、目标、三元组、基线、区间、预测、导出）原样执行，fit 写到指定路径而不是 inst/extdata。
# 产物只用于检查管道（反变换、区间、预测、导出字段），权重是随机的，预测没有意义，绝不能随包发布。
# 运行：Rscript model_traning/smoke_train_without_torch.R <输出 rds 路径>

out <- commandArgs(TRUE)[1]
stopifnot(!is.na(out), !grepl("inst/extdata", out, fixed = TRUE))
src <- readLines("model_traning/train_price_lstm.R")
a <- grep("^lstm_cell <- nn_module\\(", src)
b <- grep("^model\\$eval\\(\\)", src)
stopifnot(length(a) == 1, length(b) == 1)
stub <- c(
  "set.seed(20261022)",
  "Wst <- list(w_ih = matrix(rnorm(4 * HID * NCH, sd = 0.05), 4 * HID, NCH),",
  "            w_hh = matrix(rnorm(4 * HID * HID, sd = 0.05), 4 * HID, HID),",
  "            b_ih = rep(0, 4 * HID), b_hh = rep(0, 4 * HID),",
  "            w_out = matrix(rnorm(H * HID, sd = 0.05), H, HID), b_out = rep(0, H))",
  "model <- function(X) {",
  "  n <- dim(X)[1]; Hm <- matrix(0, n, HID); Cm <- matrix(0, n, HID); sg <- function(x) 1 / (1 + exp(-x))",
  "  for (t in seq_len(dim(X)[2])) {",
  "    g <- matrix(X[, t, ], n) %*% t(Wst$w_ih) + Hm %*% t(Wst$w_hh) +",
  "      matrix(Wst$b_ih + Wst$b_hh, n, 4 * HID, byrow = TRUE)",
  "    i <- sg(g[, 1:HID]); f <- sg(g[, HID + 1:HID]); gg <- pmax(g[, 2 * HID + 1:HID], 0); o <- sg(g[, 3 * HID + 1:HID])",
  "    Cm <- f * Cm + i * gg; Hm <- o * pmax(Cm, 0)",
  "  }",
  "  sweep(Hm %*% t(Wst$w_out), 2, Wst$b_out, '+')",
  "}",
  "torch_tensor <- function(x) x; as_array <- function(x) x; with_no_grad <- function(x) x",
  "model_sd <- list(cell.w_ih = Wst$w_ih, cell.w_hh = Wst$w_hh, cell.b_ih = Wst$b_ih, cell.b_hh = Wst$b_hh,",
  "                 out.weight = Wst$w_out, out.bias = Wst$b_out)",
  "eval_es <- function() list(pred_norm = model(va$X))",
  "best <- NA_real_"
)
src <- c(src[seq_len(a - 1)], stub, src[(b + 1):length(src)])
src <- sub("suppressMessages(library(torch))", "", src, fixed = TRUE)
src <- sub("torch_manual_seed(20261022)", "", src, fixed = TRUE)
src <- sub("sd_ <- model$state_dict()", "sd_ <- model_sd", src, fixed = TRUE)
src <- sub('saveRDS(fit, "inst/extdata/price_lstm_fit.rds")', "saveRDS(fit, out)", src, fixed = TRUE)
stopifnot(!any(grepl("inst/extdata/price_lstm_fit.rds\")", src, fixed = TRUE) & grepl("saveRDS", src)))
eval(parse(text = src), envir = globalenv())
cat("smoke fit written to", out, "(random weights; pipeline check only)\n")
