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
    (0x401600, 0x401708, '0x401600: aniInsertAngleObject ring (per instance +0xae, frame step, move／round angle k·256/n)'),
]
# The patterned inserts run natively: the ANIMAL op's handler (jump table 0x404ee8 via the byte
# table 0x404f48) passes its words to the inserter, which builds every instance in one call on the
# executing tick; the probe calls that inserter at the script point (camera (0,0)) and runs the
# instances together on the one RNG stream. op → (inserter, argument count after the code).
PATTERN_OPS = {'aniInsertAngleObject': (0x401600, 5)}
# Rows whose patterned inserts the remake draws from the native runs (無想冥殺's rings); the other
# rings (妖華紅蓮舞 op 20, 冰 op 21) and the tornado columns (op 22) keep the remake geometry.
PATTERN_ROWS = ('special:magicOTHER:magicCode03',)
# Arrow tracer (毒魔箭 obj_Special19_01, command 17): objmDelay 20, objmSetSpeed 128,0x00200000,
# objmDelay 10, objmWaitOutScreen.
ARROW = 'obj_Special19_01'
# Story-script defProcObjectMove objects run by the same interpreter, each created at the probe
# origin from its level's obj-0xx.obs template (obj_Mode／obj_Zoom*／obj_Data9 as written there):
# key → (level, obj code, obj_Data7 program). Level 37's white lights keep their bare symbols;
# every other level's object is keyed symbol@level.
STORY_OBJECTS = {
    'obj_Story_Level_WhiteLight': (37, 17, '21'), 'obj_Story_Level_WhiteLight2': (37, 19, '62'),
    'obj_Story_Level10_Lightn@010': (10, 18, '5'), 'obj_Story_Level10_Lightn2@010': (10, 24, '5'),
    'obj_Story_Level10_Ring@010': (10, 19, '7'), 'obj_Story_Level_WhiteScreen@013': (13, 17, '151'),
    'obj_Story_Level_WhiteLight@022': (22, 20, '21'), 'obj_Story_Level_WhiteLight@028': (28, 22, '21'),
    'obj_Story_Level_DisappearRock@039': (39, 19, '5'), 'obj_Story_Level53_Rope@053': (53, 25, '150'),
    'obj_Story_Level58_Star@058': (58, 15, '149'), 'obj_Story_Level_WhiteLight@059': (59, 21, '21'),
    'obj_Story_Level_WhiteLight2@059': (59, 22, '62'), 'obj_Story_Level_WhiteLight@076': (76, 17, '21'),
    'obj_Story_Level_WhiteLight@077': (77, 17, '21'), 'obj_Story_Level_WhiteLight@079': (79, 17, '21'),
    'obj_Story_Level_WhiteLight2@079': (79, 18, '21'), 'obj_Story_Level_DarkLight@080': (80, 22, '13'),
    'obj_Story_Level_WhiteLight@080': (80, 19, '13'),
}
MAP_OBJECTS = ROOT / 'content/imported/hsl/chapter01'


def story_obs(level: int) -> str:
    return f'@:\\data\\obj-{level:03d}.obs'


def story_key(symbol: str, level: int) -> str:
    return symbol if level == 37 else f'{symbol}@{level:03d}'


def story_scope() -> dict[str, tuple[int, int, str]]:
    """Every defProcObjectMove script object of the chapter's map_objects, keyed like STORY_OBJECTS."""
    scope = {}
    for path in sorted(MAP_OBJECTS.glob('battle*/map_objects.json')):
        level = int(path.parent.name[len('battle'):])
        for row in json.loads(path.read_text(encoding='utf-8')).get('script_objects', []):
            if row.get('process') == 'defProcObjectMove':
                scope[story_key(row['symbol'], level)] = (level, int(row['object_code']), str(row['object_fields']['obj_Data7']['value']))
    return scope


def story_rows(exe_image, reader, obs: bytes, defines, sounds, metrics, words, members: dict[str, int], names) -> tuple[dict, dict]:
    """The native tracks of the named STORY_OBJECTS and the digests of the level OBS files read."""
    rows, digests = {}, {}
    for name in names:
        level, code, command = STORY_OBJECTS[name]
        raw = reader.read(story_obs(level))
        digests[f'{level:03d}'] = em.digest(raw)
        # The level OBS names its own objects (雨's obj_Data4 → obj_Story_Level10_Rain): OBJ-0xx.H defines.
        header = (MAP_OBJECTS / f'battle{level:03d}/source_texts/OBJ-{level:03d}.H').read_bytes().decode('cp950')
        local = dict(defines, **{name: int(value, 0) for name, value in re.findall(r'^\s*#define\s+(\w+)\s+(-?(?:0x[0-9a-fA-F]+|\d+))', header, re.M)})
        templates = em.Templates([obs, raw], local)
        variants, runs = [], []
        for variant in range(VARIANTS):   # programs 5／149 draw objmRandomShape／objmRandomDelay
            machine = run(exe_image, templates, sounds, metrics, words, code, em.ORIGIN, variant)
            encoded = em.encode_instances(machine, members)
            if variant and encoded == variants[0]:
                break
            variants.append(encoded); runs.append(machine)
        rows[name] = {'code': code, 'command_code': command, 'point': list(em.ORIGIN), 'level_obs': story_obs(level),
                      'frames': max(machine.frame for machine in runs), 'open_ended': any(obj['dead'] is None for obj in runs[0].objects),
                      'variants': variants,
                      'sounds': runs[0].heard()}
    return rows, digests


# objmPlayHitSound (op 52, 0x4059cf) sounds only when the hit roll [0x4c1418] is below the hit rate
# [0x4c6f58] (0x4059e0); its call to the sound player returns to 0x4059f3, objmPlaySound's (op 51)
# to 0x4059c7. The hit rate is written by the defender insert 0x406eb0 (0x406f81), the roll by
# aniProcessHitMiss (0 = hit). The same comparison gates the hit-only throws at 0x405434／0x405495:
# the miss run's tracks stay `variants`, the hit run's go to `hit_variants` where they differ.
HIT_ROLL, HIT_RATE = 0x4c1418, 0x4c6f58
HIT_SOUND_RETURN = 0x4059f3
# objmInitMultiHitData (op 71) → 0x405d6d: 0x4c6f6a++ (as a program's first word the init 0x40524d does it); objmSetMultiHitData (op 72) → 0x405d76: 0x4c6f6a--,
# 0x4c6f68++ (neither yields). aniProcessHitMissMulti (0x4047af) holds the defense script while the dword
# 0x4c6f68 (counters 0x4c6f68／0x4c6f6a) is non-zero and settles one strike (0x4047d5: 0x4c6f68--) on each
# frame it finds 0x4c6f68 non-zero; both zero ends the wait (0x4047b8).
MULTI_HIT_OPS = {0x40524d: 71, 0x405d6d: 71, 0x405d76: 72}


class Machine(em.Machine):
    reviewed = REVIEWED
    processes = (em.EFFECT_PROCESS, em.SHADOW_PROCESS, OBJECT_MOVE, OBJECT_FADE)

    def _guard(self, m, at, size, data) -> None:
        if at == em.SOUND:
            from unicorn.x86_const import UC_X86_REG_ESP
            self.sound_returns = getattr(self, 'sound_returns', []) + [self.read(m.reg_read(UC_X86_REG_ESP), '<I')]
        elif at in MULTI_HIT_OPS:
            self.events.append([self.frame, 'multi_hit', self.current['id'], MULTI_HIT_OPS[at]])
        super()._guard(m, at, size, data)

    def multi_hits(self, ids=None) -> list[list[int]]:
        """[frame, op] of every op 71／72 the tree (or the objects `ids`) executed, in execution order."""
        return [[event[0], event[3]] for event in self.events if event[1] == 'multi_hit' and (ids is None or event[2] in ids)]

    def heard(self, ids=None) -> list[list]:
        """[frame, WAV, hit_only] of every sound the tree (or the objects `ids`) played, in call order."""
        played = [event for event in self.events if event[1] == 'sound']
        return [[event[0], event[3], caller == HIT_SOUND_RETURN] for event, caller in zip(played, getattr(self, 'sound_returns', []))
                if ids is None or event[2] in ids]

    def call(self, entry: int, args: list[int]) -> None:
        """One native cdecl call outside the frame loop (the patterned inserters), returning to STOP."""
        from unicorn.x86_const import UC_X86_REG_ESP, UC_X86_REG_EIP
        self.m.mem_write(em.STACK, struct.pack('<I', em.STOP) + b''.join(struct.pack('<I', arg & 0xffffffff) for arg in args))
        self.m.reg_write(UC_X86_REG_ESP, em.STACK)
        self.m.emu_start(entry, em.STOP, count=400000)
        if self.m.reg_read(UC_X86_REG_EIP) != em.STOP:
            raise ValueError(f'inserter {entry:#x} did not return')

    def instance_ids(self) -> list[set[int]]:
        """The object ids of each root (parent −1, creation order) and everything it threw."""
        roots: dict[int, int] = {}
        for obj in self.objects:
            roots[obj['id']] = obj['id'] if obj['parent'] < 0 else roots[obj['parent']]
        order = [obj['id'] for obj in self.objects if obj['parent'] < 0]
        return [{one for one, root in roots.items() if root == first} for first in order]


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


def pattern_inserts() -> dict[str, tuple[str, list[str]]]:
    """PATTERN_ROWS' patterned inserts keyed `op:code,x,y,…` as written: key → (op, words)."""
    scope = json.loads(SCOPE.read_text(encoding='utf-8'))
    found: dict[str, tuple[str, list[str]]] = {}
    for key in PATTERN_ROWS:
        for lines in scope['rows'][key]['actions'].values():
            tokens = [token.strip() for line in lines for token in line.split(',')]
            for index, token in enumerate(tokens):
                if token in PATTERN_OPS:
                    words = tokens[index + 1:index + 2 + PATTERN_OPS[token][1]]
                    found.setdefault(f'{token}:{",".join(words)}', (token, words))
    return found


def run_pattern(exe_image, templates, sounds, metrics, words, op: str, args: list[str], hit: bool = False) -> Machine:
    """The inserter of `op` called with the script words (x／y as written: camera (0,0), see run),
    then the frame loop; the instances share seed 0's stream as the original's share one."""
    machine = Machine(exe_image, templates, sounds, metrics)
    first, second = seed(0)
    machine.write(em.RNG_STATE[0], first); machine.write(em.RNG_STATE[1], second)
    machine.write(em.CAMERA[0], 0); machine.write(em.CAMERA[1], 0)
    if hit:
        machine.write(HIT_ROLL, 0); machine.write(HIT_RATE, 1)
    table, at = PROGRAM_BASE, PROGRAM_BASE + 4 * 256
    for number, program in words.items():
        machine.write(table + 4 * number, at)
        machine.m.mem_write(at, b''.join(struct.pack('<I', word & 0xffffffff) for word in program))
        at += 4 * len(program)
    machine.write(PROGRAM_TABLE, table)
    code = templates.value(args[0])
    x, y, *rest = (int(word, 0) for word in args[1:])
    machine.call(PATTERN_OPS[op][0], [x, y, code, *rest])
    for _ in range(FRAME_LIMIT):
        machine.step()
        if all(obj['dead'] is not None for obj in machine.objects):
            break
    return machine


def split_instances(machine: Machine, members: dict[str, int], point: tuple[int, int]) -> list[list[dict]]:
    """Per instance k (the inserter's k-th object), its tree in encode_instances' shape, parents renumbered."""
    for obj in machine.objects:
        obj['samples'] = [[s[0], s[1] + em.ORIGIN[0] - point[0], s[2] + em.ORIGIN[1] - point[1], *s[3:]] for s in obj['samples']]
    encoded = em.encode_instances(machine, members)
    trees = []
    for ids in machine.instance_ids():
        local = {one: rank for rank, one in enumerate(sorted(ids))}
        trees.append([dict(encoded[one], parent=local.get(encoded[one]['parent'], -1)) for one in sorted(ids)])
    return trees


def pattern_rows(env: dict, members: dict[str, int]) -> dict:
    """Per patterned insert: variants／hit_variants are its instances (index k), sounds and op 71／72 per instance."""
    rows, pending = {}, {}
    for key, (op, args) in pattern_inserts().items():
        point = (int(args[1], 0), int(args[2], 0))
        common = (env['exe_image'], env['templates'], env['sounds'], env['metrics'], env['words'], op, args)
        miss, hit = run_pattern(*common), run_pattern(*common, hit=True)
        pending[key] = (hit, point)
        instances = hit.instance_ids()
        heard = [hit.heard(ids) for ids in instances]
        multi = [hit.multi_hits(ids) for ids in instances]
        variants = split_instances(miss, members, point)
        row = {'op': op, 'object': args[0], 'code': env['templates'].value(args[0]), 'point': list(point),
               'frames': miss.frame, 'open_ended': any(obj['dead'] is None for obj in miss.objects),
               'variants': variants, 'sounds': heard[0], 'variant_sounds': heard}
        if any(multi):
            row['multi_hit'] = multi[0]; row['variant_multi_hit'] = multi
        rows[key] = row
    for key, (hit, point) in pending.items():   # hit trees after every miss tree (members order)
        hit_variants = split_instances(hit, members, point)
        if hit_variants != rows[key]['variants']:
            rows[key]['hit_variants'] = hit_variants
            rows[key]['hit_frames'] = hit.frame
    return rows


def seed(variant: int) -> tuple[int, int]:
    return ((em.SEED[0] + 0x9e3779b9 * variant) & 0xffffffff, (em.SEED[1] ^ (0x7f4a7c15 * variant)) & 0xffffffff)


def run(exe_image, templates, sounds, metrics, words, code: int, point: tuple[int, int], variant: int, screen: bool = False,
        hit: bool = False) -> Machine:
    """screen: point is a SPECIAL script point. aniInsertObject 0x403989 creates the object at point + camera
    (0x4c091c／0x4c0920) and the off-screen tests subtract the camera again, so the root runs with the camera
    at (0,0) and the point as written; otherwise the camera stays where effect_motion centres it."""
    machine = Machine(exe_image, templates, sounds, metrics)
    first, second = seed(variant)
    machine.write(em.RNG_STATE[0], first); machine.write(em.RNG_STATE[1], second)
    if screen:
        machine.write(em.CAMERA[0], 0); machine.write(em.CAMERA[1], 0)
    if hit:
        machine.write(HIT_ROLL, 0); machine.write(HIT_RATE, 1)
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


def setup(exe: Path) -> dict:
    """The pak reader, templates, programs, SHP metrics and EXE image every run shares."""
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

    return {'reader': reader, 'process_def': process_def, 'level_obs': level_obs, 'defines': defines, 'obs': obs,
            'templates': templates, 'words': words, 'metrics': metrics,
            'sounds': {value: name for name, value in templates.sounds.items()}, 'exe_image': image(exe.read_bytes())}


def story_packet_rows(exe: Path, names, members: dict[str, int]) -> tuple[dict, dict]:
    """Only the named story objects' rows (appending to a tracked packet keeps its other rows)."""
    env = setup(exe)
    return story_rows(env['exe_image'], env['reader'], env['obs'], env['defines'], env['sounds'], env['metrics'], env['words'], members, names)


def execute_packet(exe: Path) -> dict:
    env = setup(exe)
    reader, process_def, level_obs, defines, obs = env['reader'], env['process_def'], env['level_obs'], env['defines'], env['obs']
    templates, words, metrics, sounds, exe_image = env['templates'], env['words'], env['metrics'], env['sounds'], env['exe_image']
    points = insert_points()
    members: dict[str, int] = {}
    objects = {}
    pending_hits: dict[str, list] = {}
    for name, entry in scope_objects().items():
        code = int(entry['obj_code'])
        point = points.get(name, em.ORIGIN)
        variants, runs = [], []
        for variant in range(VARIANTS):
            machine = run(exe_image, templates, sounds, metrics, words, code, point, variant, screen=True)
            for obj in machine.objects:
                obj['samples'] = [[s[0], s[1] + em.ORIGIN[0] - point[0], s[2] + em.ORIGIN[1] - point[1], *s[3:]] for s in obj['samples']]
            encoded = em.encode_instances(machine, members)
            if variant and encoded == variants[0]:
                break
            variants.append(encoded); runs.append(machine)
        # A hit run of each kept variant: objmPlayHitSound sounds only on a hit (hit_only marks them) and the
        # hit-only throws 0x405434／0x405495 fire only then; its tracks are encoded after every miss run.
        hit_runs = [run(exe_image, templates, sounds, metrics, words, code, point, variant, screen=True, hit=True)
                    for variant in range(len(variants))]
        for machine in hit_runs:
            for obj in machine.objects:
                obj['samples'] = [[s[0], s[1] + em.ORIGIN[0] - point[0], s[2] + em.ORIGIN[1] - point[1], *s[3:]] for s in obj['samples']]
        pending_hits[name] = hit_runs
        heard = [machine.heard() for machine in hit_runs]
        objects[name] = {'code': code, 'command_code': entry['command_code'], 'point': list(point),
                         'frames': max(machine.frame for machine in runs),
                         'open_ended': any(obj['dead'] is None for obj in runs[0].objects),
                         'variants': variants,
                         'sounds': heard[0]}
        if any(one != heard[0] for one in heard):
            objects[name]['variant_sounds'] = heard
        multi = [machine.multi_hits() for machine in hit_runs]
        if multi[0] or any(multi):
            objects[name]['multi_hit'] = multi[0]
            if any(one != multi[0] for one in multi):
                objects[name]['variant_multi_hit'] = multi
    story, story_digests = story_rows(exe_image, reader, obs, defines, sounds, metrics, words, members, STORY_OBJECTS)
    objects.update(story)
    # Hit tracks last, so members the hit-only throws add append after the miss runs' table.
    for name, hit_runs in pending_hits.items():
        hit_variants = [em.encode_instances(machine, members) for machine in hit_runs]
        if hit_variants != objects[name]['variants']:
            objects[name]['hit_variants'] = hit_variants
            objects[name]['hit_frames'] = max(machine.frame for machine in hit_runs)
    patterns = pattern_rows(env, members)
    from hsltools.probes.effect_motion import digest
    return {'schema': SCHEMA, 'exe_sha256': EXE_SHA, 'native_execution': True, 'evidence_tier': 'static-derived',
            'sources': {'global_obs': digest(obs), 'objcomd': digest(COMMANDS.read_bytes()), 'process_def': digest(process_def),
                        'obj_051_obs': digest(level_obs), 'obj_037_obs': story_digests['037'], 'story_obs': story_digests},
            'frame_limit': FRAME_LIMIT, 'seeds': [[f'{a:#010x}', f'{b:#010x}'] for a, b in map(seed, range(VARIANTS))],
            'reviewed': [[f'{low:#x}', f'{high:#x}', note] for low, high, note in REVIEWED],
            'members': sorted(members, key=members.get), 'objects': objects, 'patterns': patterns,
            'limits': ['Positions are relative to the creation point; each root is created at its first script insertion '
                       'point with the camera at (0,0), so off-screen waits end where that point would (other insertion '
                       'points and random spreads are drawn with the same track).',
                       'Random programs run under up to four RNG seeds (variants); the original draws each instance from the '
                       'one shared stream.',
                       'Objects alive after frame_limit (programs ending in objmOver or looping without an exit) are '
                       'open_ended: the script end removes them.',
                       'variants are the miss run (hit roll [0x4c1418] not under the hit rate [0x4c6f58]); hit_variants, '
                       'present only where they differ, are the same seeds with the roll under the rate (the hit-only throws '
                       '0x405434／0x405495 fire), hit_frames their length.',
                       'sounds are [frame, WAV, hit_only] from a run with the hit roll under the hit rate (objmPlayHitSound '
                       'sounds only on a hit); variant_sounds, when present, lists them per variant.',
                       'multi_hit, present only where the tree runs objmInitMultiHitData／objmSetMultiHitData, is [frame, op] '
                       '(71 init 0x405d6d or, as the first word, 0x40524d; 72 set 0x405d76) of the hit run in execution order; variant_multi_hit lists them '
                       'per variant when they differ.',
                       'patterns: each patterned insert of PATTERN_ROWS keyed op:words as written, its inserter (0x401600) '
                       'called at the script point with the camera at (0,0) and every instance run together under seed 0; '
                       'variants／hit_variants／variant_sounds／variant_multi_hit are indexed by instance (the inserter\'s '
                       'creation order), positions relative to the script point, frames count from the inserting tick.',
                       'The objcomd.txt word layout (one word per token, objmOver closing each block) is provisional.']}


def check(packet: dict) -> None:
    if packet.get('schema') != SCHEMA or packet.get('exe_sha256') != EXE_SHA or packet.get('native_execution') is not True:
        raise ValueError('objcomd motion identity differs')
    if packet['sources']['global_obs'] != em.digest(GLOBAL_OBS.read_bytes()) or packet['sources']['objcomd'] != em.digest(COMMANDS.read_bytes()):
        raise ValueError('global.obs／objcomd.txt changed: regenerate objcomd_motion')
    scope = scope_objects()
    if story_scope() != STORY_OBJECTS:
        raise ValueError('STORY_OBJECTS differs from the defProcObjectMove script objects of the chapter map_objects')
    if set(packet['objects']) != set(scope) | set(STORY_OBJECTS):
        raise ValueError('objcomd motion scope differs from the defProcObjectMove objects of the SPECIAL and story scripts')
    if set(packet.get('patterns', {})) != set(pattern_inserts()):
        raise ValueError('objcomd motion patterns differ from the patterned inserts of PATTERN_ROWS')
    for key, row in packet['patterns'].items():
        op, words = pattern_inserts()[key]
        count = abs(int(words[3], 0))
        if row['op'] != op or row['object'] != words[0] or len(row['variants']) != count or len(row.get('hit_variants', row['variants'])) != count:
            raise ValueError(f'{key}: op／object／instance count differ from the script words')
    for name, row in list(packet['objects'].items()) + list(packet['patterns'].items()):
        if name in packet['patterns']:
            pass
        elif name in STORY_OBJECTS:
            level, code, command = STORY_OBJECTS[name]
            if (row['code'], row['command_code'], row['level_obs']) != (code, command, story_obs(level)):
                raise ValueError(f'{name}: code／command／level OBS differ from STORY_OBJECTS')
        elif row['code'] != int(scope[name]['obj_code']) or row['command_code'] != scope[name]['command_code']:
            raise ValueError(f'{name}: code／command differ from the scope')
        if 'hit_variants' in row and len(row['hit_variants']) != len(row['variants']):
            raise ValueError(f'{name}: hit_variants differ in count from variants')
        for instances in row['variants'] + row.get('hit_variants', []):
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
            f'variants={sum(len(row["variants"]) for row in objects.values())} '
            f'patterns={len(packet["patterns"])} instances={sum(len(row["variants"]) for row in packet["patterns"].values())} executed_now={executed_now}')


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
