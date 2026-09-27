"""Protect source-execution evidence and its declared boundaries from drift."""
import copy
import json
import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hsltools.probes.ai_support as support


class SupportEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.packet = json.loads(support.PACKET.read_text())

    def test_checked_original_replies_and_cursors(self):
        support.check(self.packet)
        scans = [row for row in self.packet['cases'] if row['normal_return']]
        self.assertTrue(any(len(row['result']['indices']) > 3 for row in scans))
        self.assertTrue(all(row['result']['indices'][-1] == 0 for row in scans))

    def test_changed_result_or_rng_is_rejected(self):
        changed = copy.deepcopy(self.packet)
        row = next(row for row in changed['cases'] if row['draws'])
        row['draws'].pop()
        with self.assertRaises(ValueError): support.check(changed)
        changed = copy.deepcopy(self.packet)
        row = next(row for row in changed['cases'] if row['input']['kind'] == 'status' and row['result']['masks'])
        row['result']['masks'][0] ^= 1
        with self.assertRaises(ValueError): support.check(changed)

    def test_prefix_cannot_be_relabelled_complete(self):
        row = next(row for row in self.packet['cases'] if row['input']['kind'] == 'priority')
        row['normal_return'] = True
        with self.assertRaises(ValueError): support.check(self.packet)


if __name__ == '__main__': unittest.main()
