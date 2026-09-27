"""hsltools.assets: the native asset-importer tasks print the PASS lines `hsl check` prints."""
from __future__ import annotations

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


if __name__ == '__main__':
    unittest.main()
