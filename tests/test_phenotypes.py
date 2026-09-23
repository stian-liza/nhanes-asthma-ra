import importlib.util
import unittest
from pathlib import Path
import pandas as pd

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('prepare',ROOT/'scripts/prepare.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)


def record(**changes):
    row=dict(MCQ160A=1,arthritis_type_raw=2,MCQ010=1,current_raw=1,MCQ040=2,MCQ050=2,
             RIDAGEYR=40,RIAGENDR=1,RIDRETH1=3,DMDEDUC2=5,INDFMPIR=3,
             SMQ020=2,SMQ040=float('nan'),WTINT2YR=90,WTINT4YR=100)
    row.update(changes)
    return row


class PhenotypeTests(unittest.TestCase):
    def test_official_rounded_weight_endpoints(self):
        s=pd.Series([2571.068712346633,433085.0052624958,433086.])
        self.assertEqual(module.matches(s,'2571.0687123 to 433085.00526').tolist(),[True,True,False])

    def test_unknown_and_contradictory_arthritis_not_negative(self):
        rows=[record(arthritis_type_raw=9),record(MCQ160A=2),
              record(MCQ160A=2,arthritis_type_raw=float('nan'))]
        d=module.phenotype(pd.DataFrame(rows),2017)
        self.assertTrue(d.ra.iloc[:2].isna().all());self.assertEqual(d.ra.iloc[2],0)

    def test_cycle_specific_ra_and_unasked_adult_asthma(self):
        row=pd.DataFrame([record(arthritis_type_raw=1)])
        early=module.phenotype(row,1999);late=module.phenotype(row,2017)
        self.assertEqual(early.ra.iloc[0],1);self.assertEqual(late.ra.iloc[0],0)
        self.assertTrue(early.current.isna().all());self.assertEqual(late.current.iloc[0],1)

    def test_structural_asthma_skip_and_current_conflict(self):
        d=module.phenotype(pd.DataFrame([record(MCQ010=2,current_raw=float('nan')),
                                        record(MCQ010=2,current_raw=1)]),2017)
        self.assertEqual(d.current.iloc[0],0);self.assertTrue(pd.isna(d.current.iloc[1]))

    def test_weight_and_age_topcode(self):
        d=module.phenotype(pd.DataFrame([record(RIDAGEYR=85)]),2017)
        self.assertEqual(d.age.iloc[0],80);self.assertEqual(d.w_primary.iloc[0],10)
        self.assertEqual(d.w_ever20.iloc[0],9)


if __name__=='__main__': unittest.main()
