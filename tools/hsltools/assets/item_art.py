"""Import original inventory category/slot art; offline validation needs no Wine.

Registry task item_art (family assets): output content/imported/hsl/chapter01/item_art/.
Bodies moved verbatim from the former hsl_item_art.py.
"""
import hashlib
import json
import struct
from pathlib import Path

from PIL import Image
from hsltools.registry import Context, ScriptCheckTask, original_archive
from hsltools.sources.pak import find_decoded_paks_packages, find_paks_record_by_name, read_paks_record_bytes
from hsltools.sources.shp import parse_shp, png_sha256, write_shp_preview
from hsltools.sources.tables import TABLES, table_rows

ROOT = Path('content/imported/hsl/chapter01/item_art')
MEMBERS = {'consumable': 'SHAPE\\i_use.SHP', 'slot': 'SHAPE\\ICONBOX.SHP', 'selection': 'SHAPE\\ICONRECT.SHP'}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def bindings():
    items = table_rows('ITEM.TXT')
    result = {row['code']: row['icon'] for row in items if row['code'] in ('241', '246')}
    assert result == {'241': 'itemIconUse', '246': 'itemIconUse'}
    return result


def build(pak):
    packages = find_decoded_paks_packages(pak)
    ROOT.mkdir(parents=True, exist_ok=True)
    assets = {}
    for key, member in MEMBERS.items():
        matches = [(p, r) for p in packages if (r := find_paks_record_by_name(p['records'], '@:\\' + member))]
        if len(matches) != 1:
            raise ValueError('Missing or ambiguous inventory art: ' + member)
        package, record = matches[0]
        raw = read_paks_record_bytes(package['path'], record, data_end_offset=int(package['paks']['candidate_index_offset']))
        target = ROOT / (key + '.png')
        write_shp_preview(raw, parse_shp(raw), target)
        with Image.open(target) as image:
            size = list(image.size)
        assets[key] = {'source_member': member, 'source_sha256': digest(raw), 'res_path': 'res://' + target.as_posix(), 'sha256': png_sha256(target), 'size': size, 'draw_origin': list(struct.unpack_from('<ii', raw, 0x1c))}
    result = {'schema': 'hsl_first_battle_item_art.v1', 'evidence_tier': 'resource-derived', 'item_categories': bindings(), 'assets': assets,
              'use_contract': 'Original shared consumable category art and slot frames, selected for the remake item panel; not individual potion artwork or native layout/handler parity.'}
    (ROOT / 'manifest.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')


def check():
    data = json.loads((ROOT / 'manifest.json').read_text())
    assert data['schema'] == 'hsl_first_battle_item_art.v1'
    assert data['item_categories'] == bindings()
    assert set(data['assets']) == set(MEMBERS)
    for key, asset in data['assets'].items():
        assert asset['source_member'] == MEMBERS[key]
        path = Path(asset['res_path'].removeprefix('res://'))
        assert png_sha256(path) == asset['sha256'], path
        with Image.open(path) as image:
            assert list(image.size) == asset['size']
    print('ITEM_ART_CHECK_PASS')


class ItemArtTask(ScriptCheckTask):
    name = 'item_art'
    family = 'assets'
    inputs = ((TABLES / 'ITEM.TXT').as_posix(),)
    outputs = (ROOT.as_posix() + '/',)
    replaces = ('tools/hsl_item_art.py --check',)
    scripts = ('tools/hsltools/assets/item_art.py',)

    def verify(self, ctx: Context) -> None:
        check()

    def build(self, ctx: Context) -> None:
        build(original_archive(ctx))


def tasks() -> list[ItemArtTask]:
    return [ItemArtTask()]
