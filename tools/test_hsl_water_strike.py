import copy
import json
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from hsltools.data.skill_book import build
from hsltools.probes.water_strike import PACKET, check
from hsltools.data.water_strike import OUT, SKILL_ID, definitions
from hsltools.data.water_strike_trial import build as trial, OUT as TRIAL


class WaterStrikeTests(unittest.TestCase):
    def test_exact_source_and_ownership(self):
        book=build();spell=book['skills'][SKILL_ID]
        self.assertEqual(spell['fields'],definitions()['water']['fields'])
        self.assertEqual(spell['element'],'1')
        self.assertIn(SKILL_ID,book['actors']['025']['supported_initial_ids'])
        self.assertNotIn(SKILL_ID,book['actors']['002']['supported_initial_ids'])
        self.assertNotIn(SKILL_ID,book['actors']['026']['supported_initial_ids'])

    def test_native_coverage_and_rejection(self):
        data=json.loads(PACKET.read_text());check(data)
        self.assertTrue(data['rolls'])
        self.assertTrue(data['applications'])
        bad=copy.deepcopy(data);bad['applications'][0]['normal_return']=True
        with self.assertRaises(ValueError):check(bad)

    def test_original_assets_not_wind_reskins(self):
        data=json.loads((OUT/'manifest.json').read_text())
        self.assertEqual(len(data['images']),11)
        self.assertEqual(set(data['sounds']),{'WAV\\WATER005.WAV'})
        self.assertTrue(all(name.startswith('MAGIC\\WAT') for name in data['images']))
        self.assertEqual(data['bindings']['water']['actions'][2],'effWait,80')

    def test_public_trial_has_real_learning_and_cross(self):
        data=trial()[TRIAL];actors={a['id']:a for a in data['playable_units']}
        self.assertEqual(actors['tina']['actor_id'],'002')
        self.assertNotIn('learned_skills',actors['tina'])
        self.assertEqual(sum(actors['tina']['combat_profile'][k] for k in ['str','dex','mind','con']),62)
        self.assertEqual(actors['enemy021_1']['coord'],[12,16])
        self.assertEqual(actors['enemy021_2']['coord'],[11,15])
        self.assertNotIn([11,16],[a['coord'] for a in actors.values()])
