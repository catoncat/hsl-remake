"""Original mapobjCloud drift and mapobjMoveBG parallax under the _enemy_level machine
(diagnostic; registers no task).

The level is entered by the original new-level branch 0x42da60 and halted at the first round
sort (_enemy_level.round_sort_machine); the clouds have been ticking through the whole opening.
Every live pool object (base [0x4a19c0], count [0x4a19c4], stride [0x4a19c8]; in use = +0x80
bit 31) with process word +0x64 = 2 (defProcStandObject) and obj_Data9 word +0xac = 3
(mapobjCloud) or 6 (mapobjMoveBG) is listed with its position +4／+8, range +0x10..+0x1c, motion
block +0x34 (vx, x fraction, vy, y fraction), obj_Data7／8 +0xa4／+0xa8, obj_Score／HitPoint
+0x84／+0x88, saved origin +0x92／+0x90 and the frame metrics of its shape (descriptor
0x4abf28[+0x30]: +4 height, +8 width, +0xc／+0x10 draw origin).

Then, in the same process:
- drift: the original frame loop runs --ticks more frames (the level loop head hook samples every
  cloud once per frame, the same place 0x42d600 runs the object executor 0x45f5f7). The shape
  loaders of the machine are shims (0x4601a2／0x460058 return 0), so up to the halt 0x4abf28[shape]
  was empty and 0x4606a9 handed the wrap test zero width／height／origin: the halt positions carry
  wraps by the bare map size, not the original's. The frame descriptors (below) are installed at
  the halt, before this run, so the drift run and the wrap step use the original metrics;
- wrap: the frame descriptor installed is the one the SHP loader 0x45fa1e builds from the
  resource header (+4 = header +0x18 height, +8 = +0x14
  width, +0xc／+0x10 = +0x1c／+0x20 draw origin; SHP read from hsl.pak by the name the resource-id
  shim 0x45fc01 gave the shape). Each cloud is then put at its right／left (by vx sign) and
  bottom／top (by vy sign) edge, x = X2 + origin_x or X1 − width + origin_x (y alike), and its own
  process 0x43ccf0 is called with its +0x80 as the message (as the dispatcher 0x45f655 does) until
  both axes wrapped;
- parallax: each moveBG process is called with the camera [0x4c091c]／[0x4c0920] set to the
  corners and centre of the camera range [0, [0x4c0958]]／[0, [0x4c095c]].

  uv run --no-project --with unicorn==2.1.4 --python /opt/homebrew/bin/python3 python3 \\
    tools/hsltools/probes/_map_object_drift.py --level 1 --out ignored/clouddrift/L001.json

Readings: docs/evidence_packets/static_reverse/original_map_object_drift.md.
"""
import argparse
import json
import sys
from pathlib import Path

if __package__ in (None, ''):   # `python3 tools/hsltools/probes/_map_object_drift.py`
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from hsltools.paths import ORIGINAL_EXE  # noqa: E402
from hsltools.probes import _enemy_level as lv  # noqa: E402

SCHEMA = 'hsl_map_object_drift.v1'
POOL_BASE, POOL_COUNT, POOL_STRIDE = 0x4a19c0, 0x4a19c4, 0x4a19c8
IN_USE, STAND_OBJECT, CLOUD, MOVE_BG = 0x80000000, 2, 3, 6
STAND_PROC, SHAPES = 0x43ccf0, 0x4abf28
CAMERA_X, CAMERA_Y, CAMERA_MAX_X, CAMERA_MAX_Y = 0x4c091c, 0x4c0920, 0x4c0958, 0x4c095c
DEFAULT_RANGE = 0x4c0948, 0x4c094c   # the 0x43ce35／0x43ce3e substitute for a 0,0,640,480 range


def s32(value: int) -> int:
    return value - (1 << 32) if value & 0x80000000 else value


def s16(value: int) -> int:
    return value - (1 << 16) if value & 0x8000 else value


def objects(m) -> list[int]:
    base, count, stride = m.get(POOL_BASE), m.get(POOL_COUNT), m.get(POOL_STRIDE)
    found = []
    for index in range(count):
        obj = base + index * stride
        if m.get(obj + 0x80) & IN_USE and m.get16(obj + 0x64) == STAND_OBJECT and m.get16(obj + 0xac) in (CLOUD, MOVE_BG):
            found.append(obj)
    return found


def row(m, obj: int) -> dict:
    shape = m.get16(obj + 0x30)
    desc = m.get(SHAPES + 4 * shape) if shape != 0xffff else 0
    metrics = dict(height=m.geti(desc + 4), width=m.geti(desc + 8), origin=[m.geti(desc + 0xc), m.geti(desc + 0x10)]) if desc else {}
    return dict(object=hex(obj), code=m.get(obj + 0x54), kind='cloud' if m.get16(obj + 0xac) == CLOUD else 'move_bg',
                xy=[m.geti(obj + 4), m.geti(obj + 8)], range=[m.geti(obj + 0x10 + 4 * i) for i in range(4)],
                motion=[s32(m.get(obj + 0x34)), m.get16(obj + 0x38), s32(m.get(obj + 0x3c)), m.get16(obj + 0x40)],
                angle=m.geti(obj + 0xa4), speed=hex(m.get(obj + 0xa8)), score=m.geti(obj + 0x84), hit_point=m.geti(obj + 0x88),
                saved_origin=[s16(m.get16(obj + 0x92)), s16(m.get16(obj + 0x90))], mode=hex(m.get(obj)), flags=hex(m.get(obj + 0x80)),
                delay=m.get16(obj + 0xae), shape=metrics)


def drift(m, driver, clouds: list[int], ticks: int) -> list[dict]:
    samples = []
    driver.callback = lambda _idle: samples.append([[m.geti(o + 4), m.geti(o + 8)] for o in clouds])
    driver.limit = driver.frame + ticks
    m.resume()
    driver.callback = None
    if m.halted != 'frame_limit':
        raise SystemExit(f'drift run stopped: {m.halted or m.stop_reason}')
    series = []
    for index, obj in enumerate(clouds):
        xs = [s[index][0] for s in samples]
        ys = [s[index][1] for s in samples]
        series.append(dict(object=hex(obj), first=[xs[0], ys[0]], last=[xs[-1], ys[-1]], ticks=len(samples) - 1,
                           dx=xs[-1] - xs[0], dy=ys[-1] - ys[0], steps_x=sorted(set(b - a for a, b in zip(xs, xs[1:]))),
                           steps_y=sorted(set(b - a for a, b in zip(ys, ys[1:]))), first_12=[s[index] for s in samples[:12]]))
    return series


def install_descriptor(m, obj: int) -> None:
    import struct
    from hsltools.native.battle_machine import Pak
    shape = m.get16(obj + 0x30)
    if m.get(SHAPES + 4 * shape):
        return
    name = {v: k for k, v in m.resources.items()}[shape]
    header = Pak(ORIGINAL_EXE.with_name('hsl.pak')).read(name.upper())
    width, height, ox, oy = struct.unpack_from('<IIii', header, 0x14)
    desc = m.alloc(0x14)
    for offset, value in ((4, height), (8, width), (0xc, ox), (0x10, oy)):
        m.put(desc + offset, value)
    m.put(SHAPES + 4 * shape, desc)


def wrap(m, obj: int) -> dict:
    install_descriptor(m, obj)
    r = row(m, obj)
    x1, y1, x2, y2 = r['range']
    w, h, (ox, oy) = r['shape']['width'], r['shape']['height'], r['shape']['origin']
    vx, vy = r['motion'][0], r['motion'][2]
    start = [x2 + ox if vx > 0 else x1 - w + ox, y2 + oy if vy > 0 else y1 - h + oy]
    m.put(obj + 4, start[0])
    m.put(obj + 8, start[1])
    trail, events = [start], []
    for tick in range(1, 40000):
        m.call_nested(STAND_PROC, obj, m.get(obj + 0x80))
        xy = [m.geti(obj + 4), m.geti(obj + 8)]
        for axis in (0, 1):
            if abs(xy[axis] - trail[-1][axis]) > 2:
                events.append(dict(tick=tick, axis='xy'[axis], before=trail[-1][axis], after=xy[axis]))
        trail.append(xy)
        if {e['axis'] for e in events} == {'x', 'y'} or (vy == 0 and events):
            break
    return dict(object=hex(obj), start=start, width=w, height=h, origin=[ox, oy], range=r['range'], wraps=events)


def parallax(m, obj: int) -> list[dict]:
    saved = m.get(CAMERA_X), m.get(CAMERA_Y)
    max_x, max_y = m.geti(CAMERA_MAX_X), m.geti(CAMERA_MAX_Y)
    rows = []
    for cam in ((0, 0), (max_x, 0), (0, max_y), (max_x, max_y), (max_x // 2, max_y // 2)):
        m.put(CAMERA_X, cam[0])
        m.put(CAMERA_Y, cam[1])
        m.call_nested(STAND_PROC, obj, m.get(obj + 0x80))
        rows.append(dict(camera=list(cam), xy=[m.geti(obj + 4), m.geti(obj + 8)]))
    m.put(CAMERA_X, saved[0])
    m.put(CAMERA_Y, saved[1])
    return rows


def run(level: int, ticks: int, use_cache: bool) -> dict:
    m, driver, info = lv.round_sort_machine(ORIGINAL_EXE, level, True, use_cache, tuple(lv.carried_slots(level)))
    found = objects(m)
    if not found:
        raise SystemExit(f'level {level}: no live mapobjCloud／mapobjMoveBG object at the round-1 halt')
    halt = dict(camera=[m.geti(CAMERA_X), m.geti(CAMERA_Y)], camera_max=[m.geti(CAMERA_MAX_X), m.geti(CAMERA_MAX_Y)],
                default_range_substitute=[m.geti(DEFAULT_RANGE[0]), m.geti(DEFAULT_RANGE[1])], frame=driver.frame,
                objects=[row(m, o) for o in found])
    clouds = [o for o in found if m.get16(o + 0xac) == CLOUD]
    backgrounds = [o for o in found if m.get16(o + 0xac) == MOVE_BG]
    result = dict(schema=SCHEMA, level=level, opening=dict(frame=info['frame'], cache=info['cache']), halt=halt)
    for obj in clouds:
        install_descriptor(m, obj)
    if clouds:
        result['drift'] = drift(m, driver, clouds, ticks)
        result['wrap'] = [wrap(m, o) for o in clouds]
    if backgrounds:
        result['parallax'] = [dict(object=hex(o), saved_origin=row(m, o)['saved_origin'], score=row(m, o)['score'],
                                   hit_point=row(m, o)['hit_point'], samples=parallax(m, o)) for o in backgrounds]
    return result


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--level', type=int, required=True)
    parser.add_argument('--ticks', type=int, default=250)
    parser.add_argument('--out', type=Path)
    parser.add_argument('--no-cache', action='store_true')
    args = parser.parse_args(argv)
    result = run(args.level, args.ticks, not args.no_cache)
    text = json.dumps(result, ensure_ascii=False, indent=1)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text + '\n', encoding='utf-8')
    for d in result.get('drift', []):
        print(f"MAP_OBJECT_DRIFT level={args.level} {d['object']} ticks={d['ticks']} dx={d['dx']} dy={d['dy']} "
              f"steps_x={d['steps_x']} steps_y={d['steps_y']}")
    for w in result.get('wrap', []):
        print(f"MAP_OBJECT_WRAP level={args.level} {w['object']} start={w['start']} size={w['width']}x{w['height']} "
              f"origin={w['origin']} range={w['range']} wraps={[(e['axis'], e['tick'], e['before'], e['after']) for e in w['wraps']]}")
    for p in result.get('parallax', []):
        print(f"MAP_OBJECT_PARALLAX level={args.level} {p['object']} origin={p['saved_origin']} score={p['score']} "
              f"hit_point={p['hit_point']} samples={[(s['camera'], s['xy']) for s in p['samples']]}")
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
