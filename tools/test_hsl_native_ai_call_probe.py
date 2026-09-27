import copy
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hsltools.probes.ai_call as probe


class AICallPacketTests(unittest.TestCase):
    def setUp(self):
        self.packet = json.loads(probe.PACKET.read_text())

    def test_saved_original_results(self):
        probe.check_packet(self.packet)
        self.assertTrue(any(row['normal_return'] for row in self.packet['cases']))
        self.assertTrue(self.packet['cases'])

    def test_unrelated_tag_changes_are_rejected(self):
        changed = copy.deepcopy(self.packet)
        changed['cases'][0]['result']['tags'][4] = 200
        with self.assertRaises(ValueError):
            probe.check_packet(changed)

    def test_prefix_cannot_be_relabelled_a_normal_return(self):
        self.packet['cases'][-1]['normal_return'] = True
        with self.assertRaises(ValueError):
            probe.check_packet(self.packet)

    def test_missing_coverage_or_executable_identity_is_rejected(self):
        changed = copy.deepcopy(self.packet)
        changed['cases'].pop()
        with self.assertRaises(ValueError):
            probe.check_packet(changed)
        self.packet['exe_sha256'] = 'different executable'
        with self.assertRaises(ValueError):
            probe.check_packet(self.packet)
