# 草稿 MVP 使用说明

先下载 `demo/MVP_demo.html`，再用浏览器打开，查看真实数据、地图、距离查询结果和限制。
GitHub 页面默认显示 HTML 源码；也可以在 `mvp-community-health` 分支点击 Code → Download ZIP，
解压后打开这个 HTML 文件。

## 在 RStudio 运行

1. 从 GitHub 安装草稿分支（安装时需要联网）：

```r
install.packages("remotes") # 已经安装过就跳过这一行
remotes::install_github("RePinkert/PHC6099-final-project",
                        ref = "mvp-community-health", build_vignettes = FALSE)
library(lifewatt)
f <- example_facility()
p <- nearby_communities(f$longitude, f$latitude, radius_km = 10)
plot_communities(p)
compare_communities(p)
export_communities(p, "nearby_communities.csv")
```

也可以安装已下载的源码文件夹：
`install.packages("源码文件夹的路径", repos = NULL, type = "source")`。
如果拿到的是单独交付的 `lifewatt_0.1.0.tar.gz`，可使用
`install.packages(file.choose(), repos = NULL, type = "source")` 选中它安装。
安装完成后，示例可离线运行；每次新开 R 会话需要重新运行 `library(lifewatt)`。

2. 把 `radius_km` 改成 3 或 5，观察选择结果。
3. 用 `county_context()` 查看独立的县级寿命背景。
4. `demo/run_demo.R` 会重新生成 10 公里查询 CSV、距离分组表、地图和散点图。

这个版本已经使用 58 个真实社区并完成 GEOID 匹配。它用于探索周边健康背景；
社区粗死亡率不等于预期寿命，距离也不等于污染暴露，输出不能解释为算力中心的因果影响。
设施位置使用官方地址的街道插值点，后续仍可用经核实的建筑坐标替换。

默认数据范围只有 Alachua County。函数支持其他查询点，但其他地区需要另外提供
同样字段的社区数据，不能仅更换坐标就自动获得全国数据。

源码和数据可作为两人共同检查的起点。提交前还需要共同核对署名、最终课程要求、
数据使用说明与每个人对代码的理解。
