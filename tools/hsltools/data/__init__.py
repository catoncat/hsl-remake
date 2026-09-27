"""Compiled data tables generated from the original sources (content/generated, content/battles).

Every module exposes tasks() -> list[Task] (discovered by hsltools.registry.task_modules())
and the generator bodies moved verbatim from the former tools/hsl_*.py script named by the
task's `replaces` ledger command.
"""
from __future__ import annotations

import contextlib
import io
import json
from pathlib import Path

from hsltools.paths import ORIGINAL_PAK
from hsltools.registry import CheckFailed, Context, NotGeneratable, Task
from hsltools.runner import last_line


def json_bytes(payload, ensure_ascii: bool = False) -> bytes:
    """The tracked serialisation shared by the JSON generators: indent=2 plus a trailing newline."""
    return (json.dumps(payload, ensure_ascii=ensure_ascii, indent=2) + '\n').encode('utf-8')


COMPACT_WIDTH = 1000


def _flat(value) -> bool:
    items = value.values() if isinstance(value, dict) else value if isinstance(value, list) else ()
    return all(not isinstance(item, (dict, list)) for item in items)


def compact_json_text(value, indent: int = 0, width: int = COMPACT_WIDTH) -> str:
    """JSON for large generated receipts (no trailing newline): a value whose one-line form fits in
    `width`, and any array whose elements are scalars or flat objects / arrays, stay on one line;
    other objects and arrays get one key / element per line, indent 2. One line per case or per
    draw list instead of one per number (09-25 audit: indent=2 receipts were 95% of a day's
    +14,106 docs lines — original_range_terrain.json 9,305 lines, original_enemy_turn.json 3,703)."""
    compact = json.dumps(value, ensure_ascii=False)
    if not isinstance(value, (dict, list)) or not value or len(compact) <= width:
        return compact
    if isinstance(value, list) and all(_flat(item) for item in value):
        return compact
    pad, inner = ' ' * indent, ' ' * (indent + 2)
    if isinstance(value, list):
        return '[\n' + ',\n'.join(inner + compact_json_text(item, indent + 2, width) for item in value) + '\n' + pad + ']'
    return '{\n' + ',\n'.join(f'{inner}{json.dumps(key, ensure_ascii=False)}: {compact_json_text(item, indent + 2, width)}'
                              for key, item in value.items()) + '\n' + pad + '}'


def printed_last_line(function, *args, marker: str | None = None) -> str:
    """Run a verbatim legacy body that reports by printing and return its report line: the last
    printed line, or with `marker` the first line containing it (checkers whose detail lines
    follow their PASS line; the other lines are printed again so they stay in the job log).

    Validation failures raised as AssertionError / ValueError / SystemExit / KeyError, or reported
    as a non-zero int return (the CLI-shaped main/check bodies), become CheckFailed so the runner
    reports them as a failed check rather than a crash."""
    buffer = io.StringIO()
    try:
        with contextlib.redirect_stdout(buffer):
            result = function(*args)
    except (AssertionError, ValueError, SystemExit, KeyError) as error:
        raise CheckFailed(f'{buffer.getvalue()}{type(error).__name__}: {error}') from error
    lines = buffer.getvalue().splitlines()
    if isinstance(result, int) and result != 0:
        raise CheckFailed('\n'.join(lines) or f'exit code {result}')
    if marker is None:
        return last_line(buffer.getvalue())
    passed = next((line for line in lines if marker in line), None)
    if passed is None:
        raise CheckFailed('\n'.join(lines) or f'{function.__module__}: no {marker} line printed')
    for line in lines:
        if line != passed:
            print(line)
    return passed


class OriginalArchiveTask(Task):
    """A tracked import from the original archive: check validates the tracked files the way the
    script's --check did; generate re-imports them from `archive` (hsl.pak unless overridden) and
    fails (NotGeneratable) when the original install is absent."""
    archive: Path = ORIGINAL_PAK

    def verify(self, ctx: Context) -> str:
        """Validate the tracked outputs; returns the PASS line."""
        raise NotImplementedError

    def rebuild(self, ctx: Context) -> None:
        """Re-import the outputs from self.archive (known to exist)."""
        raise NotImplementedError

    def check(self, ctx: Context) -> str:
        return self.verify(ctx)

    def generate(self, ctx: Context) -> str:
        if not self.archive.exists():
            raise NotGeneratable(f'{self.name}: original archive not found at {self.archive} (needs the documented original install; WINEPREFIX)')
        self.rebuild(ctx)
        return self.verify(ctx)
