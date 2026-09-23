"""Download official codebooks first, then explicitly requested XPTs to external storage.

Requires requests, lxml, pandas. Never downloads participant data to the repository.
"""
import argparse
import csv
import hashlib
import json
import os
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd
import requests
from lxml import html

REPO = Path(__file__).resolve().parents[1]
WANTED = {
    'DEMO': ['SEQN','RIDAGEYR','RIAGENDR','RIDRETH1','DMDEDUC2','INDFMPIR',
             'SDDSRVYR','SDMVSTRA','SDMVPSU','WTINT2YR','WTINT4YR','WTMEC2YR','WTMEC4YR'],
    'MCQ': ['SEQN','MCQ010','MCQ030','MCQ035','MCQ040','MCQ050','MCQ160A','MCQ190','MCQ191','MCQ195'],
    'SMQ': ['SEQN','SMQ020','SMQ040'],
}

def clean(el):
    return ' '.join(el.text_content().split())

def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def write_csv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        raise ValueError(f'No rows for {path}')
    with path.open('w', newline='') as f:
        w=csv.DictWriter(f, fieldnames=list(rows[0]),lineterminator='\n'); w.writeheader(); w.writerows(rows)

def require_download_gate(gate, dictionary):
    if not gate.exists():
        raise RuntimeError('Metadata gate is missing')
    review=json.loads(gate.read_text())
    if review.get('primary_download_verdict')!='pass':
        raise RuntimeError('Metadata gate not passed; see docs/data/metadata_review.json')
    if review.get('dictionary_sha256')!=digest(dictionary):
        raise RuntimeError('Metadata dictionary changed after review')

def fetch(url, dest, binary=False):
    dest.parent.mkdir(parents=True, exist_ok=True)
    if not dest.exists():
        for attempt in range(3):
            try:
                r=requests.get(url, timeout=(20,60)); r.raise_for_status()
                break
            except requests.RequestException:
                if attempt==2:
                    raise
                time.sleep(attempt+1)
        body=r.content
        if binary and not body.startswith(b'HEADER RECORD*******LIBRARY'):
            raise ValueError(f'Not SAS XPORT: {url}')
        if not binary and b'Variable Name:' not in body:
            raise ValueError(f'Not a codebook: {url}')
        tmp=dest.with_suffix(dest.suffix+'.partial'); tmp.write_bytes(body); tmp.replace(dest)
    if binary and not dest.read_bytes().startswith(b'HEADER RECORD*******LIBRARY'):
        raise ValueError(f'Invalid cached XPT: {dest}')

def one_metadata(item, root):
    year, mod, stem=item
    cycle=f'{year}-{year+1}'
    url=f'https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/{year}/DataFiles/{stem}.htm'
    dest=root/'codebooks'/cycle/f'{stem}.htm'
    fetch(url,dest)
    tree=html.parse(str(dest))
    rows=[]; details=[]
    for heading in tree.xpath('//h3[contains(@class,"vartitle")]'):
        name=heading.get('id','')
        if name.upper() not in WANTED[mod]:
            continue
        block=heading.getparent(); info={}
        for dt in block.xpath('./dl/dt'):
            dd=dt.getnext()
            if dd is not None:
                info[clean(dt).rstrip(':').strip()]=clean(dd)
        vals=[]
        for tr in block.xpath('./table/tbody/tr'):
            cells=[clean(td) for td in tr.xpath('./td')]
            if len(cells)>=4:
                vals.append(dict(code=cells[0], label=cells[1], count=int(cells[2].replace(',','')),
                                 cumulative=cells[3], skip=cells[4] if len(cells)>4 else ''))
        rows.append(dict(cycle=cycle,module=mod,file=stem,variable=name,
                         label=info.get('SAS Label',''),question=info.get('English Text',''),
                         instructions=info.get('English Instructions',''),target=info.get('Target',''),
                         values_json=json.dumps(vals,ensure_ascii=False),source_url=url,
                         codebook_sha256=digest(dest),status='extracted_requires_semantic_review'))
        details.append(dict(cycle=cycle,module=mod,file=stem,variable=name,values=vals))
    assert rows,(cycle,mod)
    print(f'CODEBOOK {stem}: {len(rows)} selected fields',flush=True)
    return rows,details

def one_data(item, root, reuse):
    year,mod,stem=item; cycle=f'{year}-{year+1}'
    dest=root/'raw'/cycle/f'{stem}.xpt'
    url=f'https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/{year}/DataFiles/{stem}.xpt'
    reused=False
    if reuse and (reuse/f'{stem}.xpt').exists() and not dest.exists():
        src=reuse/f'{stem}.xpt'
        body=src.read_bytes()
        assert body.startswith(b'HEADER RECORD*******LIBRARY'),src
        # Verify parser before preserving the user's existing file as a source copy.
        pd.read_sas(src,format='xport')
        dest.parent.mkdir(parents=True,exist_ok=True); dest.write_bytes(body); reused=True
    fetch(url,dest,binary=True)
    frame=pd.read_sas(dest,format='xport')
    assert 'SEQN' in frame and not frame.SEQN.duplicated().any(),stem
    print(f'XPT {stem}: {len(frame)} records',flush=True)
    return dict(cycle=cycle,module=mod,file=stem,url=url,bytes=dest.stat().st_size,
                sha256=digest(dest),relative_path=str(dest.relative_to(root)),rows=len(frame),
                reused_existing=reused,retrieved_utc=datetime.now(timezone.utc).isoformat())

def main():
    p=argparse.ArgumentParser(); p.add_argument('--root',required=True,type=Path)
    p.add_argument('--data',action='store_true'); p.add_argument('--reuse',type=Path)
    args=p.parse_args()
    root=args.root.resolve()
    # A genuine mounted external volume is required on this Mac acquisition entrypoint.
    if not str(root).startswith('/Volumes/'):
        raise ValueError(f'External /Volumes path required: {root}')
    volume=Path('/Volumes')/root.parts[2]
    if not os.path.ismount(volume):
        raise ValueError(f'External volume not mounted: {volume}')
    items=[]
    for i,year in enumerate(range(1999,2019,2)):
        suffix='' if i==0 else '_'+chr(ord('A')+i)
        for mod in WANTED:
            items.append((year,mod,mod+suffix))
    with ThreadPoolExecutor(max_workers=3) as ex:
        results=list(ex.map(lambda item:one_metadata(item,root),items))
    rows=[r for a,b in results for r in a]; detail=[d for a,b in results for d in b]
    write_csv(REPO/'docs/data/variable_dictionary.csv',rows)
    (REPO/'docs/data/codebook_values.json').write_text(json.dumps(detail,ensure_ascii=False,indent=2))
    if args.data:
        # Human review stamp is deliberately separate from extraction.
        gate=REPO/'docs/data/metadata_review.json'
        require_download_gate(gate, REPO/'docs/data/variable_dictionary.csv')
        with ThreadPoolExecutor(max_workers=3) as ex:
            manifests=list(ex.map(lambda item:one_data(item,root,args.reuse),items))
        previous=REPO/'manifests/downloads.csv'
        if previous.exists():
            old={r['file']:r for r in csv.DictReader(previous.open())}
            for row in manifests:
                before=old.get(row['file'])
                if before and before['sha256']==row['sha256']:
                    row['retrieved_utc']=before['retrieved_utc']
                    row['reused_existing']=before['reused_existing']
        write_csv(REPO/'manifests/downloads.csv',manifests)

if __name__=='__main__':
    main()
