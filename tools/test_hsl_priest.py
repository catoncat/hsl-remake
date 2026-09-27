import copy
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parent))
import hsltools.probes.priest as priest
import hsltools.probes.priest_motion as motion
import hsltools.probes.mana_item as mana
from hsltools.assets.combat_animation import compile_action, PROGRAMS
from hsltools.data.priest import build
from hsltools.probes.job_stats import sources


class PriestIntegrationTests(unittest.TestCase):
    def test_original_mapping_refresh_and_corruption(self):
        packet=json.loads(priest.PACKET.read_text());priest.check(packet)
        actual=next(r for r in packet['bindings'] if r['input']['slot']==1)
        self.assertEqual(actual['template_index'],2)
        self.assertNotEqual(actual['template_index'],actual['input']['previous_template'])
        for kind in ['template','stat','boundary','bytes']:
            bad=copy.deepcopy(packet)
            if kind=='template':bad['bindings'][1]['template_index']=29
            elif kind=='stat':bad['stats'][0]['native'][0]['values']['max_mp']+=1
            elif kind=='boundary':bad['bindings'][0]['prefix_stop']='0x407f15'
            else:bad['anchors'][0]['bytes']='00'+bad['anchors'][0]['bytes'][2:]
            with self.assertRaises(ValueError):priest.check(bad)

    def test_motion_proof_and_complete_source_program(self):
        packet=json.loads(motion.PACKET.read_text());motion.check(packet)
        source=next(r for r in json.loads(PROGRAMS.read_text())['records'] if r['code']=='SID_PLAYER1')
        dispatch=compile_action(source['programs']['action'],6)
        self.assertEqual(dispatch['motion_offsets'][0],[0,0])
        self.assertEqual(dispatch['motion_offsets'][-1],[0,0])
        self.assertEqual(min(p[1] for p in dispatch['motion_offsets']),-136)
        self.assertLess(next(e['update'] for e in dispatch['events'] if e['op']=='aniSetStopSpeed'),dispatch['release_update'])
        bad=copy.deepcopy(packet);bad['native']['states'][5]['y']+=1
        with self.assertRaises(ValueError):motion.check(bad)

    def test_mana_source_prefix_and_zero_draws(self):
        packet=json.loads(mana.PACKET.read_text());mana.check(packet)
        self.assertTrue(all(r['rng_calls']==0 for r in packet['cases']))
        self.assertTrue(any(r['native']['restored_mp']==0 for r in packet['cases']))
        bad=copy.deepcopy(packet);bad['cases'][0]['native']['flags']=9
        with self.assertRaises(ValueError):mana.check(bad)

    def test_trial_is_explicit_and_source_healing_is_not_granted_to_leonard(self):
        actor,scenario,rules,items=build()
        self.assertEqual((actor['actor']['actor_id'],actor['actor']['growth_profile']['job_code']),('002',85))
        self.assertEqual(scenario['player_unit_id'],'tina')
        self.assertEqual(scenario['rule_adapter'],'development_battle')
        self.assertEqual(items['items']['244']['heal_mp'],30)
        self.assertEqual(rules['schema'],'hsl_development_objectives.v1')
        book=json.loads(Path('content/generated/hsl/skills/initial_book.json').read_text())
        self.assertEqual(book['actors']['002']['supported_initial_ids'],['special:magicOTHER:magicCode06','magic:magicWATER:magicCode06'])
        self.assertNotIn('magic:magicWATER:magicCode06',book['actors']['001']['supported_initial_ids'])
        players,_,_=sources()
        story=players['029']
        self.assertTrue(all(int(story.get(key,0))==0 for key in ['weapon_equip','head_equip','armor_equip','foot_equip','other1_equip','other2_equip']))
        self.assertEqual(book['actors']['029']['supported_initial_ids'],[])
        self.assertNotIn('029',json.loads(Path('content/generated/hsl/roles/profiles.json').read_text())['actors'])
