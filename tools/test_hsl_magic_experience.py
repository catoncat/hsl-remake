import copy
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hsltools.probes.experience as xp
import hsltools.probes.magic_damage as magic
from hsltools.data.equipment import build as equipment
from hsltools.data.skill_book import build as book


class NativeMagicExperienceTests(unittest.TestCase):
    def test_saved_original_results_and_boundaries(self):
        for module in [xp, magic]:
            module.check(json.loads(module.PACKET.read_text()))
        packet = json.loads(xp.PACKET.read_text())
        self.assertTrue(any(draw['bound'] == 0 for row in packet['cases'] for draw in row['draws']))
        for row in packet['status_contributions']:
            self.assertEqual(row['native'], xp.status_expected(row['input'], row['draws']))

    def test_zero_contribution_is_not_minimum_one_and_chain_is_capped(self):
        case = xp.fixtures()[0]
        self.assertEqual(xp.expected(case, []), 0)
        case = dict(case, contribution=20, target_hp=0)
        draws = [{'bound': 10, 'value': 0}, {'bound': 9, 'value': 0}]
        self.assertEqual(xp.expected(dict(case, kill_word=0), draws), 30)
        self.assertEqual(xp.expected(dict(case, kill_word=8), draws), 150)
        self.assertEqual(xp.expected(dict(case, kill_word=0x10009), draws), 150)
        with self.assertRaisesRegex(ValueError, 'random-call'):
            xp.expected(case, [{'bound': 11, 'value': 0}])

    def test_changed_native_receipts_cannot_pass(self):
        data = json.loads(xp.PACKET.read_text())
        for section, key, value in [('cases', 'native', 999), ('cases', 'normal_return', False),
                                    ('suffixes', 'normal_return', True), ('suffixes', 'stop_address', '0x0')]:
            changed = copy.deepcopy(data)
            changed[section][0][key] = value
            with self.assertRaises(ValueError): xp.check(changed)
        changed = copy.deepcopy(data)
        changed['anchors'][0]['bytes'] = '00' + changed['anchors'][0]['bytes'][2:]
        with self.assertRaisesRegex(ValueError, 'bytes differ'): xp.check(changed)
        changed = copy.deepcopy(data)
        changed['status_contributions'][0]['native']['contribution'] += 1
        with self.assertRaisesRegex(ValueError, 'contribution'): xp.check(changed)
        data = json.loads(magic.PACKET.read_text())
        changed = copy.deepcopy(data)
        changed['applications'][0]['normal_return'] = True
        with self.assertRaisesRegex(ValueError, 'boundary'): magic.check(changed)

    def test_generated_catalogs_preserve_ownership_and_supported_passive(self):
        items = equipment()['items']
        self.assertTrue(items['228']['experience_double'])
        self.assertTrue(items['228']['supported'])
        self.assertFalse(items['225']['experience_double'])
        skills = book()
        self.assertEqual(skills['actors']['001']['supported_initial_ids'], ['special:magicOTHER:magicCode01'])
        self.assertTrue(skills['actors']['026']['supported_initial_ids'])
        for identifier in skills['actors']['026']['supported_initial_ids']:
            self.assertEqual(skills['skills'][identifier]['damage_policy'], 'native_magic_damage')


if __name__ == '__main__': unittest.main()
