"""Original reward／birth random draws under the _enemy_level referee (diagnostic; registers no task).

Which stream the drop roll 0x44f580, the birth carry 0x407c40 (from 0x407cc0) and the birth
jitter draw from, in what order against the opening level-up 0x40e870, and what they give from a
known state — the inputs the remake's BattleRewardRules must reproduce. Every rand(n) 0x458c80
and raw 0x458c10 call is logged with its call site (return - 5; inside the damage wrappers
0x42c780／0x42c720 the wrapper's caller, stream 'damage') and the global words 0x4795d4／0x4795d8
before it; events: 0x407cc0 birth (object, live mode 0x40ba20 at 0x407e3b), 0x407c40 carry
(shape +0x2e table code, TOWNDEF list 0x44e100, result via 0x436e30), 0x40e870 level-up,
0x44f580 drop (bag live +0x138, result via 0x44f2d0).

  birth  --level N [--seed A B]: a cold enter_level (the booted engine cache only) to the first
         round sort; with --seed the global words and seeded flag 0x4c1e8c are written first.
  drop   --level N --unit ID --bag CODE,CODE.. --seeds 1..32: at the level's cached round-1 halt,
         per seed s the global words = [s, s ^ 0xe54a231c] (0x458bb0's seed), the unit's bag =
         the codes, then 0x44f580(unit) runs nested with 0x44f2d0 stubbed (recorded).
  carry  --level N --unit ID --seeds 1..32: the same for 0x407c40(unit), 0x436e30 stubbed.
  kill   --level N --board B --board-key K [--set ..] --bag ID=CODE,CODE.. [--seed A B]:
         run_level rounds with the bags written at the halt; every 0x44f580 the exchange reaches
         is logged with its draws (a natural kill in the original frame loop).

  uv run --no-project --with unicorn==2.1.4 --python /opt/homebrew/bin/python3 python3 \\
    tools/hsltools/probes/_reward_rng_trace.py birth --level 53 --out ignored/rngc/birth53.json

Readings: docs/evidence_packets/static_reverse/battle_reward_inputs.md.
"""
import argparse
import json
import sys
from pathlib import Path

if __package__ in (None, ''):   # `python3 tools/hsltools/probes/_reward_rng_trace.py`
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from hsltools.paths import ORIGINAL_EXE  # noqa: E402
from hsltools.probes import _enemy_level as lv  # noqa: E402
from hsltools.probes import enemy_turn as et  # noqa: E402

SCHEMA = 'hsl_reward_rng_trace.v1'
BIRTH, CARRY, CARRY_INSERT, GROWTH, DROP, DROP_GIVE = 0x407cc0, 0x407c40, 0x436e30, 0x40e870, 0x44f580, 0x44f2d0
LIVE_MODE, TOWN_LIST = 0x40ba20, 0x44e100
BAG, BAG_SLOTS, SHAPE_CARRY = 0x138, 8, 0x2e
SEED_XOR = 0xe54a231c


class Tracer:
    """Hooks every draw and the reward／birth entries; events in call order."""

    def __init__(self, machine, names=None, stub_gives=False) -> None:
        from hsltools.native.battle_machine import RAND_INNER_RETURNS
        self.m, self.names, self.inner = machine, names or {}, RAND_INNER_RETURNS
        self.events: list[dict] = []
        self.pending: list[tuple] = []
        self.wrappers: list[int] = []
        m = machine
        m.hook(et.RAND, lambda: self.pending.append((m.arg(0), m.return_address(), self.words())))
        for at in et.RAND_RETURNS:
            m.hook(at, self._rand_out)
        m.hook(0x458c10, self._raw_in)
        m.hook(et.RAW_RETURN, self._raw_out)
        for entry, ret in ((et.DAMAGE_RAND, et.DAMAGE_RAND_RET), (et.DAMAGE_RAW, et.DAMAGE_RAW_RET)):
            m.hook(entry, lambda: self.wrappers.append(m.return_address() - 5))
            m.hook(ret, lambda: self.wrappers.pop())
        m.hook(BIRTH, lambda: self.event('birth', m.arg(0)))
        m.hook(CARRY, self._carry)
        m.hook(GROWTH, lambda: self.event('growth', m.arg(0)))
        m.hook(DROP, self._drop)
        if stub_gives:
            m.hook(CARRY_INSERT, lambda: (self.event('carry_insert', m.arg(0), code=m.arg(1)), m.ret(0)))
            m.hook(DROP_GIVE, lambda: (self.event('drop_give', None, code=m.arg(0), count=m.arg(1)), m.ret(0)))
        else:
            m.hook(CARRY_INSERT, lambda: self.event('carry_insert', m.arg(0), code=m.arg(1)))
            m.hook(DROP_GIVE, lambda: self.event('drop_give', None, code=m.arg(0), count=m.arg(1)))
        self._raw_state = []

    def words(self) -> list[int]:
        return [self.m.get(et.GLOBAL_STATE[0]), self.m.get(et.GLOBAL_STATE[1])]

    def record(self, obj: int) -> int:
        return self.m.get(et.LIVE_TABLE) + et.LIVE_SIZE * self.m.get(obj + et.OBJ_LIVE)

    def name(self, obj):
        if obj is None:
            return None
        return self.names.get(obj) or f'obj{obj:#x}/code{self.m.get(self.record(obj)):03d}'

    def event(self, kind: str, obj, **fields) -> None:
        self.events.append(dict(kind=kind, unit=self.name(obj), global_before=self.words(), **fields))

    def _carry(self) -> None:
        obj = self.m.arg(0)
        self.event('carry', obj, table=self.m.get16(self.record(obj) + SHAPE_CARRY))

    def resolve(self) -> None:
        """Outside the run (halted): each carry event's TOWNDEF list 0x44e100(table)."""
        lists = {}
        for event in self.events:
            if event['kind'] == 'carry' and event['table']:
                if event['table'] not in lists:
                    listed, codes = self.m.call_nested(TOWN_LIST, event['table']), []
                    while listed and len(codes) < 32 and self.m.get(listed + 4 * len(codes)):
                        codes.append(self.m.geti(listed + 4 * len(codes)))
                    lists[event['table']] = codes
                event['choices'] = lists[event['table']]

    def _drop(self) -> None:
        obj = self.m.arg(0)
        record = self.record(obj)
        self.event('drop', obj, bag=[self.m.get(record + BAG + 4 * i) for i in range(BAG_SLOTS)])

    def _draw(self, site: int, stream: str, n, value: int, before) -> None:
        self.events.append(dict(kind='draw', site=f'{site:#x}', stream=stream, n=n, value=value, global_before=before,
                                global_after=self.words()))

    def _rand_out(self) -> None:
        n, back, before = self.pending.pop()
        damage = back == et.DAMAGE_RAND_INNER
        self._draw(self.wrappers[-1] if damage else back - 5, 'damage' if damage else 'global', n, self.m.eax(), before)

    def _raw_in(self) -> None:
        self._raw_state.append(self.words())

    def _raw_out(self) -> None:
        before = self._raw_state.pop()
        back = self.m.return_address()
        if back in self.inner:
            return
        damage = back == et.DAMAGE_RAW_INNER
        self._draw(self.wrappers[-1] if damage else back - 5, 'damage' if damage else 'global', None, self.m.eax(), before)


def seed_words(seed: int) -> list[int]:
    return [seed & 0xffffffff, (seed ^ SEED_XOR) & 0xffffffff]


def birth(args) -> dict:
    machine, _ = lv.booted_machine(ORIGINAL_EXE)
    for slot in lv.carried_slots(args.level):
        machine.call_checked(lv.SLOT_ENABLE, slot)
    if args.seed:
        machine.put(et.GLOBAL_STATE[0], args.seed[0]); machine.put(et.GLOBAL_STATE[1], args.seed[1]); machine.put(et.SEEDED, 1)
    driver = lv.LevelDriver(machine, True, tuple(lv.MENU_CHOICES.get(args.level, ())))
    driver.limit = lv.OPENING_FRAMES
    tracer = Tracer(machine)
    machine.hook(lv.ROUND_SORT, lambda: machine.halt('round_sort'))
    machine.enter_level(args.level, driver.on_frame)
    names = et.remake_names(machine, lv.battle_path(args.level), by_coord=True) if machine.halted == 'round_sort' else {}
    tracer.resolve()
    for event in tracer.events:   # opening names are only known at the halt: map obj/code strings afterwards
        unit = event.get('unit')
        if unit and unit.startswith('obj'):
            obj = int(unit.split('/')[0][3:], 16)
            event['unit'] = names.get(obj, unit)
    return dict(stop=machine.halted or machine.stop_reason, frame=driver.frame, events=tracer.events)


def nested(args, fn: int, bag: list[int] | None) -> dict:
    machine, driver, info = lv.round_sort_machine(ORIGINAL_EXE, args.level, True, True, tuple(lv.carried_slots(args.level)),
                                                  tuple(lv.MENU_CHOICES.get(args.level, ())))
    names = et.remake_names(machine, lv.battle_path(args.level), by_coord=True)
    obj = {v: k for k, v in names.items()}[args.unit]
    tracer = Tracer(machine, names, stub_gives=True)
    record = tracer.record(obj)
    saved_bag = [machine.get(record + BAG + 4 * i) for i in range(BAG_SLOTS)]
    saved_words = tracer.words()
    rows = []
    for seed in args.seeds:
        words = seed_words(seed)
        machine.put(et.GLOBAL_STATE[0], words[0]); machine.put(et.GLOBAL_STATE[1], words[1]); machine.put(et.SEEDED, 1)
        for i in range(BAG_SLOTS):
            machine.put(record + BAG + 4 * i, (bag[i] if bag and i < len(bag) else 0) if bag is not None else saved_bag[i])
        tracer.events = []
        machine.call_nested(fn, obj)
        tracer.resolve()
        rows.append(dict(seed=seed, state=words, after=tracer.words(), events=tracer.events))
    for i in range(BAG_SLOTS):
        machine.put(record + BAG + 4 * i, saved_bag[i])
    machine.put(et.GLOBAL_STATE[0], saved_words[0]); machine.put(et.GLOBAL_STATE[1], saved_words[1])
    return dict(unit=args.unit, bag=bag, opening=info, rows=rows)


class KillObserver:
    def __init__(self, bags: dict[str, list[int]]) -> None:
        self.bags = bags
        self.tracer = None

    def attach(self, machine, run, names) -> None:
        ids = {v: k for k, v in names.items()}
        self.tracer = Tracer(machine, names)
        for unit, codes in self.bags.items():
            record = self.tracer.record(ids[unit])
            for i in range(BAG_SLOTS):
                machine.put(record + BAG + 4 * i, codes[i] if i < len(codes) else 0)


def kill(args) -> dict:
    bags = {}
    for text in args.bag or []:
        unit, codes = text.split('=')
        bags[unit] = [int(c) for c in codes.split(',') if c]
    observer = KillObserver(bags)
    record = lv.run_level(ORIGINAL_EXE, args.level, lv.load_board(args.board, args.board_key), args.turns,
                          tuple(args.seed) if args.seed else None, None, args.set or (), observer=observer)
    events = observer.tracer.events
    first = next((i for i, e in enumerate(events) if e['kind'] == 'drop'), None)
    window = events[max(0, first - 4):] if first is not None else []
    return dict(stop=record['meta']['stop'], actions=[{k: a.get(k) for k in ('actor', 'action', 'target')} for a in record['actions']],
                drop_window=window[:40],
                drops=[e for e in events if e['kind'] in ('drop', 'drop_give')])


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('mode', choices=('birth', 'drop', 'carry', 'kill'))
    parser.add_argument('--level', type=int, required=True)
    parser.add_argument('--unit')
    parser.add_argument('--bag', action='append')
    parser.add_argument('--seeds', default='1..32')
    parser.add_argument('--seed', type=lambda v: int(v, 0), nargs=2)
    parser.add_argument('--board', type=Path)
    parser.add_argument('--board-key')
    parser.add_argument('--set', action='append', type=et.parse_edit)
    parser.add_argument('--turns', type=int, default=1)
    parser.add_argument('--out', type=Path)
    args = parser.parse_args(argv)
    low, _, high = args.seeds.partition('..')
    args.seeds = list(range(int(low), int(high or low) + 1))
    if args.mode == 'birth':
        result = birth(args)
    elif args.mode == 'drop':
        result = nested(args, DROP, [int(c) for c in args.bag[0].split(',')])
    elif args.mode == 'carry':
        result = nested(args, CARRY, None)
    else:
        result = kill(args)
    result = dict(schema=SCHEMA, mode=args.mode, level=args.level, **result)
    text = json.dumps(result, ensure_ascii=False, indent=1)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text + '\n', encoding='utf-8')
    else:
        print(text)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
