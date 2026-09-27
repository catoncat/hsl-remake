"""hsltools.levels: the per-level data chain families replace their legacy commands one for one.

Parity: every native task's replaces command is a ledger check command, no ledger command of
the family survives in all_tasks(), and the in-process check line equals what the CLI
(`hsl check <task>`) prints for a sample level.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))

from hsltools import registry  # noqa: E402
from hsltools.legacy import check_commands  # noqa: E402
from hsltools.paths import ROOT  # noqa: E402

# family -> (ledger script name, sample ledger commands whose task's PASS line must match the CLI's)
FAMILIES: dict[str, tuple[str, tuple[str, ...]]] = {
    'battle_seed': ('tools/hsl_battle_seed.py', ('tools/hsl_battle_seed.py --level 37 --check', 'tools/hsl_battle_seed.py --level 501 --check')),
    'opening_timeline_compile': ('tools/hsl_opening_timeline_compile.py', (
        'tools/hsl_opening_timeline_compile.py --check',
        'tools/hsl_opening_timeline_compile.py content/generated/hsl/chapter01/battle037_seed.json --message-evidence content/imported/hsl/chapter01/battle037/message_text_evidence.json --output content/imported/hsl/chapter01/battle037/opening_timeline.json --check')),
    'opening_timeline_check': ('tools/hsl_opening_timeline_check.py', (
        'tools/hsl_opening_timeline_check.py',
        'tools/hsl_opening_timeline_check.py content/imported/hsl/chapter01/battle578/opening_timeline.json --source-script story578')),
    'message_text_evidence_check': ('tools/hsl_message_text_evidence_check.py', (
        'tools/hsl_message_text_evidence_check.py', 'tools/hsl_message_text_evidence_check.py --level 37')),
    'level_map_objects': ('tools/hsl_level_map_objects.py', ('tools/hsl_level_map_objects.py --level 1 --check', 'tools/hsl_level_map_objects.py --level 12 --check')),
    'level_sounds': ('tools/hsl_level_sounds.py', ('tools/hsl_level_sounds.py --level 22 --check',)),
    'level_source_texts': ('tools/hsl_level_source_texts.py', ('tools/hsl_level_source_texts.py --level 22 --check',)),
    'level_actors': ('tools/hsl_level_actors.py', ('tools/hsl_level_actors.py --level 53 --check', 'tools/hsl_level_actors.py --level 500 --check')),
    'story_scene': ('tools/hsl_story_scene.py', ('tools/hsl_story_scene.py --level 1 --check', 'tools/hsl_story_scene.py --level 73 --check')),
}


class LevelFamilyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tasks = registry.all_tasks()
        cls.commands = check_commands()
        cls.ctx = registry.Context()

    def native(self, family: str) -> list[registry.Task]:
        return [task for task in self.tasks if task.family == family]

    def test_every_family_command_is_replaced(self):
        for family, (script, _) in FAMILIES.items():
            with self.subTest(family=family):
                native = self.native(family)
                replaced = sorted(command for task in native for command in task.replaces)
                expected = sorted(command for command in self.commands if command.split()[0] == script)
                self.assertEqual(replaced, expected)
                self.assertEqual(len(native), len(expected))

    def test_levels_come_from_the_data(self):
        imported = sorted(int(p.name[6:]) for p in (ROOT / 'content/imported/hsl/chapter01').glob('battle[0-9][0-9][0-9]') if p.is_dir() and p.name != 'battle500')
        self.assertEqual(sorted(task.level for task in self.native('battle_seed')), imported)
        story = [level for level in imported if not 501 <= level <= 578]
        self.assertEqual(sorted(task.level for task in self.native('level_sounds')), story)
        self.assertEqual(sorted(task.level for task in self.native('level_source_texts')), story)
        self.assertEqual(sorted(task.level for task in self.native('level_actors')), sorted(story + [500]))
        self.assertEqual(sorted(task.level for task in self.native('story_scene')), story)

    def test_native_check_line_matches_the_cli(self):
        by_replaces = {command: task for task in self.tasks for command in task.replaces}
        sampled = [by_replaces[command] for _, samples in FAMILIES.values() for command in samples]
        cli = registry.cli_check_lines([task.name for task in sampled])
        for task in sampled:
            with self.subTest(task=task.name):
                self.assertEqual(task.check(self.ctx), cli[task.name])

    def test_generated_families_render_the_tracked_bytes(self):
        for name in ('opening_timeline_compile:51', 'opening_timeline_compile:578', 'story_scene:53', 'story_scene:52', 'level_battle:52', 'level_battle:53'):
            task = registry.select(self.tasks, [name])[0]
            rendered = task.render(self.ctx)
            self.assertEqual(set(rendered), set(task.outputs))
            for path, data in rendered.items():
                self.assertEqual((ROOT / path).read_bytes(), data, f'{name}: {path}')

    def test_generate_without_the_original_pak_fails_and_names_it(self):
        ctx = registry.Context(original_exe=Path('/nonexistent/hsl01.exe'))
        for family in ('battle_seed', 'level_map_objects', 'level_sounds', 'level_source_texts', 'level_actors'):
            task = self.native(family)[0]
            with self.subTest(task=task.name):
                code, output, _ = registry.run_task(task, 'generate', ctx)
                self.assertEqual(code, 1, output)
                self.assertIn('/nonexistent/hsl.pak', output)

    def test_generate_of_a_pure_checker_is_skipped_not_failed(self):
        ctx = registry.Context(original_exe=Path('/nonexistent/hsl01.exe'))
        for family in ('opening_timeline_check', 'message_text_evidence_check'):
            task = self.native(family)[0]
            with self.subTest(task=task.name):
                code, output, _ = registry.run_task(task, 'generate', ctx)
                self.assertEqual(code, 2, output)
                self.assertIn('pure checker', output)


if __name__ == '__main__':
    unittest.main()
