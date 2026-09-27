import copy
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hsltools.probes.ohm_growth as growth
import hsltools.probes.bow_range as bow
import hsltools.probes.poison_arrow as arrow
from hsltools.data.ohm_village import build, OUT
from hsltools.data.combat_aftermath import build as aftermath


class OhmVillageTests(unittest.TestCase):
    def test_actual_original_packets_and_stops(self):
        for module in (growth, bow, arrow):
            module.check(json.loads(module.PACKET.read_text()))
        packet = json.loads(growth.PACKET.read_text())
        self.assertEqual({r['input']['actor'] for r in packet['stats']}, {'003','061','062'})
        self.assertTrue(all(r['normal_return'] for r in packet['growth']))
        self.assertTrue(all(not r['normal_return'] for r in packet['copies']))
        self.assertEqual({r['stop_address'] for r in packet['rewards'] if not r['normal_return']}, {'0x442a45'})

    def test_evidence_cannot_upgrade_prefix_or_change_identity(self):
        packet = json.loads(growth.PACKET.read_text())
        for kind in ('anchor','copy_mode','copy_return','reward_stop','learning_missing','learning_bytes'):
            with self.subTest(kind=kind):
                bad = copy.deepcopy(packet)
                if kind == 'anchor':bad['anchors'][0]['bytes']='00'+bad['anchors'][0]['bytes'][2:]
                elif kind == 'copy_mode':bad['copies'][0]['source_mode']=0x10000
                elif kind == 'copy_return':bad['copies'][0]['normal_return']=True
                elif kind == 'reward_stop':bad['rewards'][1]['stop_address']='0x10000000'
                elif kind == 'learning_missing':bad.pop('learning')
                else:bad['learning_table']['bytes']='00'+bad['learning_table']['bytes'][2:]
                with self.assertRaises(ValueError):growth.check(bad)

    def test_poison_damage_draws_and_application_boundary_are_independent(self):
        original = json.loads(arrow.PACKET.read_text())
        for kind in ('boundary','draw','contribution'):
            with self.subTest(kind=kind):
                bad=copy.deepcopy(original)
                if kind=='boundary':bad['applications'][0]['normal_return']=True
                elif kind=='draw':bad['applications'][0]['draws'][0]['bound']+=1
                else:bad['applications'][0]['native']['contribution']+=1
                with self.assertRaises(ValueError):arrow.check(bad)
        self.assertEqual(arrow.fields()['expend'],'1')
        self.assertEqual(arrow.fields()['function'],'magicFun_Attack,magicFun_Poison')

    def test_formal_level_is_not_a_synthetic_trial_or_new_grant(self):
        templates, scene=build()
        self.assertEqual(scene,json.loads(OUT.read_text()))
        roster=scene['playable_units']
        self.assertEqual(len(roster),18)
        self.assertEqual({a['actor_id'] for a in roster if a['player_commandable']},{'001','003'})
        self.assertEqual(scene['scenario_rules']['script_fallback']['escape_zone'],[])
        self.assertEqual(scene['scenario_rules']['reinforcements'],[])
        for code in ('061','062'):
            actor=templates[code]['actor']
            self.assertEqual(actor['growth_profile']['source']['mode'],0x50000)
            self.assertEqual(actor['growth_profile']['job_code'],80)
            self.assertEqual(actor['equipment'],[])
            self.assertEqual(actor['weapon_code'],0)
            self.assertFalse(actor['player_commandable'])
        hu=templates['003']['actor']
        self.assertEqual(hu['weapon_code'],61)
        self.assertEqual(hu['growth_profile']['job_code'],83)
        self.assertEqual(hu['growth_profile']['caps'],dict(zip(('str','dex','mind','con'),(96,98,70,88))))
        death = aftermath()['actors']
        self.assertTrue({a['actor_id'] for a in roster} <= set(death))
        for code in ('003','061','062'):
            self.assertEqual(death[code]['messages'], [])  # No invented last words; source script owns terminal dialogue.


if __name__=='__main__':unittest.main()
