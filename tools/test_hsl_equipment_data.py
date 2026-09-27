import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from hsltools.data.equipment import OUTPUT, build, job_mask
from hsltools.sources.tables import TABLES, blocks


class EquipmentDataTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.packet = build()
        cls.items = cls.packet['items']

    def test_generated_data_matches_source(self):
        self.assertEqual(json.loads(OUTPUT.read_text()), self.packet)
        self.assertEqual(len(self.items), 239)

    def test_initial_equipment_matches_saved_native_output_delta(self):
        native = json.loads(Path('docs/evidence_packets/static_reverse/original_growth_refresh.json').read_text())
        effects = [self.items[str(code)]['effects'] for code in native['source_profile']['equipment_codes'] if code]
        for field, expected in native['initial_equipment_delta'].items():
            if field == 'resist_by_type':
                self.assertEqual({k: sum(e[field][k] for e in effects) for k in expected}, expected)
            else:
                self.assertEqual(sum(e[field] for e in effects), expected, field)

    def test_type_dependent_effects_and_actual_magic_power_field(self):
        self.assertEqual(self.items['3']['effects']['attack'], 28)
        self.assertEqual(self.items['3']['effects']['magic_attack'], 5)
        self.assertEqual(self.items['153']['effects']['defense'], 6)
        self.assertEqual(self.items['125']['effects']['defense'], 18)
        self.assertEqual(self.items['181']['effects']['speed'], 2)
        self.assertTrue(all(self.items[c]['supported'] for c in ('1', '2', '3', '32', '53', '57', '153', '125', '181')))
        self.assertEqual([self.items[c]['attack_range'] for c in ('32', '53', '57')], ['range3CellCircle', 'range3CellCircle', 'range0Cell'])

    def test_job_masks_preserve_all_and_exclusions(self):
        constants = {'jobSwordMan': 80, 'jobAll': 1000, 'jobAllNoPlayer8': 1001}
        self.assertEqual(job_mask('jobSwordMan', constants), 1)
        self.assertEqual(job_mask('0', constants), 0)
        self.assertEqual(job_mask('jobAll', constants), 0xffffffff)
        self.assertEqual(job_mask('jobAllNoPlayer8', constants), 0xffffffff & ~(1 << 16) & ~(1 << 17))
        self.assertEqual(self.items['2']['job_mask'], 7)

    def test_take_off_and_unsupported_effects_are_not_silently_ignored(self):
        rows = blocks((TABLES / 'ITEM.TXT').read_bytes(), 'item')
        blocked = [row for row in rows if int(row.get('take_off', 0))]
        self.assertTrue(blocked)
        for row in rows:
            item = self.items[row['code']]
            self.assertEqual(item['unequip_blocked'], bool(int(row.get('take_off', 0))))
            self.assertEqual(item['mp_use_half'], bool(int(row.get('mp_use_half', 0))))
            for flag in ('hp_auto_restore', 'mp_auto_restore'):
                self.assertEqual(item[flag], bool(int(row.get(flag, 0))))
            if row['code'] in ('218', '223', '224'):
                self.assertTrue(item['supported'])  # Now independently proven cost/recovery lifecycle.
            self.assertEqual(item['effects']['move_point'], int(row.get('add_move', 0)))
            if row['code'] in ('138', '193', '231', '236'):
                self.assertTrue(item['supported'], row['code'])
            if row['code'] == '194':
                self.assertFalse(item['supported'], row['code'])
                self.assertTrue(item['unsupported_fields'], row['code'])
            if row['code'] == '236':
                self.assertTrue(item['move_magic_use'] and item['add_attack_range'])
        # Actual source spelling differs from TYPE.H; do not guess case-insensitive parsing.
        mixed_case = [row for row in rows if 'magic4Type' in row.get('add_resist', '')]
        self.assertTrue(mixed_case)
        self.assertTrue(all('add_resist' in self.items[row['code']]['unsupported_fields'] for row in mixed_case))


if __name__ == '__main__':
    unittest.main()
