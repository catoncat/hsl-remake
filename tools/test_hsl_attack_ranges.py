import unittest
from hsltools.data.attack_ranges import ITEM_SOURCE, SOURCE, compile_ranges, weapon_ranges


class AttackRangeTests(unittest.TestCase):
    def test_two_cell_weapon_is_cross_not_diamond(self):
        patterns = compile_ranges(SOURCE.read_bytes().decode('cp950'))
        offsets = patterns['range2Cell']['offsets']
        self.assertIn([2, 0], offsets)
        self.assertIn([0, -2], offsets)
        self.assertNotIn([1, 1], offsets)
        self.assertNotIn([0, 0], offsets)
        self.assertEqual(len(offsets), 8)

    def test_truncated_or_signed_mask_fails(self):
        source = SOURCE.read_bytes().decode('cp950')
        for changed in [source.replace('size = 3', 'size = 5', 1), source.replace('data = 0,1,0', 'data = 0,-1,0', 1)]:
            with self.assertRaises(ValueError):
                compile_ranges(changed)

    def test_line_and_wide_skill_ranges_compile(self):
        patterns = compile_ranges(SOURCE.read_bytes().decode('cp950'))
        self.assertEqual(patterns['range3CellDir'], {'index': 21, 'size': 3, 'shape': 'line', 'values': [3, 2, 1]})
        self.assertEqual(patterns['range4CellDir'], {'index': 22, 'size': 4, 'shape': 'line', 'values': [4, 3, 2, 1]})
        self.assertEqual(len(patterns['range4CellCircle']['offsets']), 40)
        self.assertEqual(len(patterns['range6CellCircle']['offsets']), 84)
        self.assertEqual(len(patterns['range1CellFull']['offsets']), 8)
        broken = SOURCE.read_bytes().decode('cp950').replace('size = 3\ndata = 3\ndata = 2\ndata = 1', 'size = 3\ndata = 3\ndata = 2\ndata = 2', 1)
        with self.assertRaises(ValueError):
            compile_ranges(broken)

    def test_level52_boss_weapon_reuses_one_cell_range(self):
        weapons = weapon_ranges(ITEM_SOURCE.read_bytes().decode('cp950'))
        self.assertEqual(weapons['5'], 'range1Cell')

    def test_source_boss_ranges_join_to_masks(self):
        patterns = compile_ranges(SOURCE.read_bytes().decode('cp950'))
        weapons = weapon_ranges(ITEM_SOURCE.read_bytes().decode('cp950'))
        self.assertEqual(weapons['32'], 'range3CellCircle')
        self.assertEqual(weapons['53'], 'range3CellCircle')
        self.assertEqual(weapons['57'], 'range0Cell')
        self.assertEqual(len(patterns['range3CellCircle']['offsets']), 24)
        self.assertEqual(patterns['range0Cell']['offsets'], [])
