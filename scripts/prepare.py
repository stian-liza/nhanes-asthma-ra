"""Validate official frequencies and construct transparent person-level phenotypes.

Only aggregate QC is written to the repository. Person records stay on external disk.
"""
import argparse
import hashlib
import json
import os
import re
from pathlib import Path

import numpy as np
import pandas as pd

REPO = Path(__file__).resolve().parents[1]


def phenotype(frame, year):
    d = frame.copy()
    a = d['MCQ160A']; t = d['arthritis_type_raw']
    positive = 1 if year <= 2009 else 2
    valid = [1, 2, 3] if year <= 2007 else [1, 2, 3, 4]
    d['ra_conflict'] = ((a == 2) & t.notna()) | (~a.isin([1, 2]) & t.isin(valid))
    d['ra'] = np.select([(a == 1) & (t == positive),
                         ((a == 2) & t.isna()) | ((a == 1) & t.isin(valid) & (t != positive))],
                        [1., 0.], default=np.nan)
    d.loc[d.ra_conflict, 'ra'] = np.nan
    d['ra_unknown_type'] = (a == 1) & ~t.isin(valid) & ~d.ra_conflict
    d['no_arthritis'] = (a == 2) & ~d.ra_conflict
    ever = d.MCQ010; still = d.current_raw
    d['asthma_conflict'] = ((ever == 2) & still.notna()) | (~ever.isin([1, 2]) & still.isin([1, 2]))
    d['ever'] = ever.map({1: 1., 2: 0.})
    d['current'] = np.select([(ever == 1) & (still == 1),
                              ((ever == 2) & still.isna()) | ((ever == 1) & (still == 2))],
                             [1., 0.], default=np.nan)
    d.loc[d.asthma_conflict, 'current'] = np.nan
    if year == 1999:
        d.loc[d.RIDAGEYR >= 20, 'current'] = np.nan
    d['asthma_state'] = np.select([d.current == 1, (d.ever == 1) & (d.current == 0),
                                    (d.ever == 0) & ~d.asthma_conflict],
                                   ['current', 'former', 'never'], default='unknown')
    d['attack'] = d.MCQ040.map({1: 1., 2: 0.})
    d['er'] = d.MCQ050.map({1: 1., 2: 0.})
    d['age'] = d.RIDAGEYR.clip(upper=80)
    d['age80'] = (d.RIDAGEYR >= 80).astype(int)
    d['sex'] = d.RIAGENDR.where(d.RIAGENDR.isin([1, 2]))
    d['race'] = d.RIDRETH1.where(d.RIDRETH1.isin([1, 2, 3, 4, 5]))
    d['education'] = d.DMDEDUC2.where(d.DMDEDUC2.isin([1, 2, 3, 4, 5]))
    d['pir'] = d.INDFMPIR.where(d.INDFMPIR.between(0, 5))
    smoked = d.SMQ020; now = d.SMQ040
    d['smoke'] = np.select([(smoked == 2) & now.isna(), (smoked == 1) & (now == 3),
                           (smoked == 1) & now.isin([1, 2])], [0., 1., 2.], default=np.nan)
    d['smoke_conflict'] = (smoked == 2) & now.notna()
    d['cycle'] = year
    d['w_primary'] = d.WTINT2YR / 9 if year >= 2001 else 0.
    d['w_ever20'] = d.WTINT4YR * .2 if year <= 2001 else d.WTINT2YR * .1
    return d


def matches(series, code):
    if code == '.':
        return series.isna()
    if re.fullmatch(r'-?\d+(\.\d+)?', code):
        return np.isclose(series, float(code), rtol=0, atol=1e-10)
    m = re.fullmatch(r'(-?[\d.]+) to (-?[\d.]+)', code)
    if m:
        # CDC displays rounded decimal endpoints; XPORT retains greater precision.
        tolerance = lambda s: max(1e-10, .5*10**(-len(s.split('.')[1]))) if '.' in s else 1e-10
        return series.between(float(m[1])-tolerance(m[1]), float(m[2])+tolerance(m[2]))
    raise ValueError(f'Unparsed official code: {code}')


def prepare(root):
    dictionary = pd.read_csv(REPO/'docs/data/variable_dictionary.csv').fillna('')
    manifest = pd.read_csv(REPO/'manifests/downloads.csv')
    qc = REPO/'results/qc'; qc.mkdir(parents=True, exist_ok=True)
    frames = []; frequency = []; joins = []
    for year in range(1999, 2019, 2):
        cycle = f'{year}-{year+1}'
        modules = {}
        for module in ['DEMO', 'MCQ', 'SMQ']:
            row = manifest[(manifest.cycle == cycle) & (manifest.module == module)].iloc[0]
            p = root/row.relative_path
            if hashlib.sha256(p.read_bytes()).hexdigest() != row.sha256:
                raise ValueError(f'Checksum changed: {row.file}')
            raw = pd.read_sas(p, format='xport'); raw.columns = raw.columns.str.upper()
            # pandas XPORT IBM-float zero can appear as 5.397605e-79.
            # These survey fields have no scientifically meaningful values this small.
            numeric=raw.select_dtypes(include='number').columns
            raw[numeric]=raw[numeric].mask(raw[numeric].abs()<1e-70,0.)
            if raw.SEQN.isna().any() or not raw.SEQN.is_unique:
                raise ValueError('Missing or repeated SEQN')
            wanted = dictionary[(dictionary.cycle == cycle) & (dictionary.module == module)]
            for variable in wanted.itertuples():
                name = variable.variable.upper()
                if name not in raw:
                    raise ValueError(f'Missing data field {name}')
                for value in json.loads(variable.values_json):
                    actual = int(matches(raw[name], value['code']).sum())
                    frequency.append(dict(cycle=cycle,module=module,variable=name,code=value['code'],
                                          expected=value['count'],actual=actual,pass_check=actual==value['count']))
            modules[module] = raw[[r.upper() for r in wanted.variable]].copy()
        d = modules['DEMO']
        for module in ['MCQ', 'SMQ']:
            other = modules[module]
            orphans = int((~other.SEQN.isin(d.SEQN)).sum())
            if orphans:
                raise ValueError(f'Orphan persons: {cycle} {module}')
            before = len(d)
            d = d.merge(other, on='SEQN', how='left', validate='one_to_one', indicator=f'{module}_match')
            joins.append(dict(cycle=cycle,module=module,source_n=len(other),demographic_n=before,
                              merged_n=len(d),unmatched_n=int((d[f'{module}_match']=='left_only').sum()),orphans=orphans))
        kind = 'MCQ190' if year <= 2007 else ('MCQ191' if year == 2009 else 'MCQ195')
        d['arthritis_type_raw'] = d[kind]
        d['current_raw'] = d['MCQ030' if year == 1999 else 'MCQ035']
        frames.append(phenotype(d, year))
    pd.DataFrame(frequency).to_csv(qc/'official_frequency_checks.csv',index=False)
    pd.DataFrame(joins).to_csv(qc/'merge_checks.csv',index=False)
    if not all(r['pass_check'] for r in frequency):
        raise ValueError('Official frequency mismatch: inspect QC before proceeding')
    all_data = pd.concat(frames, ignore_index=True)
    if not all_data.SEQN.is_unique:
        raise ValueError('Repeated SEQN across cycles')
    cols = ['SEQN','cycle','RIDAGEYR','age','age80','sex','race','education','pir','smoke',
            'ra','ra_unknown_type','ra_conflict','no_arthritis','ever','current','asthma_state',
            'asthma_conflict','attack','er','smoke_conflict','SDMVSTRA','SDMVPSU',
            'WTINT2YR','WTINT4YR','w_primary','w_ever20']
    output = root/'derived/v03'; output.mkdir(parents=True,exist_ok=True)
    all_data[cols].to_csv(output/'persons.csv', index=False)
    cov = ['age','sex','race','education','pir','smoke']
    flows = []; missing = []; cells = []
    for label,start,outcome,weight in [('primary',2001,'current','w_primary'),('ever20',1999,'ever','w_ever20')]:
        for cycle in ['all'] + list(range(start,2019,2)):
            source=all_data[all_data.cycle>=start]
            if cycle != 'all': source=source[source.cycle==cycle]
            adults=source[source.RIDAGEYR>=20]
            valid=adults[adults.ra.notna() & adults[outcome].notna()]
            complete=valid[valid[cov].notna().all(axis=1)]
            flows.append(dict(analysis=label,cycle=cycle,source_n=len(source),adult_n=len(adults),
                              ra_unknown_n=int(adults.ra.isna().sum()),outcome_unknown_n=int(adults[outcome].isna().sum()),
                              joint_known_n=len(valid),complete_n=len(complete),
                              complete_pct=100*len(complete)/len(valid),
                              weighted_complete_pct=100*complete[weight].sum()/valid[weight].sum(),
                              ra_conflicts=int(adults.ra_conflict.sum()),asthma_conflicts=int(adults.asthma_conflict.sum())))
            for r in [0,1]:
                for a in [0,1]:
                    g=valid[(valid.ra==r)&(valid[outcome]==a)]
                    cells.append(dict(analysis=label,cycle=cycle,ra=r,outcome=a,n=len(g),weight_sum=g[weight].sum()))
                    for variable in cov:
                        miss=g[variable].isna()
                        missing.append(dict(analysis=label,cycle=cycle,ra=r,outcome=a,variable=variable,n=len(g),
                                            missing_n=int(miss.sum()),missing_pct=100*miss.mean(),
                                            weighted_missing_pct=100*g.loc[miss,weight].sum()/g[weight].sum()))
    pd.DataFrame(flows).to_csv(qc/'sample_flow.csv',index=False)
    pd.DataFrame(missing).to_csv(qc/'covariate_missingness.csv',index=False)
    pd.DataFrame(cells).to_csv(qc/'joint_cells.csv',index=False)
    excluded=[]
    adults=all_data[(all_data.cycle>=2001)&(all_data.age>=20)]
    for unknown,g in adults.groupby(adults.ra.isna()):
        w=g.w_primary
        excluded.append(dict(group='RA_unknown' if unknown else 'RA_known',n=len(g),
                             weighted_age=np.average(g.age,weights=w),
                             female_pct=100*w[g.sex==2].sum()/w.sum(),
                             unknown_type_n=int(g.ra_unknown_type.sum())))
    pd.DataFrame(excluded).to_csv(qc/'ra_exclusion_characteristics.csv',index=False)
    info=dict(records=len(all_data),frequency_checks=len(frequency),all_frequency_checks_pass=True,
              derived_sha256=hashlib.sha256((output/'persons.csv').read_bytes()).hexdigest(),
              person_data_location='external_volume/NHANES/derived/v03/persons.csv')
    (qc/'preparation.json').write_text(json.dumps(info,indent=2)+'\n')
    print(json.dumps(info,indent=2))
    print(pd.DataFrame(flows).query('cycle == "all"').to_string(index=False))


if __name__ == '__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--root',type=Path,required=True)
    args=parser.parse_args(); root=args.root.resolve()
    if not str(root).startswith('/Volumes/') or not os.path.ismount(Path('/Volumes')/root.parts[2]):
        raise ValueError('Mounted external volume required')
    prepare(root)
