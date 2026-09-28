"""hsltools.assets: the asset-importer task family (PASS lines, legacy replacement) and the product importers
it drives (actor audio, combat program binding, item art, menu layout, town assets); one segment per former file."""
from __future__ import annotations

# ---- from test_hsl_assets_tasks.py ----
# hsltools.assets: the native asset-importer tasks print the PASS lines `hsl check` prints.
import sys
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))

from hsltools import registry  # noqa: E402
from hsltools.paths import ROOT  # noqa: E402


def family_tasks() -> list[registry.Task]:
    return [task for task in registry.all_tasks() if task.family == 'assets']


class AssetsFamilyTests(unittest.TestCase):
    def test_every_task_replaces_exactly_one_legacy_check_and_declares_its_module(self):
        tasks = family_tasks()
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
            for path in task.outputs:
                self.assertTrue((ROOT / path).exists(), f'{task.name}: {path}')

    def test_check_prints_the_cli_pass_line(self):
        ctx = registry.Context()
        tasks = family_tasks()
        cli = registry.cli_check_lines([task.name for task in tasks])
        for task in tasks:
            with self.subTest(task=task.name):
                self.assertEqual(task.check(ctx), cli[task.name])

    def test_generate_is_not_generatable_without_the_original_archive(self):
        ctx = registry.Context(original_exe=Path('/nonexistent/hsl01.exe'))
        for task in family_tasks():
            if isinstance(task, registry.ScriptCheckTask):
                with self.subTest(task=task.name), self.assertRaises(registry.NotGeneratable):
                    task.generate(ctx)


# ---- from test_hsl_actor_audio.py ----

import unittest
from hsltools.assets.actor_audio import bindings, SOURCE


class ActorAudioTests(unittest.TestCase):
    def test_table_bindings_preserve_distinct_walk_and_attack_resources(self):
        result = bindings(SOURCE.read_bytes())
        self.assertEqual(result['1']['walk'], 'wav/walk0011.wav')
        self.assertEqual(result['24']['walk'], 'wav/walk0012.wav')
        self.assertEqual(result['1']['attack'], 'wav/attack01.wav')
        self.assertEqual(result['25']['attack'], 'wav/attack02.wav')
        self.assertEqual(result['26']['attack'], 'wav/attack05.wav')
        self.assertEqual(set(result['1']), {'walk', 'attack', 'miss', 'dead'})

    def test_missing_character_fails_instead_of_substituting_another_sound(self):
        with self.assertRaises(ValueError):
            bindings(b'[character]\ncode=999\n')


# ---- from test_hsl_combat_program_binding.py ----

import unittest

from hsltools.assets.combat_animation import ACTION_OPCODES, CAST_OPCODES, compile_action, validate_cast_program


def op(name, *args):
    return {'op': name, 'args': list(args), 'source_line': 1}


class OrdinaryProgramBindingTests(unittest.TestCase):
    def test_delay_setup_and_zero_exit_are_separate_from_next_opcode(self):
        # Native dispatcher front-segment probe: delay D's successor is first
        # visible at result index max(D,1)+2, unlike the SHP frame helper.
        for delay in (0, 1, 2, 12, 30):
            program = [op('aniDelay', delay), op('aniInsertAttackFlash', -90, -120),
                       op('aniSetShape', 1), op('aniDelay', 3)]
            result = compile_action(program, 5)
            self.assertEqual(result['release_update'], max(delay, 1) + 2)
            self.assertEqual(result['poses'][0]['update'], result['release_update'])
            self.assertEqual(result['events'][1]['op'], 'aniInsertAttackFlash')
            self.assertEqual(result['events'][2]['op'], 'aniSetShape')

    def test_leonard_complete_order_keeps_final_wait(self):
        result = compile_action([op('aniDelay', 12), op('aniSetShape', 1),
                                 op('aniDelay', 8), op('aniSetShape', 2), op('aniDelay', 3),
                                 op('aniInsertAttackFlash', -90, -120), op('aniSetShape', 3),
                                 op('aniDelay', 30)], 5)
        self.assertEqual(result['poses'], [{'frame': 1, 'update': 14}, {'frame': 2, 'update': 24}, {'frame': 3, 'update': 29}])
        self.assertEqual(result['complete_updates'], 60)
        self.assertEqual(result['release_update'], 29)

    def test_unsupported_opcode_is_not_silently_ignored(self):
        for bad in [op('aniSetZoom', 0x11000), op('aniSetShape', 5), op('aniDelay', -1), op('aniInsertAttackFlash', 3)]:
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                compile_action([bad], 5)

    def test_cast_program_passes_through_in_source_order_or_is_refused(self):
        # 001's s_action (ANIMAL.TXT lines 14-15): the four cast opcodes, start panel 2 of 7.
        program = [op('aniSetXYDisp', -640, 0), op('aniShadowBG'), op('aniMoveToCenter'), op('aniInsertCastObject', -160, -150, 2, 6, 6)]
        self.assertEqual(validate_cast_program(program, 7, 'SID_PLAYER0'), program)
        self.assertEqual(validate_cast_program([], 0, 'SID_ENEMY021'), [])
        self.assertEqual(set(CAST_OPCODES), {'aniSetXYDisp', 'aniShadowBG', 'aniMoveToCenter', 'aniInsertCastObject'})
        self.assertFalse(set(CAST_OPCODES) - {'aniSetXYDisp'} & set(ACTION_OPCODES))
        for bad_program, panels in [(program[:3], 7), (program + [op('aniInsertCastObject', -160, -150, 2, 6, 6)], 7),
                                    (program, 2), ([op('aniDelay', 3)] + program, 7),
                                    (program[:3] + [op('aniInsertCastObject', -160, -150, 1, 6, 6)], 7)]:
            with self.subTest(bad=bad_program, panels=panels), self.assertRaises(ValueError):
                validate_cast_program(bad_program, panels, 'SID_PLAYER0')


# ---- from test_hsl_item_art.py ----

import json
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

from hsltools.assets import item_art


class ItemArtTests(unittest.TestCase):
    def test_original_category_bindings(self):
        self.assertEqual(item_art.bindings(), {'241': 'itemIconUse', '246': 'itemIconUse'})

    def test_current_art(self):
        item_art.check()

    def test_corrupt_asset_is_rejected(self):
        data = json.loads((item_art.ROOT / 'manifest.json').read_text())
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for key, asset in data['assets'].items():
                target = root / (key + '.png')
                shutil.copyfile(Path(asset['res_path'].removeprefix('res://')), target)
                asset['res_path'] = 'res://' + target.as_posix()
            (root / 'manifest.json').write_text(json.dumps(data))
            (root / 'consumable.png').write_bytes(b'corrupt')
            with patch.object(item_art, 'ROOT', root), self.assertRaises(AssertionError):
                item_art.check()

    def test_wrong_category_is_rejected(self):
        data = json.loads((item_art.ROOT / 'manifest.json').read_text())
        data['item_categories']['241'] = 'itemIconSword'
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'manifest.json').write_text(json.dumps(data))
            with patch.object(item_art, 'ROOT', root), self.assertRaises(AssertionError):
                item_art.check()


# ---- from test_hsl_menu_layout.py ----

import json
import tempfile
import unittest
from pathlib import Path

from hsltools.assets.menu_layout import ROOT as ROOT_menu_layout, EXE_SHA, points, source_tables
from hsltools.assets.command_frames import definitions


class NativeMenuDataTests(unittest.TestCase):
    def test_supported_counts_are_bounded_and_native_axes_are_not_a_circle(self):
        data = json.loads((ROOT_menu_layout / 'native_layout.json').read_text())
        self.assertEqual(data['exe_sha256'], EXE_SHA)
        self.assertEqual(points(data, 4), [[0, -72], [-66, 0], [0, 72], [66, 0]])
        self.assertEqual(points(data, 2), [[0, -72], [0, 72]])
        self.assertEqual(len(points(data, 7)), 7)
        for invalid in (0, 11, -1):
            with self.assertRaises(ValueError):
                points(data, invalid)

    def test_wrong_executable_is_rejected_before_address_reads(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'wrong.exe'
            path.write_bytes(b'not the supported game')
            with self.assertRaisesRegex(ValueError, 'Unsupported'):
                source_tables(path)

    def test_resource_flags_keep_loop_and_pingpong_distinct(self):
        data = definitions()
        self.assertFalse(data['move']['looped'])
        self.assertTrue(data['status']['looped'])
        self.assertEqual(data['status']['frame_count'], 5)
        self.assertTrue({'use', 'give', 'equip', 'drop'} <= data.keys())


# ---- from test_hsl_town_assets.py ----
# Offline unit tests for hsltools.assets.town_assets (no PAK needed).
import sys
import unittest
from pathlib import Path

ROOT_town_assets = Path(__file__).resolve().parents[1]
if str(ROOT_town_assets) not in sys.path:
    sys.path.insert(0, str(ROOT_town_assets))

import hsltools.assets.town_assets as town_assets  # noqa: E402


def _towndef() -> dict:
    return {
        "message_id_argument_positions": {"tePlayerMessage": [1], "teShapeMessage": [2], "teCheckMoney": [3], "teSelectInsertEvent": "even indexes from 2"},
        "town_events": [
            {
                "code": 9,
                "show_name": {"resource_id": 30, "text": "老闆"},
                "events": [
                    {"token": "teShapeMessage", "args": ["SHAPE\\FACE0062.SHP", "656", "858", "0"]},
                    {"token": "tePlayerMessage", "args": ["SID_雷歐納德", "859", "0"]},
                    {"token": "teCheckMoney", "args": ["100", "SHAPE\\FACE0073.SHP", "876", "1000"]},
                    {"token": "teSelectInsertEvent", "args": ["SID_雷歐納德", "2", "901", "10", "902", "11"]},
                    {"token": "teGetGold", "args": ["2000"]},
                ],
            }
        ],
    }


class ReferencedIdsTest(unittest.TestCase):
    def test_collects_messages_names_faces_and_players(self) -> None:
        refs = town_assets.referenced_ids(_towndef())
        # 606/607 are the shop engine's own refusal messages (ENGINE_MESSAGE_IDS), always included.
        self.assertEqual(refs["message_ids"], [606, 607, 858, 859, 901, 902, 1000])
        self.assertEqual(refs["name_ids"], [30, 656, 876])
        self.assertEqual(refs["faces"], ["SHAPE\\FACE0062.SHP", "SHAPE\\FACE0073.SHP"])
        self.assertEqual(refs["player_tokens"], ["SID_雷歐納德"])

    def test_players_by_name_resolves_resource_h_and_numeric_names(self) -> None:
        players = "[player]\nname = name_0\npicture = SHAPE\\FACE0000.SHP\n[player]\nname = 657\npicture = SHAPE\\FACE0058.SHP\n"
        rows = town_assets._players_by_name(players, {"0": "雷歐納德", "657": "克里歐司"}, {"name_0": 0})
        self.assertEqual(rows["雷歐納德"]["picture"], "SHAPE\\FACE0000.SHP")
        self.assertEqual(rows["克里歐司"]["row"], 2)


if __name__ == "__main__":
    import unittest
    unittest.main()
