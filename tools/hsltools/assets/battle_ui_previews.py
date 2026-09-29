"""The battle UI shapes the game loads by name from content/imported/hsl/shared/shape_previews/battle_ui/
(ContentPaths.BATTLE_UI_PREVIEWS: BattleUISkin, BattleVitals, BattleSelectionCursor's I_RECT01, the
first-battle fixture's LEVEL51 map), decoded from the original PAK.

The chapter-one payload importer (tools/hsl_payload_inspector.py) first wrote these previews from a
resource-scan manifest kept outside the repository; this task decodes the same members straight from
hsl.pak (pixels identical to the tracked PNGs, which write_shp_preview keeps byte for byte), so a checkout
without them can import them.

Registry task battle_ui_previews (family assets): check = every listed preview is present; generate =
decode the members from the PAK.
"""
from pathlib import Path

from hsltools.registry import Context, ScriptCheckTask, original_archive
from hsltools.sources.pak import find_decoded_paks_packages, find_paks_record_by_name, read_paks_record_bytes
from hsltools.sources.shp import parse_shp, write_shp_preview

ROOT = Path('content/imported/hsl/shared/shape_previews/battle_ui')
SHAPES = (
    'BARH1_01', 'BAR_BLK1', 'BAR_BLK3', 'BAR_HP1', 'BAR_ST1',
    *(f'BCMD{number:02d}_1' for number in range(1, 16)),
    'BOARD02', 'BT_ADD1', 'BT_OK', 'B_NEXT1', 'B_PREV1', 'CURSOR01', 'ICONBOX', 'ICONRECT', 'I_RECT01',
    'KILL_000', 'NUM100', 'STAT0101', 'WIN02BAR', 'WIN06BAR',
    'WINDOW10', 'WINDOW20', 'WINDOW30', 'WINDOW40', 'WINDOW50', 'WINDOW60', 'WINDOW90',
)
# PAK folder of each shape: SHAPE\ except the level-51 map the first-battle fixture draws.
MEMBERS = {**{name: f'@:\\SHAPE\\{name}.SHP' for name in SHAPES}, 'LEVEL51': '@:\\SHAPE01\\LEVEL51.SHP'}


def target(name: str) -> Path:
    return ROOT / f'{name}.SHP.png'


def build(pak: Path) -> None:
    packages = find_decoded_paks_packages(pak)
    for name, member in MEMBERS.items():
        matches = [(package, record) for package in packages if (record := find_paks_record_by_name(package['records'], member))]
        if len(matches) != 1:
            raise ValueError('missing or ambiguous SHP: ' + member)
        package, record = matches[0]
        raw = read_paks_record_bytes(package['path'], record, data_end_offset=int(package['paks']['candidate_index_offset']))
        write_shp_preview(raw, parse_shp(raw), target(name))


def check() -> None:
    absent = [target(name).as_posix() for name in MEMBERS if not target(name).is_file()]
    assert not absent, f'{len(absent)} battle UI preview(s) absent, first={absent[0] if absent else ""}'
    print(f'BATTLE_UI_PREVIEWS_CHECK_PASS shapes={len(MEMBERS)}')


class BattleUIPreviewsTask(ScriptCheckTask):
    name = 'battle_ui_previews'
    family = 'assets'
    outputs = (ROOT.as_posix() + '/',)
    scripts = ('tools/hsltools/assets/battle_ui_previews.py',)

    def verify(self, ctx: Context) -> None:
        check()

    def build(self, ctx: Context) -> None:
        build(original_archive(ctx))


def tasks() -> list[BattleUIPreviewsTask]:
    return [BattleUIPreviewsTask()]
