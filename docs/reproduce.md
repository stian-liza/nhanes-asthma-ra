# 复现入口

本项目采用已确认v0.3：主分析2001–2018当前哮喘；补充1999–2018曾患哮喘。个体数据必须在移动硬盘上；请替换下列外置盘路径，不可指向未挂载的同名本地目录。

## 环境

执行平台：Apple Silicon Mac、R4.5.1、Python3。Python依赖固定在`requirements-metadata.txt`；R直接和传递依赖版本在`renv.lock`，运行会话记录在`reports/session_info.txt`。项目R包优先从`.Rlib`加载，该目录不入Git。

```sh
python -m venv .venv
.venv/bin/pip install -r requirements-metadata.txt
Rscript -e 'dir.create(".Rlib",showWarnings=FALSE); install.packages("renv",lib=".Rlib",repos="https://cloud.r-project.org")'
Rscript -e '.libPaths(c(normalizePath(".Rlib"),.libPaths())); renv::restore(lockfile="renv.lock",library=".Rlib",prompt=FALSE)'
```

## 数据与核查

```sh
.venv/bin/python scripts/acquire.py --root /Volumes/Elements/NHANES --data
.venv/bin/python scripts/prepare.py --root /Volumes/Elements/NHANES
.venv/bin/python -m unittest discover -s tests -v
Rscript tests/test_survey.R
```

如果已有官方XPT，可在获取命令增加`--reuse /path/to/existing/files`；原件不会删除。获取脚本保存SHA256、URL、字节数和记录数。网络失败可重跑，已下载且验证通过的文件复用；官方文件更新必须核查而不是覆盖旧原件。代码字典变更将使原审核哈希失效，必须重新核查，不通过编辑verdict绕过。

## 插补与分析

```sh
mkdir -p reports/logs results/qc results/tables results/figures
bash scripts/run_R.sh R/impute.R /Volumes/Elements/NHANES > reports/logs/impute.log 2>&1
bash scripts/run_R.sh R/review_imputation.R /Volumes/Elements/NHANES
```

先检查`results/qc/imputation_stability.csv`、轨迹图、分布和事件日志；只有类别/范围合法、链无明显漂移、异常已解释时才继续，并记录`reports/imputation_review.json`的审核结论。收入缺失的条件随机假设不能靠轨迹图验证。第一次插补因共线性而被否决，保留在failed_v1目录；正式版本使用相同设计空间的满秩基，禁止使用失败对象代替。

```sh
bash scripts/run_R.sh R/analysis.R /Volumes/Elements/NHANES > reports/logs/analysis.log 2>&1
bash scripts/run_R.sh R/replay_primary.R /Volumes/Elements/NHANES
.venv/bin/python scripts/report.py
```

主表`results/tables/association_models.csv`中，`primary_MI/M2`才是预设主估计。MI代表多重插补；CC代表完整病例。其他模型是调整层级、补充或敏感性，不能择优挑选。所有优势比均为患病关联，不是新发风险。

原始数据在`raw/<cycle>/`；个体表和插补对象在外置盘`derived/v03/`。汇总表、图、代码和环境可入Git，个体对象不入库。日志不得输出SSH密钥、账号令牌或个体列表。

发作/急诊分支未获新增价值gate，不运行。BMI、用药、医疗可及性扩展也不在最小分析范围。运行状态以`reports/run_status.json`和产物校验为准，不能仅依据README的完成表述。

独立R进程回放只验证保存的插补对象可重现主模型；不代表已在另一台机器重新下载、重做插补，或完成干净环境全链复跑。后者仍须实际验证，不能由锁文件存在推定成功。

`run_R.sh`在Mac可用时按进程加载Apple Accelerate，并限制单线程，以避免参考BLAS的慢速矩阵运算；其他系统回退Rscript。`.Rruntime`只存本地动态库链接，不入Git；全局R安装不会改变。算法、包版本与随机种子相同，但不同线性代数后端仍可能存在浮点差异，应比较容差内结果而非假设逐位相同。
