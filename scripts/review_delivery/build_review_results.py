"""Render a Chinese review page from saved result CSVs; no model fitting."""
from pathlib import Path
import csv,hashlib,json
root=Path(__file__).resolve().parents[2];out=root/'outputs/year_extension_20261008_v01';dest=root/'docs/review_20261008'
used={}
def rows(p):
 f=out/p;used[str(p)]=hashlib.sha256(f.read_bytes()).hexdigest()
 return list(csv.DictReader(f.open(encoding='utf-8-sig')))
def pval(v):
 v=float(v);return '<0.001' if v<.001 else f'{v:.3f}'
def effect(r,key='OR',scale=1):return f"{float(r[key])*scale:.2f}（{float(r['lower'])*scale:.2f}—{float(r['upper'])*scale:.2f}）"
def table(head,rs):return '\n'.join(['| '+' | '.join(head)+' |','|'+'|'.join(['---']*len(head))+'|']+['| '+' | '.join(map(str,r))+' |' for r in rs])
text=['# 更新至 2023 年：结果、表格与图形','本页从已完成分析的 CSV 生成；展示值经格式化，原始精度见链接。OR 是优势比，CI 是置信区间，P 值均为双侧。比例是加权估计，人数是实际未加权人数。','## 1. 主要结果']
main=[]
for s,label in [('prepandemic','疫情前：1999—2020年3月'),('latest','最新时期：2021年8月—2023年8月')]:
 r=next(r for r in rows(Path(s)/'regression.csv') if r['model']=='M3'); main.append([label,r['n'],'M3',effect(r),pval(r['p'])])
rr=rows(Path('pooled/pooling_models.csv'));r=next(r for r in rr if r['model']=='P1');main.append(['跨期补充：已观测发布块',r['n'],'P1（另调周期）',effect(r,'estimate'),pval(r['p'])])
text += [table(['分析集合','完整病例数','模型','OR（95% CI）','P'],main),'RA 与曾患哮喘呈正向横断面关联。跨期估计是补充结果，不能取代两个时期的独立结果。']
for s,label in [('prepandemic','疫情前'),('latest','2021—2023年')]:
 text += [f'## {label}：患病比例与四个主模型',table(['组别','人数','哮喘人数','加权比例 %（95% CI）'],[[{'All':'全部完整病例','No_arthritis':'明确无关节炎','RA':'RA'}[r['group']],r['n'],r['events'],effect(r,'estimate',100)] for r in rows(Path(s)/'asthma_prevalence.csv')])]
 text += [table(['模型','人数','OR（95% CI）','P'],[[r['model'],r['n'],effect(r),pval(r['p'])] for r in rows(Path(s)/'regression.csv')])]
 text += ['M0 未调整；M1 加年龄、性别、种族/族裔；M2 再加教育、PIR；M3 再加 BMI、吸烟。四个模型使用同一完整病例样本。',f'[人群特征表](../../outputs/year_extension_20261008_v01/{s}/characteristics.csv) · [协变量与哮喘](../../outputs/year_extension_20261008_v01/{s}/covariates_asthma.csv) · [协变量与RA](../../outputs/year_extension_20261008_v01/{s}/covariates_ra.csv) · [设计校正检验](../../outputs/year_extension_20261008_v01/{s}/covariate_tests.csv)',f'### {label}：样本筛选',f'![{label}样本筛选](../../outputs/figure_revision_20261008_v03/{s}/sample_flow.png)',f'[逐步排除人数 CSV](../../outputs/year_extension_20261008_v01/{s}/sample_flow.csv)',f'### {label}：亚组结果']
 text += [table(['亚组','人数','OR（95% CI）','P'],[[{'Male':'男','Female':'女'}.get(r['subgroup'],r['subgroup']+'岁'),r['n'],effect(r),pval(r['p'])] for r in rows(Path(s)/'subgroups.csv')])]
 text += [table(['交互项','交互 P'],[[{'agegroup':'RA × 年龄组','sex':'RA × 性别'}[r['variable']],pval(r['p'])] for r in rows(Path(s)/'interaction_tests.csv')]),f'![{label}年龄亚组](../../outputs/figure_revision_20261008_v03/{s}/age_subgroups.png)',f'![{label}性别亚组](../../outputs/figure_revision_20261008_v03/{s}/sex_subgroups.png)','亚组间差异依据交互检验判断，不能比较各组是否显著。',f'### {label}：已完成的补充分析',table(['模型','人数','OR（95% CI）','P'],[[r['model'],r['n'],effect(r),pval(r['p'])] for r in rows(Path(s)/'supplement/regression.csv')]),'B0 为 M3；B1 加入年龄/PIR 非线性；B2 再加入 BMI 非线性；B3 为 B1 加发布周期；B4 为 B1 加完整病例选择概率加权。B3 在最新单一时期不适用。',f'[标准化患病比例与比例差](../../outputs/year_extension_20261008_v01/{s}/supplement/standardized_prevalence.csv) · [补充检验](../../outputs/year_extension_20261008_v01/{s}/supplement/tests.csv) · [选择权重检查](../../outputs/year_extension_20261008_v01/{s}/supplement/selection_weight_diagnostics.csv)']
text += ['## 跨期补充与时期差异',table(['模型','估计量','估计值（95% CI）','P'],[[r['model'],'共同OR' if r['estimand']=='pooled_common_OR' else '最新/疫情前OR之比',effect(r,'estimate'),pval(r['p'])] for r in rr if r['model'] in ['P1','P2'] or r['estimand']=='OR_ratio_latest_over_prepandemic']), 'P1 为完全调整并控制发布周期；P2 再处理年龄/PIR 非线性；I1、I2 为对应时期交互模型。时期交互未提供充分差异证据，但其区间仍允许有意义的差异，不能据此宣称等效或合并无风险。', '[正式跨期模型表](../../outputs/year_extension_20261008_v01/pooled/pooling_models.csv) · [时期交互检验](../../outputs/year_extension_20261008_v01/pooled/period_interactions.csv) · [各发布块权重贡献](../../outputs/year_extension_20261008_v01/pooled/cycle_contributions.csv)', '`pooled/regression.csv` 是合并计算检查中的基础模型输出；正式报告使用加入周期的 `pooling_models.csv`，两者不可混用。','## 证据边界','- **Direct evidence（直接观察证据）**：上述指定定义、样本和模型下，数据表显示自报 RA 与曾患哮喘的正向关联。\n- **Proxy evidence（代理证据）**：疾病来自受访者自报医生诊断，并非本研究重新实施的临床分类诊断。\n- **Speculation（推测）**：共同炎症、免疫通路、药物等解释没有在本研究得到机制验证。\n- **Counterevidence / uncertainty（反证与不确定性）**：现有交互检验不足以支持稳定的年龄、性别或时期差异；未测混杂、完整病例选择、自报误分和时间顺序不明仍限制解释。','## 全部汇总结果文件','以下入口同时保留阳性、阴性和不确定结果，以及诊断与验证文件。']
for s in ['prepandemic','latest','pooled']:
 text += [f'### {s}']
 text += [f'- [{str(p.relative_to(out/s))}](../../outputs/year_extension_20261008_v01/{p.relative_to(out)})' for p in sorted((out/s).rglob('*')) if p.is_file() and p.suffix in ['.csv','.json']]
(dest/'results.zh.md').write_text('\n\n'.join(text)+'\n')
(dest/'review_result_sources.json').write_text(json.dumps(used,indent=2))
print('Built review results from',len(used),'saved CSV files')
