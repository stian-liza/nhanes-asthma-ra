# 官方问卷元数据审核（2026-09-23）

更新：用户已确认范围修订A。原全十周期当前哮喘不可测的结论不变，但主分析2001–2018和补充1999–2018曾患哮喘已取得获取资格；`metadata_review.json`记录该批准及字典哈希。下文revise为发现原方案问题时的审核记录。

正式输入：已确认的研究计划 v0.2。输出：本目录的变量字典、取值表、周期覆盖表和审核状态。原始网页保存于移动硬盘，不含参与者记录的提取元数据入库。

已读取十周期 DEMO、MCQ、SMQ 共30份 CDC codebook，提取214条“周期×模块×变量”记录。`variable_dictionary.csv`保留官方拼写、题目、适用年龄、跳题、编码频数、来源网址和原件SHA256；不是最终分析字段表。跨周期变量匹配需忽略大小写（例如后期 `MCQ160a`），不能据大小写误判未测。

## 核心结果

| 周期 | 当前哮喘题目 | 成年人适用 | RA类型题目 | RA肯定编码 |
|---|---|---|---|---|
| 1999–2000 | MCQ030 | 否，仅1–19岁 | MCQ190 | 1 |
| 2001–2008 | MCQ035 | 是 | MCQ190 | 1 |
| 2009–2010 | MCQ035 | 是 | MCQ191 | 1 |
| 2011–2018 | MCQ035 | 是 | MCQ195 | 2 |

RA = rheumatoid arthritis（类风湿关节炎）。类型题必须和“曾被告知有关节炎”总题结合；类型不明不能标成没有RA。当前哮喘也必须结合曾患哮喘总题。

**1999–2000的成人当前哮喘不可按原计划构建。** [官方MCQ codebook](https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/1999/DataFiles/MCQ.htm#MCQ030)的适用年龄与[原始问卷第1页](https://wwwn.cdc.gov/nchs/data/nhanes/public/1999/questionnaires/spq-mc.pdf)一致：成人在MCQ.015处跳过当前哮喘题，直接到过去一年发作题。它是结构性未询问，不是一般漏答。[呼吸问卷](https://wwwn.cdc.gov/nchs/data/nhanes/public/1999/questionnaires/spq-rd.pdf)的喘鸣、用药和就诊问题未提供同义的“仍患哮喘”测量。

证据层级：官方适用人群与跳题属 direct evidence；疾病自报作为临床确诊的替代属 proxy evidence；假定发作/喘鸣可完全代替当前哮喘属未获支持的 speculation；官方成人跳题对“全十周期当前哮喘可协调”构成 counterevidence。上述术语描述对具体claim的支持，不表示存在新的临床结论。

## 验证 gate

- verdict：revise（原定全十周期成人当前哮喘）；其余九周期的字段存在与20岁资格检查pass。
- checked：30份官方字典；疾病题目、适用年龄、取值标签；原始1999问卷交叉验证。
- weak point：覆盖检查不等于全套语义审核。个体一致性、缺失、样本量、复杂抽样、临床有效性均未验证。
- next move：确认[范围修订](../research_plans/2026-09-23-scope-amendment.md)，再更新冻结方案和下载gate；不能凭一个字段“存在”自动启动回归。

复现（Python需requests、lxml、pandas）：

```sh
python scripts/acquire.py --root /Volumes/Elements/NHANES
python scripts/audit_metadata.py
python -m unittest discover -s tests -v
```

第一条仅获取/复用官方元数据。`--data`为个体数据获取入口，必须具备与字典哈希匹配的审核通过状态。用户确认修订后已完成30份文件获取，记录见manifest；766项频数一致。`audit_metadata.py`只保留已存在且哈希匹配的v0.3批准，不可自动批准新的/已更改的字典。原始数据禁止写仓库或自动回退到系统盘。
