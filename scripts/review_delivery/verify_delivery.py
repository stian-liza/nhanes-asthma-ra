"""Read-only publication verification; no downloads and no statistical fitting."""
import argparse,csv,hashlib,io,json,pathlib,zipfile
p=argparse.ArgumentParser();p.add_argument('--assets-dir',type=pathlib.Path);a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[2];review=root/'docs/review_20261008';out=root/'outputs/year_extension_20261008_v01'
def sha(path):
 h=hashlib.sha256()
 with path.open('rb') as f:
  for block in iter(lambda:f.read(1024*1024),b''):h.update(block)
 return h.hexdigest()
manifest=list(csv.DictReader((review/'publication_manifest.csv').open(encoding='utf-8')))
for r in manifest:
 f=root/r['path'];assert f.stat().st_size==int(r['bytes']) and sha(f)==r['sha256'],r['path']
bindings=json.loads((out/'source_bindings.json').read_text())
for path,digest in bindings['source_tables_and_figures'].items():assert sha(out/path)==digest,path
lock=json.loads((out/'plan_lock.json').read_text())
assert sha(root/'docs/research_plans/2026-10-08-asthma-ra-year-extension-experiment-plan.md')==lock['sha256']==bindings['plan_sha256']
qa=json.loads((out/'visual_qa.json').read_text())
assert sha(next(out.glob('*.docx')))==qa['docx_sha256']
assert sha(next(out.glob('*.pdf')))==qa['pdf_sha256']
for path,digest in json.loads((review/'review_result_sources.json').read_text()).items():assert sha(out/path)==digest,path
assets=[]
if a.assets_dir:
 for line in (a.assets_dir/'SHA256SUMS.txt').read_text().splitlines():
  digest,name=line.split('  ',1);f=a.assets_dir/name;assert sha(f)==digest,name;assets.append(name)
 for asset in json.loads((review/'data_assets.json').read_text()):
  f=a.assets_dir/asset['file'];assert sha(f)==asset['sha256'] and f.stat().st_size==asset['bytes']
  with zipfile.ZipFile(f) as z:
   assert z.testzip() is None
   entries=list(csv.DictReader(io.StringIO(z.read('MANIFEST.csv').decode('utf-8'))))
   assert len(entries)==asset['files']
   for r in entries:
    data=z.read(r['path']);assert len(data)==int(r['bytes']) and hashlib.sha256(data).hexdigest()==r['sha256'],r['path']
print(json.dumps({'verdict':'pass','repository_files_verified':len(manifest),'report_source_files_verified':len(bindings['source_tables_and_figures']),'locked_plan_unchanged':True,'docx_pdf_match_prior_visual_qa':True,'assets_verified':assets,'new_models_run':False},ensure_ascii=False,indent=2))
