"""hsltools.data: the data-table task family (PASS lines, legacy replacement) and the product tables with
no native probe behind them (authored skills, job formulas, original save, scope inventory, secret-man goods,
skill coverage, win/fail coverage); one segment per former file."""
from __future__ import annotations

# ---- from test_hsl_data_tasks.py ----
# hsltools.data / hsltools.checks: the migrated generators and checkers behind the registry.
#
# Every task replaces at most one ledger command and names its hsltools module in `scripts`. That
# every GeneratedFilesTask renders its tracked outputs byte for byte, inside its declared outputs,
# is GeneratedFilesTask.check, run for every task by the gate's checks stage; CLI parity
# (`hsl check <task>` prints what check() returns) is test_hsl_registry.ParityTests.
import sys
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))

from hsltools import registry  # noqa: E402
from hsltools.paths import ROOT  # noqa: E402

# family -> module registered for it; every task of these families is exercised below
DATA_FAMILIES = ('actors', 'items', 'skills', 'trials', 'scenarios', 'world', 'static', 'checks')


def data_tasks() -> list[registry.Task]:
    return [task for task in registry.all_tasks() if task.family in DATA_FAMILIES]


class DataTaskRegistrationTests(unittest.TestCase):
    def test_every_data_task_replaces_exactly_one_legacy_command_naming_its_module(self):
        tasks = data_tasks()
        self.assertTrue(tasks)
        for task in tasks:
            # Migrated tasks replace exactly one historical command; tasks born after the
            # migration have no ledger command to replace (check_ledger owns the invariant).
            self.assertLessEqual(len(task.replaces), 1, task.name)
            if task.replaces:
                self.assertTrue(task.replaces[0].startswith('tools/hsl_'), task.name)
            self.assertTrue(any(script.startswith('tools/hsltools/') for script in task.scripts), task.name)
            for script in task.scripts:
                self.assertTrue((ROOT / script).is_file(), f'{task.name}: {script}')
            for path in task.inputs:
                self.assertTrue((ROOT / path).exists(), f'{task.name}: input {path} is not tracked')


# ---- from test_hsl_authored_skills.py ----
# The authored skill table contract (hsltools.data.authored_skills): rows in SPECIAL.TXT／MAGIC.TXT
# vocabulary become skill book entries and presentation rows; anything the runtime cannot resolve
# from data alone — a new effect family, an unimplemented opcode, art the import does not carry —
# fails generation instead of silently defaulting.
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
SHOUT = dict(SPECIAL, code='authoredTestShout', name_text='試吼', type='magicOTHER', range='range2Cell', function='magicFun_CancelActive',
             attack_code='specCode79', defense_code='specCode80')


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
        book = json.loads(Path('content/generated/hsl/skills/initial_book.json').read_text())
        for skill_id, row in rendered['rows'].items():
            self.assertEqual(book['skills'][skill_id]['evidence_tier'], 'authored')
            self.assertEqual(row['presentation'], 'script')

    def test_rows_become_book_entries_and_presentation_rows(self):
        self.use([SPECIAL, MAGIC, SHOUT], {'authoredTestScript': SCRIPT})
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
        # A CancelActive row resolves through the runtime's utility family, as 獅子吼 does.
        self.assertEqual((book['skills']['special:magicOTHER:authoredTestShout']['damage_policy'], rows['special:magicOTHER:authoredTestShout']['damage_policy']),
                         ('native_special_utility', 'native_special_utility'))
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


# ---- from test_hsl_job_formulas.py ----
# The job formula table contract: hsltools.model.jobs evaluates the authored rows, the job_formulas
# task projects them for the runtime, and malformed rows are rejected instead of silently defaulting.
import copy
import json
import unittest
from pathlib import Path

from hsltools.data.job_formulas import JobFormulasTask, OUT, job_symbols
from hsltools.model import jobs
from hsltools.registry import Context


class JobFormulasTests(unittest.TestCase):
    def test_generated_table_is_the_authored_rows_joined_to_their_symbols(self):
        rendered = json.loads(JobFormulasTask().render(Context())[OUT.as_posix()])
        self.assertEqual(rendered['authored'], jobs.FORMULAS)
        symbols = job_symbols()
        symbols.update({code: symbol for symbol, code in jobs.authored_job_symbols().items()})
        for key, row in rendered['jobs'].items():
            self.assertEqual(row['symbol'], symbols[int(key)])
            self.assertEqual({k: v for k, v in row.items() if k != 'symbol'}, {k: v for k, v in jobs.formulas()[int(key)].items() if k != 'symbol'})

    def test_term_semantics_pre_divisor_cap_soft_knee_and_bonus(self):
        variables = dict(str=19, dex=9, mind=50, con=7, level=30, hp_level=0)
        # [mul, var, div] is mul*var/div; [mul, var, div, pre] divides the variable first; a bare int is a constant.
        self.assertEqual(jobs.sum_terms([[116, 'str', 100, 2], [36, 'dex', 100], 16], variables), 116 * (19 // 2) // 100 + 36 * 9 // 100 + 16)
        self.assertNotEqual(jobs.sum_terms([[116, 'str', 100, 2]], variables), jobs.sum_terms([[116, 'str', 200]], variables))
        row = dict(jobs.formulas()[85])  # soft knee 44 then +45, as the priest branch folds high magic
        base = jobs.base_values(85, variables, 30, 0)
        magic = 30 * 50 // 100 + 2 * 30
        self.assertGreater(magic, row['magic_attack']['soft_knee'])
        self.assertEqual(base['magic_attack'], (magic - 44) // 2 + 44 + 45)
        capped = jobs.base_values(80, variables, 99, 99)  # cap 76 applies before the bonus
        self.assertEqual(capped['magic_attack'], 76)
        self.assertEqual(capped["max_hp"], 99 + 180 * 7 // 100 + 19 // 8)

    def test_malformed_rows_are_rejected(self):
        good = json.loads(json.dumps(jobs.formulas()[80]))
        jobs.validate_row(80, good)
        for mutate in [lambda r: r['max_hp'].append([1, 'luck', 1]),           # unknown variable
                       lambda r: r['attack'].append([1, 'str', 0]),            # zero divisor
                       lambda r: r['resist']['rows'].pop(),                    # not five elements
                       lambda r: r.__setitem__('allocation_quota', [1, 1, 1]),
                       lambda r: r['magic_attack'].pop('bonus'),
                       lambda r: r['caps'].pop('con')]:
            broken = json.loads(json.dumps(good))
            mutate(broken)
            with self.assertRaises(ValueError):
                jobs.validate_row(80, broken)

    def test_authored_job_names_itself_without_type_h(self):
        # 101 has no TYPE.H `#define`; its row declares jobDragonLord and the character tables resolve it.
        self.assertNotIn(101, job_symbols())
        self.assertEqual(jobs.authored_job_symbols(), {'jobDragonLord': 101})
        from hsltools.native.sources import sources
        _, _, defines = sources()
        self.assertEqual(defines['jobDragonLord'], 101)
        self.assertEqual(defines['jobDarkAngel'], 100)
        profile = jobs.source_profile({'code': '102', 'job': 'jobDragonLord', 'mode': 'pmPlayer', 'evidence_tier': 'authored'}, defines)
        self.assertEqual(profile['job_code'], 101)
        self.assertNotIn('evidence', profile)

    def test_authored_job_symbol_may_not_shadow_type_h(self):
        table = copy.deepcopy(jobs.formulas())
        for job, symbol in [(101, 'jobDarkAngel'), (100, 'jobDarkAngelTwo'), (101, 'DragonLord')]:
            broken = copy.deepcopy(table)
            broken[job]['symbol'] = symbol
            jobs.authored_job_symbols.cache_clear()
            original = jobs.formulas
            jobs.formulas = lambda: broken
            try:
                with self.assertRaises(ValueError):
                    jobs.authored_job_symbols()
            finally:
                jobs.formulas = original
                jobs.authored_job_symbols.cache_clear()
        unnamed = copy.deepcopy(table)
        unnamed[101].pop('symbol')
        original = jobs.formulas
        jobs.formulas = lambda: unnamed
        try:
            with self.assertRaises(ValueError):
                jobs.authored_job_symbols()
        finally:
            jobs.formulas = original
            jobs.authored_job_symbols.cache_clear()

    def test_unknown_job_has_no_profile(self):
        with self.assertRaises(ValueError):
            # jobAll 1000 is a TYPE.H selector, not a class: no row in the formula table.
            jobs.source_profile({'code': '150', 'job': 'jobAll', 'mode': 'pmEnemy'}, {'jobAll': 1000, 'pmEnemy': 0x20000})


# ---- from test_hsl_original_save.py ----
# Offline unit tests for hsltools.data.original_save: the level-entry 回憶錄 (a save that loads
# into a level that is not a big-map point) generates, reads back through the codec and carries
# the actSetNextPlayLevelEvent header words; big-map presets keep level_files 49.
import sys
import unittest
from pathlib import Path

ROOT_original_save = Path(__file__).resolve().parents[1]
if str(ROOT_original_save / "tools") not in sys.path:
    sys.path.insert(0, str(ROOT_original_save / "tools"))

from hsltools.data import original_save as save_module  # noqa: E402
from hsltools.data.original_save import BIG_MAP_LEVEL, PRESETS, OriginalSave, apply_spec, load_sample  # noqa: E402
from hsltools.data.original_save_members import RECORD_COUNT, RECORD_SIZE, REC, i32, learned_skill_bit  # noqa: E402


class LevelEntrySaveTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.base = load_sample()
        cls.save, cls.receipt = apply_spec(cls.base, PRESETS["level53_pre_battle"])
        cls.raw = cls.save.serialize()

    def test_round_trip_through_codec(self) -> None:
        again = OriginalSave.parse(self.raw)
        self.assertEqual(again.serialize(), self.raw)
        self.assertEqual(again.header, self.save.header)
        self.assertIsNone(again.battle_tail)

    def test_header_holds_the_winfail052_next_level_words(self) -> None:
        header = OriginalSave.parse(self.raw).header
        self.assertEqual((header["next_level"], header["level_files"], header["current_level"]), (58, 58, 58))
        self.assertNotEqual(header["level_files"], BIG_MAP_LEVEL)
        self.assertEqual(header["walk_from_point"], -1)
        self.assertEqual(header["walk_to_point"], 0)
        self.assertEqual(header["current_point"], 1)   # list-row point name (歐姆村)
        self.assertEqual(header["leonard_level"], 1)
        self.assertEqual(self.receipt["entry_level"], 58)
        self.assertEqual(self.receipt["applied_flow"], ["winfail51:win", "winfail52:win"])
        self.assertEqual(self.receipt["skipped_tokens"],
                         ["winfail51:actSetNextPlayLevelEvent", "winfail51:actSetNextPlayLevelEvent", "winfail52:actSetNextPlayLevelEvent"])

    def test_only_leonard_is_registered_and_tina_record_is_never_initialised(self) -> None:
        again = OriginalSave.parse(self.raw)
        self.assertEqual(again.slot_code(0), 800)
        self.assertEqual([slot for slot in range(21) if again.slot_code(slot)], [0])
        self.assertEqual(i32(again.record(0), REC["code"]), 1)
        # 0x407ec0 copies the PLAYERS 002 template into live index 2 only while +0x4c..+0x58 are zero
        tina = again.record(1)
        self.assertEqual(bytes(tina), bytes(RECORD_SIZE))
        for index in range(RECORD_COUNT):
            if index != 1:
                self.assertEqual(bytes(again.players[index * RECORD_SIZE:(index + 1) * RECORD_SIZE]), bytes(RECORD_SIZE), index)

    def test_big_map_presets_keep_the_big_map_level_files(self) -> None:
        for name, spec in PRESETS.items():
            if "entry_level" in spec:
                continue
            header = apply_spec(self.base, spec)[0].header
            self.assertEqual(header["level_files"], BIG_MAP_LEVEL, name)
            self.assertEqual(header["next_level"], spec["point"], name)

    def test_entry_level_and_point_are_exclusive(self) -> None:
        spec = dict(PRESETS["level53_pre_battle"], point=1)
        with self.assertRaises(ValueError):
            apply_spec(self.base, spec)

    def test_level05_preset_stands_at_milando_with_the_carried_party(self) -> None:
        save, receipt = apply_spec(self.base, PRESETS["level05_pre_battle"])
        again = OriginalSave.parse(save.serialize())
        self.assertEqual((again.header["next_level"], again.header["level_files"]), (4, BIG_MAP_LEVEL))
        self.assertEqual(receipt["point"]["id"], 4)
        self.assertEqual([slot for slot in range(21) if again.slot_code(slot)], [0, 1, 2, 3])
        self.assertEqual([i32(again.record(slot), REC["level"]) for slot in range(4)], [7, 4, 6, 7])
        self.assertEqual([member["max_hp"] for member in receipt["party"]], [39, 38, 42, 50])
        self.assertEqual(again.header["leonard_level"], 7)

    def test_level06_preset_stands_in_sheeda_with_the_tavern_soldier_and_learned_skills(self) -> None:
        save, receipt = apply_spec(self.base, PRESETS["level06_pre_battle"])
        again = OriginalSave.parse(save.serialize())
        self.assertEqual((again.header["next_level"], again.header["level_files"]), (6, BIG_MAP_LEVEL))
        self.assertEqual(receipt["towns"]["6"], {"tree": {"0": [16, 17, 18, 20], "20": [21, 22, 23]}, "exec_event": 19})
        self.assertEqual([i32(again.record(slot), REC["level"]) for slot in range(4)], [8, 5, 7, 8])
        self.assertEqual(i32(again.record(1), REC["magic_words"] + 4) & 0x1, 0x1)  # 水剎: water word, bit 0
        self.assertEqual(i32(again.record(3), REC["special_words"] + 4 * 5) & 0x400, 0x400)  # 逆刃: other word, bit 10

    def test_learned_skill_bit_rejects_unknown_ids(self) -> None:
        with self.assertRaises(ValueError):
            learned_skill_bit("magic:magicLIGHT:magicCode01")

    def test_preset_summary_names_the_entry_level(self) -> None:
        task = save_module.PresetTask("level53_pre_battle")
        rendered = task.render(save_module.Context())
        summary = task.summary(rendered, "check")
        self.assertIn("entry_level=58", summary)
        self.assertIn("slots=0 ", summary)


# ---- from test_hsl_scope_inventory.py ----

import json
import tempfile
import unittest
from pathlib import Path

import hsltools.data.scope_inventory as inv
from hsltools import original_content


class ScopeInventoryTests(unittest.TestCase):
    def test_classify_level_ranges(self):
        self.assertEqual(inv.classify_level(1), "main")
        self.assertEqual(inv.classify_level(99), "main")
        self.assertEqual(inv.classify_level(501), "battle_stub_500")
        self.assertEqual(inv.classify_level(901), "special_900")
        self.assertEqual(inv.classify_level(250), "other")

    def test_section_and_message_counting_skips_comments(self):
        text = "#include X.H\n[magic]\ncode = 1\n;[magic]\n [magic] \n[special]\n"
        self.assertEqual(inv.count_sections(text, "magic"), 2)
        self.assertEqual(inv.count_sections_by_name(text), {"magic": 2, "special": 1})
        story = "actMessage,SID_PLAYER0,1,1\n;actMessage,SID_PLAYER0,1,2\nactMessageIfExist,SID_X,1,3\n"
        self.assertEqual(inv.count_messages(story), 1)

    def test_summarize_levels_separates_battles_and_story_only(self):
        levels = {
            1: {"level": 1, "range": "main", "story": True, "winfail": True, "level_bin": True, "story_messages": 3},
            2: {"level": 2, "range": "main", "story": True, "winfail": False, "level_bin": True, "story_messages": 2},
            3: {"level": 3, "range": "main", "story": False, "winfail": False, "level_bin": True, "story_messages": 0},
            501: {"level": 501, "range": "battle_stub_500", "story": True, "winfail": True, "level_bin": True, "story_messages": 0},
        }
        summary = inv.summarize_levels(levels)
        self.assertEqual(summary["main"]["levels"], 3)
        self.assertEqual(summary["main"]["battles"], 1)
        self.assertEqual(summary["main"]["story_only"], 1)
        self.assertEqual(summary["main"]["story_messages"], 5)
        self.assertEqual(summary["battle_stub_500"]["battles"], 1)

    def test_remake_coverage_reads_campaign_and_scenarios(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "content/battles").mkdir(parents=True)
            (root / "content/battles/a.json").write_text(json.dumps({"id": "a", "status": "mechanics-playable-provisional"}), encoding="utf-8")
            (root / "content/battles/b.json").write_text(json.dumps({"id": "b", "status": "opening-preview-provisional", "level_kind": "story"}), encoding="utf-8")
            (root / "content/battles/c.json").write_text(json.dumps({"id": "c", "status": "story-scene-provisional", "level_kind": "story"}), encoding="utf-8")
            campaign = root / "content/battles/campaign.json"
            campaign.write_text(
                json.dumps(
                    {
                        "battles": {
                            "51": {"scenario": "res://content/battles/a.json", "title": "A"},
                            "53": {"scenario": "res://content/battles/b.json", "title": "B", "kind": "story"},
                            "58": {"scenario": "res://content/battles/c.json", "title": "C", "kind": "story"},
                        }
                    }
                ),
                encoding="utf-8",
            )
            coverage = inv.remake_coverage(campaign, root=root)
        self.assertEqual(coverage["registered_levels"], [51, 53, 58])
        self.assertEqual(coverage["counts"], {"registered": 3, "battle_scenarios": 1, "story_only_scenes": 1, "opening_previews": 1})
        self.assertEqual(coverage["entries"][1]["scenario_id"], "b")

    @unittest.skipUnless(original_content.present(), 'original-derived content absent (hsltools.original_content)')
    def test_tracked_inventory_is_consistent_offline(self):
        self.assertTrue(inv.DEFAULT_OUTPUT.exists())
        self.assertEqual(inv.check(inv.DEFAULT_OUTPUT, None, inv.DEFAULT_CAMPAIGN), 0)


# ---- from test_hsl_secret_man_goods.py ----

import json
import unittest

import hsltools.data.secret_man_goods as goods


class SecretManGoodsTests(unittest.TestCase):
    def test_tracked_table_passes_offline_cross_checks(self):
        data = json.loads(goods.OUTPUT.read_text(encoding="utf-8"))
        self.assertEqual(goods.offline_issues(data), [])
        self.assertEqual([row["price"] for row in data["rows"]], [5000, 7500, 10000, 15000, 20000, 30000, 40000, 60000, 99999])
        self.assertEqual([row["event"] for row in data["rows"]], [123, 113, 114, 115, 116, 117, 118, 119, 120])
        self.assertEqual(data["rows"][0]["items"][:2], [8, 145])
        self.assertEqual(data["rows"][8]["items"][-1], 301)
        self.assertTrue(all(len(row["items"]) == goods.SLOTS and all(row["items"]) for row in data["rows"]))

    def test_corrupted_rows_are_reported(self):
        data = json.loads(goods.OUTPUT.read_text(encoding="utf-8"))
        data["rows"][1]["price"] = 5000
        data["rows"][2]["items"][0] = 99999
        issues = goods.offline_issues(data)
        self.assertTrue(any("does not increase" in issue for issue in issues), issues)
        self.assertTrue(any("does not quote" in issue for issue in issues), issues)
        self.assertTrue(any("not all in ITEM.TXT" in issue for issue in issues), issues)

    def test_check_uses_offline_mode_without_the_exe(self):
        self.assertEqual(goods.main(["--check", "--exe", "/nonexistent/hsl01.exe"]), 0)


# ---- from test_hsl_skill_coverage.py ----

import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from hsltools.data.skill_coverage import OUT as OUT_skill_coverage, build


class SkillCoverageTests(unittest.TestCase):
    def test_generated_coverage_matches_source_and_reports_baseline(self):
        data = build()
        self.assertEqual(json.loads(OUT_skill_coverage.read_text()), data)
        summary = data["summary"]
        self.assertEqual(summary["total"], 99)
        self.assertEqual(summary["learned_total"], 79)
        # Wave 9 lane A2 closed the source table: every MAGIC/SPECIAL row resolves and every
        # learned row is castable. Four unowned rows (高級金之手／百裂突刺2／獅子吼2／吸血劍2) are data-only.
        self.assertEqual(summary["supported"], 99)
        self.assertEqual(summary["learned_supported"], 79)
        self.assertEqual(summary["by_resolution"], {"ok": 99})
        unowned = {row["display_name"] for row in data["skills"] if not row["initial_owners"] and not row["learners"]}
        self.assertEqual(unowned, {"高級金之手", "百裂突刺", "獅子吼", "吸血劍"})
        self.assertEqual(summary["by_resolution"]["ok"], summary["supported"])
        self.assertEqual(sum(summary["by_resolution"].values()), summary["total"])
        self.assertEqual(summary["learned_by_resolution"]["ok"], summary["learned_supported"])
        self.assertEqual(sum(summary["learned_by_resolution"].values()), summary["learned_total"])
        self.assertEqual(set(summary["by_resolution"]) - {"ok", "unknown_skill"}, set())
        barrier = next(row for row in data["skills"] if row["display_name"] == "魔障壁")
        self.assertEqual(barrier["current_descriptor"]["damage_policy"], "native_magic_stat")
        self.assertEqual(barrier["current_descriptor"]["magic_key"], "resist_up")
        self.assertEqual([(item["job"], item["level"]) for item in barrier["learners"]], [("87", 48)])

    def test_job_up_tiers_learn_from_current_job_tables(self):
        data = build()
        tears = next(row for row in data["skills"] if row["display_name"] == "女神之淚")
        self.assertEqual([(item["job"], item["level"]) for item in tears["learners"]], [("86", 32), ("87", 32), ("82", 45)])
        moon = next(row for row in data["skills"] if row["display_name"] == "孤月斬")
        self.assertEqual({item["job"] for item in moon["learners"]}, {"80", "81", "82"})
        wrath = next(row for row in data["skills"] if row["display_name"] == "神怒")
        self.assertEqual(wrath["learners"], [{"job": "97", "level": None, "tier": 2, "attributes": {"str": 80, "dex": 40, "mind": 28, "con": 45}, "kind": "special"}])

    def test_early_learning_order_is_source_backed(self):
        data = build()
        self.assertIn("magic:magicWATER:magicCode06", data["learned_order"][:20])
        water = next(row for row in data["skills"] if row["id"] == "magic:magicWATER:magicCode06")
        self.assertEqual(water["learners"][0], {"job": "85", "level": 1, "kind": "magic"})
        self.assertEqual(water["current_resolution"], "ok")


# ---- from test_hsl_winfail_coverage.py ----

import json
import tempfile
import unittest
from pathlib import Path

import hsltools.data.winfail_coverage as coverage


FAKE_RULES = '''extends RefCounted
const RULES_SCHEMA := "hsl_winfail_script_rules.v1"
const SUPPORTED_CONDITIONS := [
\t"actCheckPlayer",  # dead-unit check
\t"actTRUE",
]
const KNOWN_UNSUPPORTED_CONDITIONS := [
\t"actFALSE",
]
const APPLIED_ACTIONS := [
\t"actMessage",
\t"actInsertObject",
]
const WORLD_FLAG_ACTIONS := [
\t"actAddTE",
]
const PRESENTATION_ACTIONS := [
\t"actDelay",
]
'''

FAKE_ACTION_H = '''#define actDelay                \t1   // [delay counter]
#define actMessage\t\t\t\t\t10\t// [player code][serial][message code]
#define actInsertObject \t\t\t18\t// [code][x][y]
#define actCheckPlayer          \t38  // [num][id1][id2][...]
#define actTRUE\t\t\t\t\t\t67
#define actAddTE \t\t\t\t\t80\t// [town id][parent][num][child1][...]
'''


def fake_level(level, tokens):
    return {
        "level": level,
        "member": f"@:\\\\data\\\\winfail{level:03d}.txt",
        "byte_length": 10,
        "sha256": "0" * 64,
        "section_counts": {"win": 1},
        "tokens": tokens,
    }


class WinfailCoverageTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.rules = Path(self.tmp.name) / "WinfailScenarioRules.gd"
        self.rules.write_text(FAKE_RULES, encoding="utf-8")
        self.sets = coverage.support_sets(self.rules)

    def tearDown(self):
        self.tmp.cleanup()

    def test_support_sets_come_from_gd_constants(self):
        self.assertEqual(self.sets["SUPPORTED_CONDITIONS"], ["actCheckPlayer", "actTRUE"])
        self.assertEqual(self.sets["APPLIED_ACTIONS"], ["actMessage", "actInsertObject"])
        self.assertEqual(self.sets["PRESENTATION_ACTIONS"], ["actDelay"])
        self.assertEqual(coverage.applied_tokens(self.sets), {"actCheckPlayer", "actTRUE", "actMessage", "actInsertObject"})
        self.assertEqual(coverage.recorded_tokens(self.sets), {"actAddTE", "actDelay"})

    def test_missing_constant_or_wrong_schema_fails(self):
        broken = Path(self.tmp.name) / "broken.gd"
        broken.write_text(FAKE_RULES.replace("const PRESENTATION_ACTIONS", "const OTHER"), encoding="utf-8")
        with self.assertRaises(ValueError):
            coverage.support_sets(broken)
        broken.write_text(FAKE_RULES.replace("hsl_winfail_script_rules.v1", "v2"), encoding="utf-8")
        with self.assertRaises(ValueError):
            coverage.support_sets(broken)

    def test_level_tokens_count_every_chain_command(self):
        metadata = {
            "section_blocks": [
                {"name": "win", "actions": [{"chain": [{"name": "actCheckPlayer", "args": ["1", "SID_ENEMY025"]}]}, {"chain": [{"name": "actMessage", "args": []}]}]},
                {"name": "event", "actions": [{"chain": [{"name": "actTRUE", "args": []}]}, {"chain": [{"name": "actMessage", "args": []}, {"name": "actDelay", "args": ["20"]}]}]},
            ]
        }
        tokens, sections = coverage.level_tokens(metadata)
        self.assertEqual(tokens, {"actCheckPlayer": 1, "actDelay": 1, "actMessage": 2, "actTRUE": 1})
        self.assertEqual(sections, {"event": 1, "win": 1})

    def test_classification_distinguishes_applied_recorded_and_unsupported(self):
        verdict = coverage.classify({"actCheckPlayer": 1, "actMessage": 2}, self.sets)
        self.assertEqual(verdict, {"unsupported_tokens": [], "recorded_only_tokens": [], "fully_supported": True, "fully_applied": True})
        verdict = coverage.classify({"actCheckPlayer": 1, "actDelay": 3, "actAddTE": 1}, self.sets)
        self.assertTrue(verdict["fully_supported"])
        self.assertFalse(verdict["fully_applied"])
        self.assertEqual(verdict["recorded_only_tokens"], ["actAddTE", "actDelay"])
        verdict = coverage.classify({"actFALSE": 1, "actUseItem": 1, "actMessage": 1}, self.sets)
        self.assertEqual(verdict["unsupported_tokens"], ["actFALSE", "actUseItem"])
        self.assertFalse(verdict["fully_supported"])

    def test_report_totals_and_check_roundtrip(self):
        levels = [
            fake_level(1, {"actCheckPlayer": 1, "actMessage": 1}),
            fake_level(2, {"actCheckPlayer": 1, "actDelay": 2}),
            fake_level(3, {"actCheckPlayer": 1, "actUseItem": 1}),
            fake_level(501, {"actCheckPlayer": 1, "actUseItem": 1, "actGetItem": 1}),
            fake_level(502, {"actTRUE": 1}),
        ]
        report = coverage.build_report(levels, self.sets, self.rules)
        totals = report["totals"]
        self.assertEqual(totals["file_count"], 5)
        self.assertEqual(totals["main_level_count"], 3)
        self.assertEqual(totals["main_fully_supported"], 2)
        self.assertEqual(totals["main_fully_applied"], 1)
        self.assertEqual(totals["all_fully_supported"], 3)
        self.assertEqual(totals["unsupported_token_main_level_counts"], {"actUseItem": 1})
        self.assertEqual(totals["token_totals"]["actCheckPlayer"], 4)
        self.assertFalse(report["levels"]["501"]["main_level"])
        self.assertEqual(coverage.check(json.loads(json.dumps(report)), self.sets), [])

    def test_check_detects_stale_verdicts_and_support_set_drift(self):
        report = coverage.build_report([fake_level(1, {"actCheckPlayer": 1, "actDelay": 1})], self.sets, self.rules)
        stale = json.loads(json.dumps(report))
        stale["levels"]["001"]["fully_applied"] = True
        self.assertTrue(any("fully_applied is stale" in error for error in coverage.check(stale, self.sets)))
        stale = json.loads(json.dumps(report))
        stale["totals"]["main_fully_supported"] = 0
        self.assertIn("totals are stale", coverage.check(stale, self.sets))
        drifted = dict(self.sets)
        drifted["PRESENTATION_ACTIONS"] = []
        errors = coverage.check(json.loads(json.dumps(report)), drifted)
        self.assertTrue(any("PRESENTATION_ACTIONS differs" in error for error in errors))
        self.assertTrue(any("unsupported_tokens is stale" in error for error in errors))

    def test_tracked_report_matches_current_interpreter(self):
        output = coverage.DEFAULT_OUTPUT
        if not output.exists():
            self.skipTest("tracked coverage report not generated")
        report = json.loads(output.read_text(encoding="utf-8"))
        self.assertEqual(coverage.check(report, coverage.support_sets()), [])
        self.assertEqual(report["totals"]["main_level_count"], 47)
        self.assertTrue(report["levels"]["053"]["fully_applied"])
        self.assertTrue(report["levels"]["052"]["fully_supported"])


    def test_token_meanings_come_from_trailing_comments(self):
        meanings = coverage.parse_gd_token_meanings(FAKE_RULES, "SUPPORTED_CONDITIONS")
        self.assertEqual(meanings, {"actCheckPlayer": "dead-unit check", "actTRUE": ""})
        self.assertEqual(coverage.parse_gd_token_meanings(FAKE_RULES, "MISSING"), {})

    def test_action_header_shapes_join_opcode_and_argument_comment(self):
        header = Path(self.tmp.name) / "ACTION.H"
        header.write_text(FAKE_ACTION_H, encoding="utf-8")
        shapes = coverage.action_header_shapes(header)
        self.assertEqual(shapes["actMessage"], (10, "[player code][serial][message code]"))
        self.assertEqual(shapes["actTRUE"], (67, ""))

    def test_token_table_rows_report_missing_meaning_and_missing_define(self):
        header = Path(self.tmp.name) / "ACTION.H"
        header.write_text(FAKE_ACTION_H, encoding="utf-8")
        shapes = coverage.action_header_shapes(header)
        rows, problems = coverage.token_table_rows(self.rules, shapes, {"actCheckPlayer": 4, "actDelay": 2})
        self.assertEqual([row["token"] for row in rows], ["actCheckPlayer", "actTRUE", "actMessage", "actInsertObject", "actAddTE", "actDelay"])
        self.assertEqual(rows[0]["occurrences"], 4)
        self.assertEqual(rows[0]["args"], "[num][id1][id2][...]")
        self.assertEqual(rows[1]["occurrences"], 0)
        # every token but actCheckPlayer lacks its comment; actAddTE is in the header, actInsertObject too
        self.assertEqual(len([p for p in problems if "no `# meaning`" in p]), 5)
        self.assertFalse(any("not defined in ACTION.H" in p for p in problems))
        del shapes["actDelay"]
        _, problems = coverage.token_table_rows(self.rules, shapes, {})
        self.assertTrue(any(p == "PRESENTATION_ACTIONS: actDelay is not defined in ACTION.H" for p in problems))

    def test_token_table_renders_one_row_per_token_in_constant_order(self):
        documented = FAKE_RULES.replace('\t"actTRUE",', '\t"actTRUE",  # always holds').replace('\t"actMessage",', '\t"actMessage",\t# push a line')
        rules = Path(self.tmp.name) / "documented.gd"
        rules.write_text(documented, encoding="utf-8")
        header = Path(self.tmp.name) / "ACTION.H"
        header.write_text(FAKE_ACTION_H, encoding="utf-8")
        report = coverage.build_report([fake_level(1, {"actCheckPlayer": 1, "actMessage": 3})], self.sets, rules)
        rows, _ = coverage.token_table_rows(rules, coverage.action_header_shapes(header), report["totals"]["token_totals"])
        table = coverage.render_token_table(rows, report)
        self.assertIn("| `actTRUE` | — | always holds | 0 |", table)
        self.assertIn("| `actMessage` | `[player code][serial][message code]` | push a line | 3 |", table)
        self.assertEqual(table.count("\n| `act"), 6)
        self.assertLess(table.index("## 条件"), table.index("## 动作"))
        self.assertEqual(coverage.token_table_summary("X", rows), "X tokens=6 conditions=2 applied=2 world_flags=1 presentation=1")

    def test_inline_empty_array_does_not_swallow_next_constant(self):
        source = 'const A := []\nconst B := [\n\t"x",\n\t"y",\n]\nconst C := [\n]\n'
        self.assertEqual(coverage.parse_gd_string_array(source, 'A'), [])
        self.assertEqual(coverage.parse_gd_string_array(source, 'B'), ['x', 'y'])
        self.assertEqual(coverage.parse_gd_string_array(source, 'C'), [])


# ---- table overlay (hsltools.sources.tables.table_rows) ----
# content/authored/overrides/<PLAYERS|ITEM>.json lays authored field values over imported rows
# for every generator; a table, row or field the original does not have fails generation.

from unittest import mock

from hsltools.sources import tables as source_tables


@unittest.skipUnless(original_content.present(), 'original-derived content absent (hsltools.original_content)')
class TableOverlayTests(unittest.TestCase):
    def overlay(self, files):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        for name, rows in files.items():
            (Path(folder.name) / name).write_text(json.dumps({'schema': 'hsl_table_override.v1', 'rows': rows}), encoding='utf-8')
        patch = mock.patch.object(source_tables, 'OVERRIDE_DIR', Path(folder.name))
        patch.start()
        self.addCleanup(patch.stop)

    def test_overlay_reaches_the_generated_equipment_and_roles(self):
        from hsltools.data.equipment import build as equipment
        from hsltools.data.role_profiles import build as roles
        self.overlay({'ITEM.json': {'1': {'attack_damage': 40}}, 'PLAYERS.json': {'1': {'str': 30}}})
        self.assertEqual(equipment()['items']['1']['effects']['attack'], 40)
        self.assertEqual(roles()['actors']['001']['attributes']['str'], 30)
        # The parity probes keep reading the imported rows.
        from hsltools.native.sources import original_sources
        self.assertEqual(original_sources()[0]['001']['str'], '16')

    def test_item_overlay_leaves_the_probe_checks_inside_generators_on_the_original(self):
        # mobile_jobs / ai_profiles re-run a native probe check whose fixtures equip ITEM 21 / 40.
        from hsltools.data.ai_profiles import build as ai_profiles
        from hsltools.data.mobile_jobs import build as mobile_jobs
        self.overlay({'ITEM.json': {'21': {'attack_damage': 21}, '40': {'attack_damage': 93}}})
        self.assertTrue(mobile_jobs())
        self.assertTrue(ai_profiles()['actors'])

    def test_unknown_table_row_or_field_fails_naming_it(self):
        for files, message in (({'MAGIC.json': {'1': {'damage': '1,2'}}}, 'overrides/MAGIC.json: no overridable table'),
                               ({'ITEM.json': {'9999': {'cost': 1}}}, 'overrides/ITEM.json: rows["9999"]: ITEM.TXT has no row'),
                               ({'ITEM.json': {'1': {'attak_damage': 40}}}, 'rows["1"]: ITEM.TXT has no field attak_damage')):
            with self.subTest(message=message):
                self.overlay(files)
                with self.assertRaisesRegex(ValueError, message.replace('[', r'\[').replace(']', r'\]')):
                    source_tables.table_rows('ITEM.TXT')


if __name__ == "__main__":
    import unittest
    unittest.main()
