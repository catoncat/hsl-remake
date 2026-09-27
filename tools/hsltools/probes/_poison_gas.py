"""Original 噴人沼氣 (defProcPoisonGas, process 71 → 0x43c7c0) trace under the _enemy_level referee
(diagnostic; registers no task).

Question: when WINFAIL032 event 9 spews gas, where, whom it poisons and with what status word
(docs/evidence_packets/static_reverse/original_poison_gas.md). The observer runs a level through
`_enemy_level.run_level` (player turns end through Wait) and logs:

  gas     — each gas object leaving state 1 (0x43c8b4, first smoke install): the script position
            (+0x92／+0x90), the drawn centre pixel (ESI／EDI), the handoff counter word 0x4c1ad4 and
            the serial deadline word 0x4c1ad6, round and frame;
  poison  — each 0x409140(record, n) call: caller (gas cell 0x43c7aa, AI terrain 0x441f05, player
            terrain 0x4454f4), unit, n, the record's +0x24 flags and +0x30 poison DWORD before／after;
  handoff — each 0x407510 entry: counter／deadline words, round.

  uv run --no-project --with unicorn==2.1.4 --python /opt/homebrew/bin/python3 python3 \\
    tools/hsltools/probes/_poison_gas.py --level 32 --seed 1 1 --turns 2 --out FILE
"""
import argparse
import json
import sys
from pathlib import Path

if __package__ in (None, ''):   # `python3 tools/hsltools/probes/_poison_gas.py`
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from hsltools.probes import _enemy_level as lv  # noqa: E402
from hsltools.probes import enemy_turn as et  # noqa: E402

SCHEMA = 'hsl_poison_gas_trace.v1'
GAS_PLACED = 0x43c8b4        # state 1, centre in ESI／EDI, before the first 0x45e307(…, 706, 0)
STATE1 = 0x43c84d            # state 1 entry: global words before the offset draws
POISON = 0x409140            # (record, n)
HANDOFF = 0x407510
COUNTER, DEADLINE = 0x4c1ad4, 0x4c1ad6
CALLERS = {0x43c7aa: 'gas_cell', 0x441f05: 'ai_terrain', 0x4454f4: 'player_terrain'}


class GasObserver:
    def __init__(self) -> None:
        self.events: list[dict] = []
        self.pending: dict | None = None
        self.global_words: list[int] = []

    def attach(self, machine, run, names: dict[int, str]) -> None:
        from unicorn.x86_const import UC_X86_REG_EBP, UC_X86_REG_EDI, UC_X86_REG_ESI
        m, self.run = machine, run
        index_names = {m.get16(obj + et.OBJ_LIVE): name for obj, name in names.items()}

        def stamp() -> dict:
            return dict(round=m.get16(et.ROUND), frame=run.frame_index, counter=m.get16(COUNTER), deadline=m.get16(DEADLINE))

        def placed() -> None:
            obj = m.mu.reg_read(UC_X86_REG_EBP)   # EBP holds the gas object here
            if m.get(m.esp() + 0x18) != 3:        # the three-smoke loop re-enters here; log its first pass
                return
            self.flush()
            self.events.append(dict(kind='gas', script_xy=[m.get16(obj + 0x92), m.get16(obj + 0x90)], global_words=self.global_words,
                                    centre=[m.mu.reg_read(UC_X86_REG_ESI), m.mu.reg_read(UC_X86_REG_EDI)], **stamp()))

        def poison() -> None:
            self.flush()
            record, n = m.arg(0), m.arg(1)
            index = (record - m.get(et.LIVE_TABLE)) // et.LIVE_SIZE
            self.pending = dict(kind='poison', caller=CALLERS.get(m.return_address(), f'{m.return_address():#x}'),
                                unit=index_names.get(index, f'record{index}'), n=n, record=record,
                                flags_before=m.get(record + 0x24), word_before=m.get(record + 0x30),
                                damage_words=[m.get(et.DAMAGE_STATE[0]), m.get(et.DAMAGE_STATE[1])], **stamp())

        def handoff() -> None:
            self.flush()
            self.events.append(dict(kind='handoff', **stamp()))

        def state1() -> None:   # 0x43c84d: before the two rand(65) offsets
            self.global_words = [m.get(et.GLOBAL_STATE[0]), m.get(et.GLOBAL_STATE[1])]

        m.hook(STATE1, state1)
        m.hook(GAS_PLACED, placed)
        m.hook(POISON, poison)
        m.hook(HANDOFF, handoff)
        self.m = m

    def flush(self) -> None:
        if self.pending is not None:
            record = self.pending.pop('record')
            self.pending.update(flags_after=self.m.get(record + 0x24), word_after=self.m.get(record + 0x30))
            self.events.append(self.pending)
            self.pending = None


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description='Trace the original poison gas (defProcPoisonGas) over N rounds.')
    lv.add_level_arguments(parser)
    args = parser.parse_args(argv)
    board = lv.load_board(args.board, args.board_key) if args.board else {'growth': False}
    observer = GasObserver()
    seed = et.parse_seed(args.seed)
    if seed is not None and getattr(args, 'mix', 0):
        seed = lv.mixed_seed(seed[0], args.mix)
    turn = lv.run_level(args.exe, args.level, board, args.turns, seed, et.parse_seed(args.damage_seed),
                        args.edits, not args.no_cache, args.frames, observer=observer, align=args.align, choices=args.select)
    observer.flush()
    out = dict(schema=SCHEMA, level=args.level, seed=args.seed, stop=turn['meta']['stop'],
               opening_board={k: v['cell'] for k, v in turn['meta']['opening_board'].items()},
               actions=[f'{a["actor"]} {a["from"]}->{a["to"]} {a["action"]} {a["target"]}' for a in turn['actions']],
               events=observer.events)
    text = json.dumps(out, ensure_ascii=False, indent=1)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text + '\n', encoding='utf-8')
    for event in observer.events:
        if event['kind'] != 'handoff':
            print(json.dumps(event, ensure_ascii=False))
    print(f'stop={out["stop"]} gas={sum(e["kind"] == "gas" for e in observer.events)} '
          f'poison={sum(e["kind"] == "poison" for e in observer.events)} handoffs={sum(e["kind"] == "handoff" for e in observer.events)}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
