"""Package exact public inputs on the external disk; no download or model fitting."""
import argparse,csv,hashlib,json,pathlib,zipfile
p=argparse.ArgumentParser();p.add_argument('data_root',type=pathlib.Path);a=p.parse_args()
root=a.data_root.resolve();repo=pathlib.Path(__file__).resolve().parents[2]
assert str(root).startswith('/Volumes/'), 'Release data must remain on external storage'
out=repo/'outputs/year_extension_20261008_v01';review=repo/'docs/review_20261008'
release=root/'github_review_release';release.mkdir(exist_ok=True)
def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for block in iter(lambda:f.read(1024*1024),b''):h.update(block)
 return h.hexdigest()
def archive(name,entries):
 entries=sorted(set(entries),key=lambda e:e[1]);rows=[]
 for source,relative in entries:rows.append(dict(path=relative,bytes=source.stat().st_size,sha256=sha(source)))
 manifest=release/(name+'.manifest.csv')
 with manifest.open('w',newline='',encoding='utf-8') as f:
  w=csv.DictWriter(f,fieldnames=['path','bytes','sha256']);w.writeheader();w.writerows(rows)
 zpath=release/(name+'.zip')
 with zipfile.ZipFile(zpath,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
  for src,rel in entries:z.write(src,rel)
  z.write(manifest,'MANIFEST.csv')
 with zipfile.ZipFile(zpath) as z:
  assert z.testzip() is None
  for row in rows:assert hashlib.sha256(z.read(row['path'])).hexdigest()==row['sha256']
 (review/manifest.name).write_bytes(manifest.read_bytes())
 return dict(file=zpath.name,bytes=zpath.stat().st_size,sha256=sha(zpath),files=len(rows),verified_zip_contents=True)
raw=[]
for fname,count in [('data_manifest.csv',44),('metadata_manifest.csv',44),('questionnaire_manifest.csv',64)]:
 rows=list(csv.DictReader((out/fname).open(encoding='utf-8-sig')));assert len(rows)==count
 for r in rows:
  # Rebase execution-time path, preserving the path within the external data root.
  rel=r['path'].split('NHANES_asthma_ra_extension_20261008_fresh_v1/',1)[1]
  src=root/rel;assert src.stat().st_size==int(r['bytes']) and sha(src)==r['sha256']
  raw.append((src,rel))
  prov=src.with_suffix(src.suffix+'.download.json')
  if prov.exists():raw.append((prov,str(prov.relative_to(root))))
 raw.append((out/fname,'sources/'+fname))
frames=[(root/'master_frame.rds','master_frame.rds')]
for scope in ['prepandemic','latest','pooled']:
 rel=scope+'/derived/analysis_frame.rds';frames.append((root/rel,rel))
for src in (release/'exports').rglob('*'):
 if src.is_file() and not src.name.startswith('.'):
  frames.append((src,'exports/'+str(src.relative_to(release/'exports'))))
result=[archive('nhanes-public-inputs-20261008',raw),archive('nhanes-analysis-frames-20261008',frames)]
(review/'data_assets.json').write_text(json.dumps(result,indent=2))
print(json.dumps(result,indent=2))
