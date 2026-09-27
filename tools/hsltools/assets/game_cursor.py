"""Import the original game cursor (object 2 游標, defProcCursor) and its animation fields.

Registry task game_cursor (family assets): output content/imported/hsl/shared/game_cursor/.
Every original OBS that defines object 2 (the title's OBJ-000, every battle, the big map) gives
it the same fields: SHAPE\\CURSOR01.SHP, 10 shapes (CURSOR01..CURSOR10), obj_Shape_Delay 5, plane
planeCursor, process defProcCursor. The build re-reads all of them and refuses a disagreement,
so the manifest's `obs_definitions` count is the proof that one cursor serves every screen. Each
frame keeps its SHP draw origin (header 0x1c／0x20): the object stands on the mouse (0x430410
copies [0x4c1a8c]／[0x4c1a90] to +4／+8) and a shape draws at its position minus that origin, so
the origin is the hotspot. Frames advance every obj_Shape_Delay + 1 ticks (0x45e5a6, as the
level-51 fire: fire_animation.py).
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
OUT = ROOT / 'content/imported/hsl/shared/game_cursor'
SOURCE_MEMBER = '@:\\DATA\\OBJ-000.OBS'
CURSOR_CODE = '2'


def _object_fields(text: str, code: str) -> dict[str, str] | None:
    for block in text.split('[Object]'):
        if re.search(rf'^obj_code\s*=\s*{code}\s*(;.*)?$', block, re.M):
            return {k: v.strip() for k, v in re.findall(r'^(obj_\w+)\s*=\s*([^;\r\n]+)', block, re.M)}
    return None


def check():
    m = json.loads((OUT / 'manifest.json').read_text())
    fields = m['source_fields']
    assert fields['obj_Process_Code'] == 'defProcCursor' and fields['obj_Plane'] == 'planeCursor'
    assert len(m['frames']) == int(fields['obj_Shape_Number']) == 10
    assert m['frame_ticks'] == int(fields['obj_Shape_Delay']) + 1
    assert m['obs_definitions'] >= 100 and m['obs_disagreements'] == []
    for index, frame in enumerate(m['frames']):
        assert frame['source_member'].upper().endswith(f'CURSOR{index + 1:02}.SHP')
        assert len(frame['draw_origin']) == 2 and len(frame['size']) == 2
        p = ROOT / frame['texture'].removeprefix('res://')
        assert hashlib.sha256(p.read_bytes()).hexdigest() == frame['png_sha256']
    print('GAME_CURSOR_CHECK_PASS')


def build(pak):
    pkgs = find_decoded_paks_packages(pak)

    def read_record(p, r):
        return read_paks_record_bytes(p['path'], r, data_end_offset=int(p['paks']['candidate_index_offset']))

    def read(member):
        matches = [(p, r) for p in pkgs if (r := find_paks_record_by_name(p['records'], member))]
        if len(matches) != 1:
            raise ValueError('missing or ambiguous resource: ' + member)
        return read_record(*matches[0])

    raw = read(SOURCE_MEMBER)
    fields = _object_fields(raw.decode('cp950'), CURSOR_CODE)
    if fields is None or fields.get('obj_Process_Code') != 'defProcCursor':
        raise ValueError('OBJ-000.OBS has no defProcCursor object 2')
    definitions = 0
    disagreements = []
    seen = set()
    for p in pkgs:
        for r in p['records']:
            name = str(r.get('name', ''))
            if not name.lower().endswith('.obs') or name.lower() in seen:
                continue
            seen.add(name.lower())
            other = _object_fields(read_record(p, r).decode('cp950', 'replace'), CURSOR_CODE)
            if other is None or other.get('obj_Process_Code') != 'defProcCursor':
                continue
            definitions += 1
            if other != fields:
                disagreements.append(name)
    shape = re.fullmatch(r'SHAPE\\CURSOR(\d\d)\.SHP', fields['obj_Shape_Name'], re.I)
    if shape is None or int(shape.group(1)) != 1:
        raise ValueError('unexpected cursor shape name: ' + fields['obj_Shape_Name'])
    OUT.mkdir(parents=True, exist_ok=True)
    frames = []
    for index in range(1, int(fields['obj_Shape_Number']) + 1):
        member = f'@:\\SHAPE\\CURSOR{index:02}.SHP'
        payload = read(member)
        shp = parse_shp(payload)
        p = OUT / f'CURSOR{index:02}.png'
        write_shp_preview(payload, shp, p)
        frames.append({'source_member': member, 'source_sha256': hashlib.sha256(payload).hexdigest(),
            'texture': 'res://' + p.relative_to(ROOT).as_posix(),
            'png_sha256': hashlib.sha256(p.read_bytes()).hexdigest(),
            'size': [shp['width'], shp['height']],
            'draw_origin': list(struct.unpack_from('<ii', payload, 0x1C))})
    m = {'schema': 'hsl_game_cursor.v1', 'source_member': SOURCE_MEMBER, 'source_sha256': hashlib.sha256(raw).hexdigest(),
        'source_fields': fields, 'obs_definitions': definitions, 'obs_disagreements': disagreements,
        'frames': frames, 'frame_ticks': int(fields['obj_Shape_Delay']) + 1,
        'hotspot': 'draw_origin',
        'evidence': 'docs/evidence_packets/runtime_observations/game_cursor/README.md',
        'not_proven': ['when [0x4c1b00] & 0x1800000 hides the cursor', 'the carried-item icon that replaces it (0x430310)']}
    (OUT / 'manifest.json').write_text(json.dumps(m, ensure_ascii=False, indent=2) + '\n')
    print('GAME_CURSOR_IMPORTED', len(frames), 'obs_definitions', definitions)


class GameCursorTask(ScriptCheckTask):
    name = 'game_cursor'
    family = 'assets'
    inputs = ()
    outputs = ('content/imported/hsl/shared/game_cursor/',)
    replaces = ()  # born as a registry task: no historical command to replace
    scripts = ('tools/hsltools/assets/game_cursor.py',)

    def verify(self, ctx: Context) -> None:
        check()

    def build(self, ctx: Context) -> None:
        build(original_archive(ctx))


def tasks() -> list[GameCursorTask]:
    return [GameCursorTask()]
