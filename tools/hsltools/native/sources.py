"""Source-table inputs of the native probes and the role generators: PLAYERS rows, ITEM rows, TYPE.H defines.

sources() -> (players by zero-padded code, items by int code, TYPE.H #define values plus the
job symbols authored formula rows declare — hsltools.model.jobs.authored_job_symbols — so an
authored character can name a job TYPE.H does not define). The generators read it with the
authored table overlay (hsltools.sources.tables.table_rows); the native parity probes import
original_sources(), the same triple over the bare imported tables, since they check the original.
Body moved verbatim from the former hsl_native_job_stats_probe.py.
"""
from __future__ import annotations

import re

from hsltools.model.jobs import authored_job_symbols
from hsltools.sources.tables import TABLES, authored_characters, blocks, character_rows, table_rows


def _triple(players, items):
    defines = {k:int(v,0) for k,v in re.findall(r'^\s*#define\s+(\w+)\s+(0x[0-9a-fA-F]+|\d+)\b',
               (TABLES/'TYPE.H').read_bytes().decode('cp950'),re.M)}
    defines.update(authored_job_symbols())
    return {r['code'].zfill(3):r for r in players},{int(r['code']):r for r in items},defines


def sources():
    return _triple(character_rows(), table_rows('ITEM.TXT'))


def original_sources():
    return _triple(blocks((TABLES/'PLAYERS.TXT').read_bytes(),'character') + authored_characters(),
                   blocks((TABLES/'ITEM.TXT').read_bytes(),'item'))
