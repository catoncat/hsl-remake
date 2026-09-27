import copy
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hsltools.probes.extra_attack as probe
from hsltools.data.equipment import build as equipment
from hsltools.data.skill_book import build as skills


class ExtraAttackEvidenceTests(unittest.TestCase):
    def test_native_boundaries_and_result_integrity(self):
        packet = json.loads(probe.PACKET.read_text())
        probe.check(packet)
        for change in ['return', 'stop', 'result']:
            broken = copy.deepcopy(packet)
            row = next(r for r in broken['cases'] if r['input']['kind'] == 'init')
            if change == 'return': row['normal_return'] = True
            elif change == 'stop': row['stop_address'] = '0x0'
            else: row['native']['remaining'] += 1
            with self.assertRaises(ValueError): probe.check(broken)

    def test_source_strikes_are_separate_from_extra_actions_and_unknown_geometry(self):
        source = probe.source()
        items = equipment()['items']
        book = skills()
        self.assertEqual([int(code) for code, item in items.items() if item['double_attack']], source['items'])
        self.assertEqual([code for code, actor in book['actors'].items() if actor['double_attack']], source['actors'])
        self.assertTrue(items['12']['supported'])
        self.assertTrue(items['55']['supported'])  # range5CellCircle is compiled from the source range table
        self.assertTrue(items['69']['supported'])
        self.assertEqual(items['69']['attack_range'], 'range5CellShoot')
        self.assertFalse(items['227']['double_attack'])
        self.assertTrue(items['227']['action_twice'])
        self.assertTrue(items['227']['supported'])
        self.assertTrue(all(not book['actors'][code]['double_attack'] for code in ['001','021','023','024','026']))


if __name__ == '__main__': unittest.main()
