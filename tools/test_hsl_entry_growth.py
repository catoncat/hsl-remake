import copy
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parent))
import hsltools.probes.auto_growth as probe
import hsltools.data.entry_growth as data

class EntryGrowthEvidenceTests(unittest.TestCase):
    def test_original_full_returns_and_sources(self):
        packet=json.loads(probe.PACKET.read_text());probe.check(packet)
        self.assertTrue(packet['cases'])
        self.assertTrue(packet['vm'])
        self.assertTrue(all(row['normal_return'] for row in packet['cases']+packet['vm']))
        self.assertEqual(data.build(),json.loads(data.OUT.read_text()))

    def test_corrupt_results_or_source_instructions_fail(self):
        packet=json.loads(probe.PACKET.read_text())
        for kind in ['bytes','result','return','draw','source','cursor']:
            broken=copy.deepcopy(packet)
            if kind=='bytes':broken['anchors'][0]['bytes']='00'+broken['anchors'][0]['bytes'][2:]
            elif kind=='result':broken['cases'][0]['native']['level']+=1
            elif kind=='return':broken['cases'][0]['normal_return']=False
            elif kind=='draw':next(r for r in broken['cases'] if r['draws'])['draws'][0]['bound']+=1
            elif kind=='source':broken['sources']['PLAYERS.TXT']='0'*64
            else:broken['vm'][0]['native']['cursor_words']=3
            with self.subTest(kind=kind),self.assertRaises(ValueError):probe.check(broken)

    def test_explicit_source_zero_and_missing_remain_distinct(self):
        # R6-L10: an undeclared pair reads 0,0 like the original parser preset (0x44ca5c／0x44ca8f);
        # parameters_declared keeps the explicit zero apart from the missing one.
        actors=data.build()['actors']
        self.assertEqual((actors['004']['parameters'],actors['004']['parameters_declared']),([0,0],True))
        self.assertEqual((actors['006']['parameters'],actors['006']['parameters_declared']),([0,0],False))
        self.assertEqual((actors['067']['parameters'],actors['067']['parameters_declared']),([0,0],False))
        self.assertEqual(actors['026']['parameters'],[22,2])

    def test_original_cap_fallback_is_not_balanced_manual_allocation(self):
        attrs=dict(str=probe.CAPS[80][0],dex=16,mind=8,con=12)
        after,level,_=probe.allocate(attrs,1,0,80,5)
        self.assertEqual(after,dict(zip(probe.ATTRIBUTES,probe.CAPS[80])))
        self.assertEqual(level,2)
