#!/usr/bin/env python3
"""Open-source audit statistics (docs/internal/OPEN_SOURCE_PLAN.md): classify every tracked file.

  A  original-derived: decoded assets, original text/source files, saves, EXE-derived tables,
     screenshots / recordings / renders of the original game, recoloured original frames
  B  remake-original: code, docs, remake-composed music, tests, authored sequel data
  C  grey: evidence-packet prose / data dumps that may quote original strings or disassembly

For A files it also reports whether a registry task (tools/hsl.py) can rebuild them from the
original install: `original` = task reads the PAK / EXE itself (ScriptCheckTask.build override
or PacketTask), `derived` = GeneratedFilesTask rendering from other tracked inputs, `none` =
no generator owns the path (migration list). Read-only; run from the repository root:

  python3 tools/oss_audit_stats.py [REF] [--migration]
"""
from __future__ import annotations

import subprocess
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from hsltools.original_content import classify  # noqa: E402  (the one A/B/C rule, shared with the gate)


def tracked(ref: str) -> list[tuple[str, int]]:
    out = subprocess.run(['git', 'ls-tree', '-r', '-l', '-z', ref], check=True, capture_output=True).stdout
    rows = []
    for entry in out.split(b'\0'):
        if not entry:
            continue
        meta, name = entry.split(b'\t', 1)
        size = meta.split()[3]
        rows.append((name.decode(), int(size) if size != b'-' else 0))
    return rows


def task_kinds() -> list[tuple[str, str, tuple[str, ...]]]:
    from hsltools import registry
    kinds = []
    for task in registry.discovered_tasks():
        if isinstance(task, registry.PacketTask):
            kind = 'original'
        elif isinstance(task, registry.ScriptCheckTask):
            kind = 'original' if type(task).build is not registry.ScriptCheckTask.build else 'checker'
        elif isinstance(task, registry.GeneratedFilesTask):
            kind = 'derived'
        else:  # plain Task: its own generate() reads the PAK / Steam folder, or it only checks
            kind = 'original' if type(task).generate is not registry.Task.generate else 'checker'
        # An importer that declares a manifest also writes the frames / clips listed beside it.
        outputs = tuple(out[: out.rfind('/') + 1] if out.startswith('content/imported/') and 'manifest' in out.rsplit('/', 1)[-1]
                        else out for out in task.outputs)
        if outputs:
            kinds.append((task.name, kind, outputs))
    return kinds


def owner_kind(path: str, kinds) -> str:
    best = 'none'
    for _name, kind, outputs in kinds:
        for out in outputs:
            if path == out or (out.endswith('/') and path.startswith(out)):
                if kind == 'original':
                    return 'original'
                if kind == 'derived':
                    best = 'derived'
    return best


def main(argv: list[str]) -> int:
    ref = next((a for a in argv if not a.startswith('--')), 'HEAD')
    rows = tracked(ref)
    kinds = task_kinds()
    cat = defaultdict(lambda: [0, 0])
    sub = defaultdict(lambda: [0, 0])
    regen = defaultdict(lambda: [0, 0])
    sub_regen = defaultdict(lambda: [0, 0])
    migration = defaultdict(lambda: [0, 0])
    for path, size in rows:
        c, s = classify(path)
        for bucket, key in ((cat, c), (sub, (c, s))):
            bucket[key][0] += 1
            bucket[key][1] += size
        if c == 'A':
            k = owner_kind(path, kinds)
            regen[k][0] += 1
            regen[k][1] += size
            sub_regen[s][0] += 1
            sub_regen[s][1] += size if k != 'none' else 0
            if k != 'none':
                sub_regen[s + ' (regen files)'][0] += 1
            if k == 'none':
                parts = str(Path(path).parent).split('/')
                key = '/'.join(parts[:5]) if parts[0] == 'docs' else '/'.join(parts[:4])
                migration[key][0] += 1
                migration[key][1] += size
    mb = lambda b: f'{b / 1048576:.1f}'
    total = sum(s for _p, s in rows)
    print(f'ref {ref}: {len(rows)} tracked files, {mb(total)} MB (blob bytes)')
    print('\n| 类别 | 文件数 | MB |\n| --- | ---: | ---: |')
    for c in 'ABC':
        print(f'| {c} | {cat[c][0]} | {mb(cat[c][1])} |')
    print('\n| 类别 | 子类 | 文件数 | MB | 生成器覆盖 |\n| --- | --- | ---: | ---: | --- |')
    print_sub = []
    for (c, s), (n, b) in sorted(sub.items(), key=lambda kv: (kv[0][0], -kv[1][1])):
        if c == 'A':
            r = sub_regen[s + ' (regen files)'][0]
            ratio = f'{r}/{n} 文件（{100 * sub_regen[s][1] / b if b else 0:.0f}% MB）'
        else:
            ratio = '—'
        print(f'| {c} | {s} | {n} | {mb(b)} | {ratio} |')
    print('\n| A 类可再生 | 文件数 | MB |\n| --- | ---: | ---: |')
    for k in ('original', 'derived', 'none'):
        print(f'| {k} | {regen[k][0]} | {mb(regen[k][1])} |')
    if '--migration' in argv:
        print('\n| A 类无生成器目录 | 文件数 | MB |\n| --- | ---: | ---: |')
        for key, (n, b) in sorted(migration.items(), key=lambda kv: -kv[1][1]):
            print(f'| {key} | {n} | {mb(b)} |')
    return 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv[1:]))
