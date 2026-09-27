"""Independent model of the 幻火 tracer programs, checked against the native effect_motion tracks.

The static reading of docs/evidence_packets/static_reverse/original_effect_motion.md written as
plain Python: the effect-object process prologue (0x415dc0..0x415e9e), effProcFlyDrop
(0x416095), effProcFireAndBomb／effProcFireAndBomb2 (0x41618a, jump table 0x42337c),
effProcSprayUpDown (0x4162e6), effProcSpray (0x416409), the random spawn helper 0x415c10,
the RNG 0x458c10／0x458c80, the shape counters 0x45e575／0x45e5a6, the velocity helpers
0x45eb9d／0x45ebdc／0x45eb75, the object creator 0x45e307 and the frame loop of 0x45f5f7
(process walk reading the next link before each call, then the draw walk that skips a
creation-flagged object once). verify(packet) rebuilds the three 幻火 objects' instance trees
from global.obs and the tracked cos／sin tables and requires them to equal the packet's native
tracks sample for sample (every instance, position, member, mode, level and zoom).
"""
from __future__ import annotations

import json
import re

from hsltools.paths import ROOT
from hsltools.sources.tables import blocks

GLOBAL_OBS = ROOT / 'content/imported/hsl/shared/first_skill/global.obs'
TRIG = ROOT / 'content/imported/hsl/shared/command_menu/native_layout.json'
TRACER = ('obj_Effect_FlyDrop', 'obj_Effect_FireBomb', 'obj_Effect_FireBomb2')
EFFECT_PROCS = {'effProcFlyDrop': 5, 'effProcFireAndBomb': 6, 'effProcSprayUpDown': 7, 'effProcSpray': 8, 'effProcFireAndBomb2': 9}
ENG_ZOOM, ENG_ADDCOLOR, ENG_MIX = 0x08000000, 0x04000000, 0x20000000
MASK = 0xffffffff


def s32(value: int) -> int:
    value &= MASK
    return value - (1 << 32) if value & 0x80000000 else value


def s16(value: int) -> int:
    value &= 0xffff
    return value - 0x10000 if value & 0x8000 else value


def sar(value: int, count: int) -> int:
    return s32(value) >> (count & 31)


def shl(value: int, count: int) -> int:
    return (value << (count & 31)) & MASK


class Model:
    def __init__(self, seed: tuple[int, int]):
        trig = json.loads(TRIG.read_text(encoding='utf-8'))['tables']
        self.cos, self.sin = trig['x'], trig['y']
        self.state = [seed[0], seed[1]]
        self.last_angle = 0          # 0x4c1a9c
        self.templates = {}
        for row in blocks(GLOBAL_OBS.read_bytes(), 'Object'):
            self.templates[int(row['obj_code'])] = row
        self.objects: list[dict] = []
        self.chain: list[dict] = []
        self.frame = 0
        self.current: dict | None = None

    # 0x458c10: two rotating words; 0x458c80: rand(n) = (rng & 0xffff) % n for n ≤ 0xffff.
    def rng(self) -> int:
        a = (self.state[0] + 1) & MASK
        b = (self.state[1] - 1) & MASK
        r = b & 31
        a2 = (sar(a, 32 - r) + shl(a, r)) & MASK
        r2 = a2 & 31
        b2 = (shl(b, 32 - r2) + sar(b, r2)) & MASK
        self.state = [a2, b2]
        return (a2 + b2) & MASK

    def rand(self, n: int) -> int:
        return 0 if n == 0 else (self.rng() & 0xffff) % n

    def create(self, x: int, y: int, code: int) -> dict:
        """0x45e307 over the global.obs template (the fields the tracer programs read)."""
        row = self.templates[code]
        zoom = lambda key: int(row.get(key, '0'), 16) if row.get(key, '').startswith('0x') else 0
        obj = {'code': code, 'x': x, 'y': y, 'mode': ENG_ZOOM if row.get('obj_Mode') == 'engZOOM' else 0,
               'zoom_x': zoom('obj_ZoomX'), 'zoom_y': zoom('obj_ZoomY'), 'level': 0, 'hit_point': int(row.get('obj_HitPoint', '0'), 0),
               'proc': EFFECT_PROCS[row['obj_Data9']], 'phase': 0, 'delay': 0, 'base_x': 0, 'base_y': 0, 'base_set': False,
               'first': 0, 'shape': 0xffff, 'count': int(row['obj_Shape_Number']), 'count_reload': int(row['obj_Shape_Number']),
               'hold': int(row['obj_Shape_Delay']), 'hold_reload': int(row['obj_Shape_Delay']),
               'initialising': True, 'skip_draw': True, 'd90': 0, 'd92': 0, 'd94': 0, 'd98': 0, 'd9c': 0, 'd96': 0,
               'id': len(self.objects), 'parent': self.current['id'] if self.current else -1, 'born': self.frame, 'dead': None, 'samples': []}
        self.objects.append(obj)
        self.chain.append(obj)
        return obj

    def destroy(self, obj: dict) -> None:
        obj['dead'] = self.frame
        self.chain.remove(obj)

    # Shape counters: 0x45e575 once-through (holds the last shape), 0x45e5a6 looping.
    @staticmethod
    def advance(obj: dict, loop: bool) -> bool:
        obj['hold'] -= 1
        if obj['hold'] >= 0:
            return False
        obj['hold'] = obj['hold_reload']
        obj['shape'] += 1
        obj['count'] -= 1
        if obj['count'] > 0:
            return False
        if loop:
            obj['count'] = obj['count_reload']
            obj['shape'] -= obj['count_reload']
        else:
            obj['count'] = 1
            obj['shape'] -= 1
        return True

    def spawn(self, x: int, y: int, code: int, x_range: int, y_range: int, delay: int, delay_range: int, count: int) -> None:
        """0x415c10 (actor reference 0): offsets rand(range) folded to (−range/2, range/2], the
        +0xae delay growing by rand(delay_range) + 1 per object."""
        half_x, half_y = int(x_range / 2), int(y_range / 2)
        for _ in range(count):
            dx = self.rand(x_range)
            if dx > half_x:
                dx = half_x - dx
            dy = self.rand(y_range)
            if dy > half_y:
                dy = half_y - dy
            child = self.create(x + dx, y + dy, code)
            child['delay'] = delay
            delay += self.rand(delay_range) + 1

    def velocity(self, obj: dict, angle: int, speed: int) -> None:
        """0x45eb9d: +0x90 = cos·speed >> 16, +0x98 = sin·speed >> 16, fractions cleared."""
        obj['d90'] = s32((self.cos[angle] * speed) >> 16)
        obj['d98'] = s32((self.sin[angle] * speed) >> 16)
        obj['d94'] = obj['d9c'] = 0

    @staticmethod
    def integrate(obj: dict) -> None:
        """0x45ebdc: add velocity to the 16-bit fractions, move by the integer parts."""
        sx = s32(obj['d90'] + obj['d94'])
        sy = s32(obj['d98'] + obj['d9c'])
        obj['d94'], obj['d9c'] = sx & 0xffff, sy & 0xffff
        obj['x'] += sar(sx, 16)
        obj['y'] += sar(sy, 16)

    def spread_angle(self, angle: int) -> int:
        """Keep a new spark at least 4 steps from the previous one (0x4c1a9c)."""
        if abs(angle - self.last_angle) < 4:
            angle = (angle + 32) & 0xff
        self.last_angle = angle
        return angle

    def process(self, obj: dict) -> None:
        self.current = obj
        if obj['initialising']:
            obj['shape'] = 0xffff
            obj['delay'] = s16(obj['delay'] - 1)
            if obj['delay'] > 0:
                return
            obj['delay'] = 0
            obj['shape'] = obj['first']
            obj['initialising'] = False
            obj['mode'] |= ENG_ADDCOLOR
            obj['level'] = 16
            if not obj['base_set']:
                obj['base_x'], obj['base_y'], obj['base_set'] = obj['x'], obj['y'], True
        getattr(self, f'proc_{obj["proc"]}')(obj)

    def proc_5(self, obj: dict) -> None:
        """effProcFlyDrop: 90 px above, sway 16·sin with 6/256 turn per tick, fall 1 px per
        tick, shapes once, then 16 fading levels under engMIX."""
        if obj['phase'] == 0:
            obj['phase'] = 1
            obj['y'] -= 90
            obj['d90'] = self.rand(0xff) & 0xff
            obj['d92'] = 6
            obj['d94'] = 16
        if obj['phase'] == 2:
            obj['level'] -= 1
            if obj['level'] <= 0:
                self.destroy(obj)
                return
        elif self.advance(obj, loop=False):
            obj['mode'] |= ENG_MIX
            obj['phase'] += 1
        obj['y'] += 1
        obj['d90'] = (obj['d90'] + obj['d92']) & 0xff
        obj['x'] = obj['base_x'] + sar(self.sin[obj['d90']] * obj['d94'], 16)

    def proc_6(self, obj: dict) -> None:
        """effProcFireAndBomb (and 9, effProcFireAndBomb2): rise 24 px and throw three
        SprayUpDown sparks, loop the shapes once at the template zoom, shrink 1/32 per tick to
        0.25, loop 24 more ticks; FireAndBomb2 throws 2×6 Spray sparks 12 ticks in."""
        phase = obj['phase']
        if phase == 0:
            obj['y'] -= 24
            obj['d94'] = 12
            obj['phase'] = 1
            self.spawn(obj['x'], obj['y'], 163, 16, 8, 0, 12, 3)
        if phase <= 1:
            if self.advance(obj, loop=True):
                obj['phase'] = 2
                obj['mode'] |= ENG_ZOOM
                obj['zoom_x'] = obj['zoom_y'] = 0x10000
                obj['d90'] = 0x800
        elif phase == 2:
            self.advance(obj, loop=True)
            zoom = obj['zoom_x'] - obj['d90']
            if zoom <= 0x4000:
                zoom = 0x4000
                obj['phase'] = 3
                obj['d90'] = 24
            obj['zoom_x'] = obj['zoom_y'] = zoom
        else:
            self.advance(obj, loop=True)
            obj['d90'] -= 1
            if obj['d90'] <= 0:
                self.destroy(obj)
                return
        if obj['proc'] == 9 and obj['d94'] != 0:
            obj['d94'] -= 1
            if obj['d94'] == 0:
                self.spawn(obj['x'], obj['y'], 164, 16, 8, 0, 2, 6)
                self.spawn(obj['x'], obj['y'], 164, 16, 8, 12, 2, 6)

    proc_9 = proc_6

    def proc_7(self, obj: dict) -> None:
        """effProcSprayUpDown: an upward angle 128..255 kept off the horizontal, speed
        2.125..3.06 px, gravity 1/8 px per tick² up to 4 px, gone after its shapes."""
        if obj['phase'] == 0:
            obj['phase'] = 1
            angle = (self.rng() & 0x7f) + 0x80
            if angle > 0xf0:
                angle -= 16
            elif angle < 0x90:
                angle += 16
            angle = self.spread_angle(angle)
            self.velocity(obj, angle, (self.rng() & 0xf000) + 0x22000)
        if obj['hit_point']:
            raise ValueError('SprayUpDown afterimage branch is outside the tracer')
        self.integrate(obj)
        obj['d98'] = min(obj['d98'] + 0x2000, 0x40000)
        if self.advance(obj, loop=False):
            self.destroy(obj)

    def proc_8(self, obj: dict) -> None:
        """effProcSpray: any angle, speed 2..3.94 px, shapes once, then 16 levels under engMIX."""
        phase = obj['phase']
        if phase == 0:
            obj['phase'] = 1
            angle = self.spread_angle(self.rng() & 0xff)
            self.velocity(obj, angle, (self.rng() & 0x1f000) + 0x20000)
        elif phase == 1:
            if self.advance(obj, loop=False):
                obj['mode'] |= ENG_MIX
                obj['phase'] = 2
        else:
            obj['level'] -= 1
            if obj['level'] <= 0:
                self.destroy(obj)
                return
        if obj['hit_point']:
            raise ValueError('Spray afterimage branch is outside the tracer')
        self.integrate(obj)

    def step(self) -> None:
        index = 0
        while index < len(self.chain):
            obj = self.chain[index]
            following = self.chain[index + 1] if index + 1 < len(self.chain) else None
            self.process(obj)
            if following is None:
                break
            index = self.chain.index(following)
        for obj in self.chain:
            if obj['skip_draw']:
                obj['skip_draw'] = False
                continue
            if obj['shape'] == 0xffff:
                continue
            obj['samples'].append((self.frame, obj['x'], obj['y'], obj['shape'], obj['mode'], obj['level'], obj['zoom_x'], obj['zoom_y']))
        self.frame += 1

    def run(self, code: int, origin: tuple[int, int]) -> None:
        root = self.create(origin[0], origin[1], code)
        root['base_x'], root['base_y'], root['base_set'] = origin[0], origin[1], True
        while self.chain:
            self.step()


def verify(packet: dict) -> None:
    from hsltools.probes.effect_motion import decode_track, member_series
    seed = tuple(int(word, 16) for word in packet['seed'])
    origin = tuple(packet['origin'])
    members = packet['members']
    for name in TRACER:
        row = packet['objects'].get(name)
        if row is None:
            raise ValueError(f'tracer object {name} has no native track')
        model = Model(seed)
        model.run(row['code'], origin)
        if len(model.objects) != len(row['instances']):
            raise ValueError(f'{name}: model spawned {len(model.objects)} objects, native {len(row["instances"])}')
        for obj, instance in zip(model.objects, row['instances']):
            template = model.templates[obj['code']]
            series = member_series(template['obj_Shape_Name'].upper(), int(template['obj_Shape_Number']))
            expected = [(frame, x - origin[0], y - origin[1], members.index(series[shape]), mode, level, zx, zy)
                        for frame, x, y, shape, mode, level, zx, zy in obj['samples']]
            if (obj['code'], obj['parent'], obj['born'], obj['dead']) != (instance['code'], instance['parent'], instance['born'], instance['dead']):
                raise ValueError(f'{name}: instance {obj["id"]} identity differs from the native run')
            native = decode_track(instance)
            if expected != native:
                first = next(index for index, pair in enumerate(zip(expected, native)) if pair[0] != pair[1]) if len(expected) == len(native) else -1
                raise ValueError(f'{name}: instance {obj["id"]} model track differs from native (first sample {first})')
