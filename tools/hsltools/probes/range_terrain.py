"""Original range propagation over map words (0x4000 wall flag and occupant side bits).

Two native builders are executed on small grids that carry 0x4000 wall words and
occupant side words (0x10000 P, 0x20000 E, 0x40000 N, 0x70000 pmALL, 0x800000 magic-only):

  weapon  0x40f8b0(px, py, range, mode, flag5) -> 0x40f5d0 flood into 0x4c1b48
          (player weapon 0x444156 mode 2 flag5 1; magic/special cast 0x444eb7 mode -1 flag5 0)
  area    0x4100e0(obj, px, py, range, mode) -> 0x40fdc0 flood (matrix) or a straight line
          for RANGE 21..23 into 0x4c1b4c (effect areas 0x444f08 / 0x4450e0, AI 0x40bab0 modes)

check() compares every returned coverage byte with an independent model of the
instructions (bounds, 0x4000 stop, zero cell stop, coverage>=power stop, side-mask write
gate, onward 0x40eb80 wall check, DFS order). The actor list 0x4c34c0 is empty, so 0x40fc90
finds nobody and the 0x850000 skip depends on the word only; heights are not read.

Registry task range_terrain (family probe, hsltools.probes._base.ProbeTask).
"""
from __future__ import annotations
from pathlib import Path
import re
import struct

from hsltools.data import compact_json_text
from hsltools.native.image import EXE_SHA, image
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask
from hsltools.sources.tables import TABLES, digest

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_range_terrain.json'
SCHEMA = 'hsl_range_terrain_native.v1'
WALL, P, E, N, ALL, MAGIC = 0x4000, 0x10000, 0x20000, 0x40000, 0x70000, 0x800000
# Origin/line side exclusion (tables 0x40fa48 and 0x410498, identical): mode -> mask; other modes none.
ORIGIN_EXCLUSION = {0: P, 1: P, 2: P, 3: E, 4: P, 5: E, 7: N, 8: 0x60000, 9: 0x50000, 10: 0x30000}
# Flood step tables: mode -> (exclusion, onward 0x4000 check).
WEAPON_STEP = {2: (P, True), 3: (E, True), 4: (P, False), 5: (E, False), 6: (0, False), 7: (N, True),
               8: (0x60000, True), 9: (0x50000, True), 10: (0x30000, True)}  # 0x40f874, default (0, False)
AREA_STEP = {0: (0, False), 1: (0, False), 2: (P, True), 3: (E, True), 4: (P, False), 5: (E, False), 6: (0, True),
             7: (N, True), 8: (0x60000, True), 9: (0x50000, True), 10: (0x30000, True)}  # 0x4100a0, default (0, True)
LINE_CODES = {'range3CellDir': 21, 'range4CellDir': 22, 'range5CellDir': 23}
GRIDS = {
    'open': dict(size=15, words=[]),
    # Walls east/north-west/south of (7,7); occupants of every side around it; the caster word sits at (7,7).
    'wall': dict(size=15, words=[[9, 5, WALL], [9, 6, WALL], [9, 7, WALL], [9, 8, WALL], [5, 4, WALL], [6, 4, WALL],
                                 [7, 10, WALL], [6, 7, P], [7, 5, E], [8, 8, N], [5, 9, ALL | MAGIC], [4, 7, ALL],
                                 [10, 6, E], [7, 7, P]]),
    # One pillar two cells north and one occupant-free wall pair west: onward checks without side masks.
    'pillar': dict(size=15, words=[[7, 5, WALL], [4, 6, WALL], [4, 7, WALL]]),
    # 3x3 bodies (size_type 1; 0x411a30 writes the side word on all nine cells): an E body around (7,7)
    # with a wall right above it and one beside its lower right cell, a P body around (11,11), an E body
    # in the (1,1) corner, a magic-only pmALL and an N occupant.
    'large': dict(size=15, words=[[x, y, E] for y in (6, 7, 8) for x in (6, 7, 8)]
                  + [[x, y, P] for y in (10, 11, 12) for x in (10, 11, 12)]
                  + [[x, y, E] for y in (0, 1, 2) for x in (0, 1, 2)]
                  + [[7, 5, WALL], [9, 8, WALL], [4, 7, ALL | MAGIC], [7, 11, N]]),
}
MATRIX = ['range1Cell', 'range2Cell', 'range3Cell', 'range3CellShoot', 'range4CellShoot', 'range5CellShoot',
          'range6CellShoot', 'range2CellCircle', 'range3CellCircle', 'range4CellCircle', 'range3CellThrust',
          'range4CellThrust', 'range1CellFull', 'range2CellFull', 'range3CellFull', 'range4CellFull']


def record(code):
    """RANGE.TXT record: size and signed row-major data (Dir records keep their size only)."""
    blocks = (TABLES / 'RANGE.TXT').read_bytes().decode('cp950').split('[range]')[1:]
    block = next(b for b in blocks if re.search(r'^code\s*=\s*' + code + r'\s*$', b, re.M))
    size = int(re.search(r'^size\s*=\s*(\d+)', block, re.M)[1])
    rows = [[int(v) for v in text.split(',')] for text in re.findall(r'^data\s*=\s*([^\r\n;]+)', block, re.M)]
    if code in LINE_CODES:
        return dict(size=size, data=[])
    if len(rows) != size or any(len(r) != size for r in rows):
        raise ValueError(f'Source range dimensions differ: {code}')
    return dict(size=size, data=[v for row in rows for v in row])


def cases():
    out = []
    for grid in ['open', 'wall', 'pillar']:
        for code in MATRIX:
            out.append(dict(builder='weapon', grid=grid, code=code, origin=[7, 7], mode=2, flag5=1))
            out.append(dict(builder='weapon', grid=grid, code=code, origin=[7, 7], mode=-1, flag5=0))
    for code in ['range2Cell', 'range4CellShoot', 'range3CellCircle', 'range2CellFull']:
        for mode in [3, 7, 8, 9, 10]:
            out.append(dict(builder='weapon', grid='wall', code=code, origin=[7, 7], mode=mode, flag5=1))
        out.append(dict(builder='weapon', grid='wall', code=code, origin=[7, 7], mode=2, flag5=0))
        out.append(dict(builder='weapon', grid='wall', code=code, origin=[1, 13], mode=2, flag5=1))
    # A 3x3 actor: 0x40fa80 passes its anchor (+4/+8, the body centre) and 0x409090 its index +17
    # (range1..4CellFull). Weapon/counter/in-range from the E body, the same in the map corner, the
    # station coverage 0x40fa80(target, range, mode, 0) around the P body and 0x40d8b0's first body
    # cell (px-32, py-32); a P-controlled 3x3 actor (mode 2) from the P body.
    for code in ['range1CellFull', 'range2CellFull', 'range3CellFull', 'range4CellFull']:
        out.append(dict(builder='weapon', grid='large', code=code, origin=[7, 7], mode=3, flag5=1))
        out.append(dict(builder='weapon', grid='large', code=code, origin=[1, 1], mode=3, flag5=1))
        out.append(dict(builder='weapon', grid='large', code=code, origin=[11, 11], mode=3, flag5=0))
    out.append(dict(builder='weapon', grid='large', code='range2CellFull', origin=[10, 10], mode=3, flag5=0))
    out.append(dict(builder='weapon', grid='large', code='range2CellFull', origin=[11, 11], mode=2, flag5=1))
    for grid in ['open', 'wall', 'pillar']:
        for code in ['range1Cell', 'range2Cell', 'range1CellFull', 'range2CellCircle', 'range3CellCircle',
                     'range2CellFull', 'range3CellThrust', 'range4CellCircle']:
            for mode in [2, 3, -1]:
                out.append(dict(builder='area', grid=grid, code=code, caster=[7, 7], target=[7, 7], mode=mode))
            out.append(dict(builder='area', grid=grid, code=code, caster=[7, 7], target=[8, 6], mode=3))
    for code in ['range2Cell', 'range3CellCircle']:
        for mode in [7, 8, 9, 10]:
            out.append(dict(builder='area', grid='wall', code=code, caster=[7, 7], target=[7, 7], mode=mode))
    for grid in ['open', 'wall', 'pillar']:
        for code in LINE_CODES:
            for target in [[8, 7], [7, 6], [6, 7], [7, 8], [7, 7], [7, 4], [11, 7]]:
                for mode in [2, 3]:
                    out.append(dict(builder='area', grid=grid, code=code, caster=[7, 7], target=target, mode=mode))
    return out


def words_for(grid):
    spec = GRIDS[grid]; w = spec['size']; words = [0] * (w * w)
    for x, y, value in spec['words']:
        words[y * w + x] = value
    return w, words


def local_frame(c):
    """(local width, local height, map offset x, map offset y) of the returned coverage."""
    w, _ = words_for(c['grid']); size = record(c['code'])['size']
    if c['builder'] == 'area' and c['code'] in LINE_CODES:
        length = 1 if c['caster'] == c['target'] else size
        side = 2 * length - 1
        return side, side, c['target'][0] - (length - 1), c['target'][1] - (length - 1)
    lw = lh = min(size, w)
    anchor = c['origin'] if c['builder'] == 'weapon' else c['target']
    return lw, lh, anchor[0] - lw // 2, anchor[1] - lh // 2


def onward_clear(words, w, h, x, y, direction):
    """0x40eb80(x, y, dir, 0x4000): the three cells ahead/sideways of a step; off-map reads 0."""
    ahead = {0: [(x - 1, y), (x + 1, y), (x, y - 1)], 1: [(x - 1, y), (x + 1, y), (x, y + 1)],
             2: [(x, y - 1), (x, y + 1), (x - 1, y)], 3: [(x, y - 1), (x, y + 1), (x + 1, y)]}[direction]
    return not any(0 <= ax < w and 0 <= ay < h and words[ay * w + ax] & WALL for ax, ay in ahead)


def model(c):
    """Independent model of the native coverage bytes (row-major local frame)."""
    w, words = words_for(c['grid']); h = w
    rec = record(c['code']); size = rec['size']; half = size >> 1
    lw, lh, ox, oy = local_frame(c)
    cov = [0] * (lw * lh)
    mode = c['mode']
    if c['builder'] == 'area' and c['code'] in LINE_CODES:
        excl = ORIGIN_EXCLUSION.get(mode, 0)
        (tx, ty), (ax, ay) = c['target'], c['caster']
        dx, dy = (1 if tx > ax else -1, 0) if tx != ax else (0, 1 if ty > ay else -1)
        length = 1 if (tx, ty) == (ax, ay) else size
        x, y, lx, ly = tx, ty, length - 1, length - 1
        for remaining in range(length - 1, -1, -1):
            if not (0 <= x < w and 0 <= y < h) or words[y * w + x] & WALL:
                break
            word = words[y * w + x]
            if not (word & excl and word & ALL != ALL) and word & 0x870000 != 0x850000:
                cov[ly * lw + lx] = remaining + 1
            x += dx; y += dy; lx += dx; ly += dy
        return cov
    data = rec['data']
    ax, ay = c['origin'] if c['builder'] == 'weapon' else c['target']
    cx, cy = lw // 2, lh // 2
    word = words[ay * w + ax]; excl = ORIGIN_EXCLUSION.get(mode, 0)
    if c['builder'] == 'weapon':
        if not word & excl:
            cov[cy * lw + cx] = half + 1
        step_excl, check = WEAPON_STEP.get(mode, (0, False))
    else:
        if (not word & excl or word & ALL == ALL) and word & 0x870000 != 0x850000:
            cov[cy * lw + cx] = half + 1
        step_excl, check = AREA_STEP.get(mode, (0, True))
    flag5 = c.get('flag5', 0)

    def visit(x, y, power, lx, ly, direction):
        while True:
            if not (0 <= x < w and 0 <= y < h):
                return
            word = words[y * w + x]
            if word & WALL:
                return
            index = ly * lw + lx
            value = data[index]
            if value == 0 or cov[index] >= power:
                return
            if value > 0:
                if c['builder'] == 'weapon':
                    skip = bool(word & step_excl) and (word & ALL != ALL or bool(flag5 and word & MAGIC))
                else:
                    skip = (bool(word & step_excl) and word & ALL != ALL) or word & 0x870000 == 0x850000
                if not skip:
                    cov[index] = power
                if check and not onward_clear(words, w, h, x, y, direction):
                    power = 0
            power -= 1
            if power <= 0:
                return
            if direction == 0:
                visit(x, y - 1, power, lx, ly - 1, 0); visit(x - 1, y, power, lx - 1, ly, 2)
                x, lx, direction = x + 1, lx + 1, 3
            elif direction == 1:
                visit(x, y + 1, power, lx, ly + 1, 1); visit(x - 1, y, power, lx - 1, ly, 2)
                x, lx, direction = x + 1, lx + 1, 3
            elif direction == 2:
                visit(x, y - 1, power, lx, ly - 1, 0); visit(x, y + 1, power, lx, ly + 1, 1)
                x, lx = x - 1, lx - 1
            else:
                visit(x, y - 1, power, lx, ly - 1, 0); visit(x, y + 1, power, lx, ly + 1, 1)
                x, lx = x + 1, lx + 1

    visit(ax, ay - 1, half, cx, cy - 1, 0)
    visit(ax, ay + 1, half, cx, cy + 1, 1)
    visit(ax - 1, ay, half, cx - 1, cy, 2)
    visit(ax + 1, ay, half, cx + 1, cy, 3)
    return cov


WEAPON_RANGES = [(0x40f5d0, 0x40faa4), (0x40eb40, 0x40ecb0)]
AREA_RANGES = [(0x4100e0, 0x4104a0), (0x40fdc0, 0x4100e0), (0x40fc90, 0x40fdb3), (0x407800, 0x40793c),
               (0x446b30, 0x446b59), (0x40eb40, 0x40ecb0)]


def execute(base, mapped, c):
    from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_BLOCK
    from unicorn.x86_const import UC_X86_REG_EIP, UC_X86_REG_ESP
    m = Uc(UC_ARCH_X86, UC_MODE_32); m.mem_map(base, len(mapped)); m.mem_write(base, bytes(mapped)); m.mem_map(0x10000000, 0x20000)
    obj, actor, grid, coverage, table, shape, stack, stop = 0x10001000, 0x10002000, 0x10003000, 0x10005000, 0x10006000, 0x10007000, 0x1001ff00, 0x10000000
    w, words = words_for(c['grid']); rec = record(c['code'])

    def put(at, v):
        m.mem_write(at, struct.pack('<I', v & 0xffffffff))
    for at, value in [(0x4c0934, w), (0x4c0938, w), (0x4c0928, grid), (0x476b3c, w), (0x476b40, w), (0x4c1b48, coverage),
                      (0x4c1b4c, coverage), (0x4c1b58, table), (0x4c1bc8, actor)]:
        put(at, value)
    for i in range(24):
        put(table + 4 * i, shape)
    m.mem_write(0x4c34c0, bytes(200 * 4))
    m.mem_write(grid, struct.pack(f'<{len(words)}I', *words))
    m.mem_write(coverage, bytes([0x5a]) * 0x400)  # the builders clear their own local frame
    m.mem_write(shape, bytes([rec['size']] + [v & 255 for v in rec['data']] + ([1] * rec['size'] if not rec['data'] else [])))
    index = LINE_CODES.get(c['code'], 0)
    if c['builder'] == 'weapon':
        px, py = [v * 32 + 16 for v in c['origin']]
        args, entry, allowed = [stop, px, py, index, c['mode'], c['flag5']], 0x40f8b0, WEAPON_RANGES
    else:
        put(obj + 4, c['caster'][0] * 32 + 16); put(obj + 8, c['caster'][1] * 32 + 16); put(obj + 0xa4, 0); put(actor + 0xd8, 30)
        px, py = [v * 32 + 16 for v in c['target']]
        args, entry, allowed = [stop, obj, px, py, index, c['mode']], 0x4100e0, AREA_RANGES
    before = bytes(m.mem_read(actor, 0x1fc)) + bytes(m.mem_read(grid, w * w * 4))
    blocks = 0

    def guard(_m, at, _n, _d):
        nonlocal blocks
        blocks += 1
        if not any(lo <= at < hi for lo, hi in allowed):
            raise ValueError(f'Unreviewed range propagation block {at:#x}')
    m.hook_add(UC_HOOK_BLOCK, guard)
    m.mem_write(stack, struct.pack('<6I', *[v & 0xffffffff for v in args])); m.reg_write(UC_X86_REG_ESP, stack)
    m.emu_start(entry, stop, count=2000000)
    if m.reg_read(UC_X86_REG_EIP) != stop or m.reg_read(UC_X86_REG_ESP) != stack + 4:
        raise ValueError(f'Range propagation did not return: {c}')
    lw, lh, _ox, _oy = local_frame(c)
    if c['builder'] == 'area':
        width = struct.unpack('<2I', bytes(m.mem_read(0x476b3c, 8)))
        if width != (lw, lh):
            raise ValueError(f'Area local frame differs {c}: {width} expected {(lw, lh)}')
    else:
        width = struct.unpack('<2I', bytes(m.mem_read(0x4c1a6c, 8)))
        if width != (lw, lh):
            raise ValueError(f'Weapon local frame differs {c}: {width} expected {(lw, lh)}')
    cov = [b - 256 if b > 127 else b for b in m.mem_read(coverage, lw * lh)]
    if before != bytes(m.mem_read(actor, 0x1fc)) + bytes(m.mem_read(grid, w * w * 4)):
        raise ValueError('Range propagation changed actor/map')
    return dict(input=c, normal_return=True, entry=hex(entry), blocks=blocks, frame=list(local_frame(c)),
                coverage=bytes(v & 255 for v in cov).hex(), actor_and_map_unchanged=True)


def check(packet):
    if packet.get('schema') != SCHEMA or packet.get('exe_sha256') != EXE_SHA or packet.get('native_execution') is not True:
        raise ValueError('Range terrain original identity differs')
    if packet['sources'] != {name: digest((TABLES / name).read_bytes()) for name in ['RANGE.H', 'RANGE.TXT']}:
        raise ValueError('Range terrain source masks changed')
    if packet.get('grids') != GRIDS or [r['input'] for r in packet['cases']] != cases():
        raise ValueError('Range terrain fixtures changed')
    for r in packet['cases']:
        c = r['input']; lw, lh, _ox, _oy = local_frame(c)
        cov = [b - 256 if b > 127 else b for b in bytes.fromhex(r['coverage'])]
        if not r['normal_return'] or not r['actor_and_map_unchanged'] or r['frame'] != list(local_frame(c)) or len(cov) != lw * lh:
            raise ValueError(f'Range terrain native frame differs: {c}')
        if cov != model(c):
            raise ValueError(f'Range terrain native coverage differs from model: {c}')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base, mapped = image(exe.read_bytes())
    return dict(schema=SCHEMA, exe_sha256=EXE_SHA, native_execution=True, evidence_tier='static-derived',
                sources={name: digest((TABLES / name).read_bytes()) for name in ['RANGE.H', 'RANGE.TXT']},
                grids=GRIDS, cases=[execute(base, mapped, c) for c in cases()],
                limits=['Grids are 15x15 map words only: 0x4000 wall and occupant side bits; heights are never read by these builders.',
                        'Actor list 0x4c34c0 is empty, so 0x40fc90 finds nobody; actor-driven clearing of the word is not exercised.',
                        'Maps smaller than the RANGE record (clamped local frame) are not exercised.',
                        'Callers, cursor validation and whole action dispatch are separate.'])


def summary_line(packet: dict, executed_now: bool) -> str:
    kinds = {}
    for r in packet['cases']:
        c = r['input']; key = 'line' if c['code'] in LINE_CODES else c['builder']
        kinds[key] = kinds.get(key, 0) + 1
    return (f'RANGE_TERRAIN_NATIVE_PASS returns={len(packet["cases"])} weapon={kinds.get("weapon", 0)} '
            f'area={kinds.get("area", 0)} line={kinds.get("line", 0)} executed_now={executed_now}')


TASK = ProbeTask('range_terrain', PACKET, check, execute_packet, summary_line, replaces=(), render=compact_json_text)


def tasks() -> list[ProbeTask]:
    return [TASK]
