from __future__ import annotations
import copy
import json
import unittest
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from hsltools.data.ai_profiles import build
from hsltools.probes.ai import PACKET, check_packet, expected


class OriginalAIDecisionTests(unittest.TestCase):
    def test_saved_original_functions_and_rng_replay(self):
        packet = json.loads(PACKET.read_text())
        check_packet(packet)
        self.assertTrue(packet['cases'])

    def test_changed_return_or_rng_is_rejected(self):
        packet = json.loads(PACKET.read_text())
        bad = copy.deepcopy(packet)
        bad['cases'][0]['normal_return'] = False
        with self.assertRaises(ValueError): check_packet(bad)
        bad = copy.deepcopy(packet)
        bad['cases'][0]['draws'][0]['bound'] = 100
        with self.assertRaises(ValueError): check_packet(bad)
        bad = copy.deepcopy(packet)
        bad['cases'][-1]['native'] += 1
        with self.assertRaises(ValueError): check_packet(bad)

    def test_odd_special_first_reuses_sample_when_special_unavailable(self):
        case = {'kind': 'action', 'magic_rate': 95, 'special_rate': 100,
                'magic_available': True, 'special_available': True, 'silenced': False}
        self.assertEqual(expected(case, [{'bound': 99, 'value': 0}]), 2)
        case['special_available'] = False
        self.assertEqual(expected(case, [{'bound': 99, 'value': 0}]), 1)
        case['magic_rate'] = 0
        self.assertEqual(expected(case, [{'bound': 99, 'value': 0}]), 0)

    def test_live_actor_source_profiles_and_absence_are_explicit(self):
        data = build()
        for actor in ['001', '021', '023', '024', '025', '026', '045']:
            self.assertEqual(data['actors'][actor]['missing_required'], [])
        self.assertEqual(data['actors']['026']['profile']['ai_att_magic'], 95)
        self.assertEqual(data['actors']['025']['profile']['ai_att_magic'], 80)
        self.assertEqual(data['actors']['023']['profile']['find_no_id'], 25)
        self.assertNotIn('find_type', data['actors']['003']['profile'])
        self.assertIn('find_type', data['actors']['003']['missing_required'])
