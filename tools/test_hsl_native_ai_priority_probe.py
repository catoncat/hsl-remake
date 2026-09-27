import copy
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hsltools.probes.ai_priority as probe


class PriorityPacketTests(unittest.TestCase):
    def setUp(self):
        self.packet = json.loads(probe.PACKET.read_text())

    def test_saved_original_results_and_coverage(self):
        probe.check_packet(self.packet)
        self.assertTrue(self.packet['cases'])
        self.assertTrue(any(row['normal_return'] for row in self.packet['cases']))

    def test_output_tampering_rejected(self):
        self.packet['cases'][0]['result']['native'] = 999
        with self.assertRaises(ValueError): probe.check_packet(self.packet)

    def test_rng_consumption_rejected(self):
        self.packet['cases'][0]['draws'].append({'bound': 18, 'value': 0})
        with self.assertRaises(ValueError): probe.check_packet(self.packet)

    def test_prefix_is_not_a_normal_return(self):
        next(row for row in self.packet['cases'] if row['input']['kind'] == 'priority')['normal_return'] = True
        with self.assertRaises(ValueError): probe.check_packet(self.packet)

    def test_missing_coverage_and_identity_rejected(self):
        for mutation in ['coverage', 'identity']:
            data = copy.deepcopy(self.packet)
            if mutation == 'coverage': data['cases'].pop()
            else: data['exe_sha256'] = 'wrong'
            with self.assertRaises(ValueError): probe.check_packet(data)
