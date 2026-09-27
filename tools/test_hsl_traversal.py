import copy
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hsltools.data.skill_book as book
import hsltools.probes.traversal as native
import hsltools.data.terrain_heights as heights


class TraversalTests(unittest.TestCase):
    def test_saved_normal_returns_and_landing_prefixes(self):
        packet = json.loads(native.PACKET.read_text())
        native.check(packet)
        self.assertTrue(all(packet[key] for key in ['helper', 'flood', 'landing']))

    def test_ground_start_on_cliff_crosses_only_near_cliff_heights(self):
        # 0x40f200 passes the start cell's own height to 0x40ed50: from 0xff a ground mode
        # enters only 0xff／253／254 neighbours (never steps down); flight ignores height.
        packet = json.loads(native.PACKET.read_text())
        rows = [row for row in packet['flood'] if [3, 3, 0xff000000] in row['input']['cells']]
        self.assertTrue(rows)
        for row in rows:
            flags = native.flags_for(row['input'])
            budget = row['input']['budget']
            reached = [(x - budget + 3, y - budget + 3) for y, line in enumerate(row['native']) for x, value in enumerate(line) if value > 0 and (x, y) != (budget, budget)]
            if row['input']['mode'] == 6:
                self.assertEqual(len(reached), 36)
            else:
                self.assertTrue(all(flags[cell] >> 24 >= 253 for cell in reached), row['input'])

    def test_source_traits_are_retained_without_granting_a_default_flyer(self):
        actors = book.build()['actors']
        for name in ['001', '021', '023', '024', '025', '026']:
            self.assertEqual(actors[name]['traversal'], {'flying': False, 'no_block': False, 'size_type': 0})
        self.assertTrue(actors['006']['traversal']['flying'])
        self.assertTrue(actors['101']['traversal']['no_block'])
        self.assertEqual(actors['017']['traversal']['size_type'], 1)

    def test_changed_native_output_boundary_or_bytes_is_not_accepted(self):
        packet = json.loads(native.PACKET.read_text())
        for kind in ['result', 'stop', 'return', 'bytes']:
            changed = copy.deepcopy(packet)
            if kind == 'result': changed['flood'][0]['native'][2][2] += 1
            elif kind == 'stop': changed['landing'][0]['native']['stop_address'] = '0x443d9d'
            elif kind == 'return': changed['landing'][0]['normal_return'] = True
            else: changed['anchors'][0]['bytes'] = '00' + changed['anchors'][0]['bytes'][2:]
            with self.subTest(kind=kind), self.assertRaises(ValueError): native.check(changed)

    def test_retained_heights_reconstruct_both_original_wrd_files(self):
        for level in heights.LEVELS:
            packet = json.loads(heights.paths_for_level(level)['terrain'].read_text())
            heights.validate(packet)
            changed = copy.deepcopy(packet)
            cell = changed['grid'][0][0]
            cell['h'] = (cell['h'] + 1) % 255
            cell['b'] = 0
            with self.subTest(level=level), self.assertRaisesRegex(ValueError, 'original WRD hash'): heights.validate(changed)


if __name__ == '__main__': unittest.main()
