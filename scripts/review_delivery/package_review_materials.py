"""Create the public review ZIP and checksum file without altering analysis artifacts."""
from pathlib import Path
import argparse,csv,hashlib,json,zipfile
p=argparse.ArgumentParser();p.add_argument('release_dir',type=Path);a=p.parse_args()
root=Path(__file__).resolve().parents[2];r=root/'docs/review_20261008'
assert str(a.release_dir.resolve()).startswith('/Volumes/'), 'Store release bundles on external disk'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
source=list(csv.DictReader((r/'original_delivery_manifest.csv').open(encoding='utf-8-sig')))
files={root/x['path'] for x in source}
files.update([root/'README.md',root/'docs/research_runs/2026-10-08-github-review-delivery.md'])
for directory in [r,root/'scripts/review_delivery']:
 files.update(p for p in directory.rglob('*') if p.is_file() and p.name!='publication_manifest.csv' and '__pycache__' not in p.parts and not p.name.startswith('.'))
# Include standalone plot revisions in future review bundles.
for directory in sorted((root/'outputs').glob('figure_revision_*')):
 if directory.is_dir():files.update(p for p in directory.rglob('*') if p.is_file() and not p.name.startswith('.'))
files=sorted(files);manifest=r/'publication_manifest.csv'
with manifest.open('w',newline='',encoding='utf-8') as f:
 w=csv.DictWriter(f,fieldnames=['path','bytes','sha256']);w.writeheader()
 for p in files:w.writerow(dict(path=str(p.relative_to(root)),bytes=p.stat().st_size,sha256=sha(p)))
zpath=a.release_dir/'nhanes-review-materials-20261008.zip'
with zipfile.ZipFile(zpath,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
 for p in files+[manifest]:z.write(p,str(p.relative_to(root)))
with zipfile.ZipFile(zpath) as z:
 assert z.testzip() is None
 for p in files+[manifest]:assert hashlib.sha256(z.read(str(p.relative_to(root)))).hexdigest()==sha(p)
assets=json.loads((r/'data_assets.json').read_text())
for asset in assets:assert sha(a.release_dir/asset['file'])==asset['sha256']
assets.append(dict(file=zpath.name,sha256=sha(zpath),bytes=zpath.stat().st_size))
(a.release_dir/'SHA256SUMS.txt').write_text(''.join(f"{x['sha256']}  {x['file']}\n" for x in assets))
print(json.dumps({'repository_files':len(files),'assets':assets},indent=2))
