import copy
import json
import sys
import unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from hsltools.probes.moon_dance import PACKET, check
from hsltools.data.moon_dance import definition, check_assets, trial, ID
from hsltools.data.skill_book import build


class MoonDanceTests(unittest.TestCase):
    def test_actual_original_callbacks_and_mutation_guards(self):
        packet=json.loads(PACKET.read_text());check(packet)
        for key in ['hp','draw','normal','cost','bytes']:
            bad=copy.deepcopy(packet)
            if key=='hp':bad['cases'][0]['results'][1]['native']['hp']+=1
            elif key=='draw':bad['cases'][1]['results'][0]['draws'][0]['bound']+=1
            elif key=='normal':bad['cases'][1]['results'][0]['normal_return']=True
            elif key=='cost':bad['suffixes'][0]['native']['stamina']+=20
            else:bad['anchors'][0]['bytes']='00'+bad['anchors'][0]['bytes'][2:]
            with self.assertRaises(ValueError):check(bad)

    def test_complete_source_program_assets_and_ownership(self):
        value=definition();check_assets(value)
        self.assertEqual(value['source_hit_delays'],[80,90,100,110,120])
        self.assertEqual(len([p for p in value['program'] if p['op']=='aniProcessHitMiss']),5)
        self.assertEqual(value['source_fields']['range'],'range0Cell')
        book=build()
        self.assertIn(ID,book['actors']['002']['supported_initial_ids'])
        self.assertNotIn(ID,book['actors']['001']['supported_initial_ids'])
        self.assertEqual(book['actors']['029']['supported_initial_ids'],[])

    def test_development_stamina_and_roster_are_explicit(self):
        value=trial()
        self.assertEqual(value['skill_rules']['initial_stamina'],40)
        self.assertTrue(value['playable_units'])
        self.assertIn('not a formal',value['development_note'])
        self.assertEqual(json.loads(Path('content/battles/first_battle.json').read_text())['skill_rules']['initial_stamina'],0)
        self.assertEqual(json.loads(Path('content/battles/priest_trial.json').read_text())['skill_rules']['initial_stamina'],0)
