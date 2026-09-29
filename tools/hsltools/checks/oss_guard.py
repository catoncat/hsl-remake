"""Original-derived files stay out of Git in a public checkout: 0 tracked, 0 untracked-but-not-ignored.

A public checkout (tools/oss_export.sh) tracks no original-derived file; the player's import (`hsl bootstrap`)
writes them next to the tracked ones, and the public .gitignore keeps them out of `git add -A`. This check
compares `git ls-files` (the index: tracked and staged) and the untracked, not-ignored files of
`git status --porcelain` against

  - every class-A path of the original-derived manifest (hsltools.original_content.MANIFEST; the published
    EXE-derived rule data, PUBLISHED_EXE_DATA, is class C and allowed),
  - any other class-A path under content/imported/, content/generated/ or content/battles/,
  - outside content/authored/ (a modder's own art and sounds): the original's containers, executables, saves,
    shapes and sound / video files (ORIGINAL_SUFFIXES),
  - the folders that hold a copy of the original (legal-assets/, original-assets/, asset-dumps/; their
    README.md excepted),

and fails naming every hit. The private repository tracks the original-derived files on purpose (the export
drops them): a checkout that tracks docs/internal/ (maintainer documents the export never carries) passes
with `private=1` and checks nothing. Outside a git checkout nothing can be committed.

PASS line: OSS_GUARD_PASS tracked=N untracked=N listed=N hits=0.
"""
from __future__ import annotations

import subprocess
from pathlib import Path

from hsltools import original_content
from hsltools.checks import CheckTask
from hsltools.registry import CheckFailed, Context

ORIGINAL_SUFFIXES = ('.pak', '.exe', '.dll', '.sav', '.shp', '.wav', '.mov', '.mp4', '.avi', '.bik')
COPY_FOLDERS = ('legal-assets/', 'original-assets/', 'asset-dumps/')
PRIVATE_MARKER = 'docs/internal/'


def _git(root: Path, *args: str) -> list[str] | None:
    try:
        result = subprocess.run(['git', *args, '-z'], cwd=root, capture_output=True, check=False)
    except FileNotFoundError:  # no git installed (a downloaded ZIP): nothing can be committed either
        return None
    if result.returncode != 0:
        return None
    return [name.decode('utf-8', 'surrogateescape') for name in result.stdout.split(b'\0') if name]


def original_derived(path: str, listed: set[str]) -> bool:
    if path in listed:
        return True
    if path.startswith(original_content.A_DIRECTORIES) and original_content.classify(path)[0] == 'A':
        return True
    if path.lower().endswith(ORIGINAL_SUFFIXES) and not path.startswith('content/authored/'):
        return True
    return path.startswith(COPY_FOLDERS) and path.rsplit('/', 1)[-1] != 'README.md'


def check(root: Path) -> str:
    tracked = _git(root, 'ls-files')
    if tracked is None:
        return 'OSS_GUARD_PASS not a git checkout (nothing can be committed)'
    listed = {path for path in original_content.manifest() if original_content.classify(path)[0] == 'A'}
    # The private repository tracks docs/internal/ *and* the original-derived files themselves; a public
    # checkout that merely gained a docs/internal/ file is still checked.
    if any(path.startswith(PRIVATE_MARKER) for path in tracked) and sum(path in listed for path in tracked) > len(listed) // 2:
        return f'OSS_GUARD_PASS private=1 tracked={len(tracked)} (the private repository tracks original-derived files; tools/oss_export.sh drops them)'
    status = _git(root, 'status', '--porcelain', '--untracked-files=all', '--no-renames') or []
    untracked = [entry[3:] for entry in status if entry.startswith('?? ')]
    hits = [f'tracked {path}' for path in tracked if original_derived(path, listed)]
    hits += [f'not ignored {path}' for path in untracked if original_derived(path, listed)]
    if hits:
        raise CheckFailed(f'oss_guard: {len(hits)} original-derived file(s) tracked or not ignored'
                          ' (`git rm --cached` / add an ignore rule; NOTICE.md): ' + '; '.join(hits[:40])
                          + (f'; … {len(hits) - 40} more' if len(hits) > 40 else ''))
    return f'OSS_GUARD_PASS tracked={len(tracked)} untracked={len(untracked)} listed={len(listed)} hits=0'


class OssGuardTask(CheckTask):
    name = 'oss_guard'
    family = 'checks'
    # Reads every tracked and untracked path but declares only .gitignore (the file that decides what `git add`
    # picks up): content/ or docs/ count as original-derived, and the check must run before the import too.
    inputs = ('.gitignore',)
    replaces = ()  # born as a registry task
    scripts = ('tools/hsltools/checks/oss_guard.py', 'tools/hsltools/original_content.py')

    def check(self, ctx: Context) -> str:
        return check(ctx.root)


def tasks() -> list[OssGuardTask]:
    return [OssGuardTask()]
