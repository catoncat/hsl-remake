import copy
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0,str(Path(__file__).resolve().parent))
import hsltools.probes.stat_magic as native
import hsltools.probes.ai_stat as ai
import hsltools.data.stat_magic as data
from hsltools.data.skill_book import build


class StatMagicTests(unittest.TestCase):
    def test_bounded_native_application_refresh_and_expiry(self):
        packet=json.loads(native.PACKET.read_text())
        native.check(packet)
        for field in ['application','expiry','boundary','bytes']:
            bad=copy.deepcopy(packet)
            if field=='application':bad['applications'][0]['derived']['attack']+=1
            elif field=='expiry':bad['ticks'][-1]['derived']['defense']+=1
            elif field=='boundary':bad['applications'][0]['normal_return']=True
            else:bad['anchors'][0]['bytes']='00'+bad['anchors'][0]['bytes'][2:]
            with self.assertRaises(ValueError):native.check(bad)

    def test_original_ai_priority_and_nonredundant_scan(self):
        packet=json.loads(ai.PACKET.read_text())
        ai.check(packet)
        bad=copy.deepcopy(packet);bad['cases'][0]['result']['attempted']^=16
        with self.assertRaises(ValueError):ai.check(bad)
        self.assertEqual(ai.useful([0x20,0x40],0x30),0)
        self.assertEqual(ai.useful([0x20,0x40],0x10),1)
        self.assertEqual(ai.useful([0x20],0x20),0)

    def test_source_grants_and_explicit_training_remain_distinct(self):
        book=build();defs=data.definitions()
        self.assertEqual({k:v['fields']['expend'] for k,v in defs.items()},{'attack_up':'19','defense_up':'12','dispel':'18'})
        self.assertFalse(any(s['skill_id'] in book['actors']['002']['supported_initial_ids'] for s in defs.values()))
        self.assertTrue(all(defs[k]['skill_id'] in book['actors']['045']['supported_initial_ids'] for k in ['attack_up','defense_up']))
        self.assertIn(defs['dispel']['skill_id'],book['actors']['027']['supported_initial_ids'])
        self.assertEqual(book['actors']['029']['supported_initial_ids'],[])
        trial,inventory=data.training()
        self.assertEqual(json.loads(data.TRIAL.read_text()),trial)
        self.assertEqual(json.loads(data.INVENTORY.read_text()),inventory)
        self.assertEqual(set(trial['training_skill_grants']['002']),{s['skill_id'] for s in defs.values()})
        self.assertNotIn('training_skill_grants',json.loads(Path('content/battles/first_battle.json').read_text()))

    def test_source_effect_frames_and_audio_are_intact(self):
        data.check(data.definitions(),data.OUT,data.FRAME_MEMBERS)
        frames=data.FRAME_MEMBERS['MAGIC\\MIN12_01.SHP']
        self.assertEqual(len(frames),12)
        self.assertEqual(frames[3],'MAGIC\\MIN12_11.SHP')
