"""Original ordinary-offense exit trace under the _enemy_level referee (diagnostic; registers no task).

Question: after a magic cast finds nothing, why an immobile actor never strikes from the
ordinary category (docs/evidence_packets/static_reverse/original_ai_navigation.md, 普通进攻的
移动力 0 出口). Places leonard on each given cell (hp／max_hp 999, growth off), drives N
rounds (player turns end through Wait) with the batch seeds (mixed_seed(S, 20), damage
mixed_seed(S + DAMAGE_MIX_OFFSET, 20)) and logs for the traced actor:

  side_entry／side_roll — 0x43ff1f side walk entry, 0x43ff37 rand(100) result;
  normal_0x440041       — ordinary category entry;
  search_in／search_out — 0x40d8b0(actor, held) with its return address, and its 0x40dc47 result;
  flood_0x40f200        — the station flood radius (esp+8) and mode inside that search;
  collect_0x413390      — per call the flood buffer dims and its reached cells (nonzero, no 0x80);
  search_ret_0x440062   — 0x40d8b0 result in the ordinary category;
  move_test_0x440094    — live+0x12c read on the no-station edge;
  state_b_0x4400a2／end_turn_0x441eb8.

  uv run --no-project --with unicorn==2.1.4 --python /opt/homebrew/bin/python3 python3 \\
    tools/hsltools/probes/_normal_attack_trace.py --level 59 --actor actor060_1 \\
    --cells "40,21;37,19;35,16" --seeds 1,2,3,4,5,6,7,8 --turns 2 --out FILE
"""
import argparse
import json
import sys
from collections import Counter
from pathlib import Path

if __package__ in (None, ''):   # `python3 tools/hsltools/probes/_normal_attack_trace.py`
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from hsltools.probes import _enemy_level as lv  # noqa: E402
from hsltools.probes import enemy_turn as et  # noqa: E402

SCHEMA = 'hsl_normal_attack_trace.v1'
SIDE_ENTRY, SIDE_ROLL = 0x43ff1f, 0x43ff37
NORMAL, STATION_RET, MOVE_TEST, STATE_B, END_TURN = 0x440041, 0x440062, 0x440094, 0x4400a2, 0x441eb8
SEARCH, SEARCH_RET, FLOOD, COLLECT = 0x40d8b0, 0x40dc47, 0x40f200, 0x413390
FLOOD_W, FLOOD_H, FLOOD_BUF = 0x4c1a64, 0x4c1a68, 0x4c1b44
LIVE_MOVE = 0x12c


class Trace:
    """`_enemy_level.run_level` observer: attach() runs before the first resume."""

    def __init__(self, actor):
        self.actor = actor
        self.events = []
        self.in_search = False

    def attach(self, m, run, names):
        from unicorn.x86_const import UC_X86_REG_EBP, UC_X86_REG_EDI
        boss = next(obj for obj, name in names.items() if name == self.actor)

        def ebp():
            return m.mu.reg_read(UC_X86_REG_EBP)

        def ev(kind, **kw):
            self.events.append(dict(kind=kind, round=m.get16(et.ROUND), **kw))

        def own(kind, **fields):
            def hook():
                if ebp() == boss:
                    ev(kind, **{k: f() for k, f in fields.items()})
            return hook

        def search():
            if m.arg(0) == boss:
                self.in_search = True
                ev('search_in', held=m.arg(1), caller=hex(m.return_address()))

        def search_ret():
            if self.in_search:
                self.in_search = False
                ev('search_out', eax=m.eax())

        def flood():
            if self.in_search:
                ev('flood_0x40f200', radius=m.geti(m.esp() + 8), mode=m.get(m.esp() + 12))

        def collect():
            if self.in_search:
                w, h = m.get(FLOOD_W), m.get(FLOOD_H)
                buf = bytes(m.mu.mem_read(m.get(FLOOD_BUF), w * h))
                ev('collect_0x413390', flood_dims=[w, h], flood_reached=sum(1 for b in buf if b and not b & 0x80))

        move = lambda: m.geti(m.mu.reg_read(UC_X86_REG_EDI) + LIVE_MOVE)  # noqa: E731
        hooks = ((SIDE_ENTRY, own('side_entry')), (SIDE_ROLL, own('side_roll', roll=m.eax)),
                 (NORMAL, own('normal_0x440041')), (STATION_RET, own('search_ret_0x440062', eax=m.eax)),
                 (MOVE_TEST, own('move_test_0x440094', move=move)),
                 (STATE_B, own('state_b_0x4400a2')), (END_TURN, own('end_turn_0x441eb8')),
                 (SEARCH, search), (SEARCH_RET, search_ret), (FLOOD, flood), (COLLECT, collect))
        for at, fn in hooks:
            m.hook(at, fn)


def main(argv=None) -> int:
    p = argparse.ArgumentParser(prog='_normal_attack_trace.py')
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
    for cell in cells:
        for seed in (int(s) for s in a.seeds.split(',')):
            board = {'growth': False, 'units': {'leonard': cell}, 'max_hp': {'leonard': 999}, 'hp': {'leonard': 999}}
            trace = Trace(a.actor)
            turn = lv.run_level(et.ORIGINAL_EXE, a.level, board, a.turns, lv.mixed_seed(seed, 20),
                                lv.mixed_seed(seed + lv.DAMAGE_MIX_OFFSET, 20), (), True, observer=trace, align=True)
            acts = [dict(action=x.get('action'), skill=x.get('skill'), target=x.get('target'), to=x.get('to'))
                    for x in turn['actions'] if x.get('actor') == a.actor]
            rows.append(dict(cell=cell, seed=seed, stop=turn['meta']['stop'], actions=acts, events=trace.events))
            total.update(e['kind'] for e in trace.events)
            total.update('action_' + str(x['action']) for x in acts)
            total['flood_reached'] += sum(e.get('flood_reached', 0) for e in trace.events)
            total['move_nonzero'] += sum(1 for e in trace.events if e.get('move'))
            total['radius_nonzero'] += sum(1 for e in trace.events if e.get('radius'))
            total['search_nonzero'] += sum(1 for e in trace.events if e['kind'] == 'search_out' and e['eax'])
    a.out.parent.mkdir(parents=True, exist_ok=True)
    a.out.write_text(json.dumps(dict(schema=SCHEMA, level=a.level, actor=a.actor, rows=rows), ensure_ascii=False, indent=1) + '\n',
                     encoding='utf-8')
    print(a.out, len(rows), 'runs', ' '.join(f'{k}={v}' for k, v in sorted(total.items())))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
