import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('acquire', ROOT/'scripts/acquire.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class DownloadGateTests(unittest.TestCase):
    def test_revise_blocks_participant_download(self):
        with tempfile.TemporaryDirectory() as directory:
            gate=Path(directory)/'gate.json'
            gate.write_text(json.dumps({'primary_download_verdict':'revise'}))
            with self.assertRaisesRegex(RuntimeError, 'not passed'):
                module.require_download_gate(gate,ROOT/'docs/data/variable_dictionary.csv')

    def test_changed_dictionary_invalidates_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            dictionary = root/'dictionary.csv'
            dictionary.write_text('original metadata')
            gate = root/'gate.json'
            gate.write_text(json.dumps({'primary_download_verdict':'pass',
                                        'dictionary_sha256':module.digest(dictionary)}))
            module.require_download_gate(gate, dictionary)
            dictionary.write_text('changed metadata')
            with self.assertRaisesRegex(RuntimeError, 'changed'):
                module.require_download_gate(gate, dictionary)


if __name__ == '__main__':
    unittest.main()
