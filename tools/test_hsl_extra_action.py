import copy
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parent))
import hsltools.probes.extra_action as native
import hsltools.data.equipment as equipment


class ExtraActionTests(unittest.TestCase):
    def test_original_gate_and_return_boundaries(self):
        packet=json.loads(native.PACKET.read_text())
        native.check(packet)
        self.assertTrue(packet['queries'])
        self.assertTrue(packet['prefixes'])

    def test_changed_result_stop_or_bytes_refused(self):
        original=json.loads(native.PACKET.read_text())
        for kind in ['result','stop','bytes','return']:
            packet=copy.deepcopy(original)
            if kind=='result': packet['prefixes'][0]['native']['again']=True
            elif kind=='stop': packet['prefixes'][0]['stop_address']='0x407510'
            elif kind=='bytes': packet['anchors'][0]['bytes']='00'+packet['anchors'][0]['bytes'][2:]
            else: packet['prefixes'][0]['normal_return']=True
            with self.subTest(kind=kind),self.assertRaises(ValueError): native.check(packet)

    def test_source_wings_are_independent_of_extra_strikes(self):
        items=equipment.build()['items']
        self.assertTrue(items['227']['supported'])
        self.assertEqual(items['227']['name'],'白光之翼')
        self.assertTrue(items['227']['action_twice'])
        self.assertFalse(items['227']['double_attack'])
        self.assertTrue(items['12']['double_attack'])
        self.assertFalse(items['12']['action_twice'])
        self.assertTrue(items['55']['supported'])  # range5CellCircle is compiled from the source range table
        self.assertTrue(items['55']['action_twice'] and items['55']['double_attack'])


if __name__=='__main__':unittest.main()
