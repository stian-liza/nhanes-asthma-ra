import csv
import importlib.util
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('audit_metadata', ROOT/'scripts/audit_metadata.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class MetadataTests(unittest.TestCase):
    def test_children_only_is_not_adult_measurement(self):
        self.assertIs(module.includes_age('Both males and females 1 YEARS - 19 YEARS'), False)
        self.assertIs(module.includes_age('Both males and females 20 YEARS - 150 YEARS'), True)
        self.assertIsNone(module.includes_age('unknown'))

    def test_ra_label_not_fixed_numeric_code(self):
        for code in ['1', '2']:
            row = {'values_json': json.dumps([{'code': code, 'label': 'Rheumatoid arthritis'}])}
            self.assertEqual(module.ra_code(row), code)
        with self.assertRaises(ValueError):
            module.ra_code({'values_json': '[]'})

    def test_official_coverage_and_case_insensitivity(self):
        with (ROOT/'docs/data/variable_dictionary.csv').open() as f:
            rows = list(csv.DictReader(f))
        results = module.audit(rows)
        self.assertEqual(len(results), 10)
        self.assertEqual([r['cycle'] for r in results if r['adult_current_coverage_verdict']=='revise'],
                         ['1999-2000'])
        self.assertEqual([r['ra_positive_code'] for r in results], ['1']*6 + ['2']*4)
        self.assertTrue(all(not r['missing_required'] for r in results))


if __name__ == '__main__':
    unittest.main()
