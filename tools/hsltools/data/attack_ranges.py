"""Compile normal-weapon RANGE masks used by the current chapter battle slices.

Registry task attack_ranges (family items): output content/generated/hsl/chapter01/attack_ranges.json
(ASCII-escaped JSON, as the script always wrote it). Bodies moved verbatim from the former hsl_attack_ranges.py.
"""
import hashlib
import json
import re
from pathlib import Path

from hsltools.data import json_bytes
from hsltools.registry import GeneratedFilesTask, Context
from hsltools.sources.tables import override_rows

SOURCE = Path('content/imported/hsl/global/tables/RANGE.TXT')
OUTPUT = Path('content/generated/hsl/chapter01/attack_ranges.json')
ITEM_SOURCE = Path('content/imported/hsl/global/tables/ITEM.TXT')
# ITEM loader 0x447a5e reads attack_range through 0x4466d0 into ITEM+0x84; 0x409090 returns that index
# (+1 with the range-extension bit, +0x11 capped 20 for large actors) and 0x40f8b0 floods the RANGE row
# generically, so range6CellShoot (71 朧月) needs no shape of its own. Extension reaches range7CellShoot.
WEAPON_SELECTED = ('range0Cell', 'range1Cell', 'range2Cell', 'range3CellShoot', 'range4CellShoot', 'range5CellShoot',
                    'range6CellShoot', 'range3CellCircle', 'range3CellThrust', 'range5CellCircle')
SELECTED = (*WEAPON_SELECTED, 'range2CellCircle', 'range3Cell', 'range7CellShoot', 'range2CellFull', 'range3CellFull', 'range4CellFull',
            'range4CellCircle', 'range6CellCircle', 'range1CellFull', 'range3CellDir', 'range4CellDir')
# RANGE.H "N Line"/"E Line" symbols: size=N rows of one value. 0x4100e0 (indices 21..23) does not
# read the rows; it writes a straight N-cell line from the chosen cell away from the caster.
LINE_SELECTED = ('range3CellDir', 'range4CellDir')
INDEX_SOURCE = SOURCE.with_name('RANGE.H')


def compile_ranges(text: str) -> dict:
    records = {}
    indices = {key:int(value) for key,value in re.findall(r'^#define\s+(range\w+)\s+(\d+)', INDEX_SOURCE.read_bytes().decode('cp950'), re.M)}
    for block in text.split('[range]')[1:]:
        fields = {}
        rows = []
        for line in block.splitlines():
            line = line.split(';', 1)[0].split('//', 1)[0].strip()
            if '=' not in line:
                continue
            key, value = (part.strip() for part in line.split('=', 1))
            if key == 'data':
                rows.append([int(cell) for cell in value.split(',')])
            else:
                fields[key] = value
        code = fields.get('code')
        if code not in SELECTED:
            continue
        size = int(fields['size'])
        if code in LINE_SELECTED:
            if size < 1 or len(rows) != size or any(len(row) != 1 for row in rows) or [row[0] for row in rows] != list(range(size, 0, -1)):
                raise ValueError(f'invalid line mask: {code}')
            records[code] = {'index': indices[code], 'size': size, 'shape': 'line', 'values': [row[0] for row in rows]}
            continue
        if size % 2 != 1 or len(rows) != size or any(len(row) != size for row in rows):
            raise ValueError(f'invalid square mask: {code}')
        if any(value < 0 for row in rows for value in row) and code not in ('range3CellShoot','range4CellShoot','range5CellShoot','range6CellShoot','range7CellShoot'):
            raise ValueError(f'unsupported signed mask: {code}')
        center = size // 2
        # 'data' keeps the signed rows: the original 0x40f8b0/0x40f5d0 flood reads every value (a negative
        # cell carries the flood without being written, a zero cell stops it), not only the positive offsets.
        records[code] = {'index':indices[code], 'size': size, 'offsets': [[x - center, y - center] for y, row in enumerate(rows) for x, value in enumerate(row) if value > 0 and (x, y) != (center, center)], 'data': rows}
    if set(records) != set(SELECTED):
        raise ValueError('missing first-battle weapon range')
    return records


def weapon_ranges(text: str) -> dict:
    result = {'0':'range0Cell'}  # Native409090 returns0 for no weapon, even with range extension.
    for fields in override_rows('ITEM.TXT', [dict(re.findall(r'^\s*(\w+)\s*=\s*([^;\r\n]+)', block, re.M)) for block in text.split('[item]')[1:]]):
        code = fields.get('code', '').strip()
        if fields.get('type', '').strip() == 'itemTypeWeapon' and fields.get('attack_range', '').strip() in WEAPON_SELECTED:
            result[code] = fields['attack_range'].strip()
    if not {'1', '2', '3', '5', '41', '81'}.issubset(result) or any(value not in SELECTED for value in result.values()):
        raise ValueError('missing or unsupported chapter battle weapon range')
    return result


def build():
    raw = SOURCE.read_bytes()
    result = {'schema': 'hsl_first_battle_attack_ranges.v1', 'evidence_tier': 'resource-derived', 'source': str(SOURCE), 'source_sha256': hashlib.sha256(raw).hexdigest(), 'patterns': compile_ranges(raw.decode('cp950')), 'index_source':str(INDEX_SOURCE), 'index_sha256':hashlib.sha256(INDEX_SOURCE.read_bytes()).hexdigest(), 'unresolved_semantics': ['legacy schema name retained for compatibility; current weapon join includes bow61', 'signed shooting3/4 masks exclude close negative cells, verified by original_bow_range full builders; no weapon selects range0 and therefore has no hostile normal target; the original 0x4000 wall and occupant-side propagation over these rows is game/sim/RangePropagationRules.gd (original_weapon_ranges.md); heights are never read by the range builders']}
    item_raw = ITEM_SOURCE.read_bytes()
    result['weapon_source'] = str(ITEM_SOURCE)
    result['weapon_source_sha256'] = hashlib.sha256(item_raw).hexdigest()
    result['weapons'] = weapon_ranges(item_raw.decode('cp950'))
    return result


class AttackRangesTask(GeneratedFilesTask):
    name = 'attack_ranges'
    family = 'items'
    inputs = (SOURCE.as_posix(), ITEM_SOURCE.as_posix(), INDEX_SOURCE.as_posix())
    outputs = (OUTPUT.as_posix(),)
    replaces = ('tools/hsl_attack_ranges.py --check',)
    scripts = ('tools/hsltools/data/attack_ranges.py',)

    def render(self, ctx: Context) -> dict[str, bytes]:
        return {OUTPUT.as_posix(): json_bytes(build(), ensure_ascii=True)}

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        return 'ATTACK_RANGES_CHECK_PASS'


def tasks() -> list[AttackRangesTask]:
    return [AttackRangesTask()]
