"""The original-derived manifest (hsltools.original_content.MANIFEST): every tracked A-class file
as path + hash + the registry task whose outputs cover it ('' when no generator owns it). A PNG is
hashed by its decoded pixels (`rgba_sha256`: SHA-256 of b'<width>x<height>\n' + the RGBA bytes), every
other file by its bytes (`sha256`): a player's importer may encode the same image with different PNG
chunks / zlib settings than the tracked file (docs/OPEN_SOURCE_PLAN.md §8).

It carries no original content, so the public repository tracks it in place of the files: a
player's import is proved equal to ours by `hsl check original_derived_manifest`, and the
per-level task lists are enumerated from it while the content is absent.

  private repository (A files tracked)   check = the rendered manifest equals the tracked one;
                                         a content change needs `hsl generate original_derived_manifest`
  public checkout after the import       check = every generator-owned entry exists with its SHA-256
                                         (entries no generator owns — screenshots — may be absent)
  public checkout before the import      SKIP original-absent (hsltools.registry)
"""
from __future__ import annotations

import hashlib
import json
import subprocess

from hsltools import original_content
from hsltools.registry import CheckFailed, Context, GeneratedFilesTask
from hsltools.sources.shp import png_sha256

OUTPUT = original_content.MANIFEST_RELATIVE


def tracked_original_derived(ctx: Context) -> list[str]:
    """Tracked A-class paths ([] outside a git checkout or in the public repository)."""
    result = subprocess.run(['git', 'ls-files', '-z'], cwd=ctx.root, capture_output=True, check=False)
    if result.returncode != 0:
        return []
    paths = [name.decode() for name in result.stdout.split(b'\0') if name]
    return sorted(path for path in paths if original_content.classify(path)[0] == 'A')


def owners(paths: list[str]) -> dict[str, str]:
    """{path: owning task}: an exact output first, else the longest output directory holding it,
    else the importer whose declared content/imported manifest sits in an enclosing directory
    (importers declare the manifest and write the frames / clips listed beside it)."""
    from hsltools import registry
    exact: dict[str, str] = {}
    directories: list[tuple[str, str]] = []
    for task in registry.discovered_tasks():
        if isinstance(task, registry.PacketTask):
            continue
        for output in task.outputs:
            if output.endswith('/'):
                directories.append((output, task.name))
            else:
                exact.setdefault(output, task.name)
                if output.startswith('content/imported/') and 'manifest' in output.rsplit('/', 1)[-1]:
                    directories.append((output[: output.rfind('/') + 1], task.name))
    directories.sort(key=lambda item: (-len(item[0]), item[1]))
    result = {}
    for path in paths:
        owner = exact.get(path) or next((name for directory, name in directories if path.startswith(directory)), '')
        result[path] = owner
    return result


def render_manifest(entries: dict[str, dict[str, str]]) -> bytes:
    """One entry per line (parallel lanes touching different files merge cleanly)."""
    lines = [f'    {json.dumps(path, ensure_ascii=False)}: {json.dumps(entry, ensure_ascii=False, sort_keys=True)}'
             for path, entry in sorted(entries.items())]
    return ('{\n  "files": {\n' + ',\n'.join(lines) + '\n  },\n  "schema": 2\n}\n').encode('utf-8')


def sha256(path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def content_hash(path) -> dict[str, str]:
    """The manifest's hash field for one file: {'rgba_sha256': ...} for a PNG, else {'sha256': ...}."""
    if path.suffix.lower() == '.png':
        return {'rgba_sha256': png_sha256(path)}
    return {'sha256': sha256(path)}


class OriginalDerivedManifestTask(GeneratedFilesTask):
    name = 'original_derived_manifest'
    family = 'checks'
    inputs = ('content/', 'docs/evidence_packets/', 'docs/evidence_questions/')
    outputs = (OUTPUT,)
    replaces = ()  # born as a registry task: no historical command to replace
    scripts = ('tools/hsltools/checks/original_derived_manifest.py', 'tools/hsltools/original_content.py', 'tools/hsltools/sources/shp.py')

    def render(self, ctx: Context) -> dict[str, bytes]:
        paths = tracked_original_derived(ctx)
        if not paths:
            raise CheckFailed(f'{self.name}: no tracked original-derived files to list (the manifest is generated in the private repository)')
        owned = owners(paths)
        entries = {path: {**content_hash(ctx.root / path), 'task': owned[path]} for path in paths}
        return {OUTPUT: render_manifest(entries)}

    def check(self, ctx: Context) -> str:
        if tracked_original_derived(ctx):
            return super().check(ctx)
        # Public checkout after the player's import: the local files must match our hashes.
        entries = json.loads((ctx.root / OUTPUT).read_text(encoding='utf-8'))['files']
        missing, differ, unowned_absent = [], [], 0
        for path, entry in entries.items():
            target = ctx.root / path
            if not target.is_file():
                if entry['task']:
                    missing.append(path)
                else:
                    unowned_absent += 1
            elif content_hash(target) != {key: value for key, value in entry.items() if key != 'task'}:
                differ.append(path)
        if missing or differ:
            raise CheckFailed(f'{self.name}: local import differs from the manifest: missing={len(missing)} differ={len(differ)}'
                              f' first={(differ or missing)[0]}')
        return (f'ORIGINAL_DERIVED_MANIFEST_IMPORT_PASS files={len(entries)} matched={len(entries) - unowned_absent}'
                f' unowned_absent={unowned_absent}')

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        entries = json.loads(rendered[OUTPUT])['files']
        unowned = sum(1 for entry in entries.values() if not entry['task'])
        verb = 'CHECK' if mode == 'check' else 'BUILD'
        return f'ORIGINAL_DERIVED_MANIFEST_{verb}_PASS files={len(entries)} owned={len(entries) - unowned} unowned={unowned}'


def tasks() -> list[OriginalDerivedManifestTask]:
    return [OriginalDerivedManifestTask()]
