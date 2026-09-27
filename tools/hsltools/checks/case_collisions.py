"""Tracked paths that differ only in letter case: 0 required.

Windows (NTFS) and macOS (APFS default) folders are case-insensitive, so two tracked paths such as
`audio_normalized/Attack01.WAV` and `audio_normalized/attack01.wav` check out as one file there (the
second overwrites the first, `git status` never settles). A Linux clone, or a regeneration on a
case-sensitive disk, is where such a pair appears; this check stops it before it is committed. Directory
prefixes count too (`Battle001/x` next to `battle001/y`).

Outside a git checkout (a plain export tree) the files on disk are listed instead, skipping hidden
entries, ignored/ and __pycache__.

PASS line: CASE_COLLISIONS_PASS paths=N collisions=0.
"""
from __future__ import annotations

import os
import subprocess
from collections import defaultdict
from pathlib import Path

from hsltools.checks import CheckTask
from hsltools.registry import CheckFailed, Context


def tracked_paths(root: Path) -> list[str]:
    result = subprocess.run(['git', 'ls-files', '-z'], cwd=root, capture_output=True, check=False)
    if result.returncode == 0:
        return [name.decode('utf-8', 'surrogateescape') for name in result.stdout.split(b'\0') if name]
    paths = []
    for folder, dirs, files in os.walk(root):
        dirs[:] = [name for name in dirs if not name.startswith('.') and name not in ('ignored', '__pycache__')]
        relative = Path(folder).relative_to(root)
        paths += [(relative / name).as_posix() for name in files]
    return paths


def collisions(paths: list[str]) -> list[list[str]]:
    """Groups of distinct spellings of one case-folded path or directory prefix."""
    spellings: dict[str, set[str]] = defaultdict(set)
    for path in paths:
        parts = path.split('/')
        for end in range(1, len(parts) + 1):
            prefix = '/'.join(parts[:end])
            spellings[prefix.casefold()].add(prefix)
    return sorted(sorted(group) for group in spellings.values() if len(group) > 1)


def check(root: Path) -> str:
    paths = tracked_paths(root)
    found = collisions(paths)
    if found:
        listed = '; '.join(' | '.join(group) for group in found[:20])
        raise CheckFailed(f'case_collisions: {len(found)} path(s) differ only in case (rename one): {listed}')
    return f'CASE_COLLISIONS_PASS paths={len(paths)} collisions=0'


class CaseCollisionsTask(CheckTask):
    name = 'case_collisions'
    family = 'checks'
    # Reads every tracked path but declares only .gitattributes (the file that governs how paths and text check
    # out): a directory would drag this check into every affected set, and content/ or docs/ count as original-
    # derived (the task would SKIP while the original is absent). `hsl check --all`, the gate set, always runs it.
    inputs = ('.gitattributes',)
    replaces = ()  # born as a registry task
    scripts = ('tools/hsltools/checks/case_collisions.py',)

    def check(self, ctx: Context) -> str:
        return check(ctx.root)


def tasks() -> list[CaseCollisionsTask]:
    return [CaseCollisionsTask()]
