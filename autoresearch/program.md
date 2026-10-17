# autoresearch · lifewatt 版（adapting karpathy/autoresearch）

LLM 自主研究闭环：唯一目标是降低 `autoresearch/prepare.R::evaluate_model()` 输出的
**mase**（MASE ÷ 季节朴素，越低越好），同时保 **coverage ∈ [0.85, 0.95]**。

任务：州级月度住宅电价（EIA B1，2023-01 → 2026-07，51 单元 × 43 月）多步预测
（valid 单次全窗评估，h 实际 1..13；horizon 分桶仅用于区间校准；2026-10-16 勘误）。

## Setup（首次，与 user 确认后执行）

1. 本分支已是 `autoresearch/price-nov18`，勿换 tag。
2. 通读三个文件：
   - `autoresearch/prepare.R` — **只读固件**：数据准备 + 评估基准（MASE/coverage/一致性检查）
   - `autoresearch/train.R` — **唯一可改文件**：fit_model_fn / predict_fn + 训练逻辑，一切公平游戏
   - 本文件 — 组织章程（agent 不改，human 修改）
3. 数据检查：若 `data-raw/b1_monthly_cache.csv` 不存在 → 要求 user 设置 `EIA_API_KEY`
   （注册 https://www.eia.gov/opendata/register.php ）后由 `Rscript autoresearch/prepare.R`
   的一次性调用拉全。**不要绕过缓存**（尊重 EIA API rate limit）。
4. 账本 `autoresearch/results.tsv`（header: commit / mase / bad_coverage / status / description，
   tab 分隔）已存在且随 git 跟踪；**只在末尾追加新实验行**，历史行不改写（契约见 autoresearch/README.md）。
5. 第一次运行必须是无改动 baseline（季节朴素，预期 mase ≈ 1.0）。

## 硬约束

- **不可改**：`prepare.R`、`autoresearch/results.tsv` 的 schema、评估协议（时序切分 2025-06 =
  30 训练月/13 valid 月、单次全窗评估 h=1..13、MASE 分母、coverage=90% 目标）。
- **不可新增依赖**：只用 base R + `jsonlite`（prepare 已用）。torch 等 heavyweight
  需 user 显式批准才可加 `Suggests`，且必须过 `02_check_backend` 式门禁。
- **预算**：单实验 ≤ 5 min wall clock（R 无 GPU 亦无重编译，通常 <5s；超 10 min kill as crash）。
- **诚实判定**：mase 必须回落到同一 `evaluate_model()`；禁止改 metric、不得测试集泄漏
  （valid 段 2025-07..2026-07 永远不可在 fit 内可见）。
- **简洁准则**：同量改善取简单方案；复杂度换 0.001 级 mase 改善 = discard；删复杂代码
  保持相等 mase = keep。

## 输出锚点（grep 用）

`Rscript autoresearch/train.R` 打印：

```
mase:       0.xxxxxx
bad_coverage: 0.xxxxxx
coverage:   0.xxxxxx
n_predict:  N
```

## Experiment loop（LOOP FOREVER，autonomous）

1. `git status / log --oneline -1` 确认分支与当前 commit。
2. 在 `train.R` 实施一个**单一假设**的改动（一次改一个 idea，便于归因）。
3. `git add -A autoresearch/ train.R && git commit -m "<idea>"`
4. 运行 `Rscript autoresearch/train.R > autoresearch/run.log 2>&1`。
5. 读取结果 `grep "^mase:\|^coverage:\|^bad_coverage:" autoresearch/run.log`。
   为空 → crash：读 `tail -n 50`，简单 bug 修后重跑（仍是同一 commit），结构性问题
   → 记 `crash`，`git reset`，go to next idea。
6. 追加 `autoresearch/results.tsv`（随 commit 走；只加行，历史行不动）。
7. **advance 条件（词典序，2026-11-18 修订）**：
   a. 若当前最好 bad_coverage > 0.05：coverage 持平或改善 即可 keep（首要任务是过 coverage 门），mase 不得劣化超过 0.05；
   b. coverage 门已过（≤0.05）后：mase 严格更低才算 keep；
   否则 `git reset --hard` 回退本实验。
8. 每逢 mase 创新低：记 `keep` 并继续。
9. 简洁裁汰：改进 < 0.5% 且代码复杂度上升 → 也 git reset。

## 阶段 B（全量重训，仅当 user 早上或其他触发点确认阶段A结束）

- 用胜者模型在 2023-01..2026-07 全量重训，产出 `data-raw/price_forecast_fit.rds`
  （含 fit_as_of / valid_window / fit_protocol 字段）。
- 一致性 gate（fit_price_forecast.R 实装，2026-10-16 统一口径）：重训 in-sample 残差 MAD
  （2025-07..2026-07 全州池化，三体均值口径）÷ 阶段A valid 残差 MAD ≤ 1.5；
  超标 → 记 keep_at_risk（gate_pass=false 落 rds），下游不得当作已验证口径引用。
- 本阶段产出服务 `my_electricity()` 的 price_draws，不触发新的评估循环。

## 阶段 C（包函数可用性，2026-10-16 human 批准）

- 目标：把 4 个导出桩接到合法数据路径并产出真实、带 provenance 的返回值；以
  `expected_life_loss(zipcode, time, bill)` / `my_electricity(zipcode, bill, time)` 为正门
  （2026-10-16 mock 意向：electricity_price(mom) 为内隐估价层；bill 默认不填充——它是贝叶斯证据）。
- 循环：单假设 → commit → 校验（testthat 全绿 + ≥5 真实调用锚点 + provenance 列齐全）
  → 记 HANDOVER「第四回合」节 → 不合格 `git reset` 回退。
- 可改面：`R/`、`inst/`、`tests/`、`data-raw/*.R` 组装脚本（一次性网络步骤放这里）；
  `prepare.R` 仍只读；`autoresearch/results.tsv` 静止（mase 账本），阶段 C 不写。
- 数据面：包函数一律走 `inst/extdata/`（缓存优先）或声明式延迟下载，**禁止读 data-raw/**。
- 预算与节奏同主循环（单实验 ≤ 5 min wall clock）；无来源的分布假设不得上产线，
  一律以显式参数 + `sensitivity_assumption` 列声明。

## NEVER STOP

循环启动后不要问 user "continue?"。想法枯竭时：重读 prepare.R 找漏掉的信号（季节
形态 / preliminary 段跳变 / 单元聚类）、组合次优近失.try 更激进的结构（层级状态空间
、Rcpp 加速、RcppArmadillo 需先声明）。循环直到被外部中止。
