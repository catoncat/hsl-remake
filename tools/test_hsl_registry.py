"""hsltools.registry: task set and ledger invariant, parity with the replaced commands, check/generate contract."""
from __future__ import annotations

import contextlib
import importlib
import io
import json
import pkgutil
import re
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))

from hsltools import registry  # noqa: E402
from hsltools.legacy import check_commands  # noqa: E402
from hsltools.paths import ROOT  # noqa: E402


class FakeTask(registry.GeneratedFilesTask):
    family = 'fake'

    def __init__(self, name: str, outputs: dict[str, bytes], inputs: tuple[str, ...] = (), replaces: tuple[str, ...] = ()) -> None:
        self.name = name
        self.payload = outputs
        self.outputs = tuple(outputs)
        self.inputs = inputs
        self.replaces = replaces

    def render(self, ctx):
        return dict(self.payload)

    def summary(self, rendered, mode):
        return f'FAKE_{mode.upper()} files={len(rendered)}'


class RegistryTaskSetTests(unittest.TestCase):
    def setUp(self):
        self.tasks = registry.all_tasks()
        self.commands = check_commands()

    def test_every_ledger_command_is_replaced_by_exactly_one_task(self):
        names = [task.name for task in self.tasks]
        self.assertEqual(len(names), len(set(names)))
        replaced = [command for task in self.tasks for command in task.replaces]
        self.assertEqual(len(replaced), len(set(replaced)), 'a ledger command is replaced by two tasks')
        self.assertEqual(sorted(replaced), sorted(self.commands))
        # Tasks born after the migration have replaces=(), so the task set is a superset of the ledger.
        self.assertGreaterEqual(len(self.tasks), len(self.commands))
        self.assertEqual(len(self.tasks) - len(self.commands), sum(1 for task in self.tasks if not task.replaces))

    def test_ledger_command_replaced_by_no_task_fails_the_registry(self):
        with self.assertRaisesRegex(ValueError, r"replaced by no task: 'tools/hsl_unmigrated\.py --check'"):
            registry.check_ledger(self.tasks, [*self.commands, 'tools/hsl_unmigrated.py --check'])

    def test_ledger_command_replaced_twice_fails_the_registry(self):
        twin = FakeTask('terrain_heights_twin', {'x': b''}, replaces=('tools/hsl_terrain_heights.py',))
        with self.assertRaisesRegex(ValueError, r"replaced by 2 tasks \['terrain_heights', 'terrain_heights_twin'\]: 'tools/hsl_terrain_heights\.py'"):
            registry.check_ledger([*self.tasks, twin], self.commands)

    def test_replacing_a_command_missing_from_the_ledger_fails_the_registry(self):
        stray = FakeTask('stray', {'x': b''}, replaces=('tools/hsl_stray.py --check',))
        with self.assertRaisesRegex(ValueError, r"task stray replaces a command missing from the ledger: 'tools/hsl_stray\.py --check'"):
            registry.check_ledger([*self.tasks, stray], self.commands)
        with self.assertRaisesRegex(ValueError, r"duplicate task names: \['terrain_heights'\]"):
            registry.check_ledger([*self.tasks, FakeTask('terrain_heights', {'x': b''})], self.commands)

    def test_every_discovered_module_exposes_tasks_and_every_public_module_is_discovered(self):
        modules = registry.task_modules()
        self.assertEqual(modules, sorted(modules))
        self.assertEqual(len(modules), len(set(modules)))
        for name in modules:
            tasks = importlib.import_module(name).tasks()
            self.assertTrue(tasks, f'{name}: tasks() returned nothing')
            for task in tasks:
                self.assertIsInstance(task, registry.Task, name)
        # The task packages hold nothing but task modules and their helpers (`_`-prefixed, or
        # hsltools.schema.validate, the validator shared with game/sim/UnitSchema.gd).
        # hsltools.levels.scenario: the shared winfail readers of the scenario assemblers.
        helpers = {'hsltools.schema.validate', 'hsltools.levels.scenario'}
        public = sorted(info.name for package_name in registry.TASK_PACKAGES
                        for info in pkgutil.iter_modules(importlib.import_module(package_name).__path__, package_name + '.')
                        if not info.name.rsplit('.', 1)[1].startswith('_'))
        self.assertEqual(sorted(set(public) - helpers), modules)

    def test_tasks_declare_outputs_inside_the_repository(self):
        for task in self.tasks:
            declared = task.outputs or task.inputs  # pure checkers (hsltools.checks) declare only what they read
            self.assertTrue(declared, task.name)
            for path in declared:
                # A folder output may hold nothing for some levels (git tracks no empty folder); its parent must exist.
                target = ROOT / path
                self.assertTrue(target.exists() or (path.endswith('/') and target.parent.is_dir()), f'{task.name}: {path} is not tracked')

    def test_level_battle_covers_every_tracked_battle_scenario(self):
        tracked = sorted(int(p.stem[7:]) for p in (ROOT / 'content/battles').glob('battle_[0-9][0-9][0-9].json'))
        assemblers = [task for task in self.tasks if task.family in ('level_battle', 'authored_level')]
        for task in assemblers:
            # These two families are the per-level scenario assemblers; a task without a level
            # (a new check or data task) belongs in a family of its own.
            self.assertIsInstance(task.level, int, f'{task.name}: family {task.family!r} is reserved for per-level scenario '
                                  f'assemblers (level=N); give this level-less task another family name')
        levels = sorted(task.level for task in assemblers if task.family == 'level_battle')
        authored = sorted(task.level for task in assemblers if task.family == 'authored_level')
        # Every tracked battle_NNN.json has exactly one assembler: the imported chain or the authored one.
        self.assertEqual(sorted(levels + authored), tracked)
        self.assertEqual(set(levels) & set(authored), set())


class ParityTests(unittest.TestCase):
    """The CLI (`hsl check <task>`) prints the PASS line the in-process check() returns."""

    def assert_parity(self, *task_names: str):
        tasks = registry.select(registry.all_tasks(), list(task_names))
        cli = registry.cli_check_lines([task.name for task in tasks])
        for task in tasks:
            self.assertEqual(task.check(registry.Context()), cli[task.name], task.name)

    def test_initial_skill_book(self):
        self.assert_parity('initial_skill_book')

    def test_job_up_learning(self):
        self.assert_parity('job_up_learning')

    def test_level_battle(self):
        self.assert_parity('level_battle:37', 'level_battle:501')

    def test_check_is_byte_for_byte_against_tracked_outputs(self):
        for name in ('initial_skill_book', 'level_battle:6', 'level_battle:578'):
            task = registry.select(registry.all_tasks(), [name])[0]
            rendered = task.render(registry.Context())
            self.assertEqual(set(rendered), set(task.outputs))
            for path, data in rendered.items():
                self.assertEqual((ROOT / path).read_bytes(), data, f'{name}: {path}')


class GeneratedFilesTaskTests(unittest.TestCase):
    def test_check_fails_until_generated_then_passes(self):
        with tempfile.TemporaryDirectory() as tmp:
            ctx = registry.Context(root=Path(tmp))
            task = FakeTask('fake', {'out/a.json': b'{"a": 1}\n', 'out/b.txt': b'b'})
            with self.assertRaises(registry.CheckFailed):
                task.check(ctx)
            self.assertEqual(task.generate(ctx), 'FAKE_GENERATE files=2')
            self.assertEqual(task.check(ctx), 'FAKE_CHECK files=2')
            (Path(tmp) / 'out/b.txt').write_bytes(b'B')
            with self.assertRaisesRegex(registry.CheckFailed, 'out/b.txt'):
                task.check(ctx)

    def test_run_task_reports_failures_as_job_results(self):
        with tempfile.TemporaryDirectory() as tmp:
            ctx = registry.Context(root=Path(tmp))
            code, output, _ = registry.run_task(FakeTask('fake', {'x': b'1'}), 'check', ctx)
            self.assertEqual(code, 1)
            self.assertIn('stale tracked output', output)
            code, output, _ = registry.run_task(FakeTask('fake', {'x': b'1'}), 'generate', ctx)
            self.assertEqual((code, output), (0, 'FAKE_GENERATE files=1\n'))


class PrintingCheckTask(registry.ScriptCheckTask):
    name = 'printing'
    family = 'fake'

    def __init__(self, run):
        self.run = run

    def verify(self, ctx):
        self.run()


class ScriptCheckTaskTests(unittest.TestCase):
    def test_check_returns_the_last_printed_line_and_reemits_the_rest(self):
        def run():
            print('SUB_CHECK_PASS')
            print('MAIN_CHECK_PASS n=1')
        captured = io.StringIO()
        with contextlib.redirect_stdout(captured):
            line = PrintingCheckTask(run).check(registry.Context())
        self.assertEqual((line, captured.getvalue()), ('MAIN_CHECK_PASS n=1', 'SUB_CHECK_PASS\n'))

    def test_assert_value_error_and_system_exit_become_check_failures(self):
        def failing_assert():
            assert False, 'stale hash'

        def failing_exit():
            raise SystemExit('manifest check failed: missing PNG')

        def silent():
            pass
        for run, fragment in ((failing_assert, 'stale hash'), (failing_exit, 'missing PNG'), (silent, 'no result line')):
            with self.assertRaisesRegex(registry.CheckFailed, fragment):
                PrintingCheckTask(run).check(registry.Context())
        code, output, _ = registry.run_task(PrintingCheckTask(failing_exit), 'check', registry.Context())
        self.assertEqual(code, 1)
        self.assertIn('missing PNG', output)

    def test_generate_is_not_generatable_without_build_or_original_archive(self):
        task = PrintingCheckTask(lambda: print('X_PASS'))
        with self.assertRaises(registry.NoRegenerationPath):
            task.generate(registry.Context())
        missing = registry.Context(original_exe=Path('/nonexistent/hsl01.exe'))
        with self.assertRaises(registry.NotGeneratable):
            registry.original_archive(missing)
        # hsl generate: a pure checker is skipped (2), a missing original input fails (1).
        self.assertEqual(registry.run_task(task, 'generate', registry.Context())[0], 2)

        class ArchiveTask(PrintingCheckTask):
            def build(self, ctx):
                registry.original_archive(ctx)
        code, output, _ = registry.run_task(ArchiveTask(lambda: print('X_PASS')), 'generate', missing)
        self.assertEqual(code, 1)
        self.assertIn('/nonexistent/hsl.pak', output)
        self.assertIn('WINEPREFIX or --exe', output)
        with tempfile.TemporaryDirectory() as tmp:
            exe = Path(tmp) / 'hsl01.exe'
            (Path(tmp) / 'movie.pak').write_bytes(b'')
            self.assertEqual(registry.original_archive(registry.Context(original_exe=exe), 'movie.pak'), Path(tmp) / 'movie.pak')


class SelectionAndOrderTests(unittest.TestCase):
    def test_select_by_name_family_and_glob(self):
        tasks = registry.all_tasks()
        self.assertEqual([t.name for t in registry.select(tasks, ['level_battle:37'])], ['level_battle:37'])
        self.assertEqual(len(registry.select(tasks, ['level_battle'])), sum(t.family == 'level_battle' for t in tasks))
        self.assertEqual({t.level for t in registry.select(tasks, ['level_battle:90*'])}, {900, 901, 902, 903, 904})
        with self.assertRaises(KeyError):
            registry.select(tasks, ['no_such_task'])

    def test_generation_order_puts_producers_before_consumers(self):
        producer = FakeTask('producer', {'gen/seed.json': b''})
        consumer = FakeTask('consumer', {'gen/battle.json': b''}, inputs=('gen/seed.json',))
        other = FakeTask('other', {'gen/other.json': b''}, inputs=('data/',))
        self.assertEqual([t.name for t in registry.generation_order([consumer, other, producer])], ['producer', 'consumer', 'other'])
        loop_a = FakeTask('a', {'x': b''}, inputs=('y',))
        loop_b = FakeTask('b', {'y': b''}, inputs=('x',))
        with self.assertRaises(ValueError):
            registry.generation_order([loop_a, loop_b])


class AffectedTests(unittest.TestCase):
    def setUp(self):
        self.tasks = registry.all_tasks()

    def names(self, changed):
        return [t.name for t in registry.affected(self.tasks, changed)]

    def test_core_and_shared_source_changes_affect_everything(self):
        self.assertEqual(len(self.names(['tools/hsltools/paths.py'])), len(self.tasks))
        self.assertEqual(len(self.names(['content/imported/hsl/global/tables/PLAYERS.TXT'])), len(self.tasks))

    def test_level_data_change_affects_that_level_only(self):
        names = self.names(['content/battles/story_037.json'])
        self.assertIn('level_battle:37', names)
        self.assertIn('story_scene:37', names)  # the level's story scene task (native since P1-levels)
        self.assertNotIn('level_battle:38', names)
        # A document change reaches only the documentation tool-reference check (hsltools.checks.doc_tool_references).
        self.assertEqual(self.names(['docs/PROJECT.md']), ['docs:tool_references'])
        # A game module change reaches the engine chapter-path check (hsltools.checks.engine_chapter_paths), the
        # player-copy check (hsltools.checks.player_copy_traditional: its strings are player copy) and the
        # provenance header check (hsltools.checks.provenance) and the parity inventory (which reads those headers), nothing else.
        self.assertEqual(self.names(['game/sim/CoreCombatRules.gd']), ['engine:chapter_paths', 'parity_inventory', 'content:player_copy_traditional', 'provenance', 'content:simplified_display'])

    def test_script_change_follows_the_import_graph(self):
        # No task depends on a stand-alone tools/hsl_*.py any more (T2: the library bodies the tasks
        # used live in hsltools, the scripts import the package), so a script change reaches no task.
        self.assertEqual(self.names(['tools/hsl_payload_inspector.py']), [])
        for task in self.tasks:
            self.assertEqual([script for script in task.scripts if Path(script).name.startswith('hsl_')], [], task.name)

    def test_package_never_imports_the_stand_alone_scripts(self):
        # hsltools is the shared core; tools/hsl_*.py are its command lines and independent tools.
        pattern = re.compile(r'^\s*(?:from|import)\s+(?:tools\.)?hsl_\w+', re.M)
        offenders = sorted(path.relative_to(ROOT).as_posix() for path in (ROOT / 'tools' / 'hsltools').rglob('*.py')
                           if pattern.search(path.read_text(encoding='utf-8')))
        self.assertEqual(offenders, [])


if __name__ == '__main__':
    unittest.main()
