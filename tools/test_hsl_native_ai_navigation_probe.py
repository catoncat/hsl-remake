import copy
import json
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parent))
import hsltools.probes.ai_navigation as probe


class NavigationEvidenceTests(unittest.TestCase):
    def test_saved_original_results_and_boundaries(self):
        probe.check(json.loads(probe.PACKET.read_text()))

    def test_changed_value_or_fake_whole_return_rejected(self):
        packet=json.loads(probe.PACKET.read_text())
        for kind in ['value','return','stop','coverage','identity']:
            bad=copy.deepcopy(packet)
            if kind=='value':bad['cases'][0]['native']['value']^=1
            elif kind=='return':bad['cases'][-1]['normal_return']=True
            elif kind=='stop':bad['cases'][-1]['stop_address']='0x10000000'
            elif kind=='coverage':bad['cases'].pop()
            else:bad['exe_sha256']='unverified'
            with self.subTest(kind=kind), self.assertRaises(ValueError):probe.check(bad)


if __name__=='__main__':unittest.main()
