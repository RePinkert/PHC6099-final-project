# lifewatt 数据源候选清单

> 双重标注：**颗粒度** = 空间 × 时间（决定它能回答什么问题）
> **新鲜度** = 数据截止期 / 发布日 / 典型滞后（决定它值不值得用）
> 状态：**入选** / **备选** / **排除**
> 最后核实：2026-10-15

---

## 硬约束

> **4 年时间窗口 = 2023-01 → 2026-12**（含 2023 / 2024 / 2025 完整年 + 2026 年内月度数据）。
> 该约束按**数据年份 / 数据 vintage** 判定，不按发布日期判定。
> **池化禁令（2026-10-15 确立）：多年池化估计一律拒绝，不设例外。**
> 成分年含 < 2023 的年份即出局——三年池化的 CHR&R（2020–2022 / 2021–2023）
> 与五年池化的 **ACS 5-year**（vintage 2023 = 2019–2023、2024 = 2020–2024）同罪同罚。
> 因此 CHR&R、**F2 ACS 详细表**、**F1 自建能源负担（分母依赖 F2）**、
> NCHS 州生命表 2022、LEAD Tool 2022 版、USALEEP、IHME 县寿命**全部出局**。
> 单年观测不受禁令约束；非池化的模型化小区域估计（CDC PLACES）按 **BRFSS 参考年**判定：
> 仅 **2025 release（35 项 = BRFSS 2023）**合规。

### 约束的两处豁免

1. **Census 2020 关系文件（G 组）**：属**地理边界文件**（十年一版），不是时间序列观测，不适用年份约束。
   窗口内不存在任何其他 ZCTA 关系文件，若不豁免则整个 ZIP 级方案无法成立。
2. **数据存在"最终"与"暂定"两层**（2026-10-15 更正，详见"硬约束更正记录"）：
   EIA 月度电价可到 **2026-07**（已实测）；EIA-861 年度到 **2025**；
   **最终死亡数据止于 2024**；**暂定（provisional）死亡数据总覆盖 2018 → 至今，窗口内切片 2023-01 → 2026-09（约 45 个月）**。
   → 报告须明确区分这两层，并声明 provisional 会被回改。

> **不设第三豁免**：ACS 5-year 曾以"ZCTA 级收入唯一来源"申请豁免，**已否决**。
> 窗口内不存在非池化的 ZCTA 级收入数据（ACS 1-year 为单年估计但不覆盖 ZCTA），
> 正确结论是"能源负担无法合规构建"（F 组全删），而非给池化开口子。

---

## 判据说明

| 维度 | 判定标准 |
|---|---|
| 颗粒度·空间 | ZIP/ZCTA > utility > county > ISO 分区 > 州 > 全国 |
| 颗粒度·时间 | 小时 > 日 > 月 > 年 > 单一期 |
| 新鲜度 | 数据年距今 ≤ 2 年为**新**；2–5 年为**可接受**；> 5 年为**陈旧** |
| 工程约束 | 包必须能被 TA 一键装上就跑 → 网络调用一律 `\dontrun{}`；核心数据免 key，EIA key 可选 |
| 池化 | **多年池化估计一律拒绝**（CHR&R 三年、ACS 五年同罪同罚）；单年观测按观测年判定；模型化估计按参考年判定（PLACES = BRFSS 年） |

**结构性事实（决定天花板）：**

- 居民零售电价：空间最高 ZIP（须经 utility 归属），时间最高 **月**（月频仅到州）
- 批发电价：可到**小时**，但非居民零售、非 ZIP → 排除
- 断供：州/utility × **月**，**只有 2024 一年**（EIA-112 未延展）
- 死亡率 county 级有两个层次：
  - **最终数据**总覆盖 2018–2024，**窗口内切片 2023–2024**（Multiple Cause of Death, Single Race）
  - **暂定数据**总覆盖 2018 → 至今，**窗口内切片 2023-01 → 2026-09（约 45 个月）**（Weekly / Monthly / Quarterly Provisional Deaths）
- 期望寿命：窗口内 sub-state **无任何数据**；州级已出局；仅全国 2023 / 2024 可用
- 健康现况指标：**CDC PLACES 是唯一 ZCTA 原生且在窗口内的公共卫生数据集**——
  但 **release 年 ≠ 数据年（滞后约 2 年）**：2023 release = BRFSS 2021、2024 = BRFSS 2022、
  2025 = BRFSS 2023（35 项）+ BRFSS 2022（5 项）→ **仅 2025 release 的 35 项合规**
- 能源负担：**窗口内无非池化的 ZCTA 级收入来源**（单年估计不覆盖 ZCTA，五年估计为池化）
  → "能源负担"在本项目中无法合规构建，不设该维度

---

## 存留总表（一眼版）

| 组 | 数据源 | 数据年（实测） | 窗口覆盖（4 年） | 判定 |
|---|---|---|---|---|
| A1 | EIA-861 年度（utility 级价格 / 收入 / 用户数） | 2023 / 2024 / 2025（终值 2026-10-07；另有 2026-08 early vintage） | 3/4 年（无 2026 年度） | ✅ 入选 |
| A2 | OpenEI ZIP→utility 费率表（仅作映射） | 2024 | 映射 1 版套 3 年（近似已声明） | ✅ 入选 |
| A3 | OpenEI USURDB（费率结构） | 费率生效事件流（更新至 2026） | n/a（事件流） | ✅ 入选 |
| B1 | EIA API v2 `retail-sales` 月度 | 2023-01 → **2026-07**（43 月；2025/2026 为 preliminary） | 43/48 月 | ✅ 入选 |
| B2 | rOpenSci `eia` | — | — | ✅ 入选（范式） |
| C1 | **EIA-112 住宅断供调查** | **2024**（唯一一年） | **1/4 年** | ✅ **核心** |
| D1a | CDC WONDER MCD **最终**（county 死亡计数） | 总覆盖 2018–2024；窗口内 **2023 / 2024** | 2/4 年 | ✅ 入选（可选模块） |
| **D1b** | **CDC WONDER Provisional Mortality** | **2023-01 → 2026-09**（45 月） | 45/48 月 | ✅ **入选（时序外推的唯一标签源）** |
| D2 | NCHS United States Life Tables | 2023 / 2024 | 2/4 年 | ✅ 入选（全国锚点） |
| **E1** | **CDC PLACES** | **BRFSS 2023**（2025 release，35 项） | 1/4 年（2023） | ✅ **主干** |
| G1 | Census 2020 ZCTA 关系文件 | 边界文件（豁免） | 豁免 | ✅ 入选 |
| H1 | EIA RECS 2024 | 2024 | 1/4 年（背景） | ⚠️ 备选（背景） |

---

## A 组 · 零售电价（ZIP 级）

### A1. EIA-861 年度数据 — 入选（ZIP 级数值的唯一来源）

| 标注 | 内容 |
|---|---|
| 发布方 | U.S. Energy Information Administration (EIA) |
| 主页 | https://www.eia.gov/electricity/data/eia861/ |
| 2025 终值压缩包 | https://www.eia.gov/electricity/data/eia861/zip/f8612025.zip |
| 历年归档 | `https://www.eia.gov/electricity/data/eia861/archive/zip/f861<YYYY>.zip` |
| data.gov 归档入口 | https://catalog.data.gov/dataset/annual-electricity-price-by-state |
| 颗粒度·空间 | **utility（EIA ID）× state × sector**；另含 utility → county 服务区表 |
| 颗粒度·时间 | **年**；窗口内取 **2023 / 2024 / 2025** |
| 新鲜度 | **2025 终值 2026-10-07 发布**（另有 2026-08 early release vintage → **取 final**）→ 窗口内最新年度数据 |
| 鉴权 | 免 key，FTP 直下；文件名 `f861<YYYY>.zip` |
| 关键字段 | 住宅 `price`（cents/kWh）、`revenue`（千美元）、`customers`、`sales`（MWh） |
| 派生量 | **年均每户电费 = residential revenue ÷ residential customers**（美元/户·年） |
| 角色 | `electricity_price(zip, year)` 的**唯一**数值来源 |

**关键设计：数值与映射解耦。** ZIP→utility 归属（服务区）变化极慢，而价格逐年变动。
因此只取一次映射（A2，2024 版），再把 EIA-861 各年的 **utility 级价格**逐年套上去，
即可得到 **ZIP 级 2023 / 2024 / 2025 三年序列、两个同比差值**。

⚠️ 代价：2023 与 2025 的 utility 归属沿用 2024 边界，属近似，须在文档与 limitation 中标注。

### A2. OpenEI / NREL — U.S. Electric Utility Companies and Rates: Look-up by Zip Code — 入选（仅作 ZIP→utility 映射）

| 标注 | 内容 |
|---|---|
| 发布方 | NREL（原 Oak Ridge National Laboratory），OpenEI 平台，编制人 Jay Huggins |
| 底层 | EIA-861 + ABB + Velocity Suite（服务区边界） |
| 2024 版入口 | https://data.openei.org/submissions/8563 |
| 直接文件 | https://data.openei.org/files/8563/iou_zipcodes_2024.csv<br>https://data.openei.org/files/8563/non_iou_zipcodes_2024.csv |
| data.gov 元数据 | https://catalog.data.gov/dataset/u-s-electric-utility-companies-and-rates-look-up-by-zip-code-2024 |
| 许可 | CC-BY-4.0 |
| 鉴权 | 免 key，`read.csv()` 直下 |
| 颗粒度·空间 | **ZIP × utility**（IOU / non-IOU 两张表） |
| 颗粒度·时间 | **仅取 2024 版**；2022 / 2023 版虽在窗口内，但因 A1 已提供三年数值，不再需要 |
| 新鲜度 | 数据年 2024，发布 2025-11-10 |
| 体量 | 两个 CSV，各约 10 万行 |
| 在本包中的角色 | **只提供"哪个 ZIP 归哪个 utility"这一映射**，价格数值全部来自 A1 |
| 注意 | 官方原文 "average rates for each utility (**not** average rates per zip code)"。文件里的费率字段**仅作合理性校验**，不作返回值 |

**滞后断层记录**：EIA-861 已有 2025 终值（2026-10-07），OpenEI 的 ZIP 映射仍停在 2024 → 须写入 `NEWS.md`。

**一个 ZIP 命中多个 utility 的合并规则**是本包必须回答的方法学问题（住宅客户数加权 / 取默认档 / 返回多行），做成显式参数并提供敏感性对照。

### A3. OpenEI USURDB — U.S. Utility Rate Database — 入选（tariff 层）

| 标注 | 内容 |
|---|---|
| 主页 | https://apps.openei.org/USURDB |
| 按 ZIP 查询示例 | https://apps.openei.org/USURDB?utilRateFindByZip=90001 |
| REST API | https://api.openei.org/utility_rates?version=latest&format=json&api_key=YOUR_KEY |
| API 文档 | https://apps.openei.org/services/doc/rest/util_rates?version=7 |
| 全量下载（免 key） | https://openei.org/apps/USURDB/download/usurdb.csv.gz<br>https://openei.org/apps/USURDB/download/usurdb.json.gz |
| 字段文档 | https://openei.org/services/doc/rest/util_rates/?version=3#response-fields |
| 维护方 | National Laboratory of the Rockies（DOE），采集由 Illinois State University 代 DOE 执行 |
| 颗粒度·空间 | ZIP → utility（一个 ZIP 常命中多家；90001 → LADWP #11208 + SCE #17609） |
| 颗粒度·时间 | **费率生效日事件流**（`startdate` / `enddate` / `supersedes` / `is_default`），非周期序列 |
| 新鲜度 | **近实时**：条目更新到 2026 年（PPL 更新 2026-03-09；SDG&E 有 2026-06-01 生效费率） |
| 体量 | 63,298 条费率 / 3,700+ 家公用事业；年度更新覆盖美国 70% 负荷（约 150 家 IOU） |
| 关键字段 | `energyratestructure`（阶梯电价）、`energyweekdayschedule` / `energyweekendschedule`（TOU 日/周计划）、`fixedmonthlycharge`、`flatdemand*`、`sector`、`approved`、`is_default`、`startdate` / `enddate` / `supersedes` |
| 角色 | `tariff(zip, sector)`、`tariff_changes(zip, from, to)`；`period = "yoy"` 在 tariff 生效事件上的落点 |

---

## B 组 · 月度零售电价（州级）

### B1. EIA API v2 — electricity/retail-sales — 入选（`period = "mom"` 的唯一合法落点）

| 标注 | 内容 |
|---|---|
| 查询界面 | https://www.eia.gov/opendata/browser/electricity/retail-sales |
| 端点模板 | https://api.eia.gov/v2/electricity/retail-sales/data/?frequency=monthly&data[0]=price&facets[stateid][]=TX&facets[sectorid][]=RES&api_key=YOUR_KEY |
| key 注册 | https://www.eia.gov/opendata/register.php |
| 颗粒度·空间 | `stateid` facet 共 **62** 个取值（50 州 + DC + PR + 若干城市/分区编码，**实施时需枚举确认**） |
| 颗粒度·时间 | **月**；窗口内取 **2023-01 → 2026-07（约 43 个月）** |
| 新鲜度 | 月频约 2.5 个月延迟（实测：2026-07 数据 2026-09-24 发布，8 月数据 2026-10-23）；2025/2026 月度为 **preliminary**，将被年度终值修订 |
| 鉴权 | 需免费 key → **设计为 key 可选，无 key 时回落到随包缓存** |
| 字段 | `customers` / `price` / `revenue` / `sales`；price 单位 **cents/kWh**；sector：ALL / COM / IND / OTH / RES / TRA |
| 数据来源表 | Form EIA-826 / EIA-861 / EIA-861M |
| 角色 | `electricity_price(zip, period = "mom")` 的价格变量；**设计 D1 的解释变量** |

### B2. rOpenSci `eia` (CRAN 0.4.2) — 入选（代码范式，不作依赖）

| 标注 | 内容 |
|---|---|
| CRAN | https://cran.r-project.org/package=eia |
| 文档 | https://docs.ropensci.org/eia/ |
| GitHub | https://github.com/ropensci/eia |
| 内容 | `eia_data()` + API key 管理 + 请求结果缓存的 rOpenSci 风格封装；MIT |
| 角色 | **不直接依赖**，作为缓存层与 key 管理写法的参考范式 |

---

## C 组 · 断供 —— 电价 → 健康的机制变量 — 入选（项目核心）

### C1. EIA-112 Residential Utility Disconnections Survey — 入选

| 标注 | 内容 |
|---|---|
| 性质 | **美国首个**住宅因欠费断供的月度官方统计 |
| 法律依据 | P.L. 117-328 的 3,000,000 美元拨款条款（"monthly survey of final termination notices … due to bill non-payment"） |
| 时间线 | 2023-04 启动设计与试点 → **2024-10 OMB 批准 Form EIA-112** → 2025-02 采集启动 → 2025-12 完成 → 2026-02 处理完毕 → **2026-04-14 首次发布** |
| 报告主页 | https://www.eia.gov/analysis/requests/residential/utility/ |
| 报告 PDF | https://www.eia.gov/analysis/requests/residential/utility/pdf/Residential%20Utility%20Disconnections%20Report%20-%20April%202026.pdf |
| 电力微数据 | https://www.eia.gov/analysis/requests/residential/utility/xls/112%20electric%20utility%20level%20data%202024.xlsx |
| 燃气微数据 | https://www.eia.gov/analysis/requests/residential/utility/xls/112%20natural%20gas%20utility%20level%20data%202024.xlsx |
| OMB 文件 | https://omb.report/icr/202410-1905-001/doc/147730101.pdf |
| 颗粒度·空间 | **州 × 燃料** + **公用事业公司级**（微数据） |
| 颗粒度·时间 | **月** |
| 新鲜度 | 数据年 **2024（唯一一年）**；采集 2025-02 → 2025-12，发布 **2026-04-14**（数据年末 → 发布约 15.5 个月） |
| 覆盖 | 2024 年住宅电力用户 **1.43 亿**、燃气 **0.74 亿**；加权回应率电力 **93.5%**、燃气 96.1% |
| 2024 电力结果 | 最终通知 **9490 万**；**断供 1340 万次**；复电 1140 万次 |
| 季节结构 | **10 月断供峰值 150 万**，7 月最低 967,012 |
| 鉴权 | 免 key |
| 与 A1 的同源关系 | **EIA-112 的应答框正是 EIA-861 的应答实体**（EIA-861S 小实体除外）→ 价格侧与机制侧口径内部一致 |
| 角色 | `disconnections(state, month, fuel = "electric")`；**设计 D1 的因变量** |

2024 年实测季节模式：断供峰在 10 月，而夏季是电价峰 → 这是 D1 滞后假设的直接经验依据。

诚实限制：只有 1 年、612 个州-月观测、生态层面、无法做个体因果推断。
报告须写明"若 EIA-112 延续至 2025/2026 才具备时序因果推断条件"。

---

## D 组 · 死亡率与寿命

### D1a. CDC WONDER Multiple Cause of Death, 2018–2024（Single Race） — 入选（**最终数据，可选模块，需人工取数**）

| 标注 | 内容 |
|---|---|
| 查询页 | https://wonder.cdc.gov/mcd-icd10-expanded.html |
| 帮助文档 | https://wonder.cdc.gov/wonder/help/mcd-expanded.html |
| 颗粒度·空间 | **county**（含 3 种 NCHS Urban-Rural county 分类：2023 / 2013 / 2006） |
| 颗粒度·时间 | **年**；窗口内取 **2023 / 2024**（共 2 年） |
| 新鲜度 | 数据至 2024；2026-10 时点滞后约 1.5 年 |
| 关键约束（有利） | 文档明确：**county 级 + Single Race 时，10 岁组与单岁组不提供 rates/populations，但 5 岁组可以** |
| 关键约束（致命） | **API 不返回 subnational**。https://wonder.cdc.gov/wonder/help/wonder-api.html 原文："only national data are available for query by the API … These 'sub-national' data fields cannot be grouped by or limited via the API, although these fields are available in the web application." → **必须浏览器表单提交，一次性人工取数** |
| 分母来源 | Census **CC-EST2025-AGESEX**：county × 年 × 19 个 5 岁年龄组 × 性别，2020-04-01 → 2025-07-01，2026-06 发布 |
| 分母页面 | https://www.census.gov/data/tables/time-series/demo/popest/2020s-counties-detail.html |
| 分母字段说明 | https://www2.census.gov/programs-surveys/popest/technical-documentation/file-layouts/2020-2025/CC-EST2025-ALLDATA.pdf |
| 体量 | 3143 county × 2 year × 15 组（0-4 … 70-74）≈ **9.4 万行** |
| 角色 | `premature_mortality(zip, years, deaths = NULL)` 的底层；**作为可选第二层，不构成包的运行前提** |

#### 为什么主指标是 YPLL-75 而非期望寿命 e₀

三条真实的方法学缺陷（非权宜之计）：

| e₀ 的问题 | 后果 |
|---|---|
| 对**婴幼儿死亡**高度敏感 | 小区域噪声被放大 |
| 被**高龄死亡**主导 | e₀ 年际变动 < 1 岁，而 county e₀ 的 SE 常 0.5–2 岁 → 信号淹没在噪声 |
| **不可加**，正确聚合需重建生命表，而窗口内只剩 2 年原始死亡数据 | 重建噪声翻倍 |

**YPLL-75（75 岁前潜在寿命损失）的优势：**

1. 环境正义关心的是**可改变的过早死亡**（Case–Deaton "deaths of despair" 一脉）
2. **基于计数，跨单元完美可加** —— 分子相加、分母相加、再相除，绕开寿命不可加的陷阱
3. 无需构造生命表 → 2 年数据也够稳
4. 对电价冲击的路径更直接：电费↑ → 削减供暖/制冷 → 过早死亡
5. 抑制规则简单透明（年龄别死亡数过小则不出值）

聚合的两种口径必须都实现并对比：

```
YPLL_rate(correct)  = Σ_c (YPLL_c)  ÷ Σ_c (pop<75_c)     # 聚合并发率再相除  ← 默认
rate(weighted)      = Σ_c w_c · (YPLL_rate_c)              # 对率做人口加权平均  ← 对照，有偏
```

#### WONDER 取数规格 · 表 1：年度最终数据（D1a 启用时执行一次）

| 项 | 值 |
|---|---|
| 数据库 | Multiple Cause of Death, 2018–2024, Single Race |
| 年份过滤 | **2023、2024** |
| 年龄组 | Five-Year Age Groups，**仅 0-4 … 70-74**（YPLL-75 需 15 组） |
| Group Results By | `County` + `Five-Year Age Groups` |
| 种族 / 性别 | Single Race 6 → All；Sex → All |
| Measures | Deaths、Population |
| 导出 | 结果表导出 CSV |
| 前置 | 点击 "I Agree"（数据使用限制条款） |
| 行数 | 3143 × 15 ≈ **47,000 行 / 年** |

### D1b. CDC WONDER Provisional Mortality（Weekly / Monthly / Quarterly） — 入选（**时序外推的唯一标签源**）

> **2026-10-15 更正。** 此前误判"标签止于 2024、无法时间外推"。WONDER 的 Provisional 系列
> 覆盖 2018 年至今，因此**窗口内**存在约 45 个月（2023-01 → 2026-09）的 county 级月度暂定死亡数据，
> **训练 2023–2025 / 测试 2026 的时序外推预测成立**。

| 标注 | 内容 |
|---|---|
| 数据库清单（WONDER 欢迎页） | https://wonder.cdc.gov/welcomet.html<br>- Mortality - Multiple Cause of Death (Provisional)<br>- Mortality - **Monthly Provisional Deaths**<br>- Mortality - **Quarterly Provisional Estimates**<br>- Mortality - Weekly Provisional Deaths |
| 帮助文档 | https://wonder.cdc.gov/wonder/help/mcd-provisional.html |
| 颗粒度·空间 | **全国 / 州 / county**（county 等价区），按单一种族类别 |
| 颗粒度·时间 | **月 / 季 / 周**；覆盖 **2018 → 至今**，窗口内取 **2023-01 → 2026-09（约 45 个月）** |
| 年龄组 | single-year of age / 5-year / 10-year / infant groups（**单岁组与 10 岁组在 county 级同样不提供 rates 与 populations**，5 岁组可用） |
| 新鲜度 | Weekly 版滞后约 **8–10 天**；2026-10-15 时点应覆盖至 2026 年 10 月上旬 |
| 关键时间戳 | "On **February 18, 2026**, the final 2024 death records replaced the provisional 2024 death records ... with deaths occurring through February 7, 2026."→ 最终数据止于 2024，provisional 覆盖 2025 年初至今 |
| ⚠️ **抑制规则** | "**Death counts are suppressed for sub-national data representing zero to nine (0-9) deaths**"（2018 年起适用）。county × 月的缺口集中在小县，面板严重不平衡 |
| ⚠️ **可靠性规则已变更** | "**Prior to** sharing the 2024 final deaths … in February 2026, rates were flagged as unreliable when the number of deaths was **less than twenty**"。2026-02 起改用基于 RSE 的呈现标准；且 "**Beginning with 2023 data, new statistical standards for the presentation of death rates and counts were implemented by NCHS**"（Natl Vital Health Stat Rep 2023;2(200)，Parker et al.）→ 跨 2026-02 的可比性存疑，须声明 |
| ⚠️ **可回改** | provisional 数据会被终值替换（2023 年于 2025-01-22、2024 年于 2026-02-18 均已发生）。若用作测试集，须声明"测试标签为暂定值，终值将于后续回改" |
| 鉴权 | 需网页同意条款；**API 同样不返回 subnational** → 仍需表单提交 |
| 体量 | 3143 county × 45 月 × 15 组 ≈ **210 万行**（压缩后约 20–30 MB，**不进包**，运行时取用或只取州级） |
| 角色 | `premature_mortality(zip, years, deaths = NULL)` 与预测任务 P1′ 的标签源 |

#### P1′ 时序外推预测（唯一合法的时序预测任务）

| 项 | 内容 |
|---|---|
| 任务 | 用 2023-01 – 2025-12 的价格与死亡关系，预测 **2026-01 – 2026-06/07** 的 county 月度过早死亡 |
| 标签 | county 月度 YPLL-75（或 <75 岁死亡计数） |
| 特征 | 住宅电价 1/3/6/12 月滚动均值、标准差、趋势斜率、YoY；滞后阶 0–3；tariff 生效事件。（EIA-930 不参与关联设计；**断供仅 2024** → 不入评分特征集，仅作 2024 年机制分析或显式插补） |
| 特征截止 | EIA 月度电价**已实测至 2026-07** → 测试集最多到 2026-06/07 |
| 评估 | 滚动起点（walk-forward）+ 按 county 分组，防止空间泄漏 |
| 前提 | **必须先做可行性预检**（见下） |

**标签 vintage 分层（必须声明）**：2023–2024 的 provisional 已被终值替换（2025-01-22 / 2026-02-18），
现取到的训练标签即为**终值**，as-of 暂定值**不可恢复**；2025–2026 为**暂定**且近月因报告延迟**系统性低估**
→ 训练期（已定稿）与测试期（未定稿、偏低）标签不同质，评估结果按此解读。

#### ⚠️ 可行性预检（P1′ 成立的唯一闸门，建议 30 分钟内完成）

> 拉**任意单月**（建议 2025-06）的 county × 5 岁年龄组死亡数，统计：
> 1. 被抑制（缺行）的 county 占比
> 2. 各人口规模分位下的缺失率
> 3. 剔除小县（如人口 < 25,000）后剩余 county 数

判定：

| 预检结果 | 处置 |
|---|---|
| county 级缺失 < 30% | P1′ county 级成立，样本约 45 × 2,500 ≈ **11 万 county-month** |
| 缺失 ≥ 30% | P1′ 降级为**州级月度**（51 × 45 = **2,295 obs**，抑制可忽略），仍可做时序外推 |

**断供变量未延展**（EIA-112 仍仅 2024）→ P1′ 少了"电价 → 断供 → 死亡"这条中介链的多年支持，
只能靠滞后价格特征直接预测死亡，因果解释力弱于 P2，必须在 limitation 中点明。

### D2. NCHS United States Life Tables — 入选（**仅全国锚点**）

| 标注 | 内容 |
|---|---|
| 2024（NVSR 75/5，2026-08-25） | https://www.cdc.gov/nchs/data/nvsr/nvsr75/nvsr75-05.pdf<br>stacks：https://stacks.cdc.gov/view/cdc/252458 |
| 2023（NVSR 74/6，2025-07-15） | https://www.cdc.gov/nchs/data/nvsr/nvsr74/nvsr74-06.pdf |
| 2022（NVSR 74/2，2025-04-08） | https://www.cdc.gov/nchs/data/nvsr/nvsr74/nvsr74-02.pdf |
| 简报 | 2023 数据：https://www.cdc.gov/nchs/data/databriefs/db521.pdf （Data Brief 521）<br>2024 数据：Data Brief 548，2026-01-29 |
| 产品页 | https://www.cdc.gov/nchs/products/life_tables.htm<br>NVSS 汇总：https://www.cdc.gov/nchs/nvss/life-expectancy.htm |
| 颗粒度·空间 | **全国**（按 Hispanic origin / race / sex 分层） |
| 颗粒度·时间 | **年**；窗口内取 **2023、2024** |
| 新鲜度 | 2024 版 NVSR **2026-08-25** 发布（数据年末 → 发布约 20 个月）；头条数值更早可得：Data Brief 548，**2026-01-29** |
| 窗口内数值 | 2023 = **78.4**（男 75.8 / 女 81.1）；2024 = **79.0**（男 76.5 / 女 81.4） |
| 鉴权 | 免 key |
| 角色 | ① 全国 e₀ 趋势背景；② **D1 自建结果的全国级验证锚点**；③ 不参与任何 ZIP 级关联 |

**验证方案**（因 sub-state 已无独立基准，只剩三层）：

| 层次 | 内容 |
|---|---|
| **L1 全国锚点**（强） | 自建全国 e₀ vs NCHS 2023 = 78.4 / 2024 = 79.0 |
| **L2 加总守恒**（强） | county → 州 → 全国逐级加总分子分母的一致性检查 |
| **L3 内部稳定性**（弱） | 两套聚合口径（分子分母聚合 vs 率加权）之差作为自诊断量 |

---

## E 组 · 健康现况指标（主干）

### E1. CDC PLACES 2025 release — 入选（**架构主干**，仅 BRFSS-2023 指标）

| 标注 | 内容 |
|---|---|
| 主页 | https://www.cdc.gov/places |
| 方法学 | https://cdc.gov/places/methodology/index.html |
| 2025 release（tract，GIS 友好格式） | https://data.cdc.gov/resource/yjkw-uj5s |
| 2025 release ZCTA | 每 release 均有 county / place / tract / ZCTA × 两格式共 8 个数据集；**2025 ZCTA 数据集 ID 实施时确认**（风险 #19） |
| ~~ZCTA 2023 release~~（窗口外，仅存档） | https://data.cdc.gov/api/views/c7b2-4ecy（BRFSS 2021） |
| R 包 | https://cran.r-project.org/package=CDCPLACES （brendensm，1.2.2，MIT） |
| 颗粒度·空间 | **county / place / tract / ZCTA** —— **唯一 ZCTA 原生且在窗口内的公共卫生数据集** |
| 颗粒度·时间 | **release 年 ≠ 数据年**（滞后约 2 年）；窗口内**仅 2025 release（BRFSS 2023）** |
| 数据年映射 | 2023 release = BRFSS **2021** ❌；2024 release = BRFSS **2022** ❌；2025 release = BRFSS **2023**（35 项）✅ + BRFSS **2022**（5 项）❌ |
| 新鲜度 | 2025 release（**2025-12** 发布）；数据年 BRFSS 2023 → 距今 3 年（判据：2–5 年为**可接受**） |
| 边界口径 | **2024 release 起改用 2020 Census 地理** → 2025 release 与 G 组 2020 关系文件对齐 ✅（跨 release YoY 已撤销，2023→2024 边界断点不再影响结论） |
| 鉴权 | data.cdc.gov Socrata，免 key |
| 内容 | **35 项合规指标**（2025 release 中 BRFSS 2023 部分：DIABETES / BPHIGH / CANCER / MHD / DISABILT / ACCESS2 / LPA 等），crude + age-adjusted + **95% CI**；**剔除 5 项 BRFSS-2022 指标** |
| 估计方法 | 多层回归与后分层（MRP）；基于 BRFSS + 普查人口 + ACS；Monte Carlo 1000 次抽样给 CI |
| 筛选门槛 | 成人（≥18 岁）人口 ≥50 的区域 |
| 空间降级 | **零** —— 这是选它做主干的首要理由 |
| 角色 | `health_measure(zip, measure)`（2025 release 固定）；D2/D3 的健康侧结果变量；**release 间 YoY 已撤销**（单横截面，仅空间分组留出） |

⚠️ 是**患病率**不是死亡率也不是期望寿命，函数名不得叫 `life_expectancy`。

---

## G 组 · 空间关系文件（聚合权重的唯一来源）

### G1. Census 2020 ZCTA 关系文件 — 入选（**豁免年份约束**）

| 标注 | 内容 |
|---|---|
| 目录 | https://www2.census.gov/geo/docs/maps-data/data/rel2020/zcta520/ |
| ZCTA → tract（2020） | https://www2.census.gov/geo/docs/maps-data/data/rel2020/zcta520/tab20_zcta520_tract20_natl.txt |
| ZCTA → tabulation block（2020，最细） | https://www2.census.gov/geo/docs/maps-data/data/rel2020/zcta520/tab20_zcta520_tabblock20_natl.txt |
| Record layout | https://www.census.gov/programs-surveys/geography/technical-documentation/records-layout/2020-zcta-record-layout.html |
| 关系文件总页 | https://www.census.gov/geographies/reference-files/time-series/geo/relationship-files.2020.html |
| 豁免理由 | **地理边界文件，十年一版，非时间序列观测**，不适用"数据年 ≥ 2023" |
| 用途 | ZCTA ↔ tract / county 的交叠人口权重；与 E1（2024+ release）、A1、WONDER、Census PEP 全部对齐在同一 2020 地理上 |
| 体量 | ZCTA→tract 约 17 万行 |
| 待确认 | **ZCTA → county 的 2020 关系文件确切文件名**，实施时需在 `rel2020/` 目录下确认 |

> MAUP 讨论：用**面积权重 vs 人口权重**两种 ZCTA→county 聚合口径的对比来讨论可修改面积单元问题。

---

## H 组 · 能源不安全（背景佐证，不可接 ZIP）

### H1. EIA RECS 2024 — 备选（仅作引言 / 讨论）

| 标注 | 内容 |
|---|---|
| 数据页 | https://www.eia.gov/consumption/residential/data/2024/ |
| RECS 项目 | https://www.eia.gov/consumption/residential/ |
| 2024 关键数字 | **4360 万户（32.9%）**存在某种形式能源不安全；2020 年为 3360 万户（27.2%）→ **+21%**，**历史最高**<br>其中 3290 万户为付电费而减少或放弃食物/药品；1620 万户收到断供或停供通知；820 万户无法使用空调 |
| 学术转述 | https://www.energypolicy.columbia.edu/wp-content/uploads/2026/04/Energy-insecurity-CGEP_FactSheet_042926.pdf （Columbia CGEP，2026-04） |
| 颗粒度·空间 | 全美 |
| 颗粒度·时间 | 5 年一次 |
| 新鲜度 | 2024 preliminary（2026 年发布）；**官方注明该数据早于近期电价波动 → 自认低估** |
| 限制 | **不可按 ZIP 连接**，仅作报告引言与讨论的宏观背景 |

---

> 注：`period` 只保留 `mom`（州级月频）与 `yoy`（tariff 生效事件）。

---

## 关联设计 × 数据源映射

| 设计 | 价格 | 机制 | 健康 / 死亡 | 空间权重 | 数据年 | 样本量 | 人工步骤 |
|---|---|---|---|---|---|---|---|
| **D1** 核心 | B1（州 × 月） | **C1**（州 × 月） | — | — | 2024 | 51 × 12 = **612** | 无 |
| **D2/D3**（合并） | A1 + A2（ZIP × 年） | — | **E1**（ZCTA 原生，2025 release） | G1 | 价格 2023–2025 × 健康 BRFSS 2023 | ~**33,000** ZCTA（单横截面） | 无 |
| **D4** 背景 | — | H1 RECS 2024（全美） | **D2** NCHS 全国 e₀ 78.4 → 79.0 | — | 2023–2024 | 全国 / 全美 | 无 |
| **D5** 可选 | — | — | **D1a** WONDER 最终 YPLL-75 → ZCTA，两种聚合口径对比 | G1 | 2023–2024 | 3,143 county | **WONDER 一次** |

### 预测任务 × 可用标签

| 任务 | 标签 | 特征 | 能否时序外推 | 样本量 | 人工步骤 |
|---|---|---|---|---|---|
| **P1′** ⭐ | county **月度**过早死亡（**D1b provisional**）2023-01→2026-09 | 电价滚动统计、滞后、tariff 事件（EIA-930 已删；断供不入评分特征） | ✅ **训练 2023–2025 / 测试 2026-01–06**（测试标签暂定、近月偏低） | 预检后定：11 万 county-month 或 2,295 州-月 | **WONDER 一次** |
| **P2** | 月度断供（C1）2024 | 同上 | ✅ 年内滚动起点 | 51 × 12 = **612** | 无 |
| **P3** | PLACES 指标（E1，**2025 release 单横截面**） | 年度电价 | ❌ 只能**空间**分组留出 | ~33,000 ZCTA | 无 |
| ~~P4~~ | 预测更晚年份的寿命 | — | ❌ **无可测标签** | — | 不做 |

### 预测结果的呈现规则（缺一不可）

| 模型 | 特征 | 用途 |
|---|---|---|
| M0 | 全州/全样本均值 | 最弱基线 |
| **M1** | **仅地理**（county / state 固定效应） | **关键基线** |
| M2 | 仅滞后价格（lag 0–3） | 时间基线 |
| M3 | 地理 + 价格特征全集 | 完整模型 |

- **若 M3 对 M1 改进很小 → "电价解释健康差异"这一论点不成立，必须如实报告。** 诚实的负面结果在方法学分上远高于没有基线的漂亮 R²。
- 评价指标：MAE / RMSE / R² + **按 state 聚类的稳健标准误**（同州内误差相关）。
- 报告**有效样本量**而非原始 N（county 分组留出后有效 N 远小于原始 N）。
- 四条必须写入限制的声明：
  1. **预测 ≠ 因果** —— 全文不得出现"电价导致…"
  2. **内插而非外推** —— 电价由供电公司决定、服务区内近乎常数，模型学到的是地理而非弹性
  3. **P3 无时序外推** —— E1 仅 2025 release 单横截面；**P1′ 是唯一时序外推任务**，其测试标签为暂定值
  4. **P2 的 612 观测只配惩罚回归 + 显式滞后搜索**，不配复杂模型
- **P3 必须按 county 分组切分**；随机按 ZCTA 切分会造成空间泄漏（同一 county 的邻居同时落在两侧）。

### 报告的核心论点（2026-10-15 更正：改为"最终/暂定分层"）

**原表述已作废。** 此前称"死亡数据止于 2024、电价到 2026，故存在时滞不对称"——
该表述忽略了 WONDER Provisional 系列，会低估可做的事。

更正后的论点更精细，也更有用：

> 死亡数据存在**两层**：**最终数据（2023–2024）可用于训练与验证方法**，
> **暂定数据（至 2026-09）可用于前瞻性预测演示**；而电价到 2026-07。
> `lifewatt` 因此可以做到一件此前被认为做不到的事：**用可验证的数据确定关系，再用尚未定稿的数据展示它对未来的预测能力。**
> 同时必须声明：暂定标签会被终值回改（2023 年于 2025-01-22、2024 年于 2026-02-18 均已发生）；
> 价格侧同理——2025–2026 月度电价为 **preliminary**、EIA-861 2025 有 early（2026-08）→ final（2026-10-07）双 vintage，
> 与死亡侧的最终/暂定分层**对等披露**。

**仍未延展的环节**：EIA-112 断供只有 2024 一年 → "电价 → 断供 → 死亡"这条中介链**无法做多年时序验证**。
P1′ 因此只能靠滞后价格直接预测死亡，因果解释力弱于 P2；这一点必须在 limitation 中点明。

---

## 包结构（架构 A：主干零人工 + 死亡可选模块）

```
lifewatt
├─ 电价   electricity_price(zip, year)                 # A1 × A2，ZIP 级 2023/2024/2025
│         electricity_price(zip, period = "mom")        # B1，州级月频 2023-01→2026-07
│         tariff(zip, sector) / tariff_changes(zip, from, to)   # A3
├─ 健康   health_measure(zip, measure)                  # E1，ZCTA 原生，2025 release ← 主干
├─ 机制   disconnections(state, month)                  # C1
├─ 早死   premature_mortality(zip, years, deaths = NULL)# D1a/b 可选；deaths=NULL 时返回明确提示
└─ 数据集 build_dataset(years, outcome, spatial, features) # 建模就绪 tibble + provenance 列
          price_features(unit, date) / lag_matrix(x, max_lag)
    关联   ej_profile(zip)                               # watt + health 全景 + 全国分位 + 降级诊断
            price_disconnection_lag(state, year)          # P2：滞后 0–3 月
```

**`build_dataset()` 返回的 provenance 列**（把"降级"写进数据表本身，而非脚注）：

| 列 | 含义 |
|---|---|
| `source` | 来自哪个源、哪个 vintage |
| `level` | 该值实际所在的空间层级（utility / county / zcta） |
| `degraded_from` | 从哪一级降级而来 |
| `n_units` / `max_weight` | 由几个单元加权、最大权重多少 |
| `as_of` | 数据时效戳 |
| `provisional` | 标签是否为暂定值 |

**建模放在 vignette，不放包内**：用 `lm` + `glmnet`（可选）+ `sandwich` 聚类 SE，
**不引入 `tidymodels` / `workflows`** —— 避免拖慢 `R CMD check`、避免重依赖。

**Rcpp 落点**（对应 rubric 的 15% 高级特性）：
YPLL 权重向量化应用、county→ZCTA 分子分母聚合、33,000 个 ZCTA 的分位映射批量化、
滚动窗口统计、滞后互相关矩阵（51 × 12 × 7 阶）、P1′ 的 walk-forward 特征装配。

**包体估算**：年度 county 死亡表（2 年 × 15 组 ≈ 9.4 万行）+ ZCTA 关系文件（~3 MB）+
OpenEI 映射（~1.5 MB）+ EIA-112 xlsx（<1 MB）≈ **8 MB**。
**D1b 的 210 万行月度 provisional 不进包**，运行时取用或只保留州级切片。
PLACES / EIA API 为运行时下载。
GitHub / tar.gz 友好；**不走 CRAN**（5 MB 源包限制），与作业要求一致。

---

## 文献基础（报告引言 / 文献综述用）

| 来源 | 可引用论点 | 入口 |
|---|---|---|
| **McTague et al. (2025), _Energy Economics_** | HRS 10 波浪纵向数据，**电价 → 能源贫困 → 健康**，双向固定效应。与设计 D2/D3 同构 | https://www.sciencedirect.com/science/article/pii/S031359262500195X |
| **Hernández (2026), Columbia CGEP** | RECS 2024：能源不安全 4360 万户（32.9%），四年 +21%，创历史最高 | https://www.energypolicy.columbia.edu/wp-content/uploads/2026/04/Energy-insecurity-CGEP_FactSheet_042926.pdf |
| Drehobl, Ross & Ayala (2020), ACEEE | 能源负担 >6% 为高、>10% 为严重；低收入家庭负担 8.1% vs 全国 3.1%；weatherization 可降 25%（**负担阈值仅作讨论引用，F 组数据已删**） | https://www.energy.gov/sites/default/files/2022-03/How%20High%20are%20Household%20Energy%20Burdens.pdf |
| _Health Affairs_（Hernández 等） | 能源不安全与心理 / 呼吸 / 睡眠 / 儿童健康 | https://www.healthaffairs.org/do/10.1377/hpb20230518.472953/full |
| Bohrn & McCreery (2019) | 能源负担家庭留在贫困状态的概率高 175–200% | 经 ACEEE 2020 转引 |
| Lewis, Hernández & Geronimus (2019) | 能源负担限制家庭经济流动性与技能提升 | 经 ACEEE 2020 转引 |
| Hernández, Phillips & Siegel (2016) | 高额公用事业账单 → 牺牲供暖/健康 | https://pmc.ncbi.nlm.nih.gov/articles/PMC7147484 |
| **Silcocks PB, Jenner DA, Reza R (2001).** _J Epidemiol Community Health_ 55(1):38–43 | **期望寿命对年龄结构差异敏感、对婴幼儿死亡敏感** → 支撑"弃用 e₀"的论证 | 经 CHR&R 引用转引 |
| **Eayres D, Williams ES (2004).** _J Epidemiol Community Health_ 58(3):243–249 | **小区域期望寿命估计方法评估** → 支撑"2 年数据不足以稳定估计 county e₀" | 经 CHR&R 引用转引 |
| **Dranger E, Remington P (2004).** YPLL: A summary measure of premature mortality. UW PHIP | **YPLL 作为过早死亡综合指标的方法学依据** | 经 CHR&R 引用转引 |
| **MMWR (1986);35(suppl 2):1S–11** | YPLL 的原始定义与公共健康解释（死亡年龄越低权重越大） | 经 CHR&R 引用转引 |

---

## 待定 / 风险登记

| # | 事项 | 状态 |
|---|---|---|
| 1 | WONDER county 死亡数据须**浏览器表单人工取数**（API 不返回 subnational）；已降级为**可选模块**，不构成包的运行前提 | 设计已规避，待确认是否启用 D1a/D1b |
| 2 | D1a 自建结果的外部验证只剩**全国级**（NCHS 78.4 / 79.0），sub-state 无独立基准 | 不可解，须写入 limitation |
| 3 | **EIA-112 未延展**，仍只有 2024 一年 → P1′ 缺少"电价 → 断供 → 死亡"的多年中介链支持 | 不可知，只能写进 limitation |
| 4 | OpenEI ZIP 映射滞后 EIA-861 一年（2024 vs 2025 终值 2026-10-07） | 需写入 `NEWS.md` |
| 5 | EIA-112 公司级微数据的再分发许可需自行核实（公共数据、非个体数据，判断可行但**未验证**） | 待查 |
| 6 | EIA API key 是否接受（拟采用 key 可选 + 本地缓存兜底）；**Census API key 不再需要**（ZCTA 收入表已删；CC-EST 与关系文件走 FTP/直下） | 待确认（仅 EIA） |
| 7 | G1 中 **ZCTA → county 2020 关系文件**的确切文件名 | 实施时确认 |
| 8 | EIA-861 中 62 个 `stateid` 取值的完整枚举 | 实施时确认 |
| 9 | WONDER county 级**死亡计数**是否可在 Single Race 下按单岁年龄组获取（YPLL 权重精度相关） | 实施时确认（文档仅说明单岁组不提供 rates/populations，未说明 counts） |
| 11 | 截止日期 **Nov 30 或 Dec 8** —— 作业 PDF 第 1 页与第 2 页自相矛盾 | **未确认，影响时间线** |
| 12 | 个人还是组队（≤3 人） | **未确认，决定工作分工** |
| 13 | 数据体积：**GitHub / tar.gz 分发，不走 CRAN**（5 MB 源包限制） | 已定 |
| **14** | **D1b 抑制比例未知** —— sub-national 死亡数 0–9 被抑制，county × 月面板缺口集中于小县，**P1′ 成败取决于此** | **必须先做 30 分钟可行性预检** |
| **15** | **provisional 回改 + vintage 异质**：2023/2024 已被终值替换（2025-01-22 / 2026-02-18，as-of 暂定**不可恢复**）；2025–2026 为暂定且近月**系统性低估** → 训练/测试标签不同质 | 已识别，须写入 limitation |
| **16** | **抑制/可靠性规则于 2026-02 变更**（原 n<20 标记不可靠，改为 RSE 标准；2023 起启用 NCHS 新呈现标准 Nat Vital Health Stat Rep 2023;2(200)）→ 跨 2026-02 可比性存疑 | 待核实，须写入方法学 |
| **17** | provisional 最新覆盖日期（推断约 2026-10 上旬，滞后 8–10 天）未实测确认 | 实施时确认 |
| **18** | EIA 月度电价截止日**已实测：2026-07**（EPM 2026-09-24 发布；8 月数据 2026-10-23）→ P1′ 测试集最多到 2026-06/07 | ✅ 已确认，已写入 B1 / P1′ |
| **19** | E1 2025 release 的 **ZCTA 数据集 ID** 待实测（每 release 均有 ZCTA，portal 八数据集） | 实施时确认 |
| **20** | **池化禁令的代价**：无合规"可负担性"数据维度，能源负担只能以文献进入讨论 | 已接受，写入 limitation |

---

## 硬约束更正记录

| 日期 | 更正内容 |
|---|---|
| 2026-10-15 | 此前记"死亡类数据最新仅到 2024–2025"与"时滞不对称"论点**作废**。WONDER Provisional Mortality 系列（Weekly / Monthly / Quarterly）覆盖 2018 → 至今，county 级可用。由此新增 D1b，并把报告论点改为**最终数据用于训练验证 / 暂定数据用于前瞻预测**的分层表述 |
| 2026-10-15 | 由此**时序外推预测成为可能**（P1′：训练 2023–2025 / 测试 2026），此前误判为不可行 |
| 2026-10-15 | CHR&R 因数据年 2020–2022 / 2021–2023 违反硬约束被排除；例外申请已明确否决 |
| 2026-10-15 | **池化禁令**确立：多年池化估计一律拒绝——三年 CHR&R 与五年 ACS 5-year 同罪同罚 → **F2/F1 出局，F 组全组排除**；ACS"ZCTA 收入唯一来源"豁免申请**否决**（不设第三豁免） |
| 2026-10-15 | **E1 收缩**：release 年 ≠ 数据年（2023 release = BRFSS 2021、2024 = 2022、2025 = 2023 + 5 项 2022）→ 仅 **2025 release 的 35 项**合规；2023/2024 release 与 5 项 BRFSS-2022 指标排除，**release 间 YoY 撤销** |
| 2026-10-15 | 4 年窗口实测更新：B1 截止 2026-09 → **2026-07（43 个月）**；P1′ 特征删 EIA-930（批发需求不参与关联设计）、断供移出评分特征、补标签 vintage 分层声明；价格侧 preliminary / early-final vintage 与死亡侧对等披露；存留总表新增"实测数据年 / 窗口覆盖"列 |