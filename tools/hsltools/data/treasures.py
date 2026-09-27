"""Source EVEF contents for the already-playable Ohm and Gol battle chests.

Registry task treasure_data (family items): output content/generated/hsl/treasures/battles.json.
Bodies moved verbatim from the former hsl_treasure_data.py.
"""
from __future__ import annotations
import json
from pathlib import Path
from hsltools.probes.treasure import PACKET, check
from hsltools.data import json_bytes
from hsltools.data.equipment import build as equipment_data
from hsltools.paths import ROOT
from hsltools.registry import Context, GeneratedFilesTask

OUTPUT = ROOT / 'content/generated/hsl/treasures/battles.json'
RESOURCE = 'res://' + OUTPUT.relative_to(ROOT).as_posix()
# PROCESS.DEF objattr* values; 0x415730 keeps the chest's shape only when the template's
# obj_Attribute carries objattrATTACKFLAG, otherwise the shape word becomes 0xffff
# (docs/evidence_packets/static_reverse/original_treasure.md §隐藏宝物).
OBJATTR = {'objattrATTACKFLAG': 0x10000, 'objattrPARENT': 0x40000000, 'objattrFLAG6': 0x200,
           'objattrFLAG7': 0x100, 'objattrATTACKFLAG_FLAG7': 0x10100}


def chest_hidden(record: dict) -> bool:
    """A seed chest record is a hidden treasure unless its template's obj_Attribute holds 0x10000."""
    tokens = [t.strip() for t in str(record.get('object_data_fields', {}).get('obj_Attribute', '')).split('|') if t.strip()]
    if any(t not in OBJATTR for t in tokens):
        raise ValueError(f'chest record {record.get("record_index")}: unknown obj_Attribute {tokens}')
    return not any(OBJATTR[t] & 0x10000 for t in tokens)


def build() -> dict:
    proof = json.loads(PACKET.read_text())
    check(proof)
    items = equipment_data()['items']
    levels = {}
    for source in proof['sources']['levels']:
        level = source['level']
        seed = json.loads((ROOT / ('content/generated/hsl/chapter01/battle%03d_seed.json' % level)).read_text())
        manifest = json.loads((ROOT / ('content/imported/hsl/chapter01/battle%03d/map_objects.json' % level)).read_text())
        rows = []
        for box in source['chests']:
            placed = next(r for r in seed['placements']['records'] if r['record_index'] == box['record_index'])
            if placed['object_process'] != 'defProcTreasureBox' or placed['placement_xy_candidate'] != box['pixel']:
                raise ValueError('Chest instance no longer matches the formal map')
            drawn = next(r for r in manifest['placements'] if r['record_index'] == box['record_index'])
            if drawn['role'] != 'treasure_box': raise ValueError('Source box has no existing visual placement')
            if any(str(code) not in items for code in box['items']): raise ValueError('Unknown original chest item')
            coord = [v // 32 for v in box['pixel']]
            width, height = seed['terrain']['grid_size']
            if not (0 <= coord[0] < width and 0 <= coord[1] < height): raise ValueError('Unsupported outside-map chest')
            rows.append(dict(id='%d:%d' % (level, box['record_index']), record_index=box['record_index'],
                             coord=coord, items=box['items'], shape_resource_id=drawn['shape_resource_id'],
                             hidden=chest_hidden(placed)))
        levels[str(level)] = dict(level=level, level_sha256=source['sha256'], obs_sha256=source['obs_sha256'], chests=rows)
    return dict(schema='hsl_battle_treasures.v1', evidence_tier='resource-derived', levels=levels,
                evidence='docs/evidence_packets/static_reverse/original_treasure.json',
                limits=['Content is the eight original EVEF override words; zeros are skipped and duplicate codes retain their quantity.',
                        'hidden: the template obj_Attribute lacks objattrATTACKFLAG, so 0x415730 draws no box and contact plays sfxGetTreasure before collection.',
                        'Only formal levels1/2 are enabled here; no extra default items, actors or boxes are added.'])


class TreasureDataTask(GeneratedFilesTask):
    name = 'treasure_data'
    family = 'items'
    inputs = ('docs/evidence_packets/static_reverse/original_treasure.json', 'content/generated/hsl/equipment/items.json',
              'content/generated/hsl/chapter01/battle001_seed.json', 'content/generated/hsl/chapter01/battle002_seed.json',
              'content/imported/hsl/chapter01/battle001/map_objects.json', 'content/imported/hsl/chapter01/battle002/map_objects.json')
    outputs = (OUTPUT.relative_to(ROOT).as_posix(),)
    replaces = ('tools/hsl_treasure_data.py --check',)
    scripts = ('tools/hsltools/data/treasures.py', 'tools/hsltools/probes/treasure.py')

    def render(self, ctx: Context) -> dict[str, bytes]:
        return {self.outputs[0]: json_bytes(build())}

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        return 'TREASURE_DATA_PASS levels=2 chests=3 hidden=3 source_items=8'


def tasks() -> list[TreasureDataTask]:
    return [TreasureDataTask()]
