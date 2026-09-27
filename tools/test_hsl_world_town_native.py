import copy
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hsltools.probes.world_town as probe


class WorldTownNativeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.packet=json.loads(probe.PACKET.read_text())

    def test_original_packet_and_distinct_boundaries(self):
        probe.validate(self.packet)
        self.assertEqual(len(self.packet['initial_towns']['empty_towns']),97)
        self.assertTrue(all(p['normal_return'] for p in self.packet['initial_towns']['calls']))
        self.assertFalse(self.packet['initial_map']['proof']['normal_return'])
        self.assertFalse(self.packet['object_sources']['native_execution'])

    def test_changed_money_semantics_and_noop_checks_fail_validation(self):
        for kind in ['money','reserved_check','te_exists','job_deny_resume']:
            packet=copy.deepcopy(self.packet)
            row=next(r for r in packet['vm_cases'] if r['input']['kind']==kind)
            row['native']['cursor']+=1
            with self.assertRaises(ValueError):probe.validate(packet)

    def test_changed_reveal_animation_or_audio_fails_validation(self):
        for kind in ['track','point','music','progress','play_time','speed']:
            packet=copy.deepcopy(self.packet)
            row=next(r for r in packet['visual_cases'] if r['input']['kind']==kind)
            row['native']['unexpected_derived_policy']=True
            with self.assertRaises(ValueError):probe.validate(packet)

    def test_item_query_and_optional_removal_are_not_the_same(self):
        rows=self.packet['item_cases']
        for location in ['store1','store2','actor']:
            query=next(r for r in rows if r['input']==dict(location=location,remove=0,event=123))
            consume=next(r for r in rows if r['input']==dict(location=location,remove=1,event=123))
            self.assertEqual(query['native']['cursor'],consume['native']['cursor'])
            self.assertNotEqual(query['native'],consume['native'])
            self.assertTrue(query['proof']['normal_return'] and consume['proof']['normal_return'])

    def test_secret_man_strict_boundary_and_cached_failure(self):
        for row in self.packet['secret_cases']:
            if row['input']['ratio']=='equal_draw':
                self.assertEqual(row['native']['cache'],-1)
                self.assertEqual(row['native']['children'],[8,12,13,14])

    def test_original_bytes_and_stop_addresses_are_not_replaceable(self):
        packet=copy.deepcopy(self.packet);packet['anchors'][0]['bytes']='00'+packet['anchors'][0]['bytes'][2:]
        with self.assertRaises(ValueError):probe.validate(packet)
        packet=copy.deepcopy(self.packet);packet['visual_cases'][0]['proofs'][0]['normal_return']=False
        with self.assertRaises(ValueError):probe.validate(packet)
