"""Original stamina (live +0xe8) trace under the _enemy_level referee (diagnostic; registers no task).

Question: what stamina does each player hold when the original first hands them control, and what
writes it (docs/evidence_packets/static_reverse/original_stamina.md, 开场实测). The observer runs a
level through `_enemy_level.run_level` (player turns end through Wait) and logs:

  write    — every store into the stamina word of any live record (the 201 × 0x1fc table *0x4c1bc8,
             unicorn UC_HOOK_MEM_WRITE, installed on the booted engine before 0x42da60 so the level
             entry is covered) that changes the value, with the writing EIP, the record index and code,
             before／after, and once the run starts the frame, round and current actor; every store
             (changing or not) is also counted per EIP in `write_sites`;
  control  — each time a player-process actor becomes current (a player turn opens: first control
             is the first one per unit), that unit's stamina and every named player's.

Carried members: a fresh boot has no party, so every player the level installs is a first
registration (constructor 0x407ec0 finds the record's four attribute words zero and copies the
PLAYERS template, 0x44cb10). --carry V stands in for a party carried from an earlier battle: on the
booted engine, for each player of the remake roster, the original's own slot enable 0x42cb30(slot)
and template copy 0x44cb10(slot + 1, 1) run, then the record's stamina is set to V (what was left
at the end of the previous battle). --keep additionally sets [0x4c1af0] = 1, the word
actKeepPlayerST (STORY／WINFAIL opcode 69, 0x452a06) writes.

  uv run --no-project --with unicorn==2.1.4 --python /opt/homebrew/bin/python3 python3 \\
    tools/hsltools/probes/_stamina_trace.py --level 51 --seed 1 2 --turns 2 [--carry 37 [--keep]] --out FILE
"""
import argparse
import json
import sys
from collections import Counter
from pathlib import Path

if __package__ in (None, ''):   # `python3 tools/hsltools/probes/_stamina_trace.py`
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from hsltools.probes import _enemy_level as lv  # noqa: E402
from hsltools.probes import enemy_turn as et  # noqa: E402

SCHEMA = 'hsl_stamina_trace.v1'
STAMINA = lv.READ_FIELDS['stamina']
RECORDS = 201                 # live table size (original_save_format.md section 4)
SLOT_ENABLE, TEMPLATE_COPY = 0x42cb30, 0x44cb10
KEEP_ST = 0x4c1af0            # actKeepPlayerST sets it; 0x4075e0 reads and clears it


def roster_players(level: int) -> list[tuple[str, int]]:
    """(unit id, actor code) of the remake roster's players (actor code ≤ 20, the registry range)."""
    units = json.loads(lv.battle_path(level).read_text(encoding='utf-8'))['playable_units']
    return [(u['id'], int(u['actor_id'])) for u in units if int(u['actor_id']) <= 20]


class StaminaObserver:
    """`_enemy_level.run_level` observer: on_boot() before the level entry, attach() before the run."""

    def __init__(self, carry: int | None = None, keep: bool = False, players: list[tuple[str, int]] = ()) -> None:
        self.carry, self.keep, self.players = carry, keep, list(players)
        self.events: list[dict] = []
        self.sites: Counter = Counter()
        self.carried: dict[str, dict] = {}
        self.run = None
        self.phase = 'level_entry'

    def on_boot(self, machine) -> None:
        from unicorn import UC_HOOK_MEM_WRITE
        from unicorn.x86_const import UC_X86_REG_EIP
        self.m = machine
        table = machine.get(et.LIVE_TABLE)
        if not table:
            raise RuntimeError('live table *0x4c1bc8 not allocated after boot')
        self.table = table
        for unit, code in self.players if self.carry is not None else ():
            machine.call_checked(SLOT_ENABLE, code - 1)
            machine.call_checked(TEMPLATE_COPY, code, 1)   # registered slot n lives at index n + 1 = code
            record = table + et.LIVE_SIZE * code
            template = machine.geti(record + STAMINA)
            machine.put(record + STAMINA, self.carry)
            self.carried[unit] = dict(code=code, template=template, carried=self.carry)
        if self.keep:
            machine.put(KEEP_ST, 1)

        def write(mu, access, address, size, value, data):
            index, offset = divmod(address - table, et.LIVE_SIZE)
            if not STAMINA <= offset < STAMINA + 4:
                return
            eip = mu.reg_read(UC_X86_REG_EIP)
            self.sites[f'{eip:#x}'] += 1
            record = table + et.LIVE_SIZE * index
            before = machine.geti(record + STAMINA)
            shift = 8 * (offset - STAMINA)
            mask = ((1 << (8 * size)) - 1) << shift
            after = (before & 0xffffffff & ~mask | (value << shift) & mask) & 0xffffffff
            after -= (after & 0x80000000) << 1
            if after == before:
                return
            event = dict(kind='write', phase=self.phase, eip=f'{eip:#x}', index=index, code=machine.get(record),
                         before=before, after=after)
            if self.run is not None:
                event.update(frame=self.run.driver.frame, round=machine.get16(et.ROUND),
                             current=self.run.name(self.run.queue_current()))
            self.events.append(event)
        machine.mu.hook_add(UC_HOOK_MEM_WRITE, write, begin=table, end=table + et.LIVE_SIZE * RECORDS - 1)

    def attach(self, machine, run, names) -> None:
        self.run, self.names, self.phase = run, names, 'rounds'
        self.index_names = {machine.get(obj + et.OBJ_LIVE): name for obj, name in names.items()}
        self.player_objs = {obj: name for obj, name in names.items() if machine.get(obj + 0x64) == et.PLAYER_PROCESS}
        on_player = run.on_player

        def control(obj) -> None:
            if obj not in self.player_objs:   # a player installed after the round-1 halt (level 53 緹娜): named by its code
                self.player_objs[obj] = names.get(obj) or f'code{self.m.get(self.record(obj)):03d}'
                self.index_names.setdefault(self.index(obj), self.player_objs[obj])
            self.events.append(dict(kind='control', unit=self.player_objs[obj], frame=run.driver.frame,
                                    round=machine.get16(et.ROUND), stamina=self.stamina(obj),
                                    players={name: self.stamina(o) for o, name in self.player_objs.items()}))
            on_player(obj)
        run.on_player = control

    def index(self, obj: int) -> int:
        return self.run.live_index.get(obj, self.m.get(obj + et.OBJ_LIVE))

    def record(self, obj: int) -> int:
        return self.table + et.LIVE_SIZE * self.index(obj)

    def stamina(self, obj: int) -> int:
        return self.m.geti(self.record(obj) + STAMINA)

    def first_control(self) -> dict[str, dict]:
        first: dict[str, dict] = {}
        for event in self.events:
            if event['kind'] == 'control' and event['unit'] not in first:
                first[event['unit']] = dict(stamina=event['stamina'], round=event['round'], frame=event['frame'])
        return first


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description='Trace the original stamina word live +0xe8 from the level entry over N rounds.')
    lv.add_level_arguments(parser)
    parser.add_argument('--carry', type=int, metavar='V',
                        help='stand in for a carried party: template-copy each roster player first, stamina V')
    parser.add_argument('--keep', action='store_true', help='with --carry: [0x4c1af0] = 1 as actKeepPlayerST leaves it')
    args = parser.parse_args(argv)
    if args.keep and args.carry is None:
        parser.error('--keep needs --carry')
    board = lv.load_board(args.board, args.board_key) if args.board else {}
    observer = StaminaObserver(args.carry, args.keep, roster_players(args.level))
    turn = lv.run_level(args.exe, args.level, board, args.turns, et.parse_seed(args.seed), et.parse_seed(args.damage_seed),
                        args.edits, not args.no_cache, args.frames, observer=observer, align=args.align, choices=args.select)
    for event in observer.events:
        if event['kind'] == 'write':
            event['unit'] = observer.index_names.get(event['index'])
    first = observer.first_control()
    mode = 'fresh' if args.carry is None else f'carry{args.carry}' + ('_keep' if args.keep else '')
    out = dict(schema=SCHEMA, level=args.level, mode=mode, growth=bool(board.get('growth', True)), seed=args.seed,
               edits=[list(e) for e in args.edits], stop=turn['meta']['stop'], carried=observer.carried,
               install_board={k: v['stamina'] for k, v in turn['meta']['install_board'].items()},
               first_control=first, write_sites=dict(sorted(observer.sites.items())),
               actions=[f'{a["actor"]} {a["from"]}->{a["to"]} {a["action"]} {a["target"]}' for a in turn['actions']],
               events=observer.events)
    text = json.dumps(out, ensure_ascii=False, indent=1)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text + '\n', encoding='utf-8')
    for event in observer.events:
        print(json.dumps(event, ensure_ascii=False))
    players = ' '.join(f'{unit}={row["stamina"]}' for unit, row in first.items())
    print(f'STAMINA_FIRST_CONTROL level={args.level:03d} mode={mode} {players} stop={out["stop"]}', file=sys.stderr)
    return 0 if out['stop'] == 'round_end' else 1


if __name__ == '__main__':
    raise SystemExit(main())
