"""Extract each required field, target population and published frequency table."""
import re,json
from lxml import html
from acquire import ROOT,OUT,required,writecsv,CYCLES
rows=[];freq=[];coverage=[];notes=[]
for cycle in CYCLES:
    year=cycle['year'];suffix=cycle['suffix'];prefix=cycle['prefix']
    for module in ['DEMO','MCQ','SMQ','BMX']:
        name=prefix+module+suffix;path=ROOT/'metadata'/str(year)/(name+'.htm')
        tree=html.parse(str(path));alltext=' '.join(tree.getroot().text_content().split())
        for variable in required(year,module):
            n=tree.xpath('//*[translate(@id,"abcdefghijklmnopqrstuvwxyz","ABCDEFGHIJKLMNOPQRSTUVWXYZ")="'+variable+'"]')[0]
            parent=n.getparent();fields={}
            for dt in parent.xpath('.//dt'):
                dd=dt.getnext()
                if dd is not None:fields[' '.join(dt.text_content().split()).rstrip(': ')]= ' '.join(dd.text_content().split())
            codes=[]
            for tr in parent.xpath('.//tbody/tr'):
                cells=[' '.join(td.text_content().split()) for td in tr.xpath('./td')]
                if len(cells)>=4:
                    codes.append(cells)
                    freq.append(dict(year=year,module=module,variable=variable,code=cells[0],label=cells[1],count=int(cells[2].replace(',','')),skip=cells[4] if len(cells)>4 else ''))
            target=fields.get('Target','');nums=re.findall(r'(\d+) YEARS',target)
            assert len(nums)==2 and int(nums[0])<=20 and int(nums[1])>=79,(year,variable,target)
            if variable.startswith('MCQ19'):
                racode='1' if year<2011 else '2';assert any(c[0]==racode and 'rheumatoid' in c[1].lower() for c in codes)
            if variable=='MCQ010':assert 'ever told' in fields['English Text'].lower()
            rows.append(dict(year=year,module=module,variable=variable,official_variable=fields.get('Variable Name',n.get('id')),label=fields.get('SAS Label',''),question=fields.get('English Text',''),instructions=fields.get('English Instructions',''),target=target,codes=json.dumps(codes,ensure_ascii=False),source=f'https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/{year}/DataFiles/{name}.htm'))
        coverage.append(dict(year=year,module=module,required_fields=len(required(year,module)),all_fields_present=True,age20_79_supported=True))
        if module=='BMX':
            for term in ['pregnan','BMI','weight','comment','invalid']:
                for m in list(re.finditer(term,alltext,re.I))[:7]:notes.append(f'{year} {term}: '+alltext[max(0,m.start()-180):m.end()+350])
writecsv(OUT/'variable_dictionary.csv',rows);writecsv(OUT/'official_frequencies.csv',freq);writecsv(OUT/'cycle_coverage.csv',coverage)
(OUT/'bmi_documentation_review.txt').write_text('\n'.join(notes))
print('PASS required fields and adult coverage',len(rows),'fields',len(coverage),'modules')

(OUT/'metadata_gate.json').write_text(json.dumps(dict(verdict='pass',fields=len(rows),modules=len(coverage),scope='required field and adult eligibility; raw frequencies pending'),indent=2))
