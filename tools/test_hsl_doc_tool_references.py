"""Stale tool paths, hsltools modules and hsl task arguments in documentation code must fail; prose,
placeholders, options and the documentation shorthands must not."""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from hsltools.checks.doc_tool_references import code_lines, command_arguments, scan  # noqa: E402
from hsltools.registry import Task  # noqa: E402


class FakeTask(Task):
    def __init__(self, name: str, family: str) -> None:
        self.name, self.family = name, family


TASKS = [FakeTask('level_battle:37', 'level_battle'), FakeTask('level_battle:51', 'level_battle'),
         FakeTask('original_save:sample', 'original_save'), FakeTask('unit_schema', 'schema')]


class DocToolReferencesTests(unittest.TestCase):
    def scan(self, source: str) -> tuple[list[str], dict[str, int]]:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'tools' / 'hsltools' / 'checks').mkdir(parents=True)
            (root / 'tools' / 'hsl.py').write_text('')
            (root / 'tools' / 'hsl_real.py').write_text('')
            (root / 'tools' / 'hsltools' / 'checks' / 'real.py').write_text('')
            (root / 'docs').mkdir()
            entry = root / 'docs' / 'guide.md'
            entry.write_text(source, encoding='utf-8')
            return scan(root, [entry], TASKS)

    def test_code_lines_take_fenced_blocks_and_inline_spans_only(self) -> None:
        text = 'prose tools/none.py `inline tools/a.py` more\n```sh\nblock tools/b.py\n```\nafter tools/c.py\n'
        self.assertEqual(code_lines(text), [(1, 'inline tools/a.py'), (3, 'block tools/b.py')])

    def test_command_arguments_drop_options_values_placeholders_and_terminators(self) -> None:
        self.assertEqual(command_arguments(" --all -j 8 level_battle:37 'level_battle:5*' # comment"),
                         ['level_battle:37', 'level_battle:5*'])
        self.assertEqual(command_arguments(' traversal --exe "$HOME/hsl01.exe"'), ['traversal'])
        self.assertEqual(command_arguments(' [PATTERN...]'), [])
        self.assertEqual(command_arguments(' unit_schema）/ godot / deep'), ['unit_schema'])
        self.assertEqual(command_arguments(' --all）/ godot / deep'), [])
        self.assertEqual(command_arguments(' a | grep b'), ['a'])

    def test_existing_references_and_shorthands_pass(self) -> None:
        issues, counts = self.scan(
            '```sh\npython3 tools/hsl.py check level_battle:37 level_battle "level_battle:5*" -j 3\n'
            'python3 tools/hsl.py generate level_battle:N level_battle:5NN original_save:<preset> level_battle:37|51\n'
            'PYTHONPATH=tools python3 -m hsltools.checks.real\n```\n'
            '`hsl list [PATTERN...]` and `hsl affected --since HEAD~3` and `tools/hsl_*.py` and `tools/$NAME.py`\n'
            '| `hsl_real.py` | a stand-alone tool named bare |\n')
        self.assertEqual(issues, [])
        self.assertEqual(counts, {'paths': 3, 'modules': 1, 'task_args': 7})

    def test_stale_path_module_and_task_fail_with_source_lines(self) -> None:
        issues, _ = self.scan('run `tools/hsl_gone.py` then `hsl_gone_too.py`\n```sh\npython3 -m hsltools.checks.gone\n'
                              'python3 tools/hsl.py check nothing level_battle:37|99 authored_level:N\n```\n')
        self.assertEqual(issues, [
            'docs/guide.md:1: tool path does not exist: tools/hsl_gone.py',
            'docs/guide.md:1: stand-alone tool does not exist: tools/hsl_gone_too.py',
            'docs/guide.md:3: hsltools module does not exist: hsltools.checks.gone',
            'docs/guide.md:4: `hsl check nothing` selects no registry task',
            'docs/guide.md:4: `hsl check level_battle:37|99` selects no registry task',
            'docs/guide.md:4: `hsl check authored_level:N` selects no registry task',
        ])


if __name__ == '__main__':
    unittest.main()
