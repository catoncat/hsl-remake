"""Shared character/inventory panel assets and display fields from original tables.

Source categories and stats are data, not proof of native layout or loot rules.
CODES contains the original panel roster followed by all campaign actor roles with
reviewed source data; actor 039 remains in the legacy roster for its large-actor panel.

Registry task panel_assets (family assets): output content/imported/hsl/shared/panels/.
Bodies moved verbatim from the former hsl_panel_assets.py.
"""
import json
import struct
from pathlib import Path

from hsltools.data.ai_profiles import definitions as type_definitions
from hsltools.registry import Context, ScriptCheckTask, original_archive
from hsltools.sources.pak import find_decoded_paks_packages, find_paks_record_by_name, read_paks_record_bytes
from hsltools.sources.shp import parse_shp, png_sha256, write_shp_preview
from hsltools.sources.tables import TABLES, blocks, digest, parse_table

ROOT = Path('content/imported/hsl/shared/panels')
NAMES = Path('content/imported/hsl/chapter01/source_texts/RESOURCE.TXT')
NATIVE_STATS = Path('docs/evidence_packets/static_reverse/second_battle_template_stats.json')
LARGE_STATS = Path('docs/evidence_packets/static_reverse/original_large_actor.json')
CODES = ('1', '21', '23', '24', '25', '26', '39', '2', '4', '6', '28', '36', '3', '61', '62',
         '5', '7', '8', '9', '27', '30', '31', '32', '33', '34', '35', '37', '38', '41', '43', '44',
         '45', '48', '49', '51', '55', '56', '64', '65', '22', '50', '52', '53', '54', '57', '58', '59', '60', '66', '67', '68', '69',
         '10', '11', '12', '13', '14', '15', '16', '17', '18', '19', '20')
ICONS = {f'itemIcon{name}': f'SHAPE\\i_{name.lower()}.SHP'
         for name in ('Sword', 'Bow', 'Axe', 'Staff', 'Spear', 'Dagger', 'Claw', 'Sting', 'Helmet', 'Armor', 'Boot', 'Other', 'Use')}
MEMBERS = dict(ICONS, **{f'bar_hp{i}': f'SHAPE\\BAR_HP{i}.SHP' for i in range(1, 7)},
               **{f'bar_st{i}': f'SHAPE\\BAR_ST{i}.SHP' for i in range(1, 5)})
MEMBERS.update({name: 'SHAPE\\' + name + '.SHP' for name in ('WINDOW21', 'WINDOW31', 'WINDOW41', 'WINDOW70', 'BT_ADD2')})
# The five element gems (earth, water, wind, fire, mind): 0x42f4fc loads MAGICON1..5 into the
# handle table 0x4c3460 indexed by element 0..4; the identity strip's resist row shows one before
# each of its five values (docs/evidence_packets/runtime_observations/closeup_floaters/README.md).
MEMBERS.update({f'magicon{i}': f'SHAPE\\MAGICON{i}.SHP' for i in range(1, 6)})
# The section-title band: actShowSectionName (0x451818) loads SHAPE\LEVELSEC.SHP and 0x452f32 draws
# it subtractively behind the level's WORD name (docs/evidence_packets/static_reverse/original_tick_counts.md §2).
MEMBERS['LEVELSEC'] = 'SHAPE\\LEVELSEC.SHP'
# The list scroll bar 0x446060 (objects 150–153): arrow buttons BAR_UP／BAR_DOWN and the 2 px thumb
# foot BAR_BLK2 that 150's draw pass puts under the BAR_BLK1 thumb (WIN02BAR and BAR_BLK1 are
# already in shape_previews/battle_ui; docs/evidence_packets/runtime_observations/menus_ui/README.md §5).
MEMBERS.update({name: 'SHAPE\\' + name + '.SHP' for name in ('BAR_UP', 'BAR_DOWN', 'BAR_BLK2')})
EMPTY_CLAW = bytes.fromhex('544c4853000000000200000000000000ff07000000000000000000000000000000000000')


def definitions():
    names = parse_table(NAMES.read_bytes())
    stats = json.loads(NATIVE_STATS.read_text())
    for name, expected in stats['inputs_sha256'].items():
        if digest((TABLES / name).read_bytes()) != expected:
            raise ValueError('Native display-stat input changed: ' + name)
    players = {r['code']: r for r in blocks((TABLES / 'PLAYERS.TXT').read_bytes(), 'character')}
    types = type_definitions(TABLES / 'TYPE.H')
    from hsltools.probes.large_actor import check as check_large
    large = json.loads(LARGE_STATS.read_text());check_large(large)
    items = {r['code']: r for r in blocks((TABLES / 'ITEM.TXT').read_bytes(), 'item')}
    from hsltools.data.role_profiles import build as roles
    role_data=roles()['actors']
    used, actors = {'241', '246'}, {}
    def type_resource_id(value: str) -> str:
        return str(types[value]) if value in types else str(int(value, 0))

    for code in CODES:
        row = players[code]
        used.update(row[k] for k in row if k.endswith('_equip') and row[k] != '0')
        actors[code.zfill(3)] = {'mind': int(row['mind']), 'con': int(row['con']),
                               'magic_attack': int(large['stats'][0]['native'][0]['values']['magic_attack'] if code=='39' else role_data[code.zfill(3)]['initial']['magic_attack']),
                               'gold': int(row.get('gold', 0)), 'job': row['job'],
                               'title': names[row['job_show_name']] if 'job_show_name' in row else names[str(types[row['job']])],
                               'race': names[type_resource_id(row['class'])]}
    fields = ('attack_damage', 'hit_ratio', 'add_speed', 'add_defense', 'add_mp', 'add_hp', 'get_ratio')
    details = {code: {'name': names[items[code]['name']], 'icon': items[code]['icon'],
                      'type': items[code]['type'], 'fields': {k: int(items[code].get(k, 0)) for k in fields}}
               for code in sorted(used, key=int)}
    return {'actors': actors, 'items': details}


def build(pak):
    packages = find_decoded_paks_packages(pak)
    ROOT.mkdir(parents=True, exist_ok=True)
    data = {'schema': 'hsl_shared_panels.v1', 'evidence_tier': 'resource-derived',
            'sources': {p.as_posix(): digest(p.read_bytes()) for p in (TABLES / 'PLAYERS.TXT', TABLES / 'ITEM.TXT', TABLES / 'TYPE.H', NAMES, NATIVE_STATS, LARGE_STATS)},
            **definitions(), 'assets': {}}
    existing=json.loads((ROOT/'manifest.json').read_text()) if (ROOT/'manifest.json').exists() else {}
    for key, member in MEMBERS.items():
        matches = [(p, r) for p in packages if (r := find_paks_record_by_name(p['records'], '@:\\' + member))]
        if len(matches) != 1:
            raise ValueError('Missing or ambiguous panel asset: ' + member)
        package, record = matches[0]
        raw = read_paks_record_bytes(package['path'], record, data_end_offset=int(package['paks']['candidate_index_offset']))
        if key in ('itemIconClaw','itemIconSting'):
            if raw != EMPTY_CLAW:raise ValueError('Original empty creature weapon icon changed: '+key)
            # This is an actual zero-sized 36-byte SHP, not a missing PNG.
            # Keep the equipment name; no invented sword/claw graphic is drawn.
            data['assets'][key]={'source_member':member,'source_sha256':digest(raw),
                                 'source_bytes':raw.hex(),'empty':True,'res_path':'','draw_origin':[0,0]}
            continue
        target = ROOT / (key + '.png')
        previous=existing.get('assets',{}).get(key,{})
        if not (target.exists() and previous.get('source_sha256')==digest(raw) and previous.get('sha256')==png_sha256(target)):
            write_shp_preview(raw, parse_shp(raw), target)
        data['assets'][key] = {'source_member': member, 'source_sha256': digest(raw),
                              'res_path': 'res://' + target.as_posix(), 'sha256': png_sha256(target),
                              'draw_origin': list(struct.unpack_from('<ii', raw, 0x1c)), 'empty':False}
    (ROOT / 'manifest.json').write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')


def check():
    data = json.loads((ROOT / 'manifest.json').read_text())
    expected = definitions()
    assert data['schema'] == 'hsl_shared_panels.v1'
    assert all(data[k] == v for k, v in expected.items())
    assert data['sources'] == {p.as_posix(): digest(p.read_bytes()) for p in (TABLES / 'PLAYERS.TXT', TABLES / 'ITEM.TXT', TABLES / 'TYPE.H', NAMES, NATIVE_STATS, LARGE_STATS)}
    assert set(data['assets']) == set(MEMBERS)
    for key, asset in data['assets'].items():
        assert asset['source_member'] == MEMBERS[key]
        if key in ('itemIconClaw','itemIconSting'):
            assert asset['empty'] is True and asset['res_path']==''
            assert bytes.fromhex(asset['source_bytes'])==EMPTY_CLAW and asset['source_sha256']==digest(EMPTY_CLAW)
            continue
        assert asset['empty'] is False
        assert png_sha256(Path(asset['res_path'].removeprefix('res://'))) == asset['sha256']
    print('PANEL_ASSETS_CHECK_PASS')


class PanelAssetsTask(ScriptCheckTask):
    name = 'panel_assets'
    family = 'assets'
    inputs = ('content/imported/hsl/global/tables/', NAMES.as_posix(), NATIVE_STATS.as_posix(), LARGE_STATS.as_posix())
    outputs = (ROOT.as_posix() + '/',)
    replaces = ('tools/hsl_panel_assets.py --check',)
    scripts = ('tools/hsltools/assets/panel_assets.py', 'tools/hsltools/data/ai_profiles.py', 'tools/hsltools/probes/large_actor.py', 'tools/hsltools/data/role_profiles.py')

    def verify(self, ctx: Context) -> None:
        check()

    def build(self, ctx: Context) -> None:
        build(original_archive(ctx))


def tasks() -> list[PanelAssetsTask]:
    return [PanelAssetsTask()]
