"""Original state 0xa magic-branch trace under the _enemy_level referee (diagnostic; registers no task).

Question: where a magic offense finds no cast and falls to the side walk 0x43ff1f
(docs/evidence_packets/static_reverse/original_ai_skills.md, state 0xa 的法术落空). Places
leonard on each given cell (hp／max_hp 999, growth off), drives N rounds (player turns end
through Wait) with the batch seeds (mixed_seed(S, 20), damage mixed_seed(S + DAMAGE_MIX_OFFSET,
20)) and logs, for every 0x40d340 call made for the traced actor:

  entry     — caller, target record and cell, the two buckets, actor cell;
  mask      — 0x40c2d0(target) result (the bucket 3/4 target mask);
  picks     — each 0x40c770(bucket, mask) result and the picked skill (type [0x4c2c54], code [0x4c2c40]);
  move_use  — 0x40e270 (move_magic_use) result, then 0x40cca0's result when it runs;
  range     — 0x4097d0 cast-range index and the 0x40f8b0(x, y, range, -1, 0) reached cells;
  cover     — 0x40c9a0 cast cells whose area count (0x40cb3d ebx) is nonzero [x, y, count, has_target];
  centers   — 0x40c9a0 result (x pixel high word, y pixel low word) as a cell, 0 for none;
  ret       — the 0x40d340 result.

  uv run --no-project --with unicorn==2.1.4 --python /opt/homebrew/bin/python3 python3 \\
    tools/hsltools/probes/_spell_pick_trace.py --level 59 --actor actor060_1 \\
    --cells "40,21;37,19;35,16" --seeds 1,2,3,4,5,6,7,8 --turns 2 --out FILE
"""
import argparse
import json
import sys
from collections import Counter
from pathlib import Path

if __package__ in (None, ''):   # `python3 tools/hsltools/probes/_spell_pick_trace.py`
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from hsltools.probes import _enemy_level as lv  # noqa: E402
from hsltools.probes import enemy_turn as et  # noqa: E402

SCHEMA = 'hsl_spell_pick_trace.v1'
PLAN, PLAN_RET = 0x40d340, 0x43fee2
MASK_RET, PICK, PICK_RETS = 0x40d3a2, 0x40c770, (0x40d3b5, 0x40d3e2)
MOVE_USE_RET, MOVE_CAST_RET, RANGE_RET, FLOOD_RET, CENTER_RET = 0x40d3fd, 0x40d421, 0x40d44c, 0x40d45e, 0x40d483
COVER = 0x40cb3d
PICK_TYPE, PICK_CODE, RESUME = 0x4c2c54, 0x4c2c40, 0x4c1a40
FLOOD_W, FLOOD_H, FLOOD_BUF, FLOOD_CX, FLOOD_CY = 0x4c1a6c, 0x4c1a70, 0x4c1b48, 0x4c63a0, 0x4c639c


def cell(m, obj):
    return [m.geti(obj + 4) // 32, m.geti(obj + 8) // 32]


class Trace:
    """`_enemy_level.run_level` observer: attach() runs before the first resume."""

    def __init__(self, actor):
        self.actor = actor
        self.calls = []
        self.cur = None

    def attach(self, m, run, names):
        from unicorn.x86_const import UC_X86_REG_EBX
        boss = next(obj for obj, name in names.items() if name == self.actor)

        def plan():
            if m.arg(0) != boss:
                return
            target = m.arg(1)
            self.cur = dict(round=m.get16(et.ROUND), caller=hex(m.return_address()), resume=m.get(RESUME),
                            actor_cell=cell(m, boss), target=names.get(target, hex(target)),
                            target_cell=cell(m, target) if target else None,
                            buckets=[m.geti(m.esp() + 12), m.geti(m.esp() + 16)], flag=m.geti(m.esp() + 24),
                            picks=[], cover=[])
            self.calls.append(self.cur)

        def within(fn):
            def hook():
                if self.cur is not None:
                    fn(self.cur)
            return hook

        def pick_in(c):
            c['picks'].append(dict(bucket=m.arg(0), mask=m.arg(1)))

        def pick_out(c):
            c['picks'][-1].update(ok=m.eax(), skill=[m.get(PICK_TYPE), m.get(PICK_CODE)])

        def flood(c):
            w, h, buf = m.get(FLOOD_W), m.get(FLOOD_H), m.get(FLOOD_BUF)
            x0, y0 = m.geti(FLOOD_CX) - w // 2, m.geti(FLOOD_CY) - h // 2
            data = bytes(m.mu.mem_read(buf, w * h))
            c.setdefault('floods', []).append(dict(dims=[w, h], reached=[[x0 + i % w, y0 + i // w] for i, b in enumerate(data) if b]))

        def cover(c):
            count = m.mu.reg_read(UC_X86_REG_EBX)
            if count:
                sp = m.esp()
                c['cover'].append([m.geti(sp + 0x24) + m.geti(sp + 0x18), m.geti(sp + 0x38) + m.geti(sp + 0x14), count, m.get(sp + 0x34)])

        def center(c):
            v = m.eax()
            c.setdefault('centers', []).append([((v >> 16) & 0xffff) // 32, (v & 0xffff) // 32] if v else 0)

        def ret():
            if self.cur is not None:
                v = m.eax()
                self.cur['ret'] = v - (1 << 32) if v & 0x80000000 else v
                self.cur = None

        hooks = [(PLAN, plan), (PLAN_RET, ret), (MASK_RET, within(lambda c: c.update(mask=m.eax()))), (PICK, within(pick_in)),
                 (MOVE_USE_RET, within(lambda c: c.update(move_use=m.eax()))),
                 (MOVE_CAST_RET, within(lambda c: c.update(move_cast=m.eax()))),
                 (RANGE_RET, within(lambda c: c.setdefault('range', []).append(m.eax()))), (FLOOD_RET, within(flood)),
                 (COVER, within(cover)), (CENTER_RET, within(center))]
        hooks += [(at, within(pick_out)) for at in PICK_RETS]
        for at, fn in hooks:
            m.hook(at, fn)


def main(argv=None) -> int:
    p = argparse.ArgumentParser(prog='_spell_pick_trace.py')
    p.add_argument('--level', type=int, required=True)
    p.add_argument('--actor', required=True)
    p.add_argument('--cells', required=True, help='leonard cells "x,y;x,y"')
    p.add_argument('--seeds', required=True, help='batch seeds "1,2,..."')
    p.add_argument('--turns', type=int, default=2)
    p.add_argument('--out', type=Path, required=True)
    a = p.parse_args(argv)
    cells = [[int(v) for v in c.split(',')] for c in a.cells.split(';')]
    rows = []
    total = Counter()
    for leo in cells:
        for seed in (int(s) for s in a.seeds.split(',')):
            board = {'growth': False, 'units': {'leonard': leo}, 'max_hp': {'leonard': 999}, 'hp': {'leonard': 999}}
            trace = Trace(a.actor)
            turn = lv.run_level(et.ORIGINAL_EXE, a.level, board, a.turns, lv.mixed_seed(seed, 20),
                                lv.mixed_seed(seed + lv.DAMAGE_MIX_OFFSET, 20), (), True, observer=trace, align=True)
            acts = [dict(action=x.get('action'), skill=x.get('skill'), target=x.get('target'), to=x.get('to'))
                    for x in turn['actions'] if x.get('actor') == a.actor]
            rows.append(dict(cell=leo, seed=seed, stop=turn['meta']['stop'], actions=acts, calls=trace.calls))
            for c in trace.calls:
                total['calls'] += 1
                total['ret_' + str(c.get('ret'))] += 1
                for k in c['picks']:
                    total[f"pick_b{k['bucket']}_{'ok' if k.get('ok') else 'none'}"] += 1
                for ctr in c.get('centers', []):
                    total['center_' + ('ok' if ctr else 'zero')] += 1
    a.out.parent.mkdir(parents=True, exist_ok=True)
    a.out.write_text(json.dumps(dict(schema=SCHEMA, level=a.level, actor=a.actor, rows=rows), ensure_ascii=False, indent=1) + '\n',
                     encoding='utf-8')
    print(a.out, len(rows), 'runs', ' '.join(f'{k}={v}' for k, v in sorted(total.items())))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
