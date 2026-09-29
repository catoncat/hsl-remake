"""Import every declared BCMD frame, rather than treating its first frame as the icon.

Registry task command_frames (family assets): output content/imported/hsl/shared/command_menu/
(manifest.json, source_objects.json, per-command frame PNGs). Bodies moved verbatim from the former hsl_command_frames.py.
"""
import json
import struct
from io import BytesIO
from pathlib import Path
from PIL import Image

from hsltools.registry import Context, ScriptCheckTask, original_archive
from hsltools.sources.pak import find_decoded_paks_packages, find_paks_record_by_name, read_paks_record_bytes
from hsltools.sources.shp import parse_shp, png_sha256, write_shp_preview
from hsltools.sources.tables import digest, blocks

ROOT = Path('content/imported/hsl/shared/command_menu')
OBJECTS = ROOT / 'source_objects.json'
COMMANDS = {'move': '01', 'attack': '02', 'item': '03', 'wait': '04', 'use': '05', 'give': '06', 'equip': '07', 'drop': '08', 'magic': '09', 'special': '10', 'status': '13'}


def definitions():
    # frame_count is obj-051.obs's obj_Shape_Number for the command object (source_objects.json).
    objects = json.loads(OBJECTS.read_text())['commands']
    return {name: {'prefix': 'BCMD' + code, 'frame_count': objects[name]['frame_count'],
                  'looped': objects[name]['data3'] != 0}
            for name, code in COMMANDS.items()}


def build(pak):
    packages = find_decoded_paks_packages(pak)
    matches = [(p, r) for p in packages if (r := find_paks_record_by_name(p['records'], '@:\\data\\obj-051.obs'))]
    if len(matches) != 1:
        raise ValueError('Missing or ambiguous command object definitions')
    package, record = matches[0]
    raw = read_paks_record_bytes(package['path'], record, data_end_offset=int(package['paks']['candidate_index_offset']))
    objects = {b['obj_Shape_Name'].replace('\\\\', '\\').upper(): b for b in blocks(raw, 'Object') if b.get('obj_Process_Code') == 'defProcBattleCommandString'}
    compact = {}
    for name, code in COMMANDS.items():
        row = objects['SHAPE\\BCMD' + code + '_1.SHP']
        compact[name] = {'object_code': int(row['obj_code']), 'frame_count': int(row['obj_Shape_Number']),
                         'data3': int(row['obj_Data3'], 0), 'command_id': int(row['obj_Data8']),
                         'process': row['obj_Process_Code']}
    OBJECTS.parent.mkdir(parents=True, exist_ok=True)
    OBJECTS.write_text(json.dumps({'schema': 'hsl_command_objects.v1', 'source_member': record['name'],
                                  'source_sha256': digest(raw), 'commands': compact}, indent=2) + '\n')
    result = {'schema': 'hsl_command_frames.v1', 'evidence_tier': 'resource-derived',
              'objects_sha256': digest(OBJECTS.read_bytes()), 'commands': {},
              'limits': 'Source frames/counts only. Hover loop timing requires the original recording.'}
    for name, definition in definitions().items():
        frames = []
        for i in range(1, definition['frame_count'] + 1):
            member = 'SHAPE\\' + definition['prefix'] + '_' + str(i) + '.SHP'
            matches = [(p,r) for p in packages if (r := find_paks_record_by_name(p['records'], '@:\\' + member))]
            if len(matches) != 1: raise ValueError('Missing/ambiguous ' + member)
            p,r = matches[0]
            data = read_paks_record_bytes(p['path'], r, data_end_offset=int(p['paks']['candidate_index_offset']))
            target = ROOT / name / (str(i - 1) + '.png')
            previous = target.read_bytes() if target.exists() else None
            write_shp_preview(data, parse_shp(data), target)
            # Compression-library changes must not churn unchanged source pixels.
            if previous is not None:
                with Image.open(BytesIO(previous)) as old, Image.open(target) as current:
                    unchanged = old.size == current.size and old.convert('RGBA').tobytes() == current.convert('RGBA').tobytes()
                if unchanged:
                    target.write_bytes(previous)
            frames.append({'res_path': 'res://' + target.as_posix(), 'source_member': member,
                           'source_sha256': digest(data), 'png_sha256': png_sha256(target),
                           'draw_origin': list(struct.unpack_from('<ii',data,0x1c))})
        result['commands'][name] = {**definition, 'frames': frames}
    (ROOT / 'manifest.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')


def check():
    data = json.loads((ROOT / 'manifest.json').read_text())
    assert data['objects_sha256'] == digest(OBJECTS.read_bytes())
    assert set(data['commands']) == set(COMMANDS)
    for name, definition in definitions().items():
        row = data['commands'][name]
        original = json.loads(OBJECTS.read_text())['commands'][name]
        assert original['process'] == 'defProcBattleCommandString' and original['command_id'] == int(COMMANDS[name])
        assert original['frame_count'] == definition['frame_count']
        assert row['frame_count'] == definition['frame_count'] == len(row['frames'])
        assert row['looped'] == definition['looped']
        for frame in row['frames']:
            assert png_sha256(Path(frame['res_path'].removeprefix('res://'))) == frame['png_sha256']
    print('COMMAND_FRAMES_CHECK_PASS')


class CommandFramesTask(ScriptCheckTask):
    name = 'command_frames'
    family = 'assets'
    outputs = (ROOT.as_posix() + '/',)
    replaces = ('tools/hsl_command_frames.py --check',)
    scripts = ('tools/hsltools/assets/command_frames.py',)

    def verify(self, ctx: Context) -> None:
        check()

    def build(self, ctx: Context) -> None:
        build(original_archive(ctx))


def tasks() -> list[CommandFramesTask]:
    return [CommandFramesTask()]
