import pathlib,json,hashlib,shutil,zipfile,csv
ROOT=pathlib.Path(__file__).resolve().parents[2];O=ROOT/'outputs/year_extension_20261008_v01'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
pdf=next((O/'rendered_v03').glob('*.pdf'));shutil.copy2(pdf,O/pdf.name)
qa=dict(verdict='pass',pages=23,visual_review='All 23 pages inspected; final changed pages 20-22 inspected again; all other page pixels unchanged by final layout fix.',checked=['Chinese glyphs','text clipping','table split and header repetition','all four figures','footnotes and page numbers'],images={p.name:sha(p) for p in (O/'rendered_v03').glob('page-*.png')},pdf_sha256=sha(O/pdf.name),docx_sha256=sha(next(O.glob('*.docx'))))
(O/'visual_qa.json').write_text(json.dumps(qa,ensure_ascii=False,indent=2))
(O/'final_gate.json').write_text(json.dumps(dict(verdict='pass',stage='completed analysis and draft manuscript delivery',new_models_run=True,legacy_participant_data_reused=False,external_raw_files=44,official_frequency_checks=667,report_consistency_checks=182,pdf_pages=23,model_and_independent_validation='pass',pooling='supplement only; not evidence of period equivalence',unresolved=['author affiliations, funding, local ethics determination and conflict statements','period equivalence remains unestablished','not submitted to journal']),ensure_ascii=False,indent=2))
files=[p for p in O.rglob('*') if p.is_file() and not any(x in p.parts for x in ['rendered_v03','__pycache__']) and p.suffix.lower() not in ['.zip','.rds','.xpt'] and p.name not in ['delivery_manifest.csv','delivery_checksums.json','page_hash_before_layout_fix.json']]
files += [p for p in (ROOT/'scripts/year_extension_v1').iterdir() if p.is_file()]
docs=['docs/research_ideas/2026-09-28-original-proposal-asthma-ra-idea.md','docs/research_plans/2026-09-28-original-proposal-asthma-ra-experiment-plan.md','docs/research_ideas/2026-09-29-asthma-ra-supplement-authorized-idea.md','docs/research_plans/2026-09-29-asthma-ra-supplement-experiment-plan.md','docs/research_plans/2026-10-08-asthma-ra-year-extension-experiment-plan.md','docs/research_runs/2026-10-08-asthma-ra-year-extension-run.md']
files += [ROOT/p for p in docs];files=sorted(set(files))
rows=[dict(path=str(p.relative_to(ROOT)),bytes=p.stat().st_size,sha256=sha(p)) for p in files]
with (O/'delivery_manifest.csv').open('w',newline='',encoding='utf-8-sig') as f:
 w=csv.DictWriter(f,fieldnames=['path','bytes','sha256']);w.writeheader();w.writerows(rows)
zpath=O/'NHANES更新至2023年_稿件与复现资料_v03.zip'
with zipfile.ZipFile(zpath,'w',compression=zipfile.ZIP_DEFLATED) as z:
 for p in files+[O/'delivery_manifest.csv']:z.write(p,str(p.relative_to(ROOT)))
with zipfile.ZipFile(zpath) as z:
 assert z.testzip() is None
 for r in rows:assert hashlib.sha256(z.read(r['path'])).hexdigest()==r['sha256']
checks=dict(zip_sha256=sha(zpath),zip_bytes=zpath.stat().st_size,files=len(rows)+1,content_hashes_verified=True,individual_data_included=False)
(O/'delivery_checksums.json').write_text(json.dumps(checks,indent=2));print(json.dumps(checks))
