"""Structural checkers over tracked imported/generated data (no regeneration path).

Every module exposes tasks() -> list[CheckTask]; the checker bodies moved verbatim from the former
tools/hsl_*.py script named by the task's `replaces` ledger command.
"""
from __future__ import annotations

from hsltools.registry import Context, NoRegenerationPath, Task


class CheckTask(Task):
    """A pure checker: check validates tracked data and returns the PASS line; nothing is generated."""
    outputs: tuple[str, ...] = ()

    def generate(self, ctx: Context) -> str:
        raise NoRegenerationPath(f'{self.name}: pure checker, nothing to regenerate')
