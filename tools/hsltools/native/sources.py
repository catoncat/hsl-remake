"""Source-table inputs of the native probes: PLAYERS rows, ITEM rows, TYPE.H defines.

sources() -> (players by zero-padded code, items by int code, TYPE.H #define values plus the
job symbols authored formula rows declare — hsltools.model.jobs.authored_job_symbols — so an
authored character can name a job TYPE.H does not define).
Body moved verbatim from the former hsl_native_job_stats_probe.py.
"""
from __future__ import annotations

import re

from hsltools.model.jobs import authored_job_symbols
from hsltools.sources.tables import TABLES, blocks, character_rows


def sources():
    players = {r['code'].zfill(3):r for r in character_rows()}
    items = {int(r['code']):r for r in blocks((TABLES/'ITEM.TXT').read_bytes(),'item')}
    defines = {k:int(v,0) for k,v in re.findall(r'^\s*#define\s+(\w+)\s+(0x[0-9a-fA-F]+|\d+)\b',
               (TABLES/'TYPE.H').read_bytes().decode('cp950'),re.M)}
    defines.update(authored_job_symbols())
    return players,items,defines
