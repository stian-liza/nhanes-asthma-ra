"""Explicit NHANES release catalog; fresh acquisition, external participant storage."""
import csv, datetime, hashlib, json, pathlib, urllib.request, time, concurrent.futures
from lxml import html
ROOT=pathlib.Path('/Volumes/Elements/NHANES_asthma_ra_extension_20261008_fresh_v1')
OUT=pathlib.Path(__file__).resolve().parents[2]/'outputs/year_extension_20261008_v01'
CYCLES=[dict(year=y,suffix='' if y==1999 else '_'+chr(65+(y-1999)//2),prefix='',survey_code=(y-1999)//2+1,label=f'{y}-{y+1}',weight='WTMEC4YR' if y<2003 else 'WTMEC2YR',duration=4 if y<2003 else 2) for y in range(1999,2017,2)]+[dict(year=2017,suffix='',prefix='P_',survey_code=66,label='2017-March2020',weight='WTMECPRP',duration=3.2),dict(year=2021,suffix='_L',prefix='',survey_code=12,label='August2021-August2023',weight='WTMEC2YR',duration=2)]
def writecsv(path,rows):
    with open(path,'w',newline='',encoding='utf-8-sig') as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
def required(year,module):
    c=next(c for c in CYCLES if c['year']==year)
    return {'DEMO':['SEQN','SDDSRVYR','RIDAGEYR','RIAGENDR','RIDRETH1','DMDEDUC2','INDFMPIR','SDMVSTRA','SDMVPSU',c['weight']], 'MCQ':['SEQN','MCQ010','MCQ160A','MCQ190' if year<2009 else 'MCQ191' if year==2009 else 'MCQ195'], 'SMQ':['SEQN','SMQ020','SMQ040'],'BMX':['SEQN','BMXBMI']}[module]
def task(args):
    c,mod,mode=args;year=c['year'];name=c['prefix']+mod+c['suffix'];ext='htm' if mode=='metadata' else 'xpt'
    path=ROOT/mode/str(year)/(name+'.'+ext);path.parent.mkdir(parents=True,exist_ok=True)
    url=f'https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/{year}/DataFiles/{name}.{ext}';prov=path.with_suffix(path.suffix+'.download.json')
    assert pathlib.Path('/Volumes/Elements').is_mount()
    if path.exists():
        assert prov.exists(),f'Untracked file cannot be reused: {path}'
        r=json.loads(prov.read_text());data=path.read_bytes();assert hashlib.sha256(data).hexdigest()==r['sha256'] and len(data)==r['bytes'];return r
    for attempt in range(5):
        try:
            req=urllib.request.Request(url+'?run=extension_20261008_v1&attempt='+str(attempt),headers={'User-Agent':'Mozilla/5.0','Accept-Encoding':'identity'})
            with urllib.request.urlopen(req,timeout=90) as response:
                data=response.read();final=response.geturl();headers=dict(response.headers)
            if mode=='data':assert data.startswith(b'HEADER RECORD*******LIBRARY HEADER RECORD'),f'Not XPT: {url}'
            else:
                tree=html.fromstring(data)
                for v in required(year,mod):assert tree.xpath('//*[@id and translate(@id,"abcdefghijklmnopqrstuvwxyz","ABCDEFGHIJKLMNOPQRSTUVWXYZ")="'+v+'"]'),(year,mod,v)
            if headers.get('Content-Length'):assert len(data)==int(headers['Content-Length'])
            assert pathlib.Path('/Volumes/Elements').is_mount()
            part=path.with_suffix('.part');part.write_bytes(data);part.rename(path)
            r=dict(year=year,module=mod,file=path.name,url=url,final_url=final,path=str(path),bytes=len(data),sha256=hashlib.sha256(data).hexdigest(),retrieved_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),fresh=True)
            prov.write_text(json.dumps(r,indent=2));print(mode,name,len(data),flush=True);return r
        except Exception as e:
            print('RETRY',name,attempt+1,str(e)[:180],flush=True)
            if attempt==4:raise
            time.sleep(2**attempt)
def main(mode):
    assert pathlib.Path('/Volumes/Elements').is_mount();ROOT.mkdir(exist_ok=True);OUT.mkdir(exist_ok=True)
    writecsv(OUT/'cycle_catalog.csv',CYCLES)
    if mode=='data':assert json.loads((OUT/'metadata_gate.json').read_text())['verdict']=='pass'
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as p:rows=list(p.map(task,[(c,m,mode) for c in CYCLES for m in ['DEMO','MCQ','SMQ','BMX']]))
    writecsv(OUT/(mode+'_manifest.csv'),rows)
    if mode=='data':
        writecsv(OUT/'input_manifest.csv',rows)
        (OUT/'input_integrity.json').write_text(json.dumps(dict(verdict='pass',files=len(rows),bytes=sum(r['bytes'] for r in rows),fresh=True,legacy_reused=False),indent=2))
    print('COMPLETE',mode,len(rows),sum(r['bytes'] for r in rows),flush=True)
if __name__=='__main__':
    import sys;assert sys.argv[1] in ['metadata','data'];main(sys.argv[1])
