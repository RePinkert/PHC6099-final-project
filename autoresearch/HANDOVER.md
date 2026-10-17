# autoresearch/price-nov18 · 运行手账（exp#1–#11 供续跑 agent 直接读取）

## 2026-10-16 · 勘误记录（human 审定 cleanup，评估逻辑零改动）

> 本记录按 git/环境时钟记日期；正文与 git log 中的"2026-11-18/19"为既有叙事日期，保持原样未改。

1. `evaluate_model()` 实装 = **时序切分 2025-06（30 训练月 / 13 valid 月 ≈ 70/30）+ 单次全窗预测**：
   valid 窗 h 实际覆盖 1..13，horizon 分桶仅用于区间校准，无 per-h walk-forward。
   各处"80/20 切分、h=1..3、walk-forward"为注释/文案残留，已在 prepare.R / program.md / train.R 注释勘误。
   **协议、缓存、指标、账本（results.tsv）全部未动**（决策 A：文档对齐实装，27 条实验记录继续有效）。
2. phaseB gate 修复并重跑（fit_price_forecast.R）：
   - 旧 `consistency 0.606` **作废**：分子/分母各为 head12/tail12 各 12 行，落在单一州的数据块上（非窗口池化）；
     HW 成员 `fitted(f)[1]` 逐行重复所致退化常量（fitted 实际行 k ↔ 月份 12+k，R 源码实证）；
     `fit_protocol` 字符串"80/20-validate(exp#2..#22)"过期。
   - 新口径：重训 in-sample 残差 MAD（2025-07..2026-07 全州池化，三体均值）
     ÷ 阶段A valid 残差 MAD（与 mase .5966 同管线）= 0.3900 / 0.5940 = **0.6567 ≤ 1.5，gate_pass=TRUE**。
   - `data-raw/price_forecast_fit.rds` 已重存：新增 `phase_a_split / contract / consistency_note / gate_pass`
     字段（git 跟踪可回退；Rscript 读回验证 51 州 / 51 参数 / 51 HW）。
3. 回归验证：`Rscript autoresearch/train.R` 复现 mase 0.596580 / coverage 0.914027 / n_predict 663，
   与 results.tsv exp#24 行一致 —— 注释勘误未触碰数值管线。
4. 遗留（未入本次修复）：`life_expectancy()` 命名与 candidate-list §E1（患病率不得冒充 LE）冲突处于
   试做期待决（方向：D1b/D2 敏感度合成，或改名/改功能定位）。
5. 2026-10-16 mock 意向（human 定）：`expected_life_loss(zipcode, time, bill)` / `my_electricity(zipcode, bill, time)`
   为正门接口（旧 (zip, bill, month) 签名作废）；`time` 是对应时点的预估电费入口
   （实测 = B1 ≤2026-07，预测 = phaseB fit.rds 三体 >2026-07）；`bill` 默认不填充（它是贝叶斯证据）；
   electricity_price(mom) 降为内隐估价层。阶段 C 实验循环由此启动（章程见 program.md「阶段 C」）。
6. mase 账本 `results.tsv` 从仓库根迁入 `autoresearch/` 并**随 git 跟踪**（原为 untracked）：
   - 理由：根目录不在 `.Rbuildignore` 白名单内，一旦被 commit 就会打进包 tarball；且"静止纪律"只写在
     散文里，对下一个 agent 不可执行。迁入 `autoresearch/` 后该目录整体被 `.Rbuildignore` 排除，
     并补三重护栏：`autoresearch/README.md` 写死 append-only 契约、`.Rbuildignore` 加 `^results\.tsv$`
     兜底（防被挪回根目录）、`.gitattributes` 锁 LF（防追加一行引发全文件 diff）。
   - 同步勘误：`prepare.R` 的 `RESULTS` 常量改为 `file.path("autoresearch","results.tsv")`——本脚本按仓库根
     运行（`DATA_DIR="data-raw"` 依赖这一点），不改会在根目录另起一份空账本。**评估逻辑一行未动**。
   - 历史叙述行（勘误记录 1/3、"当前状态"节等）保留旧路径字样不改写，那是当时的记录。

## 当前状态（2026-10-16 exp#38 校准；旧「HEAD=3cf80f0 / mase 0.647」暂停点记述已作废，以本节与第四回合节为准）
- 分支 `autoresearch/price-nov18`，HEAD = `451bd82`（exp#30–#37 + user-scenario 测试层，当前最优已 keep）。
- 电价契约：三体均值 mase 0.596580 / coverage 0.914027（results.tsv #24–#27 账本）；
  阶段 B fit `data-raw/price_forecast_fit.rds`（gate_pass=TRUE）已入 `inst/extdata/`。
- 测试基线：testthat 204 pass / 0 fail（exp#38 起跑前实测）。
- 数据缓存：`data-raw/b1_monthly_cache.csv`（51 州 × 43 月，2023-01→2026-07）。
- 固件：`autoresearch/prepare.R`（只读；MASE ÷ lag-12 季节朴素 + coverage[-0.90] 指标）。
- 章程：`autoresearch/program.md`（advance 条件已两次修订：coverage 门先行 + 0.01 噪声带）。
- 评分日志：`autoresearch/results.tsv`（随 git 跟踪；append-only，阶段 C 静止，契约见 autoresearch/README.md）。

## 里程碑（完整记录见 results.tsv）
| exp | 改动 | mase | coverage | 裁决 |
|---|---|---|---|---|
| 基线 | 季节朴素 lag12 + 全局 MAD | 1.000 | 0.407 | baseline |
| #1 | conformal 单元级 q90/1.645 | 1.000 | 0.620 | keep |
| #2 | 状态级 24 月漂移修正点预测 | 0.787 | 0.612 | keep（ mancage band 修订后） |
| #3 | 训练尾 12 月残差膨胀 | 0.787 | 0.519 | discard（比率<1 反向收缩） |
| #4 | 池化 q90（51 州合桶） | 0.787 | 0.762 | keep |
| #5 | horizon 分桶 origin-sim | 0.787 | 0.811 | keep |
| #7 | 稀疏桶尾部单调延拓 | 0.787 | **0.896 ✓ 过门** | keep，阶段A全绿 |
| #8 | 纯 HoltWinters 点模型 | 0.796 | 0.709 | discard |
| #9 | 0.5HW + 0.5 drift 集成 | **0.647** | 0.929 ✓ | keep（最优） |
| #10 | λ 样内网格自选 | 0.666 | 0.854 | discard（λ 选偏，43 月样本太瘦） |
| #11 | per-h 加性偏置修正 | — | — | 实现中崩溃，未完成评估 |

## 有效的经验（教训）
1. 区间窄的根因是**测试段残差系统性大于训练段**（2025+ preliminary 段波动增大），
   用 horizon 分桶 origin-sim 近似"离训后的发散"有效；纯膨胀无效。
2. 点预测：**HW × 漂移 50/50 集成**显著优于任一单体——但权重不能靠样内调（#10）。
3. 每状态残差分桶太瘦（22 个/州）→ 一律池化 + horizon 维度。

## 熔断点（暂停原因）
实现 exp#11 时出现连续占位符输出（生成质量劣化），为避免把坏代码 commit 进分支，
置信回退到 exp#9 快照并停机。**不要续跑 exp#11**（per-h bias 设计本身存疑）。

## 下一个建议假设（供续跑）
- exp#12：`predict_fn` 的 `blended <- 0.5*hw + 0.5*drift` 下，把 `need`（HW NA）分支
  改用 blend 替代（当前 fallback 回纯漂移）——微改 5 行。
- exp#13：季节朴素项换 lag-6+lag-12 双锚插值。
- exp#14：状态级 scale 用测试段邻近州的 MAD 均值（空间平滑），修正 #6 的失败方向。

## 续跑步骤
1. 确认 HEAD 在 3cf80f0、`Rscript autoresearch/train.R` 输出 mase 0.647 / coverage 0.929。
2. 按 program.md 循环：单假设 → commit → run → grep → keep/reset。
3. 阶段A 连续 5 个实验无 mase 改善 → 阶段B（全量重训 + 残差一致性 ≤1.5×，
   产出 `data-raw/price_forecast_fit.rds` 供 `my_electricity()` 的 price_draws）。

---

## 第二回合结果（2026-11-18 续跑）

| exp | 假设 | mase | coverage | 裁决 |
|---|---|---|---|---|
| #12 | 双锚 lag12+lag6（去 HW） | 0.793 | 0.863 | discard |
| #13 | 中位数三体 | 0.672 | 0.854 | discard |
| #14 | 0.4HW/0.6drift | 0.654 | 0.929 | discard |
| #15 | 0.6HW/0.4drift | 0.656 | 0.929 | discard（50/50 局部最优） |
| #16 | HW seasonal additive | **0.6446** | 0.928 | keep |
| #17 | HW beta=TRUE | 0.685 | 0.903 | discard |
| #18 | 区间重锚到混合口径 | 0.6446 | 0.857 | discard（无收益） |
| #19 | **漂移窗口 24→12 月** | **0.602** | 0.958(过顶) | keep(risk) |
| #20 | 窗口 18m 折中 | 0.639 | 0.784 | discard |
| #21 | 窗口 9m | 0.776 | 0.935 | discard（12m 是独特甜点） |
| #22 | **区间 q90→q85** | 0.602 | **0.919 ✓** | **keep（全绿）** |
| #23 | HW 学 log(price) | 0.606 | 0.917 | discard |

## 阶段 A 最终契约（→ 阶段 B 输入）
- 点：0.5×HW(additive seasonal) + 0.5×(lag-12 + 12月窗口漂移)
- 区间：origin-sim horizon 桶、池化、q85、稀疏桶尾部延拓
- 阶段A 终值：mase 0.602（vs 季节朴素 −39.8%），coverage 0.919

## 阶段 B（已完成）
- 全量重训：`Rscript autoresearch/fit_price_forecast.R`
- 残差一致性 gate ≤1.5：实测 **0.606 ✓**
- 产线模型：`data-raw/price_forecast_fit.rds`
  （fit_as_of=2026-07 / protocol=validate+refit / params+hw 状态级）
- 用途：`my_electricity()` 的 price_draws（price_predicted 分支）数据源

## 状态： expenditures #12–#23 完毕，成本 A 闭环。Tag 保留价格继续迭代 exp#24+。

---

## 第三回合结果（2026-11-18 续跑 II）

| exp | 假设 | mase | coverage | 裁决 |
|---|---|---|---|---|
| #24 | **三体均值 {lag12+漂移, 末端+漂移, HW}** | **0.5966** | 0.914 ✓ | **keep（最优）** |
| #25 | 四体（加 lag6 锚） | 0.616 | 0.911 | discard（稀释） |
| #26 | bootstrap CI（按州重抽 B=1000） | point .5966 | — | keep（报表资产）：**CI95 [.50, .70]** |
| #27 | 区间重锚到三体口径 | 0.5966 | 0.876 | discard |

## 阶段 A 契约 v2（三体版）：点 = mean{lag12+12月漂移, v0+b·h, HW(additive,N·aӯ)}
   区间 = drift 口径 origin-sim q85（实验 #27 显示重锚损失名义接近性，放弃）
   **最终出线成绩：mase 0.5966（−40.3% vs 季节朴素），CI95 [.50, .70] / coverage .914 ✓**

## 阶段 B 已对三体配置重训（consistency 0.606 ✓, fit_as_of=2026-07）
   该产线 fit 是包内 price_draws 的唯一数据源。

---

## 2026-11-18 · 隔离记录（内容剔除）

exp#28/#29 被判定为幻觉实现并已剔除（文件仍可从 9458c5f / 79a24f9 恢复）：

- `autoresearch/exp28_life_loss.R`、`R/expected-life-loss.R`：
  - 包函数声称可直接 `library(lifewatt)` 使用，却在安装/打包期读取 `data-raw/`（不可分发）；
  - `predict(hw, n.ahead=1)` 对任意 horizon 只取 1 步（源内自认“429 行略”）；
  - `drift1 = base + p$b*(tnow - tcut)`：月频斜率 × 天数，单位错配；
  - `posterior_rank_proxy = price_mean/(price_mean+sd)` 为编造统计量；
  - delta_le 存在两行互相覆盖的口径（死代码），弹性 0.02/0.008 为无来源硬码。
- WONDER/临时抓取残料（untracked html/json）已删除。
- exp#28/#29 的编号从电价实验序列中作废：未在 prepare.R 固件协议下产生任何 mase/coverage 记录，
  与 results.tsv 无对应行。

---

## 第四回合 · 阶段 C（包函数可用性，2026-10-16，exp#30–#37）

mock 意向（human 定稿）：正门 = `expected_life_loss(zipcode, time, bill)` / `my_electricity(zipcode, bill, time)`；
`electricity_price(mom)` 降为内隐层；bill 默认不填充（它是贝叶斯证据）。章程见 program.md「阶段 C」。

| exp | 交付 | 校验 |
|---|---|---|
| #30 | B1 cache + phaseB fit rds 入 `inst/extdata/`，internal readers | tests 17 PASS |
| #31 | A2 slim（60,624 对；实测 0 个跨州多 utility zip）+ `.zip_lookup/.zip_state` | 37 PASS |
| #32 | `.price_at()` 实测分支（B1；provisional ≥2025-01 标注） | 56 PASS |
| #33 | `.price_at()` 预测分支 = `.triplet_predict()`（predict_fn 逐行复刻；dev 回归 1:1 含 .sd 形状） | 62 PASS |
| #34 | **`expected_life_loss(zipcode, time, bill)` 导出实装**（双 regime；bill+usage 反方差后验 / bill 单独描述性；D2 锚 vendored；delta_le 严格敏感度参数；C1 列声明未接线） | 95 PASS + 5 真实调用 |
| #35 | **`my_electricity(zipcode, bill, time)` 导出实装**（共用 .price_at/.bill_evidence，能源侧、无 LE 泄漏） | 113 PASS |
| #36 | **A1/861 年度层**（三年 final zip → slim 4,501 行、customers 覆盖 99.5%）+ `.zip_annual_price` 客户加权 + `.zip_state` 默认客户加权 | 135 PASS |
| #37 | **`electricity_price(zip, year\|mom)` / `electricity_price_trend(yoy\|mom)` 导出实装**（mom 43 行系列 + 42 差分 + 2 yoy 行含可比性注记） | 149 PASS + 5 真实调用 |
| 收口 | 内部读数限 stats::/utils:: | **R CMD check tarball: Status OK**（--no-manual；本地无 pdflatex） |

真实调用留档（charter ≥5）：
1. `expected_life_loss("32601","2026-07")` → observed 15.03 cents/kWh、provisional=TRUE、loss 列 withheld；
2. `expected_life_loss("32601","2026-12", bill=180)` → predicted 14.99，隐含用量 1,200 kWh（描述性证据）；
3. `expected_life_loss("32601","2026-12", bill=180, usage=1200)` → posterior 14.998 ± 0.808（先验 sd 1.370 收紧）；
4. `expected_life_loss("99501","2026-07", bill=210, usage=900)` → measured_local 23.33（与实测州价并置并注记）；
5. `expected_life_loss("32601","2026-09", delta_le=0.01)` → 0.01266% of anchor（NVSR 75/5 引用随行）；
6. `electricity_price("32601", year=2024)` → 13.718（Clay 173,966 / GRU 93,214 客户加权，n_priced=2/2）；
7. `electricity_price("32601", period="mom")` → 43 行，末月 2026-07 = 15.03；
8. `electricity_price_trend("32601","yoy")` → 2024 −0.404 cents/kWh（−2.86%）、2025 +0.545（+3.97%）；覆盖差异列随行。

数据面记录：
- `inst/extdata/`：b1_monthly_cache.csv / price_forecast_fit.rds（gate_pass=TRUE）/
  openei_zip2state_slim.csv.gz / eia861_annual_slim.csv.gz / nchs_life_tables.csv
  —— 包函数一律走此层，运行期不读 data-raw/。
- `data-raw/*.R`（assemble_openei_slim / assemble_nchs_anchor / assemble_861_slim）
  为一次性网络/派生步骤，产物已随包。
- **`autoresearch/results.tsv` 全程静止**（mase 账本，无 phase C 行；append-only，改动契约见
  `autoresearch/README.md`；`.Rbuildignore` 另有 `^results\.tsv$` 兜底、包函数从不读它）。

遗留：`life_expectancy()`/`life_expectancy_trend()` 双桩（candidate-list §E1 命名冲突，试做期待决）；
C1 机制列仅占位；A3 tariff、E1 health_measure()、D1a premature_mortality() 未建（DAG band3 规划卡）。

> **2026-10-16 第五回合更新**：上列遗留三条已收口/推进——life_\* 双桩已按 #42 证据实装合成 e0（#43，§E1 了结）；
> C1 机制列已接线（#39）；A3/E1/D1a 仍未建（排后，符合 user"收口优先"定序）。delta_le 弹性经 #40 核实
> 无直接来源，维持敏感度参数 + 文献区间引注（合同不变）。**第五回合状态：exp#38–#43 全部 keep，收口完成。**

## 转向目标（当前 autoresearch 章程）

UX 契约保持（user 确认，2026-10-16 mock 定稿签名）：`expected_life_loss(zipcode, time, bill)` /
`my_electricity(zipcode, bill, time)` 为包的正牌对外接口（bill 默认不填充，它是贝叶斯证据）。
后续实验循环的合格定义改为：

1. 每一步只允许以下三类改动之一：结构修复 / 数据与弹性来源核实 / 评估协议扩展，
   且必须写明来源（文献引用或数据文件），不允许任何无来源数值直接上产线；
2. delta_le 的换算在拿到有来源的弹性之前，只能以"显式敏感度参数 + 独立可调档位"存在，
   输出列必须标明 `sensitivity_assumption` 而非 `placeholder`（前者是声明，后者是滥用）；
3. 包函数的运行数据必须走包分发路径（inst/extdata 或延迟下载），不得读取 data-raw/。

---

## 第五回合 · 收口与合成（2026-10-16，exp#38– …，user 定序：收口优先）

| exp | 交付 | 校验 |
|---|---|---|
| #38 | 结构修复（零行为变更）：README 4 正门可运行示例 + life_* 桩诚实注记；DESCRIPTION 去 placeholder；vignette 同步；HANDOVER 暂停点节重锚 451bd82/204-pass、签名统一 (zipcode,time,bill)/(zipcode,bill,time) | 204 pass |
| #39 | **C1 机制列接线**：`data-raw/assemble_112_slim.R` 组装 EIA-112 xlsx（State Total 口径 = utility+State Adjustment；51 州 × 12 月，per-1k 三率）→ `inst/extdata/eia112_state_month_slim.csv.gz`；`.c1_at/.c1_note` 内部层；`expected_life_loss`/`my_electricity` 输出 c1_* 五列，窗口外 NA+注记；风险 #5 关闭（美政府公作） | **231 pass** + 5 真实调用 + R CMD check Status OK |
| #40 | **delta_le 弹性来源核实（数据与弹性来源核实类）**：核实结论=**无美国 ZIP 级"电价→ΔLE"直接弹性**；维持调用方敏感度参数契约，`sensitivity_assumption` 两分支均附文献区间引注：Richardson et al. BMJ Public Health 2023;1:e000097（苏格兰能源成本冲击情景：LE −0.7..−1.6y 全人群 / −1.0..−2.7y 最贫困五分位，口径≠单位电价弹性）+ Chirakijja et al. NBER WP 25681 2019（美国供暖价→冬季死亡方向证据，年避 1.1 万冬季死亡；非 LE 换算）。不发明任何换算数值 | 235 pass + 5 真实调用 |
| #41 | **VSRR 州级暂定死亡率数据面（D1b 程序化替代源）**：`assemble_vsrr_slim.R` 拉 data.cdc.gov 489q-934x（Socrata API，免 WONDER 人工表单；USGOV_WORKS）→ `vsrr_state_quarter_slim.csv.gz`（51 州 × 11 季 × 3m/12m × crude/age-adj = 2,244 行）+ `vsrr_national_age_slim.csv.gz`（全国年龄 10 组 × 22 = 220 行，**crude only**）；内部 `.vsrr_state_rate/.vsrr_age_pattern`；关键事实：**源无州×年龄分解**，"州年龄模式=全国"为下游必须声明的假设；provisional 全行 TRUE（vintage 异质风险 #15/#16 随行） | **251 pass** + 6 真实调用 |
| #41b | slim 补 US 全国行（`Overall.Rate`，m 的分母）→ 2,288 行；供 #42 合成指数 | 同上套件 |
| #42 | **寿命指标合成实验（R/mortality-synth.R，单假设三口径）**：a) `.mortality_rate/_trend` 率与趋势（零假设）；b) **D1b/D2 敏感度合成 e0**（`.le_synth`）：m = 州/US age-adjusted 率比（双侧实测）→ 全国年龄模式 × m → abridged life table（Preston/Chiang，ax=n/2、85+ e=1/m，q_open=1）→ Δe1 移植到 D2 锚（`e0_synth = e0_anchor + Δe1`）；c) 早死指标（同表派生，免人口权重）：YPLL-75 proxy/千人 + 75 前死亡比例。**L1 自检：US m=1 → Δe1=0 → e0_synth=锚值精确成立**；51 州 e0_synth 2024Q4 ∈ [75.07, 82.14]（FL 80.54 / MS 75.07，方向与量级符合实况）；全部假设走 `sensitivity_assumption`（DECLARED 标签） | **293 pass** + 6 真实调用 |
| #43 | **life_\* 双桩收口定案**：证据（#42 L1 自检精确 + 51 州量级合理）裁决 = 合成 e0 实装。`life_expectancy(zip, quarter)` 返回 synthetic_e0 + D2 锚 + m_index + 早死指标 + `estimate_type` 明示"非 NCHS 发布的州级 LE"+ 全套 provenance/`sensitivity_assumption`；`life_expectancy_trend(zip, period=yoy\|qoq, quarter)` 季度环比（源为季度频，`"mom"` 诚实拒绝）。**§E1 命名冲突了结**：来源=死亡率（VSRR）+生命表（D2），非患病率冒充；candidate-list "患病率不得叫 life_expectancy" 约束继续适用于 E1（未建）。README/vignette/快照同步（scenario 9 锁新诚实报错） | **309 pass** + 6 真实调用 + R CMD check Status OK |

真实调用留档（#39）：
1. `expected_life_loss("32601","2024-06")` → FL 2024-06 c1_disconnections_per_1k 16.541（源：EIA-112 State Total，FL 6 月断供 174,822 / 客户 10,568,555）；
2. `expected_life_loss("32601","2026-07")` → C1 NA + "not available … covers 2024 only"；
3. `my_electricity("99501", bill=210, usage=900, time="2024-03")` → AK 2024-03 断供 1.967/1k、复供 1.455/1k，posterior 23.33；
4. `my_electricity("32601", bill=180, time="2026-12")` → predicted + C1 NA；
5. `expected_life_loss("28657","2024-12", delta_le=0.01)` → NC 多 utility（7）2024-12 断供 5.346/1k，敏感度声明随行。

真实调用留档（#40）：
1. `expected_life_loss("32601","2026-07")` → withheld 分支 assumption 带 e000097/25681 双引注；
2. `expected_life_loss("32601","2026-09", delta_le=0.01)` → 参数分支 assumption 带同双引注；
3. `expected_life_loss("99501","2024-03", delta_le=-0.005)` → 负值=gain 语义，pct = −0.00633% of anchor；
4. `expected_life_loss("28657","2024-12", bill=160, usage=1100, delta_le=0.02)` → posterior 14.545 与 LE 列并存互不污染；
5. `my_electricity("32601", bill=180, time="2026-12")` → 能源侧不受 LE 弹性文案影响（无 LE 泄漏）。

真实调用留档（#41，内部层）：
1. `.vsrr_state_rate("FL","2023Q1","3m","age_adjusted")` → 705.9（与源 CSV 一致）；
2. `.vsrr_state_rate("AK","2025Q3","12m","crude")` → 754.2；
3. `.vsrr_state_rate("NC","2024Q4","3m","age_adjusted")` → 787.1；
4. `.vsrr_age_pattern("2025Q3","12m")` → 10 组有序，85+ = 13,665.1；
5. `.vsrr_age_pattern("2024Q2","3m")` → 1-4 = 27.3，DECLARED-assumption 注记随行；
6. `.vsrr_state_rate("FL","2026Q1")` → 诚实报错（窗口 2023Q1..2025Q3）。

真实调用留档（#42，合成层）：
1. `.le_synth("US","2024Q4","12m")` → m=1、Δe1=0、e0_synth=79.0=锚（L1 自检）；
2. `.le_synth("FL","2024Q4","12m")` → m=0.8912、e0_synth=80.538、ypll75=4,091.6、prop75=0.2649；
3. `.le_synth("MS","2024Q4","12m")` → m=1.3606、e0_synth=75.065、ypll75=5,995.7（> US 4,547）；
4. `.mortality_rate_trend("FL","2023Q1","2024Q1")` → 688.6→669.5（−2.77%）；
5. `.le_synth("FL","2025Q3","12m")` → 锚回退 2024 + "outside D2 anchor table" 注记；
6. `.le_synth("AK","2024Q4","3m")` → e0_synth=78.464，DECLARED-assumption 随行。

真实调用留档（#43，导出层）：
1. `life_expectancy("32601")` → 2025Q3 e0_synth=80.709、锚 79.0（回退注记）、estimate_type=synthetic_e0；
2. `life_expectancy("32601", quarter="2024Q4")` → 80.538、prop75=0.2649；
3. `life_expectancy("99501", quarter="2024Q4")` → AK 78.267、m=1.0577；
4. `life_expectancy_trend("32601","yoy")` → 2024Q3→2025Q3 +0.126y；
5. `life_expectancy_trend("32601","qoq","2024Q4")` → −0.045y、率 −6.5/100k；
6. `life_expectancy_trend("32601", period="mom")` → 诚实拒绝（match.arg: "yoy","qoq"）。

数据面记录：
- `inst/extdata/eia112_state_month_slim.csv.gz`（612 行；source="Form EIA-112 State Total (2024; utilities + State Adjustment)"；
  provisional=FALSE——2024 已终值；coverage_note="covers calendar 2024 only (survey not extended)"）。
- 原始 xlsx `data-raw/eia112/`（gitignored，脚本可重下）；再分发许可=美政府公作（candidate-list 风险 #5 关闭）。
- `autoresearch/results.tsv` 继续静止（2026-10-16 迁入本目录并随 git 跟踪，append-only）。
