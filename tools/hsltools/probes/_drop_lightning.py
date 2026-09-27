"""Original 打人閃電 (defProcDropLightn, process 67 → 0x43ca70) trace under the _enemy_level referee
(diagnostic; registers no task).

Question: when WINFAIL010 event 6 drops a lightning object, where it lands, whom it hits and for how
much (docs/evidence_packets/static_reverse/original_drop_lightning.md). The observer runs a level
through `_enemy_level.run_level` (player turns end through Wait) and logs:

  bolt    — each lightning object's creation message (0x43ca8a): the camera words 0x4c091c／0x4c0920,
            the global words before its two draws, then the drawn pixel (+4／+8), the handoff counter,
            round and frame, and every named actor's pixel at that moment;
  cell    — each 0x43c9d0(x, y, lo, hi) call: the pixel, the range, the unit 0x407800 found and the
            global words before its damage draw;
  hit     — the damage draw on a found unit: roll, record HP before／after, the damage shown;
  handoff — each 0x407510 entry: the ending actor [0x4c1ba0] and its pixel, the camera, counter, round.

  uv run --no-project --with unicorn==2.1.4 --python /opt/homebrew/bin/python3 python3 \\
    tools/hsltools/probes/_drop_lightning.py --level 10 --seed 1 1 --turns 3 --out FILE
"""
import argparse
import json
import sys
from pathlib import Path

if __package__ in (None, ''):   # `python3 tools/hsltools/probes/_drop_lightning.py`
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from hsltools.probes import _enemy_level as lv  # noqa: E402
from hsltools.probes import enemy_turn as et  # noqa: E402

SCHEMA = 'hsl_drop_lightning_trace.v1'
CREATE = 0x43ca8a            # creation message, before the two global draws
PLACED = 0x43cb14            # state dispatch; after CREATE the pixel is in +4／+8
CELL = 0x43c9d0              # (x, y, lo, hi)
FOUND = 0x43c9e4             # EAX = 0x407800 result
ROLLED = 0x43ca14            # EAX = rand(hi - lo + 1), EBX = lo, EDI = record
SHOWN = 0x43ca30             # EAX = damage shown, ECX = HP written
HANDOFF = 0x407510
COUNTER = 0x4c1ad4
CAMERA = (0x4c091c, 0x4c0920)
ACTOR = 0x4c1ba0             # current actor object


class LightningObserver:
    def __init__(self) -> None:
        self.events: list[dict] = []
        self.creating = None

    def attach(self, machine, run, names: dict[int, str]) -> None:
        from unicorn.x86_const import UC_X86_REG_EAX, UC_X86_REG_EBX, UC_X86_REG_ECX, UC_X86_REG_EDI, UC_X86_REG_ESI
        m, self.run = machine, run
        reg = m.mu.reg_read

        def stamp() -> dict:
            return dict(round=m.get16(et.ROUND), frame=run.frame_index, counter=m.get16(COUNTER))

        def signed(value: int) -> int:
            return value - (1 << 32) if value & 0x80000000 else value

        def create() -> None:
            self.creating = reg(UC_X86_REG_ESI)
            self.events.append(dict(kind='bolt', camera=[signed(m.get(CAMERA[0])), signed(m.get(CAMERA[1]))],
                                    global_words=[m.get(et.GLOBAL_STATE[0]), m.get(et.GLOBAL_STATE[1])],
                                    actors={name: [signed(m.get(obj + 4)), signed(m.get(obj + 8))] for obj, name in names.items()
                                            if m.get16(obj + et.OBJ_LIVE) != 0xffff}, **stamp()))

        def placed() -> None:
            if self.creating is not None and reg(UC_X86_REG_ESI) == self.creating:
                self.events[-1]['pixel'] = [signed(m.get(self.creating + 4)), signed(m.get(self.creating + 8))]
                self.creating = None

        def cell() -> None:
            self.events.append(dict(kind='cell', pixel=[signed(m.arg(0)), signed(m.arg(1))], lo=m.arg(2), hi=m.arg(3), **stamp()))

        def found() -> None:
            obj = reg(UC_X86_REG_EAX)
            self.events[-1]['unit'] = names.get(obj, f'{obj:#x}') if obj else None
            if obj:   # the damage draw follows at once: the global words before it
                self.events[-1]['global_words'] = [m.get(et.GLOBAL_STATE[0]), m.get(et.GLOBAL_STATE[1])]

        def rolled() -> None:
            record = reg(UC_X86_REG_EDI)
            self.events.append(dict(kind='hit', unit=names.get(reg(UC_X86_REG_ESI), f'{reg(UC_X86_REG_ESI):#x}'),
                                    roll=reg(UC_X86_REG_EAX), lo=reg(UC_X86_REG_EBX), hp_before=m.get(record + 0xd8), **stamp()))

        def shown() -> None:
            self.events[-1].update(damage=reg(UC_X86_REG_EAX), hp_after=reg(UC_X86_REG_ECX))

        def handoff() -> None:   # 0x407510 entry: the actor whose action just ended is [0x4c1ba0]
            actor = m.get(ACTOR)
            self.events.append(dict(kind='handoff', actor=names.get(actor, f'{actor:#x}'), at=[signed(m.get(actor + 4)), signed(m.get(actor + 8))] if actor in names else None,
                                    camera=[signed(m.get(CAMERA[0])), signed(m.get(CAMERA[1]))], **stamp()))

        m.hook(CREATE, create)
        m.hook(PLACED, placed)
        m.hook(CELL, cell)
        m.hook(FOUND, found)
        m.hook(ROLLED, rolled)
        m.hook(SHOWN, shown)
        m.hook(HANDOFF, handoff)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description='Trace the original 打人閃電 (defProcDropLightn) over N rounds.')
    lv.add_level_arguments(parser)
    args = parser.parse_args(argv)
    board = lv.load_board(args.board, args.board_key) if args.board else {'growth': False}
    observer = LightningObserver()
    seed = et.parse_seed(args.seed)
    turn = lv.run_level(args.exe, args.level, board, args.turns, seed, et.parse_seed(args.damage_seed),
                        args.edits, not args.no_cache, args.frames, observer=observer, align=args.align, choices=args.select)
    out = dict(schema=SCHEMA, level=args.level, seed=args.seed, stop=turn['meta']['stop'],
               opening_board={k: v['cell'] for k, v in turn['meta']['opening_board'].items()},
               actions=[f'{a["actor"]} {a["from"]}->{a["to"]} {a["action"]} {a["target"]}' for a in turn['actions']],
               events=observer.events)
    text = json.dumps(out, ensure_ascii=False, indent=1)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text + '\n', encoding='utf-8')
    for event in observer.events:
        if event['kind'] == 'bolt':
            print(json.dumps({k: v for k, v in event.items() if k != 'actors'}, ensure_ascii=False))
        elif event['kind'] == 'hit':
            print(json.dumps(event, ensure_ascii=False))
    print(f'stop={out["stop"]} bolts={sum(e["kind"] == "bolt" for e in observer.events)} '
          f'hits={sum(e["kind"] == "hit" for e in observer.events)} handoffs={sum(e["kind"] == "handoff" for e in observer.events)}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
