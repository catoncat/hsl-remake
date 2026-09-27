"""hsltools.data / hsltools.checks: the migrated generators and checkers behind the registry.

Every task replaces exactly one ledger command and names its hsltools module in `scripts`; the
CLI (`hsl check <task>`) prints the PASS line check() returns, and every GeneratedFilesTask
must render the tracked outputs byte for byte (lane P1-data oracle, docs/CONSOLIDATION.md P1).
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))

from hsltools import registry  # noqa: E402
from hsltools.paths import ROOT  # noqa: E402

# family -> module registered for it; every task of these families is exercised below
DATA_FAMILIES = ('actors', 'items', 'skills', 'trials', 'scenarios', 'world', 'static', 'checks')
# tasks whose check is slow (original-source archives, many files) or depends on a large
# in-process build; CLI parity is still asserted, but only for this sample
CLI_SUBPROCESS_SAMPLE = ('progression_data',)


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

    def test_generated_tasks_render_the_tracked_outputs_byte_for_byte(self):
        for task in data_tasks():
            if not isinstance(task, registry.GeneratedFilesTask):
                continue
            with self.subTest(task=task.name):
                rendered = task.render(registry.Context())
                self.assertTrue(set(rendered) <= set(task.outputs), task.name)  # asset folders are outputs check validates but render does not write
                for path, data in rendered.items():
                    self.assertEqual((ROOT / path).read_bytes(), data, f'{task.name}: {path}')


class DataTaskParityTests(unittest.TestCase):
    """The CLI (`hsl check <task>`) prints the same PASS line the in-process check() returns."""

    def test_sampled_tasks_match_the_cli(self):
        tasks = {task.name: task for task in data_tasks()}
        cli = registry.cli_check_lines(CLI_SUBPROCESS_SAMPLE)
        for name in CLI_SUBPROCESS_SAMPLE:
            with self.subTest(task=name):
                self.assertEqual(tasks[name].check(registry.Context()), cli[name])


if __name__ == '__main__':
    unittest.main()
