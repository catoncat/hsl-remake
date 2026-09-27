import copy,json,sys,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
import hsltools.probes.departure as probe

class DepartureEvidenceTests(unittest.TestCase):
    def test_native_phase_and_request_boundaries(self):
        packet=json.loads(probe.PACKET.read_text());probe.check(packet)
        self.assertTrue(packet['phases'])
        self.assertTrue(packet['requests'])
        self.assertTrue(packet['walk_requests'])
        self.assertTrue(packet['relookup'])
        self.assertTrue(all(r['normal_return'] for r in packet['walk_requests']))
        self.assertTrue(any(not r['normal_return'] for r in packet['phases']))
        self.assertTrue(any(r['normal_return'] and not r['native']['active'] for r in packet['phases']))
    def test_reject_modified_source_result_and_order(self):
        original=json.loads(probe.PACKET.read_text())
        for mutate in ['bytes','vitals','current','order','boundary','request']:
            packet=copy.deepcopy(original)
            cleanup=next(r for r in packet['phases'] if '0x44cb90' in r['calls'])
            if mutate=='bytes':packet['anchors'][0]['bytes']='00'+packet['anchors'][0]['bytes'][2:]
            elif mutate=='vitals':cleanup['native']['vitals_unchanged']=False
            elif mutate=='current':cleanup['native']['index']=99
            elif mutate=='order':cleanup['calls'].reverse()
            elif mutate=='boundary':cleanup['stop_address']='0x0'
            else:packet['requests'][0]['native_index']=2
            with self.assertRaises(ValueError,msg=mutate):probe.check(packet)
