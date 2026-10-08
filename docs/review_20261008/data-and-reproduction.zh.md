# 使用数据、字段和复现说明

## 数据下载入口

本仓库的 [GitHub Release：更新至2023年评阅版](https://github.com/stian-liza/nhanes-asthma-ra/releases/tag/review-2023-v03-20261008) 提供：

| 附件 | 用途 |
|---|---|
| `nhanes-public-inputs-20261008.zip` | 实际使用的44个官方XPT、44份代码本、62个不同问卷PDF（64条来源记录），以及获取记录与来源清单 |
| `nhanes-analysis-frames-20261008.zip` | 实际使用的主数据框与3个分析数据框RDS；3个完整框CSV和3个完整病例CSV；字段类型及人数清单 |
| `nhanes-review-materials-20261008.zip` | 本次代码、中文统计学解释、汇总表、图、Word/PDF和核验材料 |
| `SHA256SUMS.txt` | 上述3个附件的SHA256校验值 |

这些是公开 NHANES 资料和从其派生的数据，保留原始 `SEQN` 以核对连接。未上传私人项目申请书、联系人材料、凭据或本地软件包。原始与派生数据继续保存在移动硬盘，同时按本次用户要求发布附件；未将参与者级数据写进 Git 历史。

**历史说明的区别：** `outputs/.../复现与交付说明.md` 和 `original_delivery_checksums.json` 记录之前稿件交付时“数据仅在外置盘、原压缩包不含个体数据”的状态。本次新增独立数据附件，不改写原稿件记录。当前发布以本页、`data_assets.json` 和 Release 校验值为准。

## 附件内部结构

原始数据包解压到移动硬盘研究目录，得到 `data/`、`metadata/`、`questionnaires/` 和 `sources/`。它不包含重复的单独2017—2018文件；使用2017—2020年3月的P文件。

分析数据包解压到同一研究目录，得到：

```text
master_frame.rds
prepandemic/derived/analysis_frame.rds
latest/derived/analysis_frame.rds
pooled/derived/analysis_frame.rds
exports/
  frame_inventory.csv
  frame_schema.csv
  prepandemic/broad_frame.csv
  prepandemic/complete_cases.csv
  latest/broad_frame.csv
  latest/complete_cases.csv
  pooled/broad_frame.csv
  pooled/complete_cases.csv
```

RDS 是模型实际读取的数据框，保留因子水平和完整浮点精度；CSV 是本次为检查导出的等价表格版本，缺失值为空白。两个数据包各自带 `MANIFEST.csv`；若解压到同一目录，后解压的清单会覆盖同名文件，故请在覆盖前分别保留清单，或在 ZIP 内核对。仓库同时保存两份不同文件名的清单。

完整框包括未纳入分析的人，不能对全部行直接拟合主模型。`design_valid` 先限定有效体检设计，再将 `eligible` 作为完整病例子总体。不要用仅有完整病例的 CSV 代替完整框构造调查设计。

| 集合 | 完整框行数 | 有效体检设计人数 | 完整病例人数 |
|---|---:|---:|---:|
| 疫情前 | 107622 | 102362 | 37127 |
| 2021—2023 | 11933 | 8860 | 3563 |
| 跨期补充 | 119555 | 111222 | 40690 |

人数已由数据框读取后与保存结果核对，见 [frame_inventory.csv](frame_inventory.csv)。`master_frame.rds` 是分集合前的数据，不含后加的全部资格标志；复现模型使用相应集合的 `analysis_frame.rds`。

## 字段怎么读

完整56字段的类型、缺失数和因子水平见 [frame_schema.csv](frame_schema.csv)；209行逐周期原始字段定义见 [variable_dictionary.csv](../../outputs/year_extension_20261008_v01/variable_dictionary.csv)。

| 字段 | 含义与处理 |
|---|---|
| `SEQN` | 官方受访者编号；连接键，检查唯一性 |
| `year`, `cycle_label`, `SDDSRVYR` | 发布块起始年、标签及官方周期编码；2017表示2017—2020年3月P文件 |
| `MCQ010` | 曾被告知患哮喘的原始回答 |
| `MCQ160A` | 医生告知患关节炎的原始回答 |
| `MCQ190`, `MCQ191`, `MCQ195` | 不同时期关节炎类型；非适用周期的空值为结构性缺失 |
| `arthritis_type`, `ra_code` | 该周期实际使用的类型值和RA编码 |
| `asthma_status`, `arthritis_status`, `smoke_status` | 区分确定回答、合理跳题、未询问、拒答、不知道、缺失或逻辑冲突 |
| `asthma`, `ra` | 模型二元变量；1有、0无；RA的0仅为明确无关节炎 |
| `RIDAGEYR`, `RIAGENDR`, `RIDRETH1`, `DMDEDUC2`, `INDFMPIR` | 人口学原始字段 |
| `BMXBMI`, `BMXWT`, `BMXHT` | 官方实测BMI、体重、身高；后两者用于核验BMI |
| `BMIWT`, `BMIHT`, `BMAEXSTS`, `BMDSTATS` | 体测备注或完成状态；因周期适用性不同可为空，详见该周期代码本 |
| `SMQ020`, `SMQ040` | 一生是否吸烟达到100支、现在吸烟状态 |
| `age`, `bmi`, `pir` | 连续协变量；PIR保留官方有效范围0—5，上限编码仍有测量限制 |
| `sex` | Male为参考；Female |
| `race` | NH_White为参考；Mexican、Other_Hispanic、NH_Black、Other_Multiracial |
| `education` | College_grad为参考；Less_than_9th、9th_11th、High_school、Some_college |
| `smoking` | never为参考；former、current；合理跳题用于定义never，未知状态不填为never |
| `agegroup`, `bmigroup`, `pirgroup` | 已确认的描述/分组变量，界值见统计说明 |
| `WTMEC4YR`, `WTMEC2YR`, `WTMECPRP` | 官方不同发布块体检权重，不适用的字段留空 |
| `official_mec_weight`, `analysis_weight` | 所选官方体检权重、当前集合合成权重 |
| `SDMVSTRA`, `SDMVPSU` | 官方分层和层内PSU；使用`nest=TRUE`；不任意按周期重编号 |
| `matched_DEMO`, `matched_MCQ`, `matched_SMQ`, `matched_BMX` | 相应模块是否连接成功 |
| `design_valid`, `age_valid` | 体检设计有效、年龄20—79岁 |
| `pre_covariate` | 年龄、设计及疾病资格通过，尚未排除协变量缺失 |
| `eligible` | 全部主分析资格满足；四模型共用 |
| `era` | prepandemic（参考）、latest；用于时期交互 |

## 不运行模型也能检查什么

1. 查看Word/PDF、在线结果、图表和CSV；比对人数与定义。
2. 下载附件后执行 `shasum -a 256 -c SHA256SUMS.txt`。
3. 在仓库根目录执行以下命令，核对仓库交付文件及数据附件内部的每个文件：

```bash
python3 scripts/review_delivery/verify_delivery.py \
  --assets-dir /Volumes/Elements/NHANES_asthma_ra_extension_20261008_fresh_v1/github_review_release
```

可另用 `Rscript scripts/review_delivery/verify_data_exports.R /外置盘/研究目录` 逐字段比对CSV与RDS。本次6个CSV共336列已通过比对（数值容差1e-12）；CSV会丢失因子类型，全空列也可能被读为逻辑型，检查时需恢复原字段类型。

只检查仓库文件时省略 `--assets-dir`。它不下载数据、不拟合模型。哈希证明文件一致性，不等于独立重新完成统计分析。

## 原执行环境与复现入口

已执行环境：R 4.5.1、survey 4.5。每个集合保存 `environment.txt` 与 `environment_diagnostics.txt`。主要R依赖为haven、survey、dplyr、jsonlite、lpSolve、car、ggplot2、ragg；Python报告/文档工具依赖lxml、python-docx、pypdf。

`scripts/year_extension_v1` 按执行时版本原样发布。脚本默认研究目录为：

```text
/Volumes/Elements/NHANES_asthma_ra_extension_20261008_fresh_v1
```

异机复现需要统一调整其中的外置盘根路径；获取脚本还验证 `/Volumes/Elements` 为真实挂载点。路径不是可自动识别的配置，不能直接假定跨平台即开即用。代码中的旧`R_library`只是软件包搜索路径，不读取旧数据或旧结果。

完整重算入口（会重建同名输出，应在新副本中执行）：

```bash
NHANES_PYTHON=/path/to/python3 bash scripts/year_extension_v1/run_analysis.sh
```

各步骤在之前分析阶段已执行；该汇总入口只做过语法检查，没有为本次上传再次完整运行。下载器只接受本轮带来源记录且哈希匹配的已有文件；已核对文件不会重复下载。原始下载目标仍须是移动硬盘。

`validate_report.py` 的最后一项还核对原版冻存 ZIP。该历史文件不包含在本次数据附件，独立机器缺少它时此脚本会停止，不能虚报全部182项重新通过。当前评阅可用新增的 `verify_delivery.py` 检查发布文件与正文来源；如要执行原182项检查，需要提供本人保存的原冻存文件及原相对路径。

生成PDF另需LibreOffice与中文字体；原版23页PDF及Word已经完成逐页检查，本次发布不改动其字节。独立机器重新渲染后的版面需要重新检查。

## 验证边界

- 本轮仅导出数据、生成检查页面、打包及验证，没有重新拟合统计模型。
- 原稿件的182项检查、23页版面检查，以及输入/模型独立核验，属于之前执行记录，完整保留。
- 当前附件实际包含原始及派生数据；不包含占用较大的模型RDS、分离诊断矩阵或本地软件环境。模型对象可以按公开脚本重建。
- 公开方案副本删除一处无关的私人微信缓存路径。原执行文件未改动，删除前后哈希记录在 [public_copy_provenance.json](public_copy_provenance.json)。早期方案引用的原哈希仍指原件，不应与脱敏副本混淆。已锁定年份扩展方案及其哈希不变。
