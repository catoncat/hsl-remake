import copy
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hsltools.probes.script_wait as probe


class ScriptWaitEvidenceTests(unittest.TestCase):
    def test_native_replay_and_distinct_wait_scopes(self):
        packet = json.loads(probe.PACKET.read_text())
        probe.check(packet)
        self.assertTrue(packet['vm'])
        self.assertGreater(sum(r['native']['returns'] for r in packet['vm']), 0)
        unrelated = [r for r in packet['vm'] if r['input']['opcode'] == 88
                     and r['input']['phase'] == 0 and r['input']['other_phase']]
        self.assertTrue(unrelated)
        self.assertTrue(all(r['native']['first_cursor_words'] == 3 for r in unrelated))

    def test_corruption_does_not_become_evidence(self):
        original = json.loads(probe.PACKET.read_text())
        for kind in ['instruction', 'result', 'return', 'boundary', 'source']:
            packet = copy.deepcopy(original)
            if kind == 'instruction': packet['anchors'][0]['bytes'] = '00' + packet['anchors'][0]['bytes'][2:]
            elif kind == 'result': packet['vm'][0]['native']['wait_values'][0] += 1
            elif kind == 'return': packet['vm'][0]['normal_return'] = False
            elif kind == 'boundary': packet['wait'][0]['stop_address'] = '0x450840'
            else: packet['source_action_sha256'] = '0' * 64
            with self.subTest(kind=kind), self.assertRaises(ValueError): probe.check(packet)
