"""Import the original reward-float art: KILL N, EXP N, $ N and LEVEL UP, the LEVEL UP star, the
red damage digits with their flash, the green heal／blue MP digits and MISS; offline validation
needs no Wine.

defProcShowNumber (0x408580) draws kind 1 (EXP) as NUM511 then NUM400..409 digits, kind 4 ($)
as NUM512 then NUM500..509, kind 6 as NUM514 alone; defProcShowContinueKillNumber (0x4083e0,
object 395 whose shape is KILL_000.SHP with 11 frames) draws KILL_000 then KILL_001..010 for
the digits 0..9 (static-derived, docs/evidence_packets/runtime_observations/cutin_floaters/
README.md). Kind 0 (red damage) draws NUM100..109 with NUM510 as the zoomed flash of the newest
digit (0x40863e..0x40888e: frame base + digit, base + 0x32); kind 2 (heal) draws NUM200..209 and kind 3
(MP) NUM300..309 with no prefix glyph (0x4088b0／0x408929: frame base 10／0x14, prefix units 0); kind 5
clears the digit string and draws NUM513 (MISS, frame 0x35) alone at (x, y) by its draw origin; kind 6 scatters obj_LevelUp_Star 149,
whose shape is MAGIC\\AIR06_03.SHP with 4 frames (0x408b20 case 3 → 0x415c10; static-derived,
docs/evidence_packets/runtime_observations/map_pose_floaters/README.md). Pixels and draw origins
are decoded from hsl.pak (resource-derived).

Registry task reward_floats (family assets): output content/imported/hsl/shared/reward_floats/.
"""
import hashlib
import json
import struct
from pathlib import Path

from PIL import Image
from hsltools.registry import Context, ScriptCheckTask, original_archive
from hsltools.sources.pak import find_decoded_paks_packages, find_paks_record_by_name, read_paks_record_bytes
from hsltools.sources.shp import parse_shp, png_sha256, write_shp_preview

ROOT = Path('content/imported/hsl/shared/reward_floats')
SCHEMA = 'hsl_reward_floats.v1'
MEMBERS = {'kill': 'SHAPE\\KILL_000.SHP', 'exp': 'SHAPE\\NUM511.SHP', 'gold': 'SHAPE\\NUM512.SHP',
           'level_up': 'SHAPE\\NUM514.SHP'}
MEMBERS.update({f'kill_digit_{d}': f'SHAPE\\KILL_{d + 1:03d}.SHP' for d in range(10)})
MEMBERS.update({f'exp_digit_{d}': f'SHAPE\\NUM4{d:02d}.SHP' for d in range(10)})
MEMBERS.update({f'gold_digit_{d}': f'SHAPE\\NUM5{d:02d}.SHP' for d in range(10)})
MEMBERS.update({f'damage_digit_{d}': f'SHAPE\\NUM1{d:02d}.SHP' for d in range(10)})
MEMBERS.update({f'heal_digit_{d}': f'SHAPE\\NUM2{d:02d}.SHP' for d in range(10)})
MEMBERS.update({f'mp_digit_{d}': f'SHAPE\\NUM3{d:02d}.SHP' for d in range(10)})
MEMBERS['damage_flash'] = 'SHAPE\\NUM510.SHP'
MEMBERS['miss'] = 'SHAPE\\NUM513.SHP'
MEMBERS.update({f'level_up_star_{f}': f'MAGIC\\AIR06_{f + 3:02d}.SHP' for f in range(4)})
# Layout constants of the two draw routines (static-derived; the runtime reads them from here).
LAYOUT = {
    'show_number': {'pitch': 14, 'prefix_units': {'exp': 4, 'gold': 2, 'heal': 0, 'mp': 0}, 'lift': 48,
                    'note': '0x408580: first glyph at x − ((digits − 1) + prefix_units) × pitch／2, the prefix advances '
                            'prefix_units × pitch, each digit pitch; EXP／$ spawned by 0x442720 at the recipient '
                            '(x, y − 48); heal／MP (kinds 2／3, 0x4088b0／0x408929) carry no prefix'},
    'kill': {'first_digit': 114, 'digit_pitch': 38, 'left_per_digit': 19, 'left_base': 38, 'lift': 24, 'ticks': 40,
             'note': '0x4083e0: KILL at x − (19 × digits + 38), first digit +114, each next +38, held 40 ticks '
                     'without rising; spawned by the victim\'s dead branch (0x43f0aa／0x4435c5) at (x, y − 24) '
                     'when the killer\'s chain word is above 1'},
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def build(pak):
    packages = find_decoded_paks_packages(pak)
    ROOT.mkdir(parents=True, exist_ok=True)
    assets = {}
    for key, member in MEMBERS.items():
        matches = [(p, r) for p in packages if (r := find_paks_record_by_name(p['records'], '@:\\' + member))]
        if len(matches) != 1:
            raise ValueError('Missing or ambiguous reward float art: ' + member)
        package, record = matches[0]
        raw = read_paks_record_bytes(package['path'], record, data_end_offset=int(package['paks']['candidate_index_offset']))
        target = ROOT / (key + '.png')
        write_shp_preview(raw, parse_shp(raw), target)
        with Image.open(target) as image:
            size = list(image.size)
        assets[key] = {'source_member': member, 'source_sha256': digest(raw), 'res_path': 'res://' + target.as_posix(),
                       'sha256': png_sha256(target), 'size': size, 'draw_origin': list(struct.unpack_from('<ii', raw, 0x1c))}
    result = {'schema': SCHEMA, 'evidence_tier': 'resource-derived', 'layout': LAYOUT, 'assets': assets}
    (ROOT / 'manifest.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')


def check():
    data = json.loads((ROOT / 'manifest.json').read_text())
    assert data['schema'] == SCHEMA
    assert data['layout'] == LAYOUT
    assert set(data['assets']) == set(MEMBERS)
    for key, asset in data['assets'].items():
        assert asset['source_member'] == MEMBERS[key]
        path = Path(asset['res_path'].removeprefix('res://'))
        assert png_sha256(path) == asset['sha256'], path
        with Image.open(path) as image:
            assert list(image.size) == asset['size']
    print('REWARD_FLOATS_CHECK_PASS')


class RewardFloatsTask(ScriptCheckTask):
    name = 'reward_floats'
    family = 'assets'
    inputs = ()
    outputs = (ROOT.as_posix() + '/',)
    scripts = ('tools/hsltools/assets/reward_floats.py',)

    def verify(self, ctx: Context) -> None:
        check()

    def build(self, ctx: Context) -> None:
        build(original_archive(ctx))


def tasks() -> list[RewardFloatsTask]:
    return [RewardFloatsTask()]
