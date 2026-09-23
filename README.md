# nhanes-asthma-ra

核查 NHANES 1999–2018 数据，研究自报医生诊断的类风湿关节炎与哮喘的患病关联；具体可分析周期由官方问卷资格决定。

## 当前状态

**用户已整体确认研究计划 v0.2和范围修订A；当前按v0.3执行。**

**第一版真实数据分析已完成：2001–2018当前哮喘与RA为主；1999–2018曾患哮喘诊断史为补充。30份必需数据文件已获取，766项官方频数检查通过。**

主分析纳入45,558名疾病状态明确的成人，预设完整调整模型的患病优势比为 **2.09（95%置信区间1.76–2.49）**；曾患哮喘补充分析为 **1.86（1.60–2.16）**。结果支持自报疾病共存的正向关联，不能解释为因果或新发风险。主分析4,501名成人RA状态不明，排除及自报测量的局限必须保留。

入口：[中文结果报告](reports/results.zh.md) · [完整模型表](results/tables/association_models.csv) · [主要关联图](results/figures/key_associations.png) · [复现说明](docs/reproduce.md) · [阶段验收](docs/research_execution/2026-09-24-results-review.md)。运行状态与产物以报告、日志和校验清单为准。

**三图四表导师评阅报告（9页）：** [PDF](reports/manuscript/nhanes_asthma_ra_report_3fig4table_v03.pdf) · [可编辑Word](reports/manuscript/nhanes_asthma_ra_report_3fig4table_v03.docx) · [在线正文](reports/manuscript/nhanes_asthma_ra_report_3fig4table_v03.md)。参考Baljet等2023年文章的图表规模，使用本项目已有结果，不含尚未开展的年龄分层或加重分析。

- 主要问题：20 岁及以上成人中，自报类风湿关节炎者是否更常报告当前哮喘？在考虑年龄、性别、吸烟等差异后，关联有多大？
- 有条件的次要问题：当前哮喘成人中，类风湿关节炎是否与过去一年哮喘发作和哮喘相关急诊就诊有关？
- 设计：多周期合并的横断面观察性研究；不推断因果或新发疾病风险。
- 用户于 2026-09-23 确认：以“两病共存”为主要科研问题；哮喘发作和急诊仅在样本量与创新性条件满足后作为次要分析。尚未记录老师确认。

## 文档

- [Idea 与范围记录](docs/research_ideas/2026-09-23-nhanes-asthma-ra-idea.md)
- [完整研究计划](docs/research_plans/2026-09-23-nhanes-asthma-ra-experiment-plan.md)
- [来源与当前核实范围](docs/evidence/2026-09-23-source-register.md)
- [实施记录与任务状态](docs/research_execution/2026-09-23-execution.md)
- [十周期元数据审核](docs/data/README.md)
- [已确认范围修订](docs/research_plans/2026-09-23-scope-amendment.md)
- [v0.3实施入口](docs/research_execution/2026-09-23-v03-run.md)
- [模型前缺失策略锁定](docs/research_execution/2026-09-23-analysis-lock.md)
- [定向查新记录](docs/evidence/2026-09-23-novelty-screen.md)

发作和急诊分支未开展：现有同数据库研究重叠，尚未通过新增价值门槛。当前交付是观察性关联分析及技术核验，不代表已完成临床验证、充分查新或具备投稿条件。

## 数据与结果约定

原始 `.xpt` 文件保存在移动硬盘，原件保留并记录 SHA256 校验值；仓库不保存个体级研究数据。移动硬盘路径由本地配置提供，禁止自动回退下载到系统盘。

确认计划后，分析代码、非敏感配置、运行说明、数据来源清单、汇总表和图均写入本仓库。尚不存在的结果不使用占位数值或模拟数值冒充。

项目不以显著性或发表承诺作为验收标准；数据、方法、结果和局限必须可追溯。
