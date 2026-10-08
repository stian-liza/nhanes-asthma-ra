# 全部已观测时期合并图：v04

按用户本轮要求，所有图使用合并样本，不再拆为两个时期展示。沿用已确认规则：R软件绘图；中文思源黑体（正文Regular，列头Medium）；英文和数字Arial；年龄和性别分别出图；图内无图题、图号或A/B面板标号。图题由用户在正文中另行添加。

[下载六张独立图片、矢量PDF及绘图代码](https://github.com/stian-liza/nhanes-asthma-ra/releases/download/review-2023-v03-20261008/nhanes-figures-v04-pooled.zip)

## 合并样本及模型

- 合并完整病例40,690人：自报RA者2,627人，明确无关节炎者38,063人。
- 覆盖本研究已纳入的NHANES 1999年至2020年3月及2021年8月至2023年8月调查资料。属于已观测周期合并，不代表调查空档期间有人群观测。
- 本次仅从既有CSV重绘，未下载数据、重新拟合模型或改动原统计结果。合并结果仍按已确认方案列为补充分析；图示不分时期，不改变来源、权重和设计的说明义务。
- 亚组图取自合并样本M3：调整年龄、性别、种族/族裔、教育、贫困收入比、BMI和吸烟；性别分层模型不再调整性别。年龄、BMI和PIR采用原连续线性形式。
- **本组亚组估计和诊断图没有额外调整调查周期。** 另存的P1/P2为加入调查周期的模型，本次不将其估计或时期交互值混入M3亚组图。若稿件以P1/P2为主模型，不能把本组图片标为P1/P2的亚组结果。
- 年龄与性别交互P值来自同一合并样本的复杂抽样联合Wald F检验；与比较各亚组P值是否显著不同。

## 独立文件

| 内容 | 300 dpi PNG | 矢量PDF |
|---|---|---|
| 年龄亚组 | [PNG](pooled/age_subgroups.png) | [PDF](pooled/age_subgroups.pdf) |
| 性别亚组 | [PNG](pooled/sex_subgroups.png) | [PDF](pooled/sex_subgroups.pdf) |
| 样本筛选流程 | [PNG](pooled/sample_flow.png) | [PDF](pooled/sample_flow.pdf) |
| 年龄模型诊断 | [PNG](pooled/residual_age.png) | [PDF](pooled/residual_age.pdf) |
| BMI模型诊断 | [PNG](pooled/residual_bmi.png) | [PDF](pooled/residual_bmi.pdf) |
| PIR模型诊断 | [PNG](pooled/residual_pir.png) | [PDF](pooled/residual_pir.pdf) |

## 亚组数值核对

| 亚组 | 人数 | OR（95% CI） | P值 |
|---|---:|---|---:|
| 20—39岁 | 17,603 | 2.35（1.63—3.38） | <0.001 |
| 40—59岁 | 13,934 | 2.39（1.90—2.99） | <0.001 |
| 60—79岁 | 9,153 | 1.82（1.44—2.29） | <0.001 |
| 男性 | 20,192 | 2.38（1.86—3.05） | <0.001 |
| 女性 | 20,498 | 2.14（1.79—2.55） | <0.001 |

年龄交互P=0.1386；性别交互P=0.7542。

## 图外说明

结局为自报曾被医生或其他卫生专业人员告知患哮喘；比较RA者与明确无关节炎者。点为调整后优势比，横线为95%置信区间，虚线为OR=1。采用复杂抽样权重、分层和抽样单位；人数为未加权样本量。横断面关联不代表因果或新发风险。

年龄、性别图分别保留相同0.5—10的对数横轴。模型诊断分别展示年龄、BMI、PIR的分箱观察比例减预测比例，仅用于检查原模型拟合。

## 复现与版本

在macOS仓库根目录执行（R需要ggplot2、ragg、systemfonts，可将R包库路径作为首个参数；Python需要pypdf、fonttools；另需clang）：

```sh
Rscript scripts/review_delivery/redraw_figures_v04_pooled.R
python3 scripts/review_delivery/fix_figure_pdf_unicode.py --figure-dir outputs/figure_revision_20261008_v04_pooled
```

[绘图代码](../../scripts/review_delivery/redraw_figures_v04_pooled.R) · [字体注册](../../scripts/review_delivery/register_figure_fonts.c) · [PDF中文映射修正](../../scripts/review_delivery/fix_figure_pdf_unicode.py) · [字体及许可](../../assets/fonts/source-han-sans-cn/) · [核对记录](validation.json)

来源为 [合并结果目录](../year_extension_20261008_v01/pooled/) 中的subgroups、interaction_tests、sample_flow、asthma_prevalence和binned_model_residuals五个CSV，各保存一份原字节副本。本次保留全部旧版文件，原Word/PDF尚未替换图片。
