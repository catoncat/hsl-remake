"""Import level-51 fire frames and preserve native OBS animation parameters.

Registry task fire_animation (family assets): output content/imported/hsl/chapter01/fire_animation/.
Bodies moved from the former hsl_fire_animation.py (its main() split into check() / build(pak)
statement-for-statement).
"""
import hashlib
import json
import re
import struct
from pathlib import Path

from hsltools.registry import Context, ScriptCheckTask, original_archive
from hsltools.sources.pak import find_decoded_paks_packages, find_paks_record_by_name, read_paks_record_bytes
from hsltools.sources.shp import parse_shp, write_shp_preview
ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'content/imported/hsl/chapter01/fire_animation'


def check():
    m = json.loads((OUT / 'manifest.json').read_text())
    assert len(m['frames']) == int(m['source_fields']['obj_Shape_Number'])
    assert m['frame_ticks'] == int(m['source_fields']['obj_Shape_Delay']) + 1
    assert m['scale'] == [int(m['source_fields'][key], 0) / 65536 for key in ['obj_ZoomX', 'obj_ZoomY']]
    assert len({f['texture'] for f in m['frames']}) == 10
    assert all(len(f['draw_origin']) == 2 for f in m['frames'])
    for f in m['frames']:
        p = ROOT / f['texture'].removeprefix('res://')
        assert hashlib.sha256(p.read_bytes()).hexdigest() == f['png_sha256']
    print('FIRE_ANIMATION_CHECK_PASS')


def build(pak):
    pkgs = find_decoded_paks_packages(pak)
    def read(member):
        matches = [(p, r) for p in pkgs if (r := find_paks_record_by_name(p['records'], member))]
        if len(matches) != 1:
            raise ValueError('missing or ambiguous resource: ' + member)
        p, r = matches[0]
        return read_paks_record_bytes(p['path'], r, data_end_offset=int(p['paks']['candidate_index_offset']))
    raw = read('@:\\DATA\\OBJ-051.OBS')
    blocks = raw.decode('cp950').split('[Object]')
    block = next(b for b in blocks if re.search(r'^obj_code\s*=\s*22\s*$', b, re.M))
    fields = {k: v.strip() for k, v in re.findall(r'^(obj_\w+)\s*=\s*([^;\r\n]+)', block, re.M)}
    OUT.mkdir(parents=True, exist_ok=True)
    frames = []
    for index in range(1, int(fields['obj_Shape_Number']) + 1):
        member = f'@:\\SHAPE01\\FIRE01-{index:02}.SHP'
        payload = read(member)
        p = OUT / f'FIRE01-{index:02}.png'
        write_shp_preview(payload, parse_shp(payload), p)
        frames.append({'source_member': member, 'source_sha256': hashlib.sha256(payload).hexdigest(),
            'texture': 'res://' + p.relative_to(ROOT).as_posix(),
            'png_sha256': hashlib.sha256(p.read_bytes()).hexdigest(),
            'draw_origin': list(struct.unpack_from('<ii', payload, 28))})
    m = {'schema': 'hsl_fire_animation.v1', 'source_sha256': hashlib.sha256(raw).hexdigest(),
        'source_fields': fields, 'frames': frames, 'frame_ticks': int(fields['obj_Shape_Delay']) + 1,
        'tick_evidence': 'docs/evidence_packets/runtime_observations/original_tick_rate/README.md',
        'replacement_evidence': 'initial frame counter of the stand object',
        'scale': [int(fields['obj_ZoomX'], 0) / 65536, int(fields['obj_ZoomY'], 0) / 65536],
        'not_proven': ['pixel-exact RGB565 additive blending']}
    (OUT / 'manifest.json').write_text(json.dumps(m, ensure_ascii=False, indent=2) + '\n')
    print('FIRE_ANIMATION_IMPORTED', len(frames))


class FireAnimationTask(ScriptCheckTask):
    name = 'fire_animation'
    family = 'assets'
    inputs = ()
    outputs = ('content/imported/hsl/chapter01/fire_animation/',)
    replaces = ('tools/hsl_fire_animation.py --check',)
    scripts = ('tools/hsltools/assets/fire_animation.py',)

    def verify(self, ctx: Context) -> None:
        check()

    def build(self, ctx: Context) -> None:
        build(original_archive(ctx))


def tasks() -> list[FireAnimationTask]:
    return [FireAnimationTask()]
