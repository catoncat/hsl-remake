"""hsltools.probes: the native probe family (PacketTasks; every hsl_native_*_probe.py ledger command is replaced, check_player, steal_ratio and effect_motion were born after the ledger and replace nothing)."""
from __future__ import annotations

import importlib
import json
import re
import sys
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))

from hsltools import registry  # noqa: E402
from hsltools.legacy import check_commands  # noqa: E402
from hsltools.paths import ROOT  # noqa: E402
from hsltools.probes._base import ProbeTask, run_probe  # noqa: E402

LEGACY_PROBE = re.compile(r'tools/hsl_native_(\w+)_probe\.py')


class ProbeFamilyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tasks = registry.all_tasks()
        cls.probes = [task for task in cls.tasks if task.family == 'probe']

    def test_every_native_probe_check_command_is_a_native_task(self):
        legacy_probe_commands = [command for command in check_commands() if LEGACY_PROBE.fullmatch(command)]
        replaced = {command for task in self.probes for command in task.replaces}
        self.assertEqual(sorted(legacy_probe_commands), sorted(replaced))
        # No known probe may drop out: the ledger's probe names plus the ones born later.
        known = {LEGACY_PROBE.fullmatch(command).group(1) for command in legacy_probe_commands} | {'check_player', 'steal_ratio', 'effect_motion'}
        self.assertLessEqual(known, {task.name for task in self.probes})
        for task in self.probes:
            self.assertIsInstance(task, registry.PacketTask, task.name)
            self.assertEqual(task.outputs, (task.packet,))
            self.assertTrue((ROOT / task.packet).is_file(), task.name)
            self.assertIn(f'tools/hsltools/probes/{task.name}.py', task.scripts)

    def test_module_binds_the_registered_task(self):
        for task in self.probes:
            if not isinstance(task, ProbeTask):
                continue
            module = importlib.import_module(f'hsltools.probes.{task.name}')
            self.assertIs(module.TASK.__class__, ProbeTask)
            self.assertEqual(module.TASK.name, task.name)
            self.assertEqual(module.PACKET, ROOT / task.packet)
            # the two functions ProbeTask binds (hsltools.probes._base)
            self.assertTrue(callable(module.execute_packet), task.name)
            self.assertTrue(callable(module.summary_line), task.name)

    def test_pass_line_parity_with_the_cli(self):
        names = ('bow_range', 'map_binding', 'skill_cost', 'turn_select', 'ohm_growth')
        cli = registry.cli_check_lines(names)
        for name in names:
            task = registry.select(self.tasks, [name])[0]
            native = task.check(registry.Context())
            self.assertEqual(native, cli[name], name)
            self.assertEqual(run_probe(task, None, False), native)

    def test_generate_without_the_original_exe_fails_and_validate_rejects_tampering(self):
        ctx = registry.Context(original_exe=Path('/nonexistent/hsl01.exe'))
        for name in ('bow_range', 'ai', 'skill_target', 'world_town', 'job_up_learning'):
            task = registry.select(self.tasks, [name])[0]
            code, output, _ = registry.run_task(task, 'generate', ctx)
            self.assertEqual(code, 1, output)
            packet = json.loads((ROOT / task.packet).read_text())
            packet['exe_sha256'] = '0' * 64
            with self.assertRaises(ValueError, msg=name):
                task.validate(packet)
        with self.assertRaises(ValueError):
            run_probe(registry.select(self.tasks, ['bow_range'])[0], None, True)


if __name__ == '__main__':
    unittest.main()
