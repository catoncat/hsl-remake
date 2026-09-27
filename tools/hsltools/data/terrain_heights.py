"""Retain exact WRD height bytes; offline checks reconstruct the original hash.

Registry task terrain_heights (family world, OriginalArchiveTask): validates the tracked
content/generated/hsl/static/hsl01/level051_terrain.json / level052_terrain.json packets; generate re-reads
them from hsl.pak (the legacy --pak path). Bodies moved verbatim from the former hsl_terrain_heights.py.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import struct

from hsltools.data import OriginalArchiveTask
from hsltools.levels.seed import _read_records, paths_for_level, record_names
from hsltools.registry import CheckFailed, Context
from hsltools.sources.wrd import decode_wrd

LEVELS = (51, 52)


def validate(packet: dict) -> None:
    if packet.get('schema') != 'hsl_wrd_terrain.v2':
        raise ValueError('Terrain requires retained source heights')
    form = packet['source_format']
    width, height = form['width'], form['height']
    if not 0 < width <= 256 or not 0 < height <= 256 or len(packet['grid']) != height:
        raise ValueError('Terrain dimensions differ')
    raw = bytearray(struct.pack('<4s5I', b'WORL', form['version'], form['flags'], width, height, 4))
    for row in packet['grid']:
        if len(row) != width: raise ValueError('Terrain row width differs')
        for cell in row:
            if type(cell.get('h')) is not int or not 0 <= cell['h'] <= 255 or type(cell.get('t')) is not int or not 0 <= cell['t'] <= 0xffffff:
                raise ValueError('Invalid source terrain cell')
            if cell.get('b') != int(cell['h'] == 255): raise ValueError('Terrain cliff marker differs from source height')
            raw.extend(struct.pack('<I', cell['t'] | cell['h'] << 24))
    if len(raw) != packet['source']['byte_length'] or hashlib.sha256(raw).hexdigest() != packet['source']['sha256']:
        raise ValueError('Terrain bytes no longer match the original WRD hash')
    decoded = decode_wrd(raw)
    if any(packet[key] != decoded[key] for key in decoded): raise ValueError('Terrain derived metadata differs')


def run(pak: Path | None) -> str:
    """The legacy body: validate (and with pak, regenerate) both packets; returns the PASS line."""
    records = _read_records(pak, {str(level): record_names(level)['terrain'] for level in LEVELS}) if pak else {}
    for level in LEVELS:
        path = paths_for_level(level)['terrain']
        packet = json.loads(path.read_text())
        if pak:
            record = records[str(level)]
            if record['sha256'] != packet['source']['sha256']: raise ValueError('Original terrain identity changed')
            decoded = decode_wrd(record['data'])
            decoded['source'] = packet['source']
            validate(decoded)
            path.write_text(json.dumps(decoded, ensure_ascii=False, indent=2) + '\n')
            packet = decoded
        validate(packet)
    return f'TERRAIN_HEIGHTS_PASS levels={list(LEVELS)} original_read_now={bool(pak)}'


class TerrainHeightsTask(OriginalArchiveTask):
    name = 'terrain_heights'
    family = 'world'
    inputs = ()  # validation only reads the packets themselves; regeneration reads hsl.pak
    outputs = tuple(paths_for_level(level)['terrain'].as_posix() for level in LEVELS)
    replaces = ('tools/hsl_terrain_heights.py',)
    scripts = ('tools/hsltools/data/terrain_heights.py', 'tools/hsltools/levels/seed.py', 'tools/hsltools/sources/wrd.py')

    def verify(self, ctx: Context) -> str:
        try:
            return run(None)
        except ValueError as error:
            raise CheckFailed(f'{self.name}: {error}') from error

    def rebuild(self, ctx: Context) -> None:
        run(self.archive)


def tasks() -> list[TerrainHeightsTask]:
    return [TerrainHeightsTask()]
