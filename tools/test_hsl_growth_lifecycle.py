import copy
import json
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from hsltools.probes.growth_lifecycle import PACKET, check
from hsltools.data.growth_lifecycle import build, OUT
from hsltools.data.growth_lifecycle_trial import build as trial, OUT as TRIAL


class GrowthLifecycleTests(unittest.TestCase):
    def test_native_returns_and_call_boundaries(self):
        packet = json.loads(PACKET.read_text())
        check(packet)
        self.assertTrue(packet['rewards'])
        self.assertTrue(packet['learning'])
        self.assertTrue(all(not row['draws'] for row in packet['rewards'] + packet['learning']))
        self.assertTrue(any(not row['normal_return'] for row in packet['rewards']))
        for kind in ['reward', 'learning', 'source_bytes', 'table', 'vm']:
            with self.subTest(kind=kind):
                bad = copy.deepcopy(packet)
                if kind == 'reward': bad['rewards'][0]['native']['level'] += 1
                elif kind == 'learning': bad['learning'][0]['native']['rng_unchanged'] = False
                elif kind == 'source_bytes': bad['anchors'][0]['bytes'] = '00' + bad['anchors'][0]['bytes'][2:]
                elif kind == 'table': bad['special_tables']['80']['rows'][0]['attributes']['str'] -= 1
                else: bad['vm'][1]['latch'] = 1
                with self.assertRaises(ValueError): check(bad)

    def test_source_masks_and_independent_thresholds(self):
        data = build()
        self.assertEqual(json.loads(OUT.read_text()), data)
        self.assertEqual(data['actors']['002']['magic:magicWATER'] & (1 << 4), 0)
        self.assertTrue(data['actors']['002']['magic:magicWATER'] & (1 << 5))
        cure = next(row for row in data['jobs']['85']['magic'] if row['id'] == 'magic:magicWATER:magicCode05')
        self.assertEqual(cure['level'], 6)
        self.assertEqual(cure['name'], '驅毒')
        self.assertEqual(data['jobs']['80']['magic'], [])
        self.assertEqual(data['jobs']['90']['special'], [])
        first = data['jobs']['80']['special'][0]
        self.assertEqual(first['attributes'], {'str':26, 'dex':20, 'mind':20, 'con':24})
        self.assertEqual(first['id'], 'special:magicAIR:magicCode01')

    def test_campaign_policy_keeps_learned_skills(self):
        data = json.loads(Path('content/battles/campaign.json').read_text())
        self.assertIn('learned_skills', data['carry_policy']['unit_keys'])
        self.assertIn('permanent_gains', data['carry_policy']['unit_keys'])

    def test_public_trial_uses_real_learning_identities(self):
        scene = trial()[TRIAL]
        actors = {row['id']: row for row in scene['playable_units']}
        self.assertEqual(actors['companion']['actor_id'], '001')
        self.assertEqual(actors['companion']['growth_profile']['allocation'], 'manual')
        self.assertEqual(actors['companion']['status_counters']['poison'], (16 << 16) | 3)
        self.assertEqual(actors['tina']['actor_id'], '002')
        self.assertNotIn('learned_skills', actors['tina'])
        self.assertEqual(actors['tina']['coord'], [10, 16])
        self.assertEqual(actors['companion']['coord'], [10, 15])
        self.assertTrue(all(row['coord'] == row['grid_coord'] for row in actors.values()))
