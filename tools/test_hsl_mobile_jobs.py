import copy
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parent))
import hsltools.probes.mobile_jobs as jobs
import hsltools.probes.mana_strike as mana
import hsltools.probes.mobile_motion as motion
import hsltools.probes.mobile_source as optional
from hsltools.data.mobile_jobs import build
from hsltools.assets.combat_animation import PROGRAMS, compile_action
from hsltools.data.equipment import build as equipment
from hsltools.data.combat_aftermath import build as aftermath

class MobileJobsTests(unittest.TestCase):
    def test_full_native_refresh_identity_and_boundaries(self):
        packet=json.loads(jobs.PACKET.read_text());jobs.check(packet)
        for kind in ['value','boundary','bytes']:
            bad=copy.deepcopy(packet)
            if kind=='value':bad['cases'][0]['native'][0]['values']['attack']+=1
            elif kind=='boundary':bad['cases'][0]['native'][0]['normal_return']=False
            else:bad['anchors'][0]['bytes']='00'+bad['anchors'][0]['bytes'][2:]
            with self.assertRaises(ValueError):jobs.check(bad)

    def test_mana_uses_capped_last_damage_and_keeps_source(self):
        packet=json.loads(mana.PACKET.read_text());mana.check(packet)
        lethal=next(r for r in packet['impact'] if r['input']==dict(hp=1,damage=300,mp=77,effects=mana.MP_FLAG))
        self.assertEqual(lethal['native'],dict(hp=0,contribution=1,mp=77,attacker_mp=51))
        bad=copy.deepcopy(packet);bad['impact'][0]['native']['mp']+=1
        with self.assertRaises(ValueError):mana.check(bad)
        self.assertTrue(any(r['native']['effect_called'] and r['input']['hp']==0 and r['input']['remaining']>0 for r in packet['caller']))
        self.assertTrue(all(not r['native']['effect_called'] for r in packet['caller'] if r['input']['remaining'] and r['input']['hp']))

    def test_exact_defaults_flight_and_hidden_skills(self):
        data=build();actors={c:data[Path(f'content/generated/hsl/actors/{c}.json')]['actor'] for c in jobs.ACTORS}
        for code,job,weapon in [('004',88,102),('006',92,43),('028',88,21),('036',92,33)]:
            self.assertEqual((actors[code]['growth_profile']['job_code'],actors[code]['weapon_code']),(job,weapon))
        book=json.loads(Path('content/generated/hsl/skills/initial_book.json').read_text())['actors']
        self.assertTrue(book['006']['traversal']['flying']);self.assertFalse(book['036']['traversal']['flying'])
        self.assertEqual(book['004']['supported_initial_ids'],['special:magicOTHER:magicCode10'])  # 銀之手: PLAYERS special_other initial (lane A)
        self.assertEqual(book['006']['supported_initial_ids'],['magic:magicAIR:magicCode01','special:magicOTHER:magicCode16'])
        item=equipment()['items']['108']
        self.assertTrue(item['supported']);self.assertEqual(item['weapon_effect_flags'],mana.MP_FLAG)
        self.assertTrue(item['job_mask']&(1<<8));self.assertFalse(item['job_mask']&(1<<12))

    def test_source_motion_and_optional_zero(self):
        motion.check(json.loads(motion.PACKET.read_text()));optional.check(json.loads(optional.PACKET.read_text()))
        programs={r['code']:r for r in json.loads(PROGRAMS.read_text())['records']}
        for token in ['SID_PLAYER3','SID_PLAYER5']:
            dispatch=compile_action(programs[token]['programs']['action'],12)
            self.assertLess(dispatch['release_update'],dispatch['complete_updates'])
            self.assertTrue(dispatch['presentation_transform_states'])
            self.assertEqual(dispatch['presentation_transform_states'][0],dict(offset=[0,0],zoom=65536))
        bad=json.loads(motion.PACKET.read_text());bad['xy'][0]['position'][0]+=1
        with self.assertRaises(ValueError):motion.check(bad)

    def test_authored_inventory_uses_actual_role_ids(self):
        data=build();trial=data[Path('content/battles/mobile_jobs_trial.json')]
        bag=data[Path('content/generated/hsl/development/mobile_jobs_inventory.json')]
        self.assertEqual(trial['player_unit_id'],'thief')
        self.assertEqual([a['actor_id'] for a in trial['playable_units'] if a['player_commandable']],['004','006','002'])
        self.assertIn(108,bag['initial_inventory']['004']);self.assertIn(232,bag['initial_inventory']['006'])
        first=json.loads(Path('content/battles/first_battle.json').read_text())
        self.assertNotIn('004',[a['actor_id'] for a in first['playable_units']])

    def test_new_roles_have_source_death_records_even_without_a_line(self):
        records=aftermath()['actors']
        for code in jobs.ACTORS:
            self.assertIn(code,records)
            self.assertIsInstance(records[code]['messages'],list)
            self.assertTrue(all(row['id'] and row['text'] for row in records[code]['messages']))
