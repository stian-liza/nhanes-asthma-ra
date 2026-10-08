# 独立图文件

本版按用户要求使用R绘图软件从已核验的CSV结果重新绘制。未使用AI图像生成；未重新拟合模型。中文使用Heiti SC（黑体简体），图内没有图题、图号或A/B面板标号，保留必要的变量标签和统计信息。

[下载全部PNG、矢量PDF和绘图代码](https://github.com/stian-liza/nhanes-asthma-ra/releases/download/review-2023-v03-20261008/nhanes-figures-v02.zip)

## 2021年8月—2023年8月

| 内容 | 300 dpi PNG | 矢量PDF |
|---|---|---|
| 年龄亚组 | [PNG](latest/age_subgroups.png) | [PDF](latest/age_subgroups.pdf) |
| 性别亚组 | [PNG](latest/sex_subgroups.png) | [PDF](latest/sex_subgroups.pdf) |
| 样本流程 | [PNG](latest/sample_flow.png) | [PDF](latest/sample_flow.pdf) |
| 年龄模型诊断 | [PNG](latest/residual_age.png) | [PDF](latest/residual_age.pdf) |
| BMI模型诊断 | [PNG](latest/residual_bmi.png) | [PDF](latest/residual_bmi.pdf) |
| PIR模型诊断 | [PNG](latest/residual_pir.png) | [PDF](latest/residual_pir.pdf) |

## 疫情前：1999年—2020年3月

| 内容 | 300 dpi PNG | 矢量PDF |
|---|---|---|
| 年龄亚组 | [PNG](prepandemic/age_subgroups.png) | [PDF](prepandemic/age_subgroups.pdf) |
| 性别亚组 | [PNG](prepandemic/sex_subgroups.png) | [PDF](prepandemic/sex_subgroups.pdf) |
| 样本流程 | [PNG](prepandemic/sample_flow.png) | [PDF](prepandemic/sample_flow.pdf) |
| 年龄模型诊断 | [PNG](prepandemic/residual_age.png) | [PDF](prepandemic/residual_age.pdf) |
| BMI模型诊断 | [PNG](prepandemic/residual_bmi.png) | [PDF](prepandemic/residual_bmi.pdf) |
| PIR模型诊断 | [PNG](prepandemic/residual_pir.png) | [PDF](prepandemic/residual_pir.pdf) |

## 内容核对与使用

- 四张森林图分别输出，均比较RA者与明确无关节炎者的曾患哮喘调整后优势比。具体比较对象、时期和调整变量可写在图外图注中。
- 四张森林图采用相同的0.5—10对数横轴，包含全部区间端点；2021—2023年年轻组0.59—8.47的区间完整保留。
- 原来的三变量诊断组合图也拆为单独文件。诊断图仅描述原模型的残差，不代表新增研究发现。
- 每个时期保存5个来源CSV副本；数值与原结果文件逐项一致。原始数据、统计结果、旧图及旧稿件保留。
- GitHub在线结果页已改为本版独立图；原Word/PDF未在本轮改写，用户可按需要使用独立图替换并自行添加图题。

代码：[redraw_figures_v02.R](../../scripts/review_delivery/redraw_figures_v02.R)。在仓库根目录执行；如R依赖不在默认库，将库路径作为第一个参数。需要macOS的Heiti SC字体，字体缺失时应安装合适的简体中文字体并显式修改注册位置，不能用未知回退字体交付。
