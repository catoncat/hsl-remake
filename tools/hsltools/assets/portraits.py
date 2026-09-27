"""Extract the shared status-panel portraits bound by PLAYERS.TXT picture fields.

The shared manifest is indexed by actor id from BattleGiveView / BattlePresentation /
PartyEquipmentScreen, so every actor that can stand in a registered battle needs a row here:
the nine party slots, the chapter-1 enemies and the monster codes of the random encounters
501-578 plus the chapter-2 casts. The row's `name` is the remake's list label (give view,
party screen, defeat line): the PLAYERS.TXT `name` field resolved through RESOURCE.TXT (a
resource id, or a resource.h `name_N` symbol for the party slots), except that rows whose name
is the shared placeholder 306 「???」 (nameless soldiers and monsters) are labelled by their
`job_show_name` (remake display choice for those remake screens). Named NPC rows (064 克里夫
1270, 025 法蘭克 382, 053 克羅蒂 name_8, 054–060 …) therefore keep their names.
The identity strip (WINDOW10 hover／cut-in／status page) prints `panel_name` instead: the
live +0x04 name id resolved verbatim, as 0x434d10 does through 0x4477b0 — 306 prints 「???」
even on a known unit (docs/evidence_packets/static_reverse/original_identity_bar.md; lead
decision 2026-09-26). Extract new rows with --actors so tracked PNG bytes stay put.

Registry task actor_portraits (family assets): output content/imported/hsl/chapter01/portraits/.
Bodies moved verbatim from the former hsl_actor_portraits.py.
"""
import json
from pathlib import Path

from hsltools.registry import Context, ScriptCheckTask, original_archive
from hsltools.sources.pak import find_decoded_paks_packages, find_paks_record_by_name, read_paks_record_bytes
from hsltools.sources.shp import parse_shp, png_sha256, write_shp_preview
from hsltools.sources.tables import TABLES, blocks, digest, parse_table

ROOT = Path('content/imported/hsl/chapter01/portraits')
NAMES = Path('content/imported/hsl/chapter01/source_texts/RESOURCE.TXT')
RESOURCE_HEADER = TABLES / 'resource.h'
# RESOURCE.TXT 306: the shared 「???」 name of every PLAYERS row without a proper name.
UNNAMED_RESOURCE_ID = '306'
NAME_POLICY = ('PLAYERS.TXT name field (resource id or resource.h name_N symbol) resolved through RESOURCE.TXT; '
               'rows whose name is the shared placeholder 306 ??? show their job_show_name (remake display choice)')
ACTORS = ('001', '021', '023', '024', '025', '026', '039', '002', '004', '006', '028', '036', '003', '061', '062',
          '005', '007', '008', '009',
          '027', '030', '031', '032', '033', '034', '035', '037', '038', '041', '043', '044', '045', '048', '049',
          '051', '055', '056', '064', '065', '022', '050', '052', '053', '054', '057', '058', '059', '060', '066', '067', '068',
          # 069 (level-52 winged warrior): its own PLAYERS row declares SHAPE\FACE0022.SHP.
          '069',
          # 緹娜's second title 020 公主 is the only job-up row with its own face (FACE0020); rows
          # 010-019 repeat the base FACE000x and are served by the member's base portrait.
          '020')


def resource_defines() -> dict[str, str]:
    """resource.h `#define name_N <id>` symbols the PLAYERS name field may use."""
    defines = {}
    for line in RESOURCE_HEADER.read_text(encoding='latin-1').splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[0] == '#define':
            defines[parts[1]] = parts[2]
    return defines


def name_resource_id(row: dict, defines: dict[str, str]) -> str:
    field = row['name'].strip()
    return field if field.isdigit() else defines[field]


def panel_name(row: dict, names: dict[str, str], defines: dict[str, str], name_id: str | None = None) -> str:
    """The 姓名 text the identity strip prints for one live record: the RESOURCE text of its
    +0x04 name id verbatim (0x434d10 → 0x4477b0(+4)), 306 → 「???」. `name_id` is an installed
    override of +0x04 (obj_Data5 high word at 0x407ec0, or actSetPlayerName at 0x451590);
    without one the row's own PLAYERS name field."""
    return names[name_id or name_resource_id(row, defines)]


def display_name(row: dict, names: dict[str, str], defines: dict[str, str]) -> str:
    """The list label of one PLAYERS row (module doc: name field, 306 ??? → job_show_name)."""
    live_name_id = name_resource_id(row, defines)
    if live_name_id != UNNAMED_RESOURCE_ID:
        return names[live_name_id]
    return names[row['job_show_name']]


def bindings():
    players = {int(row['code']): row for row in blocks((TABLES / 'PLAYERS.TXT').read_bytes(), 'character')}
    names = parse_table(NAMES.read_bytes())
    defines = resource_defines()
    return {code: {'source_member': players[int(code)]['picture'],
                   'name': display_name(players[int(code)], names, defines)}
            for code in ACTORS}


def build(pak, selected=None):
    packages = find_decoded_paks_packages(pak)
    result = {'schema': 'hsl_actor_portraits.v1', 'evidence_tier': 'resource-derived',
              'players_sha256': digest((TABLES / 'PLAYERS.TXT').read_bytes()),
              'names_sha256': digest(NAMES.read_bytes()), 'name_policy': NAME_POLICY, 'actors': bindings(),
              'presentation': 'Original SHP pixels; modern status-panel placement, not native UI parity.'}
    if selected is not None:
        existing=json.loads((ROOT/'manifest.json').read_text())
        for code,row in existing['actors'].items():result['actors'][code]=row
    for code in result['actors'] if selected is None else selected:
        row=result['actors'][code]
        matches = [(p, r) for p in packages if (r := find_paks_record_by_name(p['records'], '@:\\' + row['source_member']))]
        if len(matches) != 1:
            raise ValueError('Missing or ambiguous portrait: ' + row['source_member'])
        package, record = matches[0]
        raw = read_paks_record_bytes(package['path'], record, data_end_offset=int(package['paks']['candidate_index_offset']))
        target = ROOT / (code + '.png')
        write_shp_preview(raw, parse_shp(raw), target)
        row.update({'res_path': 'res://' + target.as_posix(), 'source_sha256': digest(raw),
                    'png_sha256': png_sha256(target)})
    (ROOT / 'manifest.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')


def check():
    result = json.loads((ROOT / 'manifest.json').read_text())
    assert result['players_sha256'] == digest((TABLES / 'PLAYERS.TXT').read_bytes())
    assert result['names_sha256'] == digest(NAMES.read_bytes())
    assert result.get('name_policy') == NAME_POLICY, 'portrait manifest name_policy differs; regenerate'
    assert set(result['actors']) == set(ACTORS)
    for code, binding in bindings().items():
        row = result['actors'][code]
        assert all(row[key] == value for key, value in binding.items())
        assert row['res_path'] == 'res://' + (ROOT / (code + '.png')).as_posix()
        assert png_sha256(Path(row['res_path'].removeprefix('res://'))) == row['png_sha256']
    print('ACTOR_PORTRAITS_CHECK_PASS')


class ActorPortraitsTask(ScriptCheckTask):
    name = 'actor_portraits'
    family = 'assets'
    inputs = ('content/imported/hsl/global/tables/PLAYERS.TXT', NAMES.as_posix(), RESOURCE_HEADER.as_posix())
    outputs = (ROOT.as_posix() + '/',)
    replaces = ('tools/hsl_actor_portraits.py --check',)
    scripts = ('tools/hsltools/assets/portraits.py',)

    def verify(self, ctx: Context) -> None:
        check()

    def build(self, ctx: Context) -> None:
        # Whole rebuild: a different PNG encoder would rewrite every tracked portrait; add
        # rows with the script's --actors instead (see module doc).
        build(original_archive(ctx))


def tasks() -> list[ActorPortraitsTask]:
    return [ActorPortraitsTask()]
