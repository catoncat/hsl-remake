"""Skill-object motion: the objcomd.txt command programs of defProcObjectMove executed per tick.

Registry task objcomd_motion (family probe, a PacketTask whose packet is a runtime input under content/generated). generate runs the
original instructions of the object-move process (process table 0x477c2c slot 37 → 0x4051d0,
its objm* jump table 0x406bc8, the motion integrator 0x42fcb0) and of the fade process its
throws use (slot 38 → 0x4050a0) on synthetic objects built from the global.obs templates, one
root per SPECIAL-script object, created where the scripts first insert it, frame by frame, and
records every object the root and its descendants draw — the same columns as effect_motion
(position relative to the creation point, SHP member, eng* mode, mix level, zoom). Random
programs run under VARIANTS seeds so repeated instances of one object do not move in lockstep.
check validates the tracked packet offline: identity, source digests, scope (every
defProcObjectMove object of the SPECIAL scripts is tracked) and the 毒魔箭 arrow model (wait 20,
angle 128 at 32 px per tick until off screen), which must match the native track sample for
sample. Needs the documented hsl01.exe, hsl.pak next to it and unicorn for generate.

Program layout (provisional: the objcomd.txt loader is not read): every token of a [command]
block's action lines is one 32-bit word in order — objm* names and OBJ-ALL.H names by their
defines, numbers as written, a WAV as a sound id — and objmOver (0) closes the block.
"""
from __future__ import annotations

import json
import re
import struct
from pathlib import Path

from hsltools.native.image import EXE_SHA, image
from hsltools.paths import ROOT
from hsltools.probes import effect_motion as em
from hsltools.registry import PacketTask

PACKET = ROOT / 'content/generated/hsl/skills/objcomd_motion.json'
SCOPE = em.SCOPE
GLOBAL_OBS = em.GLOBAL_OBS
COMMANDS = ROOT / 'content/imported/hsl/shared/first_skill/objcomd.txt'
COMMAND_VERBS = ROOT / 'content/imported/hsl/shared/first_skill/OBJCOMD.H'
SCHEMA = 'hsl_objcomd_motion_native.v1'

OBJECT_MOVE, OBJECT_FADE = 37, 38   # PROCESS.DEF defProcObjectMove → 0x4051d0; slot 38 → 0x4050a0
PROGRAM_TABLE = 0x4c1b74            # objcomd.txt code → program words (read at 0x405236)
PROGRAM_BASE = 0x10010000
FRAME_LIMIT = 600
VARIANTS = 4
REVIEWED = em.REVIEWED + [
    (0x401390, 0x401559, '0x401390／0x401480: random throw spawners (rand offsets, growing +0xae delays, chain link)'),
    (0x4050a0, 0x4051c6, 'slot 38 fade process 0x4050a0 and the off-screen test 0x405140 (SHP metrics against 640×480)'),
    (0x4051d0, 0x406bc8, 'defProcObjectMove 0x4051d0: init, objm* interpreter (jump table 0x406bc8), phase waits'),
    (0x42f880, 0x42ffe7, 'motion setters 0x42f880..0x42fcaf and the per-tick integrator 0x42fcb0'),
]
# Arrow tracer (毒魔箭 obj_Special19_01, command 17): objmDelay 20, objmSetSpeed 128,0x00200000,
# objmDelay 10, objmWaitOutScreen.
ARROW = 'obj_Special19_01'


class Machine(em.Machine):
    reviewed = REVIEWED
    processes = (em.EFFECT_PROCESS, em.SHADOW_PROCESS, OBJECT_MOVE, OBJECT_FADE)


def command_words(templates: 'em.Templates') -> dict[int, list[int]]:
    from hsltools.data.special_effect_scripts import command_programs
    programs = command_programs(COMMANDS.read_bytes().decode('cp950'))
    return {int(code): [templates.value(token) for token in tokens] + [0] for code, tokens in programs.items()}


def scope_objects() -> dict[str, dict]:
    scope = json.loads(SCOPE.read_text(encoding='utf-8'))
    names = sorted({name for row in scope['rows'].values() if row['channel'] == 'special' for name in row['objects']})
    return {name: scope['objects'][name] for name in names if name in scope['objects'] and scope['objects'][name]['command_code'] != ''}


def insert_points() -> dict[str, tuple[int, int]]:
    """Each object's first script insertion point ([code][x][y] of the ani*Insert* verb, in row
    order); the Disp verbs' offsets are taken as written (provisional)."""
    scope = json.loads(SCOPE.read_text(encoding='utf-8'))
    points: dict[str, tuple[int, int]] = {}
    for key in sorted(scope['rows']):
        row = scope['rows'][key]
        if row['channel'] != 'special':
            continue
        for lines in row['actions'].values():
            tokens = [token.strip() for line in lines for token in line.split(',')]
            for index, token in enumerate(tokens):
                if token.startswith('aniInsert') and index + 3 < len(tokens) and tokens[index + 1].startswith('obj_'):
                    try:
                        point = (int(tokens[index + 2], 0), int(tokens[index + 3], 0))
                    except ValueError:
                        continue
                    points.setdefault(tokens[index + 1], point)
    return points


def seed(variant: int) -> tuple[int, int]:
    return ((em.SEED[0] + 0x9e3779b9 * variant) & 0xffffffff, (em.SEED[1] ^ (0x7f4a7c15 * variant)) & 0xffffffff)


def run(exe_image, templates, sounds, metrics, words, code: int, point: tuple[int, int], variant: int) -> Machine:
    machine = Machine(exe_image, templates, sounds, metrics)
    first, second = seed(variant)
    machine.write(em.RNG_STATE[0], first); machine.write(em.RNG_STATE[1], second)
    table, at = PROGRAM_BASE, PROGRAM_BASE + 4 * 256
    for number, program in words.items():
        machine.write(table + 4 * number, at)
        machine.m.mem_write(at, b''.join(struct.pack('<I', word & 0xffffffff) for word in program))
        at += 4 * len(program)
    machine.write(PROGRAM_TABLE, table)
    machine.create(point[0], point[1], code)
    for _ in range(FRAME_LIMIT):
        machine.step()
        if all(obj['dead'] is not None for obj in machine.objects):
            break
    return machine


def execute_packet(exe: Path) -> dict:
    from hsltools.data.world_map import PakReader
    from hsltools.sources.shp import parse_shp
    reader = PakReader(exe.parent)
    process_def = reader.read('@:\\data\\PROCESS.DEF')
    level_obs = reader.read('@:\\data\\obj-051.obs')
    defines = em.table_defines(process_def.decode('cp950'))
    for name, value in re.findall(r'^\s*#define\s+(objm\w+)\s+(\d+)', COMMAND_VERBS.read_bytes().decode('cp950'), re.M):
        defines.setdefault(name, int(value))
    obs = GLOBAL_OBS.read_bytes()
    templates = em.Templates([obs, level_obs], defines)
    words = command_words(templates)
    shp_cache: dict[str, tuple[int, int, int, int]] = {}

    def metrics(member: str) -> tuple[int, int, int, int]:
        if member not in shp_cache:
            found = reader.find('@:\\' + member)
            if found is None:
                raise ValueError(f'{member} missing from hsl.pak (0x4606a9 metrics)')
            raw = reader.read(found)
            origin = struct.unpack_from('<ii', raw, 0x1c)
            meta = parse_shp(raw)
            shp_cache[member] = (origin[0], origin[1], meta['width'], meta['height'])
        return shp_cache[member]

    sounds = {value: name for name, value in templates.sounds.items()}
    exe_image = image(exe.read_bytes())
    points = insert_points()
    members: dict[str, int] = {}
    objects = {}
    for name, entry in scope_objects().items():
        code = int(entry['obj_code'])
        point = points.get(name, em.ORIGIN)
        variants, runs = [], []
        for variant in range(VARIANTS):
            machine = run(exe_image, templates, sounds, metrics, words, code, point, variant)
            for obj in machine.objects:
                obj['samples'] = [[s[0], s[1] + em.ORIGIN[0] - point[0], s[2] + em.ORIGIN[1] - point[1], *s[3:]] for s in obj['samples']]
            encoded = em.encode_instances(machine, members)
            if variant and encoded == variants[0]:
                break
            variants.append(encoded); runs.append(machine)
        objects[name] = {'code': code, 'command_code': entry['command_code'], 'point': list(point),
                         'frames': max(machine.frame for machine in runs),
                         'open_ended': any(obj['dead'] is None for obj in runs[0].objects),
                         'variants': variants,
                         'sounds': [[event[0], event[3]] for event in runs[0].events if event[1] == 'sound']}
    from hsltools.probes.effect_motion import digest
    return {'schema': SCHEMA, 'exe_sha256': EXE_SHA, 'native_execution': True, 'evidence_tier': 'static-derived',
            'sources': {'global_obs': digest(obs), 'objcomd': digest(COMMANDS.read_bytes()), 'process_def': digest(process_def),
                        'obj_051_obs': digest(level_obs)},
            'frame_limit': FRAME_LIMIT, 'seeds': [[f'{a:#010x}', f'{b:#010x}'] for a, b in map(seed, range(VARIANTS))],
            'reviewed': [[f'{low:#x}', f'{high:#x}', note] for low, high, note in REVIEWED],
            'members': sorted(members, key=members.get), 'objects': objects,
            'limits': ['Positions are relative to the creation point; each root is created at its first script insertion '
                       'point with the camera at (0,0), so off-screen waits end where that point would (other insertion '
                       'points and random spreads are drawn with the same track).',
                       'Random programs run under up to four RNG seeds (variants); the original draws each instance from the '
                       'one shared stream.',
                       'Objects alive after frame_limit (programs ending in objmOver or looping without an exit) are '
                       'open_ended: the script end removes them.',
                       'The objcomd.txt word layout (one word per token, objmOver closing each block) is provisional.']}


def check(packet: dict) -> None:
    if packet.get('schema') != SCHEMA or packet.get('exe_sha256') != EXE_SHA or packet.get('native_execution') is not True:
        raise ValueError('objcomd motion identity differs')
    if packet['sources']['global_obs'] != em.digest(GLOBAL_OBS.read_bytes()) or packet['sources']['objcomd'] != em.digest(COMMANDS.read_bytes()):
        raise ValueError('global.obs／objcomd.txt changed: regenerate objcomd_motion')
    scope = scope_objects()
    if set(packet['objects']) != set(scope):
        raise ValueError('objcomd motion scope differs from the defProcObjectMove objects of the SPECIAL scripts')
    for name, row in packet['objects'].items():
        if row['code'] != int(scope[name]['obj_code']) or row['command_code'] != scope[name]['command_code']:
            raise ValueError(f'{name}: code／command differ from the scope')
        for instances in row['variants']:
            for instance in instances:
                if instance['start'] < 0:
                    continue
                length = len(instance['x'])
                if len(instance['y']) != length or any(sum(count for _, count in instance[key]) != length for key in ('member', 'mode', 'level', 'zoom_x', 'zoom_y')):
                    raise ValueError(f'{name}: instance columns differ in length')
    arrow = packet['objects'][ARROW]['variants'][0][0]
    rows = em.decode_track(arrow)
    expected = [(frame, 0 if frame <= 21 else -32 * (frame - 21), 0) for frame in range(1, 1 + len(rows))]
    if [(row[0], row[1], row[2]) for row in rows] != expected:
        raise ValueError(f'{ARROW}: native track differs from the arrow model (wait 20, then 32 px per tick left)')


def summary_line(packet: dict, executed_now: bool) -> str:
    objects = packet['objects']
    return (f'OBJCOMD_MOTION_NATIVE_PASS objects={len(objects)} open_ended={sum(1 for row in objects.values() if row["open_ended"])} '
            f'variants={sum(len(row["variants"]) for row in objects.values())} executed_now={executed_now}')


class ObjcomdMotionTask(PacketTask):
    """The native probe whose packet is a runtime input (like effect_motion)."""
    name = 'objcomd_motion'
    family = 'probe'
    packet = PACKET.relative_to(ROOT).as_posix()
    outputs = (packet,)
    inputs = ('content/imported/hsl/global/tables/', 'content/imported/hsl/shared/first_skill/global.obs',
              'content/imported/hsl/shared/first_skill/objcomd.txt', 'content/imported/hsl/shared/first_skill/OBJCOMD.H',
              'content/generated/hsl/skills/special_effect_scripts.json')
    scripts = ('tools/hsltools/probes/objcomd_motion.py', 'tools/hsltools/probes/effect_motion.py')
    replaces = ()

    def validate(self, packet: dict) -> None:
        check(packet)

    def execute(self, ctx) -> dict:
        return execute_packet(ctx.original_exe)

    def summary(self, packet: dict, executed_now: bool) -> str:
        return summary_line(packet, executed_now)

    def load(self, ctx) -> dict:
        return json.loads((ctx.root / self.packet).read_text(encoding='utf-8'))

    def generate(self, ctx) -> str:
        from hsltools.registry import NotGeneratable
        if not ctx.original_exe.exists():
            raise NotGeneratable(f'{self.name}: original EXE not found at {ctx.original_exe} (needs the documented hsl01.exe and unicorn)')
        packet = self.execute(ctx)
        self.validate(packet)
        target = ctx.root / self.packet
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(packet, ensure_ascii=False, separators=(',', ':')) + '\n', encoding='utf-8')
        return self.summary(packet, True)


TASK = ObjcomdMotionTask()


def tasks() -> list[PacketTask]:
    return [TASK]
