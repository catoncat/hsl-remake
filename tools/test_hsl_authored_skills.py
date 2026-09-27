"""The authored skill table contract (hsltools.data.authored_skills): rows in SPECIAL.TXT／MAGIC.TXT
vocabulary become skill book entries and presentation rows; anything the runtime cannot resolve
from data alone — a new effect family, an unimplemented opcode, art the import does not carry —
fails generation instead of silently defaulting."""
import copy
import json
import tempfile
import unittest
from pathlib import Path

from hsltools.data import authored_skills
from hsltools.data.authored_skills import OUTPUT, AuthoredEffectScriptsTask
from hsltools.data.skill_book import build as build_book
from hsltools.registry import Context

SPECIAL = {'channel': 'special', 'code': 'authoredTestSlash', 'name_text': '試斬', 'type': 'magicFIRE', 'range': 'range1Cell',
           'effect_range': 'range0Cell', 'expend': '1', 'damage': '10,20', 'hit_ratio': '90', 'use_ratio': '90',
           'function': 'magicFun_Attack', 'attackpow_ratio': '100', 'attack_code': 'specCode31', 'defense_code': 'specCode32'}
MAGIC = {'channel': 'magic', 'code': 'authoredTestBolt', 'name_text': '試炎', 'type': 'magicFIRE', 'range': 'range4CellThrust',
         'effect_range': 'range1Cell', 'expend': '9', 'damage': '20,30', 'hit_ratio': '90', 'function': 'magicFun_Attack',
         'use_ratio': '90', 'effect_proc': 'eff_proc_Local', 'effect_code': 'authoredTestScript'}
SCRIPT = ['effPlaySound,WAV\\FIRE0006.WAV', 'effInsertObject,obj_Effect_FireBomb2,0,0,effWait,50']


class AuthoredSkillTests(unittest.TestCase):
    def setUp(self):
        self._table = authored_skills.table

    def tearDown(self):
        authored_skills.table = self._table

    def use(self, skills, scripts=None):
        """The tracked table plus `skills`／`scripts` (102's declarations name the tracked rows)."""
        real = self._table()
        rows = real['skills'] + [{key: str(value) for key, value in row.items()} for row in skills]
        merged = dict(real['scripts'], **(scripts or {}))
        authored_skills.table = lambda: {'scripts': copy.deepcopy(merged), 'skills': copy.deepcopy(rows)}

    def test_tracked_outputs_are_current(self):
        rendered = json.loads(AuthoredEffectScriptsTask().render(Context())[OUTPUT.as_posix()])
        self.assertEqual(json.loads(Path(OUTPUT).read_text()), rendered)
        book = json.loads(Path('content/generated/hsl/skills/initial_book.json').read_text())
        for skill_id, row in rendered['rows'].items():
            self.assertEqual(book['skills'][skill_id]['evidence_tier'], 'authored')
            self.assertEqual(row['presentation'], 'script')

    def test_rows_become_book_entries_and_presentation_rows(self):
        self.use([SPECIAL, MAGIC], {'authoredTestScript': SCRIPT})
        book = build_book()
        special = book['skills']['special:magicFIRE:authoredTestSlash']
        magic = book['skills']['magic:magicFIRE:authoredTestBolt']
        self.assertEqual((special['damage_policy'], special['element'], special['declaration_field'], special['fields']['name']),
                         ('native_special_damage', '3', 'special_fire', '試斬'))
        self.assertEqual((magic['damage_policy'], magic['magic_key'], magic['declaration_field']), ('native_magic_damage', 'fire', 'magic_fire'))
        rows = authored_skills.effect_rows()
        self.assertEqual(rows['magic:magicFIRE:authoredTestBolt']['actions'], {'authoredTestScript': SCRIPT})
        self.assertEqual(rows['magic:magicFIRE:authoredTestBolt']['objects'], ['obj_Effect_FireBomb2'])
        self.assertEqual(rows['special:magicFIRE:authoredTestSlash']['opcodes'][0], 'aniDelay')
        # The chapter-1 inventory keeps only original rows.
        from hsltools.data.special_effect_scripts import render_inventory
        self.assertFalse([key for key in render_inventory()['rows'] if 'authored' in key])

    def test_targeting_grows_the_ranges_authored_rows_name(self):
        self.use([MAGIC], {'authoredTestScript': SCRIPT})
        from hsltools.data.skill_targeting import build as build_targeting
        self.assertIn('range4CellThrust', build_targeting()['ranges'])

    def test_rows_outside_the_data_vocabulary_are_rejected(self):
        cases = [
            ([dict(SPECIAL, function='magicFun_Heal')], {}, 'no data-only effect policy'),
            ([dict(SPECIAL, name_text='風刃')], {}, 'mag-spc.h skill alias'),
            ([dict(SPECIAL, type='magicOTHER2')], {}, 'is not one of'),
            ([dict(SPECIAL, damage='30,20')], {}, 'low exceeds high'),
            ([dict(SPECIAL, attackpow_ratio='2000')], {}, 'attackpow_ratio'),
            ([dict(SPECIAL, range='range9Cell')], {}, 'range'),
        ]
        for skills, scripts, message in cases:
            with self.subTest(message=message):
                self.use(skills, scripts)
                with self.assertRaisesRegex(ValueError, message):
                    authored_skills.book_rows({'風刃': 1}, {'magicFIRE': 3, 'magicOTHER2': 6})

    def test_table_shape_is_checked(self):
        authored_skills.table = self._table
        original_root = authored_skills.ROOT
        cases = [
            ([dict(SPECIAL, code='magicCode40')], 'distinct authored'),
            ([SPECIAL, dict(SPECIAL, code='authoredOther')], 'distinct non-empty name'),
            ([{k: v for k, v in SPECIAL.items() if k != 'hit_ratio'}], 'missing'),
            ([dict(SPECIAL, effect_code='authoredX')], 'unknown'),
            ([dict(SPECIAL, channel='item')], 'is not special or magic'),
        ]
        with tempfile.TemporaryDirectory() as directory:
            authored_skills.ROOT = Path(directory)
            try:
                path = Path(directory) / authored_skills.AUTHORED_SKILLS
                path.parent.mkdir(parents=True)
                for skills, message in cases:
                    with self.subTest(message=message):
                        path.write_text(json.dumps({'schema': authored_skills.SCHEMA, 'scripts': {}, 'skills': skills}), encoding='utf-8')
                        with self.assertRaisesRegex(ValueError, message):
                            authored_skills.table()
                path.write_text(json.dumps({'schema': authored_skills.SCHEMA, 'scripts': {}, 'skills': [SPECIAL]}), encoding='utf-8')
                self.assertEqual(authored_skills.names(), {'special:magicFIRE:authoredTestSlash': '試斬'})
            finally:
                authored_skills.ROOT = original_root

    def test_scripts_outside_the_player_and_import_are_rejected(self):
        cases = [
            ({'authoredTestScript': ['effShakeScreen,4']}, 'does not implement'),
            ({'authoredTestScript': ['aniDelay,4']}, 'other script family'),
            ({'authoredTestScript': ['effInsertObject,obj_Effect_NotImported,0,0']}, 'does not carry'),
            ({'authoredTestScript': ['effPlaySound,WAV\\NOTHERE.WAV']}, 'does not carry'),
            ({}, 'neither an EFFECTS.TXT block'),
        ]
        for scripts, message in cases:
            with self.subTest(message=message):
                self.use([MAGIC], scripts)
                with self.assertRaisesRegex(ValueError, message):
                    authored_skills.effect_rows()

    def test_declaration_must_sit_in_the_field_of_its_element(self):
        self.use([SPECIAL])
        from hsltools.data import skill_book
        original = skill_book.character_rows
        skill_book.character_rows = lambda: [dict(code='102', special_wind='試斬')]
        try:
            with self.assertRaisesRegex(ValueError, 'not in the field of its element'):
                build_book()
            skill_book.character_rows = lambda: [dict(code='102', special_fire='試斬')]
            self.assertEqual(build_book()['actors']['102']['supported_initial_ids'], ['special:magicFIRE:authoredTestSlash'])
        finally:
            skill_book.character_rows = original


if __name__ == '__main__':
    unittest.main()
