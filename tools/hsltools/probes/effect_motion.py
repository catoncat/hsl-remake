"""Effect-object motion: the effProc* programs of defProcEffectProcess1 executed per tick.

Registry task effect_motion (family probe, a PacketTask whose packet is a runtime input under content/generated). generate runs the
original instructions of the effect-object process (process table 0x477c2c slot 28 →
0x415dc0, its effProc* jump table 0x4231b0) and of the afterimage process (slot 24 →
0x4010c0, defProcShadowLeft) on synthetic objects built from the global.obs templates, one
root object per magic-script object, frame by frame, and records every object the root and
its descendants draw: position relative to the effect origin, SHP member, draw mode
(PROCESS.DEF eng* bits), mix level and zoom. check validates the tracked packet: identity,
the source digests, the scope (every MAGIC-script object is either tracked or listed
unrestored with the unreviewed callee that stopped it) and the independent model of the
幻火 tracer programs (FlyDrop, FireAndBomb, SprayUpDown and the shared helpers), which must
reproduce the native tracks sample for sample. Needs the documented hsl01.exe, hsl.pak next
to it and unicorn for generate; check runs offline.

Frame model (static-derived, docs/evidence_packets/static_reverse/original_effect_motion.md):
0x45f5f7 walks the plane lists calling each object's process with its +0x80 flags, reading
the next link before the call (a child appended behind the current tail waits a frame),
then walks them again to draw: an object whose +0x80 carries 0x10000000 (set by the creator
0x45e307) is skipped once and the bit cleared, a shape word 0xffff is not drawn. The effect
script interpreter (0x4237f7) creates each object at origin + displacement and writes the
origin into +0xaa／+0xa8; the root here is created the same way before frame 0.
"""
from __future__ import annotations

import hashlib
import json
import re
import struct
from pathlib import Path

from hsltools.native.image import EXE_SHA, image
from hsltools.paths import ROOT
from hsltools.registry import PacketTask
from hsltools.sources.tables import blocks

PACKET = ROOT / 'content/generated/hsl/skills/effect_motion.json'
SCOPE = ROOT / 'content/generated/hsl/skills/special_effect_scripts.json'
GLOBAL_OBS = ROOT / 'content/imported/hsl/shared/first_skill/global.obs'
TABLES = ROOT / 'content/imported/hsl/global/tables'
SCHEMA = 'hsl_effect_motion_native.v1'

PROCESS_TABLE = 0x477c2c
EFFECT_PROCESS = 28      # PROCESS.DEF defProcEffectProcess1 → 0x415dc0
SHADOW_PROCESS = 24      # PROCESS.DEF defProcShadowLeft → 0x4010c0 (the 0x401220 afterimage)
SHADOW_OBJECT = 179      # OBJ-ALL.H obj_Shadow_Left, declared in the level OBS files
STOP = 0x1000fff0
STACK = 0x1001f000
OBJ_BASE = 0x20000000
HEAP_BASE = 0x20200000
OBJ_SIZE = 0xb0
ORIGIN = (320, 240)
DISPLACEMENT = (37, -23)
SEED = (0x12345678, 0x87654321)   # the image's initial 0x4795d4／0x4795d8 words
FRAME_LIMIT = 3000
# RNG state words, the seeded flag (set: no clock seeding) and the camera words.
RNG_STATE, RNG_SEEDED = (0x4795d4, 0x4795d8), 0x4c1e8c
CAMERA = (0x4c091c, 0x4c0920)

# Code executed natively: object-local reads／writes, the shared RNG and pure geometry.
REVIEWED = [
    (0x4010c0, 0x40113a, 'defProcShadowLeft: afterimage level countdown and destroy'),
    (0x401220, 0x401307, '0x401220／0x401290: afterimage object 179 copying shape, mode|engMIX, level 6'),
    (0x415c10, 0x415d1c, 'random spawn helper: count objects around (x, y) with growing +0xae delays'),
    (0x42dc50, 0x42dc8d, 'screen shake accumulator 0x4c1b98／0x4c1b9c add and reset'),
    (0x42dcb0, 0x42dcdf, 'integer distance'),
    (0x415d40, 0x415dc0, 'obj_Y1／obj_X2 sound wrappers 0x415d40／0x415d70／0x415d90'),
    (0x415dc0, 0x4231ae, 'defProcEffectProcess1 and the effProc* programs'),
    (0x458c10, 0x458cb3, 'RNG 0x458c10 and rand(n) 0x458c80'),
    (0x45e485, 0x45e4f8, 'object chain link／unlink'),
    (0x45e575, 0x45e642, 'shape counters: once 0x45e575, loop 0x45e5a6, ping-pong 0x45e5d9'),
    (0x45e642, 0x45ed46, 'geometry: angle／distance／step／velocity helpers, zoom setters'),
    (0x46e0f0, 0x46e0fb, 'sqrt'),
    (0x46e720, 0x46e747, 'float to int'),
]
# Calls answered in Python: object pool (0x45e307 create, 0x45e3ed destroy), the sound
# player 0x42c180 (recorded), the heap (0x457b70 alloc, 0x457c20 free), the shape registry
# (0x45fc01 name → handle, 0x4606a9 handle → SHP origin and size, read from hsl.pak).
CREATE, DESTROY, SOUND, ALLOC, FREE, SHAPE_BY_NAME, SHAPE_METRICS = 0x45e307, 0x45e3ed, 0x42c180, 0x457b70, 0x457c20, 0x45fc01, 0x4606a9
SHAKE = (0x4c1b98, 0x4c1b9c)

FIELDS = {'obj_mode': 0x00, 'obj_plane': 0x0c, 'obj_x1': 0x10, 'obj_y1': 0x14, 'obj_x2': 0x18, 'obj_y2': 0x1c,
          'obj_zoomx': 0x20, 'obj_zoomy': 0x24, 'obj_data': 0x28, 'obj_shapesub': 0x2c, 'obj_process_code': 0x64,
          'obj_collide_x1': 0x68, 'obj_collide_y1': 0x6c, 'obj_collide_x2': 0x70, 'obj_collide_y2': 0x74,
          'obj_shape_delay': 0x7c, 'obj_attribute': 0x80, 'obj_score': 0x84, 'obj_hitpoint': 0x88,
          **{f'obj_data{i}': 0x8c + 4 * (i - 1) for i in range(1, 10)}}


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


class Unreviewed(Exception):
    def __init__(self, callee: int, code: int, frame: int):
        super().__init__(f'unreviewed code {callee:#x} (object {code}, frame {frame})')
        self.callee = callee


def table_defines(process_def: str) -> dict[str, int]:
    table: dict[str, int] = {}
    texts = [process_def] + [(TABLES / name).read_text(encoding='cp950', errors='replace')
                             for name in ('TYPE.H', 'SHAPEDEF.H', 'resource.h', 'OBJ-ALL.H')]
    for text in texts:
        for name, value in re.findall(r'^\s*#define\s+(\w+)\s+(-?(?:0x[0-9a-fA-F]+|\d+))', text, re.M):
            table.setdefault(name, int(value, 0))
        for name, value in re.findall(r'^(\w+)\s*=\s*(\d+)', text, re.M):
            table.setdefault(name, int(value))
    return table


def member_series(name: str, count: int) -> list[str]:
    """obj_Shape_Name + obj_Shape_Number → the consecutive SHP members (the skill_effects
    importer's convention: the trailing number counts up, width kept)."""
    found = re.match(r'^(.*?)(\d+)(\.SHP)$', name, re.I)
    if not found:
        return [name]
    stem, digits, suffix = found.groups()
    return [f'{stem}{int(digits) + index:0{len(digits)}d}{suffix}' for index in range(count)]


class Machine:
    """One unicorn machine with the EXE image, a synthetic object pool and the frame loop."""

    def __init__(self, exe_image, templates: 'Templates', sounds: dict[int, str], metrics):
        from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_CODE
        base, mapped = exe_image
        self.m = Uc(UC_ARCH_X86, UC_MODE_32)
        self.m.mem_map(base, len(mapped)); self.m.mem_write(base, bytes(mapped))
        self.m.mem_map(0x10000000, 0x20000)
        self.m.mem_map(OBJ_BASE, 0x400000)
        self.registry = templates
        self.templates, self.sounds, self.metrics = templates.bytes, sounds, metrics
        self.write(RNG_SEEDED, 1)
        self.write(RNG_STATE[0], SEED[0]); self.write(RNG_STATE[1], SEED[1])
        self.planes: dict[int, list[dict]] = {}
        self.objects: list[dict] = []
        self.next_object = OBJ_BASE
        self.next_heap = HEAP_BASE
        self.frame = 0
        self.current: dict | None = None
        self.events: list[list] = []
        self.m.hook_add(UC_HOOK_CODE, self._guard)

    def write(self, at: int, value: int, fmt: str = '<I') -> None:
        self.m.mem_write(at, struct.pack(fmt, value & (0xffffffff if fmt == '<I' else 0xffff)))

    def read(self, at: int, fmt: str = '<i') -> int:
        return struct.unpack(fmt, self.m.mem_read(at, struct.calcsize(fmt)))[0]

    def create(self, x: int, y: int, code: int) -> dict:
        """0x45e307: copy the 0xb0-byte template, +0x80 |= 0xb0000000, x／y, code, plane,
        append at the plane list's tail."""
        if code not in self.templates:
            raise Unreviewed(CREATE, code, self.frame)
        address = self.next_object; self.next_object += OBJ_SIZE
        self.m.mem_write(address, self.templates[code])
        self.write(address + 0x80, self.read(address + 0x80, '<I') | 0xb0000000)
        self.write(address + 4, x); self.write(address + 8, y)
        self.write(address + 0x54, code)
        plane = struct.unpack_from('<i', self.templates[code], 0x0c)[0]
        self.write(address + 0x58, plane)
        obj = {'address': address, 'code': code, 'plane': plane, 'id': len(self.objects),
               'parent': self.current['id'] if self.current else -1, 'born': self.frame, 'dead': None, 'samples': []}
        self.objects.append(obj)
        self.planes.setdefault(plane, []).append(obj)
        return obj

    def _return(self, value: int) -> None:
        from unicorn.x86_const import UC_X86_REG_EAX, UC_X86_REG_ESP, UC_X86_REG_EIP
        esp = self.m.reg_read(UC_X86_REG_ESP)
        self.m.reg_write(UC_X86_REG_EAX, value & 0xffffffff)
        self.m.reg_write(UC_X86_REG_EIP, self.read(esp, '<I'))
        self.m.reg_write(UC_X86_REG_ESP, esp + 4)

    def _guard(self, m, at, _size, _data) -> None:
        from unicorn.x86_const import UC_X86_REG_ESP
        if at == STOP:
            m.emu_stop(); return
        if at in (CREATE, DESTROY, SOUND, ALLOC, FREE, SHAPE_BY_NAME, SHAPE_METRICS):
            esp = m.reg_read(UC_X86_REG_ESP)
            args = [self.read(esp + 4 + 4 * index) for index in range(4)]
            value = 0
            if at == CREATE:
                child = self.create(args[0], args[1], args[2])
                value = child['address']
            elif at == DESTROY:
                self.destroy(args[0] & 0xffffffff)
            elif at == SOUND:
                self.events.append([self.frame, 'sound', self.current['id'], self.sounds.get(args[0], str(args[0]))])
            elif at == ALLOC:
                value = self.next_heap; self.next_heap += (args[0] + 15) & ~15
            elif at == SHAPE_BY_NAME:
                name = bytes(m.mem_read(args[0] & 0xffffffff, 64)).split(b'\0')[0].decode('ascii')
                value = self.registry.shape(name)
            elif at == SHAPE_METRICS:
                origin_x, origin_y, width, height = self.metrics(self.registry.member(args[0] & 0xffff))
                for pointer, word in zip(args[1:4] + [self.read(esp + 20)], (origin_x, origin_y, width, height)):
                    self.write(pointer & 0xffffffff, word)
            self._return(value)
            return
        if not any(low <= at < high for low, high, _ in REVIEWED):
            raise Unreviewed(at, self.current['code'] if self.current else -1, self.frame)

    def destroy(self, address: int) -> None:
        """0x45e3ed: clear the live bit, unlink the chain (+0x5c／+0x60), leave the plane list."""
        for obj in self.objects:
            if obj['address'] == address and obj['dead'] is None:
                obj['dead'] = self.frame
                self.planes[obj['plane']].remove(obj)
        previous, following = self.read(address + 0x5c, '<I'), self.read(address + 0x60, '<I')
        if previous:
            self.write(previous + 0x60, following)
        if following:
            self.write(following + 0x5c, previous)
        self.write(address + 0x80, self.read(address + 0x80, '<I') & 0x7fffffff)

    def process(self, obj: dict) -> None:
        from unicorn.x86_const import UC_X86_REG_ESP, UC_X86_REG_EIP
        code = self.read(obj['address'] + 0x64)
        if code not in (EFFECT_PROCESS, SHADOW_PROCESS):
            raise Unreviewed(self.read(PROCESS_TABLE + 4 * code, '<I'), obj['code'], self.frame)
        entry = self.read(PROCESS_TABLE + 4 * code, '<I')
        self.current = obj
        self.m.mem_write(STACK, struct.pack('<3I', STOP, obj['address'], self.read(obj['address'] + 0x80, '<I')))
        self.m.reg_write(UC_X86_REG_ESP, STACK)
        self.m.emu_start(entry, STOP, count=400000)
        if self.m.reg_read(UC_X86_REG_EIP) != STOP:
            raise ValueError(f'object {obj["code"]} did not return at frame {self.frame}')

    def step(self) -> None:
        """One frame: the process walk (next link read before each call), then the draw walk."""
        for plane in sorted(self.planes):
            chain = self.planes[plane]
            index = 0
            while index < len(chain):
                obj = chain[index]
                following = chain[index + 1] if index + 1 < len(chain) else None
                self.process(obj)
                if following is None:
                    break
                index = chain.index(following) if following in chain else len(chain)
        camera = [self.read(CAMERA[0]), self.read(CAMERA[1]), self.read(SHAKE[0]), self.read(SHAKE[1])]
        if camera != [0, 0, 0, 0]:
            self.events.append([self.frame, 'camera', camera])
        for plane in sorted(self.planes):
            for obj in self.planes[plane]:
                address = obj['address']
                flags = self.read(address + 0x80, '<I')
                if flags & 0x600000:
                    raise Unreviewed(0x45f688 if flags & 0x200000 else 0x45f6e2, obj['code'], self.frame)
                if flags & 0x10000000:
                    self.write(address + 0x80, flags & ~0x10000000)
                    continue
                shape = self.read(address + 0x30, '<H')
                if shape == 0xffff:
                    continue
                obj['samples'].append([self.frame, self.read(address + 4) - ORIGIN[0], self.read(address + 8) - ORIGIN[1], shape,
                                       self.read(address, '<I'), self.read(address + 0x28), self.read(address + 0x20), self.read(address + 0x24)])
        self.frame += 1

    def run_root(self, code: int, displacement: tuple[int, int]) -> None:
        root = self.create(ORIGIN[0] + displacement[0], ORIGIN[1] + displacement[1], code)
        self.write(root['address'] + 0xaa, ORIGIN[0], '<H'); self.write(root['address'] + 0xa8, ORIGIN[1], '<H')
        for _ in range(FRAME_LIMIT):
            self.step()
            if all(obj['dead'] is not None for obj in self.objects):
                return
        raise ValueError(f'object {code} still alive after {FRAME_LIMIT} frames')


class Templates:
    """global.obs (+ obj_Shadow_Left from a level OBS) → 0xb0-byte templates as 0x45dc5c writes them."""

    def __init__(self, obs_texts: list[bytes], defines: dict[str, int]):
        self.defines = defines
        self.sounds: dict[str, int] = {}
        self.shape_bases: dict[str, int] = {}
        self.bytes: dict[int, bytes] = {}
        self.rows: dict[int, dict] = {}
        for text in obs_texts:
            for row in blocks(text, 'Object'):
                code = int(row['obj_code'])
                if code in self.bytes:
                    continue
                self.rows[code] = row
                self.bytes[code] = self.template(row)

    def value(self, text: str) -> int:
        text = text.strip()
        if re.match(r'^-?(0x[0-9a-fA-F]+|\d+)$', text):
            return int(text, 0)
        if text in self.defines:
            return self.defines[text]
        if text.upper().startswith('WAV\\'):
            return self.sounds.setdefault(text.upper(), 0x100 + len(self.sounds))
        raise ValueError(f'global.obs value {text!r} is neither a number, a define nor a WAV')

    def template(self, row: dict) -> bytes:
        data = bytearray(OBJ_SIZE)
        lower = {key.lower(): value for key, value in row.items()}
        for field, offset in FIELDS.items():
            if field in lower:
                struct.pack_into('<I', data, offset, self.value(lower[field]) & 0xffffffff)
        struct.pack_into('<H', data, 0x7e, struct.unpack_from('<H', data, 0x7c)[0])
        name = lower.get('obj_shape_name', '')
        number = self.value(lower.get('obj_shape_number', '1')) if name else 0
        struct.pack_into('<i', data, 0x78, number); struct.pack_into('<H', data, 0x7a, number)
        handle = self.shape(name, number) if name else 0xffff
        struct.pack_into('<H', data, 0x30, handle); struct.pack_into('<H', data, 0x32, handle)
        return bytes(data)

    def shape(self, name: str, number: int = 0) -> int:
        """A handle block per SHP series: base + k is member k (a stand-in for the sorted
        registry 0x45fc01 searches: consecutive names get consecutive handles)."""
        key = name.upper()
        if key not in self.shape_bases:
            self.shape_bases[key] = 0x100 + 0x40 * len(self.shape_bases)
        return self.shape_bases[key]

    def member(self, handle: int) -> str:
        for name, base in self.shape_bases.items():
            if base <= handle < base + 0x40:
                return member_series(name, handle - base + 1)[-1]
        raise ValueError(f'shape handle {handle:#x} outside every registered series')


def scope_objects() -> dict[str, dict]:
    scope = json.loads(SCOPE.read_text(encoding='utf-8'))
    names = sorted({name for row in scope['rows'].values() if row['channel'] == 'magic' for name in row['objects']})
    return {name: scope['objects'][name] for name in names if name in scope['objects']}


def compact(values: list[int]) -> list[list[int]]:
    """Run-length pairs [value, count]."""
    runs: list[list[int]] = []
    for value in values:
        if runs and runs[-1][0] == value:
            runs[-1][1] += 1
        else:
            runs.append([value, 1])
    return runs


def encode_instances(machine: Machine, members: dict[str, int]) -> list[dict]:
    instances = []
    for obj in machine.objects:
        samples = obj['samples']
        if not samples:
            instances.append({'code': obj['code'], 'parent': obj['parent'], 'born': obj['born'], 'dead': obj['dead'], 'start': -1})
            continue
        start, end = samples[0][0], samples[-1][0]
        by_frame = {sample[0]: sample for sample in samples}
        columns: dict[str, list[int]] = {key: [] for key in ('x', 'y', 'member', 'mode', 'level', 'zoom_x', 'zoom_y')}
        for frame in range(start, end + 1):
            sample = by_frame.get(frame)
            if sample is None:
                row = [0, 0, -1, 0, 0, 0, 0]
            else:
                member = machine.registry.member(sample[3])
                row = [sample[1], sample[2], members.setdefault(member, len(members)), sample[4], sample[5], sample[6], sample[7]]
            for key, value in zip(columns, row):
                columns[key].append(value)
        instance = {'code': obj['code'], 'parent': obj['parent'], 'born': obj['born'], 'dead': obj['dead'], 'start': start,
                    'x': columns['x'], 'y': columns['y']}
        for key in ('member', 'mode', 'level', 'zoom_x', 'zoom_y'):
            instance[key] = compact(columns[key])
        instances.append(instance)
    return instances


def motion_class(first: Machine, second: Machine) -> str:
    """translates: the displaced run is the plain run shifted by DISPLACEMENT; anchored: the
    same positions (driven from the origin in +0xaa／+0xa8); mixed: same shape of samples,
    neither; reshaped: a different sample count."""
    a = [(s[0], s[1], s[2]) for obj in first.objects for s in obj['samples']]
    b = [(s[0], s[1], s[2]) for obj in second.objects for s in obj['samples']]
    if len(a) != len(b) or [s[0] for s in a] != [s[0] for s in b]:
        return 'reshaped'
    if all(q[1] == p[1] + DISPLACEMENT[0] and q[2] == p[2] + DISPLACEMENT[1] for p, q in zip(a, b)):
        return 'translates'
    if a == b:
        return 'anchored'
    return 'mixed'


def execute_packet(exe: Path) -> dict:
    from hsltools.data.world_map import PakReader
    reader = PakReader(exe.parent)
    process_def = reader.read('@:\\data\\PROCESS.DEF')
    level_obs = reader.read('@:\\data\\obj-051.obs')
    defines = table_defines(process_def.decode('cp950'))
    obs = GLOBAL_OBS.read_bytes()
    templates = Templates([obs, level_obs], defines)
    if SHADOW_OBJECT not in templates.bytes:
        raise ValueError('obj_Shadow_Left (179) missing from obj-051.obs')
    sound_names = {value: name for name, value in templates.sounds.items()}
    from hsltools.sources.shp import parse_shp
    shp_cache: dict[str, tuple[int, int, int, int]] = {}

    def metrics(member: str) -> tuple[int, int, int, int]:
        if member not in shp_cache:
            found = reader.find('@:\\' + member)
            if found is None:
                raise ValueError(f'{member} missing from hsl.pak (0x4606a9 metrics)')
            raw = reader.read(found)
            meta = parse_shp(raw)
            origin = struct.unpack_from('<ii', raw, 0x1c)
            shp_cache[member] = (origin[0], origin[1], meta['width'], meta['height'])
        return shp_cache[member]

    exe_image = image(exe.read_bytes())
    members: dict[str, int] = {}
    objects, unrestored = {}, {}
    for name, entry in scope_objects().items():
        code = int(entry['obj_code'])
        try:
            first = Machine(exe_image, templates, sound_names, metrics); first.run_root(code, (0, 0))
            second = Machine(exe_image, templates, sound_names, metrics); second.run_root(code, DISPLACEMENT)
        except Unreviewed as stop:
            unrestored[name] = {'code': code, 'effect_process': entry['effect_process'], 'callee': f'{stop.callee:#x}', 'reason': str(stop)}
            continue
        objects[name] = {'code': code, 'effect_process': entry['effect_process'], 'motion': motion_class(first, second),
                         'frames': first.frame, 'instances': encode_instances(first, members),
                         'sounds': [[event[0], event[3]] for event in first.events if event[1] == 'sound'],
                         'camera': [[event[0], *event[2]] for event in first.events if event[1] == 'camera']}
    by_process: dict[str, list[bool]] = {}
    for name, entry in scope_objects().items():
        by_process.setdefault(entry['effect_process'], []).append(name in objects)
    return {'schema': SCHEMA, 'exe_sha256': EXE_SHA, 'native_execution': True, 'evidence_tier': 'static-derived',
            'sources': {'global_obs': digest(obs), 'process_def': digest(process_def), 'obj_051_obs': digest(level_obs)},
            'origin': list(ORIGIN), 'displacement_probe': list(DISPLACEMENT), 'seed': [f'{SEED[0]:#010x}', f'{SEED[1]:#010x}'],
            'engine_modes': {name: defines[name] for name in sorted(defines) if name.startswith('eng')},
            'reviewed': [[f'{low:#x}', f'{high:#x}', note] for low, high, note in REVIEWED],
            'members': sorted(members, key=members.get),
            'processes': {'restored': sorted(p for p, flags in by_process.items() if all(flags)),
                          'partial': sorted(p for p, flags in by_process.items() if any(flags) and not all(flags)),
                          'unrestored': sorted(p for p, flags in by_process.items() if not any(flags))},
            'objects': objects, 'unrestored': unrestored,
            'limits': ['One RNG seed per root object: random programs (spray angles, sway phase, spawn offsets) are one '
                       'sample of the original distribution, replayed identically for every instance.',
                       'The effect origin is fixed at (320,240) with the camera at (0,0); camera words written by quake '
                       'programs are recorded (camera), not applied here.',
                       'A child appended behind the tail of its plane list is processed from the next frame '
                       '(0x45f5f7 reads the next link before each call); the root is created before frame 0 as if by an '
                       'interpreter in a lower plane — ±1 frame where the real list order differs.',
                       'Objects stopped at an unreviewed callee (shape synthesis 0x460541, screen distortion 0x46164b, '
                       'shape lookup 0x45fc01, SHP metrics 0x4606a9, camera follow 0x43bf30, …) are listed in unrestored '
                       'and keep the remake player\'s provisional static drawing.']}


# ---------------------------------------------------------------- independent model

def decode_track(instance: dict) -> list[tuple]:
    """Instance columns → [(frame, x, y, member, mode, level, zoom_x, zoom_y)] for drawn frames."""
    runs = {key: [value for value, count in instance[key] for _ in range(count)] for key in ('member', 'mode', 'level', 'zoom_x', 'zoom_y')}
    rows = []
    for index in range(len(instance['x'])):
        if runs['member'][index] < 0:
            continue
        rows.append((instance['start'] + index, instance['x'][index], instance['y'][index], runs['member'][index],
                     runs['mode'][index], runs['level'][index], runs['zoom_x'][index], runs['zoom_y'][index]))
    return rows


def check(packet: dict) -> None:
    if packet.get('schema') != SCHEMA or packet.get('exe_sha256') != EXE_SHA or packet.get('native_execution') is not True:
        raise ValueError('effect motion identity differs')
    if packet['sources']['global_obs'] != digest(GLOBAL_OBS.read_bytes()):
        raise ValueError('global.obs changed: regenerate effect_motion')
    scope = scope_objects()
    tracked, stopped = set(packet['objects']), set(packet['unrestored'])
    if tracked & stopped or tracked | stopped != set(scope):
        raise ValueError('effect motion scope differs from the MAGIC-script objects of special_effect_scripts.json')
    for name, row in packet['objects'].items():
        if row['code'] != int(scope[name]['obj_code']) or row['effect_process'] != scope[name]['effect_process']:
            raise ValueError(f'{name}: code／effect process differ from the scope')
        if row['motion'] not in ('translates', 'anchored', 'mixed', 'reshaped'):
            raise ValueError(f'{name}: unknown motion class')
        for instance in row['instances']:
            if instance['start'] < 0:
                continue
            length = len(instance['x'])
            if len(instance['y']) != length or any(sum(count for _, count in instance[key]) != length for key in ('member', 'mode', 'level', 'zoom_x', 'zoom_y')):
                raise ValueError(f'{name}: instance columns differ in length')
            if any(value >= len(packet['members']) for value, _ in instance['member']):
                raise ValueError(f'{name}: member index out of range')
    from hsltools.probes import _effect_motion_model as effect_motion_model
    effect_motion_model.verify(packet)


def summary_line(packet: dict, executed_now: bool) -> str:
    processes = packet['processes']
    return (f'EFFECT_MOTION_NATIVE_PASS objects={len(packet["objects"])} unrestored={len(packet["unrestored"])} '
            f'processes={len(processes["restored"])}+{len(processes["partial"])}/'
            f'{len(processes["restored"]) + len(processes["partial"]) + len(processes["unrestored"])} executed_now={executed_now}')


class EffectMotionTask(PacketTask):
    """The native probe whose packet is a runtime input: generate writes compact JSON (the
    tracks are per-frame integer arrays), check validates it offline (identity, sources,
    scope, the tracer model)."""
    name = 'effect_motion'
    family = 'probe'
    packet = PACKET.relative_to(ROOT).as_posix()
    outputs = (packet,)
    inputs = ('content/imported/hsl/global/tables/', 'content/imported/hsl/shared/first_skill/global.obs',
              'content/imported/hsl/shared/command_menu/native_layout.json',
              'content/generated/hsl/skills/special_effect_scripts.json')
    scripts = ('tools/hsltools/probes/effect_motion.py', 'tools/hsltools/probes/_effect_motion_model.py')
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


TASK = EffectMotionTask()


def tasks() -> list[PacketTask]:
    return [TASK]
