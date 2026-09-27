import json
from pathlib import Path
import tempfile
import unittest
from hsltools.sources.tables import parse_table
from hsltools.levels.message_text import DEFAULT_EVIDENCE, check_message_text_evidence


class MessageTextTest(unittest.TestCase):
    def test_controls_and_commas(self):
        raw = '[other]\nitem = 1,ignored\n[name]\nitem = 1,@4帝國@1萬歲！#快,走\n'
        self.assertEqual(parse_table(raw.encode('cp950')), {'1': '帝國萬歲！\n快,走'})

    def test_duplicate_rejected(self):
        with self.assertRaises(ValueError):
            parse_table(b'[name]\nitem = 1,a\nitem = 1,b')

    def test_tampering_and_missing_source(self):
        evidence = json.loads(DEFAULT_EVIDENCE.read_text())
        source = Path(evidence['sources']['text_table'])
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / source).parent.mkdir(parents=True)
            (root / source).write_bytes((DEFAULT_EVIDENCE.parent / source).read_bytes())
            path = root / 'evidence.json'
            evidence['messages']['363'] = 'invented speech'
            path.write_text(json.dumps(evidence))
            with self.assertRaisesRegex(ValueError, 'differs'):
                check_message_text_evidence(path)
            (root / source).unlink()
            with self.assertRaises(FileNotFoundError):
                check_message_text_evidence(path)
