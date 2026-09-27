import copy
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hsltools.probes.casting_equipment as native
from hsltools.data.equipment import build


class CastingEquipmentTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.packet = json.loads(native.PACKET.read_text())

    def test_original_execution_boundaries_and_integrity(self):
        native.check(self.packet)
        for category in ['return', 'draw', 'bytes']:
            bad = copy.deepcopy(self.packet)
            row = next(r for r in bad['transfers'] if r['native']['hp_loss'] > 0)
            if category == 'return': row['normal_return'] = True
            elif category == 'draw': row['draws'].pop()
            else: bad['anchors'][0]['bytes'] = '00' + bad['anchors'][0]['bytes'][2:]
            with self.assertRaises(ValueError): native.check(bad)

    def test_full_mp_and_one_hp_are_not_free_or_dead_branches(self):
        enabled = [r for r in self.packet['transfers'] if r['input']['enabled']]
        floor = [r for r in enabled if r['input']['hp'] == 1]
        self.assertTrue(floor)
        self.assertTrue(all(r['normal_return'] and len(r['draws']) == 2 and r['native']['hp_loss'] == 0 for r in floor))
        full = [r for r in enabled if r['input']['hp'] > 1 and r['input']['mp'] == r['input']['max_mp']]
        self.assertTrue(full)
        self.assertTrue(all(r['native']['hp_loss'] > 0 and r['native']['mp_gain'] == 0 for r in full))

    def test_source_equipment_maps_separate_flags_and_hit_bonus(self):
        items = build()['items']
        self.assertTrue(all(items[str(code)]['supported'] for code in [128,145,215,217,219,226]))
        self.assertTrue(items['145']['hp_transfer_mp'])
        self.assertEqual(items['145']['status_effect_flags'], 0)
        self.assertEqual(items['128']['status_effect_flags'], 0x800000)
        self.assertEqual(items['217']['status_effect_flags'], 0x800000)
        self.assertEqual(items['219']['status_effect_flags'], 0x1000000)
        self.assertEqual(items['215']['magic_hit_bonus'] + items['226']['magic_hit_bonus'], 20)
        self.assertFalse(items['194']['supported'])
        self.assertTrue(items['194']['unsupported_fields'])

    def test_refresh_keeps_existing_conditions_and_never_stacks_passes(self):
        for row in self.packet['gear']:
            first, second = (r['values'] for r in row['native'])
            self.assertEqual(first, second)
            self.assertEqual(first['status'], row['input']['status'])
            self.assertEqual((first['hp'], first['mp'], first['exp'], first['stamina']), (1,0,37,20))


if __name__ == '__main__': unittest.main()
