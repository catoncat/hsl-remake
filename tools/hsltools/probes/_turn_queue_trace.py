"""Original action-queue trace under the _enemy_level referee (diagnostic; registers no task).

Hooks the original queue calls while `_enemy_level.run_level` drives N rounds (player turns
end through the Wait path +0x8c=0x10000) and logs, per event, frame／round counter 0x4c1bbc／
queue index 0x4c6e48:

  0x4074a0 next entry (arg = [0x4c1ba0] read by 0x407510), exits 0x4074f8／0x407503;
  0x4074ec wrap call to 0x407340, 0x4074f1 round++, 0x407481／0x40748d rebuilt table
  (index, object, ready flag +8, live speed +0xb8, registry slot +4);
  0x407510 handoff (current actor, [0x4c1ba0], live +0x1b8 wait countdown);
  0x407720 unregister, 0x407660 register (+0xa2 unit, NPC cursor 0x4c1a3c);
  turn-end order 0x40e2b0 poison, 0x40e3b0／0x40e430 recovery, 0x40b910 tail, 0x408370 scan.

Injections on top of the board: --poke N:ID:V writes live speed of ID := V at the N-th
0x4074a0 entry; --kill N:ID marks ID dead (enemy_turn.apply_board) right after the N-th pick.

  uv run --no-project --with unicorn==2.1.4 --python /opt/homebrew/bin/python3 python3 \\
    tools/hsltools/probes/_turn_queue_trace.py --level 51 \\
    --board docs/evidence_packets/runtime_observations/battle_051_ai_moves/recorded_round_boards.json \\
    --board-key r1 --turns 2 [--seed S] [--set ID.FIELD=V] [--poke N:ID:V] [--kill N:ID] \\
    --out ignored/turnq/X.json

Without --board the level starts from its own opening ({"growth": false}, the oracle batch
board).  Readings: docs/evidence_packets/static_reverse/initial_battle_initiative.md
(round semantics section).
"""
import argparse
import json
import sys
from pathlib import Path

if __package__ in (None, ''):   # `python3 tools/hsltools/probes/_turn_queue_trace.py`
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from hsltools.probes import _enemy_level as lv  # noqa: E402
from hsltools.probes import enemy_turn as et  # noqa: E402

SCHEMA = 'hsl_turn_queue_trace.v1'
NEXT, NEXT_RET, NEXT_FOUND = 0x4074a0, 0x4074f8, 0x407503
WRAP_REBUILD, ROUND_INC, SORT_DONE = 0x4074ec, 0x4074f1, (0x407481, 0x40748d)
HANDOFF, UNREGISTER, REGISTER = 0x407510, 0x407720, 0x407660
TAIL, RECOVER, RECOVER_CHECK, POISON_CHECK, SCAN = 0x40b910, 0x40e430, 0x40e3b0, 0x40e2b0, 0x408370
CHAIN_FLAG, NPC_CURSOR = 0x4c1ba0, 0x4c1a3c
LIVE_SPEED, LIVE_WAIT = 0xb8, 0x1b8


class QueueObserver:
    """`_enemy_level.run_level` observer: attach() runs before the first resume."""

    def __init__(self, pokes=(), kills=()):
        self.pokes = list(pokes)
        self.kills = list(kills)
        self.events = []
        self.nexts = 0
        self.kill_done = set()
        self.kill_now = None

    def attach(self, machine, run, names):
        self.m, self.run, self.names = machine, run, names
        self.ids = {v: k for k, v in names.items()}
        m = machine
        m.hook(NEXT, self._next_in)
        m.hook(NEXT_RET, lambda: self._next_out('ret'))
        m.hook(NEXT_FOUND, lambda: self._next_out('found'))
        m.hook(WRAP_REBUILD, lambda: self._ev('wrap_rebuild'))
        m.hook(ROUND_INC, lambda: self._ev('round_inc', before=m.get16(et.ROUND)))
        for at in SORT_DONE:
            m.hook(at, lambda: self._ev('sorted', queue=self.queue()))
        m.hook(HANDOFF, lambda: self._ev('handoff', actor=self.cur(), chain_flag=m.get(CHAIN_FLAG),
                                         wait_left=self.live(self.cur_obj(), LIVE_WAIT)))
        m.hook(UNREGISTER, lambda: self._ev('unregister', obj=self.name(m.arg(0)), current=self.cur()))
        m.hook(REGISTER, lambda: self._ev('register', obj=self.name(m.arg(0)), unit=m.get16(m.arg(0) + 0xa2),
                                          next_npc_slot=m.get(NPC_CURSOR)))
        for at, kind in ((TAIL, 'tail'), (RECOVER, 'recover'), (RECOVER_CHECK, 'recover_check'),
                         (POISON_CHECK, 'poison_check')):
            m.hook(at, lambda kind=kind: self._ev(kind, obj=self.name(m.arg(0))))
        m.hook(SCAN, lambda: self._ev('scan'))
        original_resume = m.resume

        def resume(budget=0):
            while True:
                result = original_resume(budget)
                if m.halted != 'turnq_kill':
                    return result
                _, unit = self.kill_now
                obj = self.ids[et.unit_id(unit)]
                cur = self.cur_obj()
                self._ev('kill_inject', unit=unit, current=self.name(cur))
                applied = et.apply_board(m, self.names, {'dead': [unit]}, current=cur)
                self.run.removed.add(obj)
                self._ev('kill_done', applied=applied, queue=self.queue())
        m.resume = resume

    def name(self, obj):
        if not obj:
            return None
        if obj in self.names:
            return self.names[obj]
        try:
            code = self.m.get(self.m.get(et.LIVE_TABLE) + et.LIVE_SIZE * self.m.get(obj + et.OBJ_LIVE))
            return f'new{obj:#x}_code{code:03d}'
        except Exception:
            return f'obj{obj:#x}'

    def cur_obj(self):
        idx = self.m.geti(et.QUEUE_INDEX)
        return self.m.get(et.QUEUE_BASE + 12 * idx) if idx >= 0 else 0

    def cur(self):
        return self.name(self.cur_obj())

    def live(self, obj, offset):
        if not obj:
            return None
        return self.m.geti(self.m.get(et.LIVE_TABLE) + et.LIVE_SIZE * self.m.get(obj + et.OBJ_LIVE) + offset)

    def queue(self):
        out = []
        for i in range(et.REGISTRY_SLOTS):
            obj = self.m.get(et.QUEUE_BASE + 12 * i)
            if obj:
                out.append([i, self.name(obj), self.m.get(et.QUEUE_BASE + 12 * i + 8),
                            self.live(obj, LIVE_SPEED), self.m.get(et.QUEUE_BASE + 12 * i + 4)])
        return out

    def _ev(self, kind, **kw):
        self.events.append(dict(f=self.run.driver.frame, r=self.m.get16(et.ROUND), ev=kind,
                                idx=self.m.geti(et.QUEUE_INDEX), **kw))

    def _next_in(self):
        self.nexts += 1
        for n, unit, value in self.pokes:
            if n == self.nexts:
                obj = self.ids[et.unit_id(unit)]
                at = self.m.get(et.LIVE_TABLE) + et.LIVE_SIZE * self.m.get(obj + et.OBJ_LIVE) + LIVE_SPEED
                old = self.m.geti(at)
                self.m.put(at, value)
                self._ev('poke', unit=unit, speed=[old, value])
        idx = self.m.geti(et.QUEUE_INDEX)
        self._ev('next_in', n=self.nexts, arg=self.m.arg(0), current=self.cur(),
                 pending=[q[1] for q in self.queue() if q[0] > idx and q[2]])

    def _next_out(self, how):
        for n, unit in self.kills:
            if n == self.nexts and n not in self.kill_done:
                self.kill_done.add(n)
                self.kill_now = (n, unit)
                self.m.halt('turnq_kill')
                return
        self._ev('next_out', how=how, current=self.cur())


def main(argv=None):
    p = argparse.ArgumentParser(prog='_turn_queue_trace.py')
    p.add_argument('--level', type=int, required=True)
    p.add_argument('--board', type=Path)
    p.add_argument('--board-key')
    p.add_argument('--turns', type=int, default=2)
    p.add_argument('--seed', type=int, help='global stream seed pair (S, S)')
    p.add_argument('--set', dest='edits', action='append', type=et.parse_edit, default=[])
    p.add_argument('--poke', action='append', default=[], help='N:ID:V speed poke at the N-th 0x4074a0 entry')
    p.add_argument('--kill', action='append', default=[], help='N:ID kill ID right after the N-th 0x4074a0 pick')
    p.add_argument('--out', type=Path, required=True)
    a = p.parse_args(argv)
    board = lv.load_board(a.board, a.board_key) if a.board else {'growth': False}
    pokes = [(int(n), u, int(v)) for n, u, v in (x.split(':') for x in a.poke)]
    kills = [(int(n), u) for n, u in (x.split(':') for x in a.kill)]
    obs = QueueObserver(pokes, kills)
    seed = (a.seed, a.seed) if a.seed is not None else None
    turn = lv.run_level(et.ORIGINAL_EXE, a.level, board, a.turns, seed, None, a.edits, True, observer=obs)
    out = {'schema': SCHEMA,
           'meta': {k: turn['meta'][k] for k in ('stop', 'frames', 'rounds', 'round_end', 'board', 'hp_end')},
           'actions': [dict(act, frames=meta['frames'], round_counter=meta['round_counter'])
                       for act, meta in zip(turn['actions'], turn['meta']['actions'])],
           'events': obs.events}
    a.out.parent.mkdir(parents=True, exist_ok=True)
    a.out.write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding='utf-8')
    print(a.out, turn['meta']['stop'], len(obs.events), 'events', len(turn['actions']), 'actions')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
