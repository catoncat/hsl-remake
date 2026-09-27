import copy
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hsltools.probes.ai_skill as probe
import hsltools.data.skill_book as skill_book


class AISkillPacketTests(unittest.TestCase):
    def setUp(self):
        self.packet = json.loads(probe.PACKET.read_text())

    def test_original_results_and_execution_boundaries(self):
        probe.check(self.packet)
        self.assertTrue(any(row['normal_return'] for row in self.packet['cases']))
        self.assertTrue(self.packet['cases'])

    def test_tampered_result_draw_and_full_return_claim_are_rejected(self):
        for corruption in ['result', 'draw', 'boundary', 'coverage']:
            packet = copy.deepcopy(self.packet)
            if corruption == 'result': packet['cases'][0]['native'] = [99]
            elif corruption == 'draw': packet['cases'][0]['draws'] = [{'bound': 2, 'value': 0}]
            elif corruption == 'boundary': packet['cases'][-1]['normal_return'] = True
            else: packet['cases'].pop()
            with self.subTest(corruption=corruption), self.assertRaises(ValueError):
                probe.check(packet)

    def test_initial_skill_order_comes_from_original_type_and_code(self):
        book = skill_book.build()
        self.assertIn('TYPE.H', book['sources'])
        skills = book['skills']
        self.assertEqual(skills['magic:magicFIRE:magicCode01']['source_order'], 96)
        self.assertEqual(skills['magic:magicAIR:magicCode01']['source_order'], 64)
        self.assertEqual(skills['magic:magicAIR:magicCode05']['source_order'], 68)
        self.assertEqual(skills['magic:magicMIND:magicCode02']['source_order'], 129)
