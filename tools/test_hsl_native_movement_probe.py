import copy
import json
from pathlib import Path
import sys
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parent))
import hsltools.probes.movement as probe


class MovementEvidenceTests(unittest.TestCase):
    def test_saved_native_returns(self):
        probe.check(json.loads(probe.PACKET.read_text()))

    def test_reject_changed_result_or_boundary(self):
        original = json.loads(probe.PACKET.read_text())
        for key, value in [('normal_return', False), ('entry', '0x40eb80'), ('instructions', 300000)]:
            changed = copy.deepcopy(original)
            changed['flood'][0][key] = value
            with self.assertRaises(ValueError): probe.check(changed)
        changed = copy.deepcopy(original)
        changed['flood'][0]['native'][1][1] += 1
        with self.assertRaises(ValueError): probe.check(changed)

    def test_cliffs_and_obstacles_have_different_onward_cost(self):
        source = dict(size=[9,9], origin=[4,4], budget=4, cells=[[5,4,0x4000]])
        obstacle = probe.expected(source)
        cliff = probe.expected(dict(source, cells=[[5,4,0xff000000]]))
        self.assertEqual(obstacle[4][5], 0)
        self.assertEqual(cliff[4][5], 0)
        self.assertLess(obstacle[3][6], cliff[3][6])


if __name__ == '__main__': unittest.main()
