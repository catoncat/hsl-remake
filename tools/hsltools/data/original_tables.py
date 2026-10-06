"""The original text tables and chapter-01 source texts, imported from the original PAK.

Registry task original_tables (family data): writes content/imported/hsl/global/tables/ (16 `@:\\data\\`
members + carry_items.json) and the four chapter01 source texts every chain reads first. What the import
does to each member (docs/internal/records/OPEN_SOURCE_PLAN.md §8, measured against the tracked files):

  raw   ACTION.H ANIMAL.H extras.h SHAPEDEF.TXT RESOURCE.TXT — the member bytes (CRLF kept)
  text  every other member — CRLF -> LF, trailing spaces / tabs of each line dropped, trailing blank
        lines dropped, one final LF; the cp950 bytes are untouched (no re-encoding, no column change).
        PLAYERS.TXT differs from its member only there (one `carry_item = 48<TAB>` line).
  carry_items.json — battle_rewards.curate_carry: the TOWNDEF.TXT carry lists PLAYERS.TXT references.

The tracked tables predate this task (hand-copied); the modes reproduce them byte for byte. check
compares with the PAK when the original install is present, else only that every file exists.
"""
from __future__ import annotations

from pathlib import Path

from hsltools.data import json_bytes
from hsltools.registry import Context, NotGeneratable, ScriptCheckTask, original_archive

TABLES = 'content/imported/hsl/global/tables/'
SOURCE_TEXTS = 'content/imported/hsl/chapter01/source_texts/'
RAW = {'ACTION.H', 'ANIMAL.H', 'EXTRAS.H', 'SHAPEDEF.TXT', 'RESOURCE.TXT'}
# tracked path -> PAK member (members are matched case-insensitively; the tracked names keep their case)
MEMBERS = {TABLES + name: '@:\\data\\' + name for name in (
    'ACTION.H', 'ANIMAL.H', 'EXTRAS.H', 'ITEM.TXT', 'MAGIC.TXT', 'OBJ-ALL.H', 'PLAYERS.TXT', 'RANGE.H', 'RANGE.TXT',
    'SHAPEDEF.H', 'SHAPEDEF.TXT', 'SPECIAL.TXT', 'TYPE.H', 'effects.h', 'mag-spc.h', 'resource.h')}
MEMBERS.update({SOURCE_TEXTS + name: '@:\\data\\' + name for name in ('RESOURCE.TXT', 'STORY051.TXT', 'obj-051.h', 'winfail051.txt')})
CARRY = TABLES + 'carry_items.json'


def text(data: bytes) -> bytes:
    lines = [line.rstrip(b' \t') for line in data.replace(b'\r\n', b'\n').split(b'\n')]
    return b'\n'.join(lines).rstrip(b'\n') + b'\n'


def imported(pak: Path) -> dict[str, bytes]:
    """{tracked path: bytes} for every member (not carry_items.json, which needs PLAYERS.TXT on disk)."""
    from hsltools.sources.pak import find_decoded_paks_packages, find_paks_record_by_name, read_paks_record_bytes
    package = find_decoded_paks_packages(pak)[0]
    end = int(package['paks']['candidate_index_offset'])
    result = {}
    for path, member in MEMBERS.items():
        record = find_paks_record_by_name(package['records'], member)
        if record is None:
            raise ValueError(f'original member missing: {member}')
        data = read_paks_record_bytes(package['path'], record, data_end_offset=end)
        result[path] = data if Path(path).name.upper() in RAW else text(data)
    return result


class OriginalTablesTask(ScriptCheckTask):
    name = 'original_tables'
    family = 'data'
    inputs = ()
    outputs = (TABLES, *(path for path in MEMBERS if path.startswith(SOURCE_TEXTS)))
    replaces = ()  # born as a registry task
    scripts = ('tools/hsltools/data/original_tables.py', 'tools/hsltools/data/battle_rewards.py')

    def verify(self, ctx: Context) -> None:
        try:
            pak = original_archive(ctx)
        except NotGeneratable:
            pak = None
        missing = [path for path in (*MEMBERS, CARRY) if not (ctx.root / path).is_file()]
        if missing:
            raise AssertionError(f'original tables missing: {missing}')
        if pak is not None:
            from hsltools.data.battle_rewards import curate_carry
            expected = {**imported(pak), CARRY: json_bytes(curate_carry(pak))}
            stale = [path for path, data in expected.items() if (ctx.root / path).read_bytes() != data]
            if stale:
                raise AssertionError(f'original tables differ from the PAK import: {stale}'
                                     ' — `python3 tools/hsl.py generate original_tables` rewrites them')
        print(f'ORIGINAL_TABLES_PASS files={len(MEMBERS) + 1} compared_with_pak={pak is not None}')

    def build(self, ctx: Context) -> None:
        pak = original_archive(ctx)
        for path, data in imported(pak).items():
            target = ctx.root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        from hsltools.data.battle_rewards import curate_carry  # reads the PLAYERS.TXT just written
        (ctx.root / CARRY).write_bytes(json_bytes(curate_carry(pak)))


def tasks() -> list[OriginalTablesTask]:
    return [OriginalTablesTask()]
