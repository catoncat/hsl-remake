"""Original-derived content: which repository paths are derived from the original game, whether
they are present in this checkout, and the tracked path + SHA-256 manifest that stands in for
them where they are not (docs/internal/OPEN_SOURCE_PLAN.md).

  A  original-derived: decoded assets, original text / source files, saves, EXE-derived tables,
     screenshots / recordings / renders of the original game, recoloured original frames
  B  remake-original: code, docs, remake-composed music, tests, authored sequel data
  C  grey: evidence-packet prose / data dumps that may quote original strings or disassembly

The public repository carries B and processed C only; a player imports A from their own copy
(tools/hsl.py generate, HSL_ORIGINAL_DIR). While A is absent `hsl check` reports every task that
declares an A path as `SKIP original-absent`, and the per-level task lists come from MANIFEST.
"""
from __future__ import annotations

import functools
import json
from pathlib import Path

from hsltools.paths import ROOT, TABLES

MANIFEST_RELATIVE = 'content/generated/hsl/original_derived_manifest.json'
MANIFEST = ROOT / MANIFEST_RELATIVE
# Present iff the original text tables were imported (the first thing every chain reads).
SENTINEL = ROOT / TABLES / 'PLAYERS.TXT'

MEDIA = ('.png', '.jpg', '.jpeg', '.webp', '.gif', '.mp4', '.wav', '.ogg', '.bmp')
# Top-level directories whose contents are all original-derived (a declared task path naming one
# of these directories is A even when the directory itself is not a tracked file).
A_DIRECTORIES = ('content/imported/', 'content/generated/', 'content/battles/')


def classify(path: str) -> tuple[str, str]:
    """(class, subclass) of one repository-relative path."""
    low = path.lower()
    ext = Path(low).suffix
    if path == MANIFEST_RELATIVE:
        return 'B', 'original-derived manifest (paths + SHA-256 only)'
    if path.startswith('content/generated/hsl/remake_music/'):
        return 'B', 'remake-composed music (tools/compose_*.py)'
    if path.startswith('content/generated/hsl/development/autoplay/'):
        return 'B', 'remake autoplay results'
    if ext in ('.sav', '.bin'):
        return 'A', 'original saves / runtime memory dumps'
    if path.startswith('content/imported/'):
        if path.endswith('README.md') and '/source_texts/' not in path[len('content/imported/hsl/chapter01/battle'):]:
            return 'A', 'content/imported handwritten README (migrate)'
        if ext in MEDIA:
            return 'A', 'content/imported decoded media'
        return 'A', 'content/imported text/source/json'
    if path.startswith('content/generated/'):
        if path.endswith('.md'):
            return 'A', 'content/generated README / report (migrate)'
        return 'A', 'content/generated tables (EXE / PAK derived)'
    if path.startswith('content/battles/levels/') or path == 'content/battles/campaign.json':
        return 'B', 'content/battles authored level profiles / campaign'
    if path.startswith('content/battles/'):
        return 'A', 'content/battles assembled level data'
    if path.startswith('content/authored/actors/') and ext in MEDIA:
        return 'A', 'content/authored placeholder art (recoloured original frames)'
    if path.startswith(('docs/evidence_packets/', 'docs/evidence_questions/')):
        if ext in MEDIA:
            return 'A', 'evidence screenshots / recordings / renders of the original'
        if ext == '.md':
            return 'C', 'evidence packet prose (may quote strings / disassembly)'
        return 'C', 'evidence packet data dumps (json/tsv/txt)'
    if path.startswith('docs/external/'):
        return 'C', 'docs/external third-party notes'
    if path.startswith(('game/', 'tests/', 'tools/')):
        return 'B', path.split('/')[0] + '/'
    return 'B', 'docs, root files, authored sequel data, schema'


def is_original_derived(path: str) -> bool:
    """A declared task input / output (file or directory) that is, or holds, original-derived data."""
    path = path.replace('\\', '/')
    if path in ('content/battles/levels/', 'content/battles/campaign.json', MANIFEST_RELATIVE):
        return False
    if path.endswith('/'):
        if any(path.startswith(root) or root.startswith(path) for root in A_DIRECTORIES):
            return not path.startswith(('content/generated/hsl/remake_music/', 'content/generated/hsl/development/autoplay/'))
        return any(listed.startswith(path) for listed in manifest())  # e.g. an evidence folder holding screenshots
    return classify(path)[0] == 'A'


def stands_in(path: str) -> bool:
    """While the content is absent: the manifest lists this file, or files under this directory."""
    path = path.rstrip('/')
    return not present() and (path in manifest() or any(listed.startswith(path + '/') for listed in manifest()))


def present() -> bool:
    """Whether the original-derived content is in this checkout (private repository, or a public
    checkout after the player's import)."""
    return SENTINEL.is_file()


@functools.lru_cache(maxsize=1)
def manifest() -> dict[str, dict[str, str]]:
    """{path: {'sha256': hex, 'task': owning task or ''}} from the tracked manifest ({} if absent)."""
    if not MANIFEST.is_file():
        return {}
    return json.loads(MANIFEST.read_text(encoding='utf-8'))['files']


def manifest_dirs(prefix: str) -> set[str]:
    """Names of the directories directly under `prefix` (repository-relative, ending in '/') that
    the manifest lists files in: the stand-in for a glob over absent original-derived content."""
    return {path[len(prefix):].split('/', 1)[0] for path in manifest() if path.startswith(prefix) and '/' in path[len(prefix):]}


def manifest_files(prefix: str) -> set[str]:
    """Names of the files directly under `prefix` that the manifest lists."""
    return {path[len(prefix):] for path in manifest() if path.startswith(prefix) and '/' not in path[len(prefix):]}


def needs_original(task) -> bool:
    """A registry task that declares an original-derived input or output: skipped while absent."""
    return any(is_original_derived(path) for path in (*task.inputs, *task.outputs))
