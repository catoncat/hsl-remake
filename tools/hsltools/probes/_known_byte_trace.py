"""Original "known" byte trace under the _enemy_level referee (diagnostic; registers no task).

The identity strip (0x434d10) prints ??? while byte 0x4c6d80[obj+0xa2] is 0
(docs/evidence_packets/static_reverse/original_identity_bar.md). This observer runs the original
frame loop through `_enemy_level.run_level` (player turns end through Wait) and logs:

  write  — every store into 0x4c6d80..+200 (unicorn UC_HOOK_MEM_WRITE: any writer, direct or
           register-based), with the writing EIP, the index and the value;
  read   — each 0x434d10 read of the byte (0x434d9b: edx = obj+0xa2) whose (index, value,
           caller) differs from the previous read of that index since the last new exchange
           pair — i.e. when a strip is built for a unit and whether it came out masked
           (value 0 → ???);
  target — each 0x430020 call (the target push that sets the byte at 0x43006b) with its call site;
  hp     — each named unit's live HP change (per frame), and each new 0x4423c0 exchange pair
           (attacker／defender), so a write can be placed before／after a hit or a death.

  uv run --no-project --with unicorn==2.1.4 --python /opt/homebrew/bin/python3 python3 \\
    tools/hsltools/probes/_known_byte_trace.py --level 51 --turns 1 \\
    --set 021_1.cell=15/16 --set 021_1.max_hp=200 --set 021_1.hp=200 --out ignored/known/X.json
  (add `--damage-seed 23 304` for 雷歐納德's counter on 021_1; `--set 021_1.hp=10` for a counter kill)

Readings: docs/evidence_packets/static_reverse/original_identity_bar.md (runtime-measured,
emulator section).
"""
import argparse
import json
import sys
from pathlib import Path

if __package__ in (None, ''):   # `python3 tools/hsltools/probes/_known_byte_trace.py`
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from hsltools.probes import _enemy_level as lv  # noqa: E402
from hsltools.probes import enemy_turn as et  # noqa: E402

SCHEMA = 'hsl_known_byte_trace.v1'
KNOWN, KNOWN_SIZE = 0x4c6d80, 200
STRIP_READ = 0x434d9b       # 0x434d10: mov al, byte [edx + 0x4c6d80], edx = word obj+0xa2
STRIP_RETURN_DEPTH = 0x28   # sub esp 0x18 + four pushes: 0x434d10's return address at [esp+0x28]
TARGET_PUSH = 0x430020      # push a target into the 0x4c2afc table and set its known byte (0x43006b)


class KnownObserver:
    """`_enemy_level.run_level` observer: attach() runs before the first resume."""

    def __init__(self):
        self.events = []
        self.last_read = {}
        self.last_hp = {}
        self.last_exchange = None

    def attach(self, machine, run, names):
        from unicorn import UC_HOOK_MEM_WRITE
        from unicorn.x86_const import UC_X86_REG_EDX, UC_X86_REG_EIP
        self.m, self.run, self.names = machine, run, names
        self.index_names = {}
        for obj, name in names.items():
            self.index_names.setdefault(machine.get16(obj + et.OBJ_UNIT), []).append(name)
        self.initial = sorted(i for i in range(KNOWN_SIZE) if machine.mu.mem_read(KNOWN + i, 1)[0])
        self._hp_sample()
        m = machine

        def write(mu, access, address, size, value, data):
            for offset in range(size):
                index = address + offset - KNOWN
                if 0 <= index < KNOWN_SIZE:
                    self._event('write', eip=f'{mu.reg_read(UC_X86_REG_EIP):#x}', index=index,
                                units=self.index_names.get(index, []), value=(value >> (8 * offset)) & 0xff)
        m.mu.hook_add(UC_HOOK_MEM_WRITE, write, begin=KNOWN, end=KNOWN + KNOWN_SIZE - 1)

        def read():
            index = m.mu.reg_read(UC_X86_REG_EDX) & 0xffff
            value = m.mu.mem_read(KNOWN + index, 1)[0]
            caller = m.get(m.esp() + STRIP_RETURN_DEPTH)
            key = (value, caller)
            if self.last_read.get(index) != key:
                self.last_read[index] = key
                self._event('read', index=index, units=self.index_names.get(index, []), value=value,
                            caller=f'{caller:#x}', masked=value == 0)
        m.hook(STRIP_READ, read)

        def exchange():   # 0x4423c0 runs every frame of an exchange: log each new pair once
            pair = (run.name(m.arg(0)), run.name(m.arg(1)))
            if pair != self.last_exchange:
                self.last_exchange = pair
                self.last_read = {}   # a new shot: log its strips' first reads again
                self._event('exchange', attacker=pair[0], defender=pair[1])
        m.hook(et.EXCHANGE, exchange)
        m.hook(TARGET_PUSH, lambda: self._event('target', caller=f'{m.return_address() - 5:#x}', target=run.name(m.arg(0))))
        on_frame = run.on_frame

        def frame(idle):
            self._hp_sample()
            on_frame(idle)
        run.driver.callback = frame

    def _hp_sample(self):
        for obj, name in self.names.items():
            if obj in self.run.removed:
                continue
            hp = self.run.live(obj, 'hp')
            if self.last_hp.get(name) != hp:
                if name in self.last_hp:
                    self._event('hp', unit=name, before=self.last_hp[name], after=hp)
                self.last_hp[name] = hp

    def _event(self, kind, **fields):
        self.events.append(dict(kind=kind, frame=self.run.driver.frame, round=self.m.get16(et.ROUND),
                                current=self.run.name(self.run.queue_current()), **fields))


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description='Trace the original known byte table 0x4c6d80 over N rounds.')
    lv.add_level_arguments(parser)
    args = parser.parse_args(argv)
    board = lv.load_board(args.board, args.board_key) if args.board else {'growth': False}
    observer = KnownObserver()
    turn = lv.run_level(args.exe, args.level, board, args.turns, et.parse_seed(args.seed), et.parse_seed(args.damage_seed),
                        args.edits, not args.no_cache, args.frames, observer=observer, align=args.align, choices=args.select)
    out = dict(schema=SCHEMA, level=args.level, edits=[list(e) for e in args.edits], stop=turn['meta']['stop'],
               board=turn['meta']['board'], initial_known=observer.initial,
               index_units={str(k): v for k, v in sorted(observer.index_names.items())},
               actions=[f'{a["actor"]} {a["from"]}->{a["to"]} {a["action"]} {a["target"]}' for a in turn['actions']],
               events=observer.events)
    text = json.dumps(out, ensure_ascii=False, indent=1)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text + '\n', encoding='utf-8')
    for event in observer.events:
        print(json.dumps(event, ensure_ascii=False))
    print(f'KNOWN_TRACE stop={out["stop"]} initial={observer.initial} actions={len(out["actions"])}', file=sys.stderr)
    return 0 if out['stop'] == 'round_end' else 1


if __name__ == '__main__':
    raise SystemExit(main())
