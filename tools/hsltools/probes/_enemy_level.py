"""Original round referee for any level: enter the level through the original's own new-level
branch, stop where the original sorts the first round's queue, write a board into the
original's memory, and let the original's frame loop play N rounds — enemy_turn_v1 out.

Diagnostic tool beside the enemy_turn packet (no registry task). The whole-image machine
(hsltools.native.battle_machine) boots as WinMain does and calls 0x42da60(level) with the load
flag clear (enter_level: resets, level loader, EVEF instances, opening scripts) into the
original frame loop 0x42dbf0. Nothing of the original's logic is replaced; the only inputs are
the ones a player gives, written where the window procedure writes them, and the board:

- dialogue: when a wait site ran in a frame (script wait 0x453052 in 0x450840, message boxes
  0x414743／0x414152 — all test [0x4c6390] & 0x600010 or [0x4c6398] & 0x10002), the next loop
  head puts the left button [0x4c2344] = 1 for one frame, then 0 (an edge; WndProc 0x458530
  keeps bit0 there, 0x415910 folds it into [0x4c6398]);
- the player's turn: once the idle-menu input test 0x4082c4 (0x408260: [0x4c6390] & 0x100000,
  [0x4c6398] & 0x20000, run only while [0x4c1b00] & 0x7e000000 and [0x4c1cf0] are clear) ran
  with a player-process actor current, that actor's +0x8c becomes 0x10000, the turn-end mode
  enemy_turn uses (every player waits; other plans are not supported); when that end sequence
  comes back to phase 0 with the queue unmoved (an extra action: level 32 howl) it is written again;
- option menu (actSelectInsertEvent, opcode 79 → 0x451f2b opens the prompt 0x4264a0, object type
  0x2c0, and the script waits in state 0x4f on its result word): --select N picks option N (1-based,
  one per menu in order) by writing the prompt's pick +0xa4 = N - 1 once its proc 0x426680 waits in
  state 2 — the word an option button's click writes (0x426605: parent +0xa4 = button index +0xaa);
  the prompt then fades out, stores the pick in the script's result (0x42693e) and the script inserts
  that option's event (0x453574 → 0x44e7b0). A menu with no --select left halts 'select_menu'.
  batch defaults: MENU_CHOICES;
- carried members: a level whose remake roster fields install_if_carried players (the 有才產生
  slots of the 5NN encounters and most later main levels) finds an empty registry on a fresh
  boot and installs nobody; before 0x42da60 the original's own slot enable 0x42cb30(slot) runs
  for each such player (slot = actor code - 1), as a carried party would have left the registry
  0x4c4360 (original_player_install.md, original_check_targets.md);
- growth false (the remake's template roster): before the opening level-up reads the growth
  words live +0x1f8／+0x1fa, they are zeroed — NPC at 0x43eefb (EBP = object; read 0x43ef0f／
  0x43ef1d, 0x40e870 at 0x43ef26), player at 0x44345d (EAX = live record; 0x40e870 at 0x44346e);
  0x40e870 still runs, so each birth keeps the base-level inference 0x40e800 and the refresh
  0x40eb18 (level 53 緹娜: template L1 → L2; the replay export_exchanges.gd does the same);
- the board (enemy_turn.apply_board, INJECTION names each write) at the first 0x407340 entry,
  before the sort, so the original builds round 1's queue from it; resume_after then moves the
  queue with the original's own step 0x4074a0(1) from that unit's entry (the handoff 0x407510
  without its 0x408370／0x44f4e0 turn-end calls);
- RNG: --seed writes the global state 0x4795d4／0x4795d8 with the seeded flag 0x4c1e8c = 1,
  --damage-seed the damage words 0x4c3044／0x4c3040, both at that halt; batch --mix N writes
  (s, s) stepped N times by 0x458c10 instead (mixed_seed: a raw small (s, s) draws mostly even coins first)
  and the damage words (s + 7777) stepped the same way — without --mix every seed keeps the halt
  cache's one damage state, so a batch's seeds share every damage roll;
- --align: the remake scenario's opening cell goes over every unit the original installed (the
  board's own values win); meta install_board／opening_board keep the original's values before／after,
  batch rows list board_diff (cells) against the remake. hp／max_hp／speed are not aligned: with
  growth false both sides run the opening births without level dispersion (the remake exporter too,
  lane LETHALITY) and agree field for field (opening_snapshot g0); the scenario JSON's values are the
  template roster before those births (level 10 034: attack 59 there, 68 on both sides after).

Rounds count from the first round anyone acts in, as the remake counts them: levels 18／53／79 halt
at a sort whose round counter still reads 1 and act from counter 2 (meta round_counter keeps it).

The machine at the round-1 halt is cached per level and growth mode (with registers and the
live stack; ignored/native_cache/battle_machine/level_v1_*.pkl), as is the booted engine
(boot_v1_*.pkl). Units are named by opening cell, then slot order, against
content/battles/battle_<level>.json. Draw sites are call addresses; enemy_turn.SITE_MAP names the
remake Script.function each one corresponds to (--lines writes them; compare maps a raw record too).

  uv run --no-project --with unicorn==2.1.4 python3 tools/hsltools/probes/_enemy_level.py \\
      --level 51 --board docs/evidence_packets/runtime_observations/battle_051_ai_moves/recorded_round_boards.json \\
      --board-key r1 --seed 1 2 --lines ignored/oracle2/orig_r1.jsonl --brief
  ... _enemy_level.py compare ORIGINAL.jsonl REMAKE.jsonl      (actor／from／to／action／target and draw sites)
  ... _enemy_level.py batch --levels 3,51,52 --seeds 1,2,3 --jobs 3 --out ignored/oracle2/batch
      (--no-remake original side only; --no-original remake side into an --out that already holds it; --align)
"""
from __future__ import annotations

import argparse
import json
import pickle
import subprocess
import sys
import time
from collections import Counter
from pathlib import Path

if __package__ in (None, ''):   # `python3 tools/hsltools/probes/_enemy_level.py`
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from hsltools.native.image import EXE_SHA  # noqa: E402
from hsltools.paths import ORIGINAL_EXE, ROOT  # noqa: E402
from hsltools.probes import enemy_turn as et  # noqa: E402

BOARDS = ROOT / 'docs/evidence_packets/runtime_observations/battle_051_ai_moves/recorded_round_boards.json'
CACHE_VERSION = 1
WAIT_SITES = {0x453052: 'script wait 0x450840', 0x414743: 'message box 0x414743', 0x414152: 'message box 0x414152'}
IDLE_INPUT = 0x4082c4
ROUND_SORT, NEXT_ACTOR = 0x407340, 0x4074a0
NPC_GROWTH_READ, PLAYER_GROWTH_READ = 0x43eefb, 0x44345d
SLOT_ENABLE = 0x42cb30   # registered slot enable: empty -> 800 + slot (original_player_install.md)
PLAYER_CODES, PLAYER_CODE_SLOTS = 0x4c4360, 21   # registered slot codes (original_save_format.md)
GROWTH_WORDS = (0x1f8, 0x1fa)
READ_FIELDS = {'stamina': 0xe8}   # live words board_state reports but the board cannot set (original_stamina.md)
# actSelectInsertEvent prompt proc (0x4264a0 object type 0x2c0): +0x8c state (0 fade in, 1 arm +0xa4 = -1,
# 2 wait for +0xa4 != -1, 3 fade out → result), +0xa4 pick, +0xa8 the option message-id list (0-terminated, ≤ 10).
SELECT_PROC, SELECT_STATE, SELECT_PICK, SELECT_TEXTS = 0x426680, 0x8c, 0xa4, 0xa8
# Default option per level for batch (1-based; STORY opening menus): L73 STORY073 2185／2186 — both events
# 0／1 chain to event 2 (actSetNextPlayLevelEvent 41, gameBigMapLevel), no battle either way; L900 STORY900
# 1113／1114 — option 2 (event 1) is the branch that starts the battle battle_900.json remakes.
MENU_CHOICES = {73: (1,), 900: (2,)}
# The winfail event each MENU_CHOICES pick inserts (STORY900 option 2 = event code 1): the remake
# export applies it after the board (--select-event), as the original's handoff 0x4082a6 scan
# starts it after the round-1 sort, before the first actor (original_select_insert_event.md).
MENU_EVENTS = {900: 1}
OPENING_FRAMES = 20000
ROUND_FRAMES = 5000
REMAKE_TIMEOUT = 600   # seconds per remake exporter run in batch
INPUT_SHIMS = [
    'dialogue: a wait site (0x453052, 0x414743, 0x414152) ran last frame -> left button [0x4c2344] = 1 for one frame, then 0',
    'player turn: idle-menu test 0x4082c4 ran with a player-process actor current -> object +0x8c = 0x10000 (turn-end mode; every player waits)',
    'option menu: prompt proc 0x426680 waiting (state +0x8c = 2, pick +0xa4 = -1) -> +0xa4 = --select N - 1 (the option click 0x426605)',
]


def battle_path(level: int) -> Path:
    """The remake scenario of a level: campaign.json names it (levels 1／2 are not battle_NNN.json)."""
    entry = json.loads((ROOT / 'content/battles/campaign.json').read_text(encoding='utf-8'))['battles'].get(str(level), {})
    scenario = str(entry.get('scenario', ''))
    return ROOT / scenario.removeprefix('res://') if scenario else ROOT / f'content/battles/battle_{level:03d}.json'


def carried_slots(level: int) -> list[int]:
    """Registry slots of the remake roster's install_if_carried players (slot = actor code - 1)."""
    units = json.loads(battle_path(level).read_text(encoding='utf-8'))['playable_units']
    return sorted({int(u['actor_id']) - 1 for u in units if u.get('install_if_carried')})


class LevelDriver:
    """The loop-head hook of enter_level (clicks, frame count, callback, frame limit), the wait
    and idle-menu flags, and the growth-off writes."""

    def __init__(self, machine, growth: bool = True, choices: tuple[int, ...] = ()) -> None:
        from unicorn.x86_const import UC_X86_REG_EBP
        self.m, self._ebp = machine, UC_X86_REG_EBP
        self.frame, self.pressed, self.waiting, self.idle, self.clicks = -1, False, False, False, 0
        self.limit: int | None = None
        self.callback = None
        self.growth = growth
        self.zeroed: list[list] = []
        self.choices, self.menus = list(choices), []
        for at in WAIT_SITES:
            machine.hook(at, self._wait)
        machine.hook(IDLE_INPUT, self._idle)
        machine.hook(SELECT_PROC, self._menu)
        self._growth_hooks = [] if growth else [
            machine.hook(NPC_GROWTH_READ, lambda: self._zero(self._record(machine.mu.reg_read(self._ebp)))),
            machine.hook(PLAYER_GROWTH_READ, lambda: self._zero(machine.eax()))]

    def _wait(self) -> None:
        self.waiting = True

    def _idle(self) -> None:
        self.idle = True

    def _menu(self) -> None:
        """At the prompt proc's entry (arg 0 = the prompt object): once it waits for a pick, write
        the next --select option there, or halt 'select_menu' when none is left."""
        prompt = self.m.arg(0)
        if self.m.get(prompt + SELECT_STATE) != 2 or self.m.geti(prompt + SELECT_PICK) != -1:
            return
        texts, table = [], self.m.get(prompt + SELECT_TEXTS)
        while table and len(texts) < 10 and self.m.get(table + 4 * len(texts)):
            texts.append(self.m.get(table + 4 * len(texts)))
        menu = dict(frame=self.frame, options=texts, choice=None)
        self.menus.append(menu)
        if len(self.menus) > len(self.choices):
            self.m.halt('select_menu')
            return
        choice = self.choices[len(self.menus) - 1]
        if not 1 <= choice <= len(texts):
            raise ValueError(f'--select {choice}: the menu at frame {self.frame} has {len(texts)} options {texts}')
        menu['choice'] = choice
        self.m.put(prompt + SELECT_PICK, choice - 1)

    def _record(self, obj: int) -> int:
        return self.m.get(et.LIVE_TABLE) + et.LIVE_SIZE * self.m.get(obj + et.OBJ_LIVE)

    def _zero(self, record: int) -> None:
        words = [self.m.get16(record + offset) for offset in GROWTH_WORDS]
        self.zeroed.append([f'{self.m.get(record):03d}', self.frame] + words)
        for offset in GROWTH_WORDS:
            self.m.put16(record + offset, 0)

    def stop_growth_off(self) -> None:
        for handle in self._growth_hooks:
            self.m.unhook(handle)
        self._growth_hooks = []

    def on_frame(self) -> None:
        from hsltools.native.battle_machine import MOUSE_BUTTONS
        self.frame += 1
        if self.pressed:
            self.m.put(MOUSE_BUTTONS, 0)
            self.pressed = False
        elif self.waiting:
            self.m.put(MOUSE_BUTTONS, 1)
            self.pressed = True
            self.clicks += 1
        self.waiting = False
        idle, self.idle = self.idle, False
        if self.callback is not None:
            self.callback(idle)
        if self.limit is not None and self.frame >= self.limit and self.m.halted is None:
            self.m.halt('frame_limit')

    def state(self) -> dict:
        return dict(frame=self.frame, pressed=self.pressed, waiting=self.waiting, idle=self.idle, clicks=self.clicks,
                    zeroed=self.zeroed, choices=self.choices, menus=self.menus)

    def restore(self, state: dict) -> None:
        for key, value in state.items():
            setattr(self, key, value)


def _cache(kind: str, *parts) -> Path:
    from hsltools.native.battle_machine import CACHE_DIR
    return CACHE_DIR / ('_'.join([f'{kind}_v{CACHE_VERSION}', EXE_SHA[:12], *map(str, parts)]) + '.pkl')


def _machine_state(machine, registers: bool) -> dict:
    return dict(machine=machine.snapshot(registers=registers), open_files={k: list(v) for k, v in machine.open_files.items()},
                stub_hits=dict(machine.stub_hits), undefined=dict(machine.undefined))


def _restore_machine(machine, state: dict) -> None:
    from collections import Counter as C
    machine.restore(state['machine'])
    machine.open_files = {k: list(v) for k, v in state['open_files'].items()}
    machine.stub_hits, machine.undefined = C(state['stub_hits']), C(state['undefined'])


def booted_machine(exe: Path, use_cache: bool = True):
    """A machine after WinMain's engine boot (battle_machine.boot_engine), cached."""
    from hsltools.native.battle_machine import BattleMachine
    machine = BattleMachine(exe, b'')
    path = _cache('boot')
    if use_cache and path.exists():
        _restore_machine(machine, pickle.loads(path.read_bytes()))
        return machine, 'hit'
    machine.boot_engine()
    if use_cache:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(pickle.dumps(_machine_state(machine, False)))
    return machine, 'built'


def round_sort_machine(exe: Path, level: int, growth: bool = True, use_cache: bool = True, slots: tuple[int, ...] = (),
                       choices: tuple[int, ...] = (), on_boot=None):
    """(machine, driver, info): the level entered by 0x42da60 and run by its own frame loop up
    to the first round-queue sort 0x407340, halted at its entry (not yet executed). slots: registry
    slots enabled by 0x42cb30 before the level is entered (carried members). choices: the option
    picked in each opening menu, in order (1-based). on_boot(machine): runs on the booted engine
    before the slots and 0x42da60 (an observer's opening hooks or pre-level state); with it the
    level cache is neither read nor written."""
    from hsltools.native.battle_machine import LEVEL_LOOP, START_MOVIE, BattleMachine
    mask = sum(1 << slot for slot in slots)
    path = _cache('level', f'L{level:03d}', f'g{int(growth)}', *([f'c{mask:x}'] if mask else []),
                  *(['s' + '-'.join(map(str, choices))] if choices else []))
    if on_boot is not None:
        use_cache, boot_cache = False, use_cache
    else:
        boot_cache = use_cache
    if use_cache and path.exists():
        state = pickle.loads(path.read_bytes())
        machine = BattleMachine(exe, b'')
        _restore_machine(machine, state)
        driver = LevelDriver(machine, True)
        driver.restore(state['driver'])
        machine.install_frame_stubs()
        machine.stub(START_MOVIE, 0, 'opening movie 0x42def0')
        machine.hook(LEVEL_LOOP, driver.on_frame)
        return machine, driver, dict(state['opening'], cache='hit', path=path.relative_to(ROOT).as_posix())
    started = time.time()
    machine, boot = booted_machine(exe, boot_cache)
    if on_boot is not None:
        on_boot(machine)
    for slot in slots:
        machine.call_checked(SLOT_ENABLE, slot)
    registered = [machine.get(PLAYER_CODES + 4 * slot) for slot in range(PLAYER_CODE_SLOTS)]
    driver = LevelDriver(machine, growth, choices)
    driver.limit = OPENING_FRAMES
    sort = machine.hook(ROUND_SORT, lambda: machine.halt('round_sort'))
    machine.enter_level(level, driver.on_frame)
    machine.unhook(sort)
    driver.limit = None
    if machine.halted != 'round_sort':
        menus = ''.join(f', menu at frame {m["frame"]} options {m["options"]} picked {m["choice"]}' for m in driver.menus)
        hint = ' (pass --select)' if machine.halted == 'select_menu' else ''
        raise RuntimeError(f'level {level}: no round-1 queue sort ({machine.halted or machine.stop_reason}{hint}, frame {driver.frame}, '
                           f'clicks {driver.clicks}{menus}, flags [0x4c1b00] = {machine.get(0x4c1b00):#x})')
    driver.stop_growth_off()
    opening = dict(level=level, growth=growth, carried_slots=list(slots), registered_codes=registered,
                   frame=driver.frame, clicks=driver.clicks, zeroed=driver.zeroed, menus=driver.menus,
                   round=machine.get16(et.ROUND), seconds=round(time.time() - started, 1), boot=boot)
    if use_cache:
        state = _machine_state(machine, True)
        state.update(driver=driver.state(), opening=opening)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(pickle.dumps(state))
    return machine, driver, dict(opening, cache='built' if use_cache else 'off', path=path.relative_to(ROOT).as_posix())


class LevelRun(et.TurnRun):
    """TurnRun under the original frame loop: player turns are ended when the menu idles, the
    run halts once the round counter passes the last requested round."""

    def __init__(self, machine, names: dict[int, str], driver: LevelDriver, last_round: int, frame_limit: int) -> None:
        super().__init__(machine, names)
        self.driver, self.last_round, self.frame_limit = driver, last_round, frame_limit
        self.start_frame = driver.frame
        self.handoffs: list[dict] = []
        self.player_current = False
        self.unattributed: Counter = Counter()
        self.m_first_round, self.acting_round = machine.get16(et.ROUND), None
        driver.callback = self.on_frame

    def sync(self) -> None:
        obj = self.queue_current()
        if not obj:   # no queue entry current (index -1): nothing to open or close
            return
        if self.acting_round is None:   # rounds count from the first round anyone acts in: L18／L53／L79 halt
            self.acting_round = self.m.get16(et.ROUND)   # at a sort one round before it (round 1, acting from 2)
            self.last_round += self.acting_round - self.m_first_round
        if obj != self.current_obj and self.player_current:
            self.player_current = False
            self.current_obj = None   # the player's turn is not an action: the last NPC action is already closed
        super().sync()

    def on_player(self, obj: int) -> None:
        self.player_current = True

    def active(self) -> dict | None:
        action = super().active()
        return None if self.player_current else action

    def ending(self) -> bool:
        return self.handoff is not None and self.handoff['frames'][1] is None

    def record(self, site: int, stream: str, n, value: int) -> None:
        if self.active() is None and not self.ending():
            self.unattributed[f'{site:#x} {stream}'] += 1
            return
        super().record(site, stream, n, value)

    def end_player_turn(self) -> None:
        if self.handoff is not None:
            self.handoffs.append(self.handoff)
        super().end_player_turn()

    def on_frame(self, idle: bool) -> None:
        self.frame_index = self.driver.frame - self.start_frame
        if self.acting_round is None:
            self.sync()
        if self.m.get16(et.ROUND) > self.last_round:
            self.sync()
            self.stop = 'round_end'
            self.m.halt('round_end')
            return
        self.sync()
        if self.player_current and idle and (not self.ending() or self.m.get(self.current_obj + 0x8c) == 0):
            self.end_player_turn()   # phase back at 0 with the queue unmoved: an extra action (L32 howl), end it too
        if self.frame_index >= self.frame_limit:
            self.stop = 'frame_limit'
            self.m.halt('frame_limit')


def load_board(path: Path | None, key: str | None) -> dict:
    if path is None:
        return {}
    board = json.loads(path.read_text(encoding='utf-8'))
    if key is not None:
        board = board[key]
    if not isinstance(board, dict):
        raise ValueError(f'{path} {key}: not a board object')
    return board


class EmptyFiles(dict):
    """open_files where an unknown handle reads as an empty file. A resource the frame loop loads by id
    mid-round (0x4602d4 → 0x45fd4b(id) → size 0x46cb70) gets its id from the stubbed 0x45fc01 (sequential),
    past the id table's count [0x4bbb38], so 0x45fd4b returns handle 0 and the size stub had no entry
    (the batch's KeyError: 0, 20 runs in lane AIFREQ2). Resource data is not modelled (like the stubbed
    shape loaders): the frame loop then stops at 0x4603ca parsing it (unmapped 0x30000000, meta stop
    'emulator: …'), so the rounds before that one stand instead of the whole run failing."""

    def __missing__(self, handle: int) -> list:
        return [b'', 0]


def run_level(exe: Path, level: int, board: dict | None = None, turns: int = 1, global_seed=None, damage_seed=None,
              edits=(), use_cache: bool = True, frame_limit: int | None = None, observer=None, align: bool = False,
              choices=None) -> dict:
    """One enemy_turn_v1 record: rounds first..first+turns-1 of the level from the board. observer:
    an object whose attach(machine, run, names) adds its own hooks before the run (_exchange_check);
    if it also has on_boot(machine), that runs before the level is entered (round_sort_machine).
    align: first write the remake scenario's opening cell (remake_board) over every unit the
    original installed; the board's own values win. choices: the option (1-based) of
    each opening menu in order; None takes MENU_CHOICES."""
    board = dict(board or {})
    for key, value in et.edits_board(edits).items():   # --set on top of the board
        if isinstance(value, dict):
            merged = dict(board.get(key, {}))
            for unit, fields in value.items():
                merged[unit] = dict(merged.get(unit, {}), **fields) if isinstance(fields, dict) else fields
            board[key] = merged
        else:
            board[key] = list(board.get(key, [])) + value
    growth = bool(board.get('growth', True))
    choices = tuple(MENU_CHOICES.get(level, ()) if choices is None else choices)
    machine, driver, info = round_sort_machine(exe, level, growth, use_cache, tuple(carried_slots(level)), choices,
                                               getattr(observer, 'on_boot', None))
    machine.open_files = EmptyFiles(machine.open_files)
    names = et.remake_names(machine, battle_path(level), by_coord=True)
    missing = sorted(set(u['id'] for u in json.loads(battle_path(level).read_text())['playable_units']) - set(names.values()))
    rng_source = {'global': 'level entry: clock-stub seed and the opening draws', 'damage': 'level entry'}
    if global_seed is not None:
        machine.put(et.GLOBAL_STATE[0], global_seed[0]); machine.put(et.GLOBAL_STATE[1], global_seed[1]); machine.put(et.SEEDED, 1)
        rng_source['global'] = 'injected (seeded flag 0x4c1e8c = 1)'
    if damage_seed is not None:
        machine.put(et.DAMAGE_STATE[0], damage_seed[0]); machine.put(et.DAMAGE_STATE[1], damage_seed[1])
        rng_source['damage'] = 'injected'
    install_board = board_state(machine, names)
    if align:
        named = set(names.values())
        template = remake_board(level)
        template['units'] = {k: v for k, v in template['units'].items() if k in named and install_board[k]['cell'] != v}
        board = dict(board, **{field: dict({k: v for k, v in template[field].items() if k in named}, **board.get(field, {}))
                               for field in ('units',)})
    applied = et.apply_board(machine, names, {k: v for k, v in board.items() if k not in ('growth', 'resume_after')})
    rng = {'global': [machine.get(et.GLOBAL_STATE[0]), machine.get(et.GLOBAL_STATE[1])],
           'damage': [machine.get(et.DAMAGE_STATE[0]), machine.get(et.DAMAGE_STATE[1])]}
    opening_board = board_state(machine, names)
    first_round = machine.get16(et.ROUND)
    run = LevelRun(machine, names, driver, first_round + turns - 1, frame_limit or ROUND_FRAMES * turns)
    run.removed = et.killed(names, board)
    resume_after = board.get('resume_after')
    if resume_after is not None:
        after = {name: obj for obj, name in names.items()}[et.unit_id(resume_after)]
        machine.call_nested(ROUND_SORT)   # the sort the halt stopped in front of, then the queue step after that unit
        index = next(i for i in range(et.REGISTRY_SLOTS) if machine.get(et.QUEUE_BASE + et.QUEUE_ENTRY * i) == after)
        machine.put(et.QUEUE_INDEX, index)
        machine.call_nested(NEXT_ACTOR, 1)
        applied.append(f'resume_after={et.unit_id(resume_after)} (queue index {index} -> {machine.geti(et.QUEUE_INDEX)})')
        machine.mu.reg_write(machine._EIP, machine.return_address())   # the halted 0x407340 call: skip it, it ran
        machine.mu.reg_write(machine._ESP, machine.esp() + 4)
    if observer is not None:
        observer.attach(machine, run, names)
    machine.resume()
    if machine.stop_reason:
        run.stop = f'emulator: {machine.stop_reason}'
    for handoff in run.handoffs + ([run.handoff] if run.handoff else []):
        handoff.pop('_hp', None)
    handoffs = run.handoffs + ([run.handoff] if run.handoff else [])
    actions, meta_actions = [], []
    offset = (run.acting_round or first_round) - 1   # lines count rounds as the remake does: the first acting round is 1
    for action in run.actions:
        meta = action.pop('_meta')
        meta.pop('_hp', None)
        if meta['round'] > run.last_round:
            continue
        meta.update(round=meta['round'] - offset, round_counter=meta['round'])
        actions.append(action)
        meta_actions.append(meta)
    return {'format': et.FORMAT, 'battle': f'{level:03d}', 'turn': first_round, 'rng': rng, 'actions': actions,
            'meta': {'stop': run.stop, 'frames': run.frame_index, 'rounds': [run.acting_round or first_round, run.last_round],
                     'round_end': machine.get16(et.ROUND), 'opening': info, 'rng_source': rng_source, 'board': applied,
                     'unnamed': sorted(n for n in names.values() if n.startswith('slot')), 'not_on_level': missing,
                     'install_board': install_board, 'opening_board': opening_board, 'clicks': driver.clicks, 'handoffs': handoffs, 'unattributed_draws': dict(run.unattributed),
                     'stub_hits': dict(sorted(machine.stub_hits.items())), 'actions': meta_actions, 'hp_end': run.hp()}}


def board_state(machine, names: dict[int, str]) -> dict[str, dict]:
    """Each named unit at the round-1 halt (after the board): cell, live hp／max_hp／level／speed, held
    target, and the read-only live words READ_FIELDS (stamina +0xe8)."""
    ids = {machine.get16(obj + et.OBJ_SLOT) + 1: name for obj, name in names.items()}
    state = {}
    for obj, name in names.items():
        record = machine.get(et.LIVE_TABLE) + et.LIVE_SIZE * machine.get(obj + et.OBJ_LIVE)
        held = machine.get16(obj + et.OBJ_HELD)
        state[name] = dict(cell=[machine.geti(obj + et.OBJ_X) >> 5, machine.geti(obj + et.OBJ_Y) >> 5],
                           **{field: machine.geti(record + offset) for field, offset in et.LIVE_FIELDS.items()},
                           target=ids.get(held) if held else None,
                           **{field: machine.geti(record + offset) for field, offset in READ_FIELDS.items()})
    return state


def remake_board(level: int) -> dict:
    """The remake scenario's opening values the original board can take (growth false: the template
    roster): hp／max_hp／speed and opening cell per unit, for aligning the original's installs to the remake's."""
    units = json.loads(battle_path(level).read_text(encoding='utf-8'))['playable_units']
    board: dict = {'growth': False, 'max_hp': {}, 'hp': {}, 'speed': {}, 'units': {}}
    for unit in units:
        board['units'][unit['id']] = [int(v) for v in unit['coord']]
        board['max_hp'][unit['id']] = int(unit['max_hp'])
        board['hp'][unit['id']] = int(unit['hp'])
        board['speed'][unit['id']] = int(unit['live_speed'])
    return board


def board_diff(level: int, opening_board: dict[str, dict]) -> list[str]:
    """Where the original's round-1 board differs from the remake scenario's opening cells; units
    only one side has (hp／max_hp／speed: see --align)."""
    units = {u['id']: u for u in json.loads(battle_path(level).read_text(encoding='utf-8'))['playable_units']}
    diff = [f'{name} original only' for name in opening_board if name not in units]
    for name, unit in units.items():
        got = opening_board.get(name)
        if got is None:
            diff.append(f'{name} remake only')
            continue
        want = dict(cell=list(unit.get('coord', [])))
        diff += [f'{name}.{field} original={got[field]} remake={value}' for field, value in want.items() if got[field] != value]
    return diff


def draw_sequence(action: dict) -> list[tuple]:
    """An action's draws as the remake exporter names them, (site, n, value): an original record
    (draws carry `stream`) goes through enemy_turn.map_draws; mapped or remake lines are taken as they are."""
    draws = action.get('draws', [])
    if any('stream' in draw for draw in draws):
        draws = et.map_draws(draws)
    return [(draw['site'], draw['n'], draw['value']) for draw in draws]


def load_lines(path: Path) -> list[dict]:
    """enemy_turn_v1 lines (jsonl, exporter stdout), or one pretty-printed record／packet (--out)."""
    text = path.read_text(encoding='utf-8')
    lines = [json.loads(line) for line in text.splitlines() if line.startswith('{"format"')]
    if lines:
        return lines
    data = json.loads(text)
    return data['turns'] if 'turns' in data else [data]


def compare(original: list[dict], remake: list[dict]) -> tuple[list[str], dict]:
    """Per round, match each remake action to the original action of the same actor; compare
    from／to／action／target and the actor order, then the draws one by one as (site, n) — the
    value too, reported apart (equal values need the same generator state on both sides)."""
    lines, totals = [], Counter()
    sites: dict[str, list[int]] = {}
    split = lambda records: [line for record in records   # a whole enemy_turn_v1 record: split per round, draws mapped
                             for line in (et.round_lines(record, et.SITE_MAP) if record.get('meta', {}).get('actions') else [record])]
    original, remake = split(original), split(remake)
    by_round = {line['turn']: line['actions'] for line in original}
    for line in remake:
        got = list(by_round.get(line['turn'], []))
        want = line['actions']
        # order: the original's sequence without the actors the remake does not have (excluded source actors)
        shared = [a['actor'] for a in got if any(b['actor'] == a['actor'] for b in want)]
        for index, action in enumerate(want):
            totals['total'] += 1
            match = next((a for a in got if a['actor'] == action['actor']), None)
            if match is None:
                lines.append(f'ORACLE_MATCH turn={line["turn"]} {action["actor"]} MISSING')
                continue
            if index < len(shared) and shared[index] == action['actor']:
                totals['order'] += 1
            got.remove(match)
            diff = [f'{key} remake={json.dumps(action.get(key))} original={json.dumps(match.get(key))}'
                    for key in ('from', 'to', 'action', 'target') if action.get(key) != match.get(key)]
            totals['agree'] += not diff
            ours, theirs = draw_sequence(match), draw_sequence(action)
            for site, *_ in ours:
                sites.setdefault(site, [0, 0])[0] += 1
            for site, *_ in theirs:
                sites.setdefault(site, [0, 0])[1] += 1
            first = next((i for i, (a, b) in enumerate(zip(ours, theirs)) if a[:2] != b[:2]),
                         None if len(ours) == len(theirs) else min(len(ours), len(theirs)))
            same_values = first is None and all(a == b for a, b in zip(ours, theirs))
            totals['draws_same'] += first is None
            totals['draws_empty'] += not ours and not theirs   # a unit that did not move draws nothing on either side
            totals['values_same'] += same_values
            if first is None:
                draws = 'same sites' + (' and values' if same_values else '')
            else:
                show = lambda seq: f'{seq[first][0]}/{seq[first][1]}' if first < len(seq) else 'end'
                draws = f'first differs at #{first + 1}: original {show(ours)} remake {show(theirs)}'
            lines.append(f'ORACLE_MATCH turn={line["turn"]} {action["actor"].removeprefix("actor")} '
                         f'{"OK  " if not diff else "DIFF"} {action["from"]}->{action["to"]} {action["action"]} '
                         f'{(action["target"] or "-").removeprefix("actor")} | {"same" if not diff else "; ".join(diff)} '
                         f'| draws original={len(ours)} remake={len(theirs)} {draws}')
        for extra in got:
            lines.append(f'ORACLE_MATCH turn={line["turn"]} {extra["actor"]} EXTRA (original only)')
            totals['extra'] += 1
    for site, (ours, theirs) in sorted(sites.items()):
        lines.append(f'ORACLE_DRAWS site={site} original={ours} remake={theirs}')
    lines.append(f'ORACLE_MATCH total agree={totals["agree"]}/{totals["total"]} order={totals["order"]}/{totals["total"]} '
                 f'draw_sites_same={totals["draws_same"]}/{totals["total"]} draw_values_same={totals["values_same"]}/{totals["total"]} '
                 f'extra={totals["extra"]} draws_both_empty={totals["draws_empty"]}')
    return lines, dict(totals)


def brief(turn: dict) -> str:
    rows = [f'{a["actor"]} {a["from"]}->{a["to"]} {a["action"]} {a["target"]} skill={a["skill"]} draws={len(a["draws"])}'
            for a in turn['actions']]
    meta = turn['meta']
    rows.append(f'stop={meta["stop"]} frames={meta["frames"]} rounds={meta["rounds"]} opening_frame={meta["opening"]["frame"]} '
                f'clicks={meta["clicks"]} handoffs={len(meta["handoffs"])} cache={meta["opening"]["cache"]} '
                f'unnamed={meta["unnamed"]} unattributed={meta["unattributed_draws"]}')
    return '\n'.join(rows)


def run_main(args) -> int:
    if args.plan and any(part.strip() not in ('', 'wait') for part in args.plan.replace(';', ',').split(',')):
        print('_enemy_level: only the plan "wait" is supported (every player turn ends at once)', file=sys.stderr)
        return 2
    board = load_board(args.board, args.board_key)
    turn = run_level(args.exe, args.level, board, args.turns, et.parse_seed(args.seed), et.parse_seed(args.damage_seed),
                     args.edits, not args.no_cache, args.frames, align=args.align, choices=args.select)
    text = et.render(turn)
    if args.out:
        args.out.write_text(text + '\n', encoding='utf-8')
    elif not (args.lines or args.bare_lines):
        print(text)
    if args.lines:
        et.write_lines(args.lines, turn, et.SITE_MAP)
    if args.bare_lines:
        et.write_lines(args.bare_lines, turn, None)
    if args.brief or args.out or args.lines or args.bare_lines:
        print(brief(turn), file=sys.stderr)
    return 0 if turn['meta']['stop'] == 'round_end' else 1


def compare_main(args) -> int:
    lines, totals = compare(load_lines(args.original), load_lines(args.remake))
    print('\n'.join(lines))
    return 0


def remake_export(level: int, seed: int, turns: int, board: Path | None, key: str | None, out: Path) -> list[str]:
    scenario = battle_path(level)
    battle = f'{level:03d}' if scenario.name == f'battle_{level:03d}.json' else 'res://' + scenario.relative_to(ROOT).as_posix()
    command = [str(ROOT / 'tools/godot.sh'), '--headless', '--script', 'res://tests/diagnostics/export_enemy_turns.gd', '--',
               '--battle', battle, '--turns', str(turns), '--seed', str(seed), '--out', str(out)]
    if board is not None:
        command += ['--state', str(board)] + (['--state-key', key] if key else [])
    if level in MENU_EVENTS:
        command += ['--select-event', str(MENU_EVENTS[level])]
    return command


DAMAGE_MIX_OFFSET = 7777


def mixed_seed(seed: int, mix: int) -> tuple[int, int]:
    """The global words batch writes at the round-1 halt: (s, s) stepped `mix` times by the generator
    model 0x458c10. A small (s, s) is no clock state the original reaches: its first draws come out
    mostly even (rand(2) = 1 in 13 %／28 %／38 % of the first three draws over s = 1..1000, near half
    only after ~15), so round 1's first AI coins are close to fixed; stepping first gives a mixed state."""
    from hsltools.evidence.damage_random import advance
    a, b = seed & 0xffffffff, seed & 0xffffffff
    for _ in range(mix):
        a, b, _raw = advance(a, b)
    return a, b


def batch_one(job: tuple) -> dict:
    exe, level, seed, turns, board, key, out_dir, use_cache, align, choices, mix = job
    started = time.time()
    out_dir = Path(out_dir)
    stem = f'L{level:03d}_s{seed}'
    row = {'level': level, 'seed': seed}
    try:
        chosen = load_board(Path(board), key) if board else {'growth': False}
        # --mix also moves the damage words off the halt's cached state, so seeds differ in damage
        # too (the remake's --seed does); a stream offset keeps them apart from the global words.
        damage = mixed_seed(seed + DAMAGE_MIX_OFFSET, mix) if mix else None
        turn = run_level(Path(exe), level, chosen, turns, mixed_seed(seed, mix), damage, (), use_cache, align=align, choices=choices)
        et.write_lines(out_dir / f'{stem}_original.jsonl', turn, et.SITE_MAP)
        opening = turn['meta']['opening_board']
        (out_dir / f'{stem}_original_meta.json').write_text(json.dumps(
            {key_: turn['meta'][key_] for key_ in ('stop', 'frames', 'rounds', 'round_end', 'opening', 'board', 'unnamed', 'not_on_level',
                                                     'clicks', 'unattributed_draws', 'hp_end', 'install_board', 'opening_board')}
            # per action (jsonl order) its frames, hp deltas, held pursuit target after it and the call address of
            # each global draw (1:1 with the line's mapped draws), and each player turn-end's frames／hp deltas:
            # the replay judge's board correction and chain passes (ai_replay.py)
            | {'action_after': [{'frames': m['frames'], 'hp': m.get('hp', {}), 'chase': m.get('chase'),
                                 'sites': [d['site'] for d in a['draws'] if d.get('stream', 'global') == 'global']}
                                for a, m in zip(turn['actions'], turn['meta']['actions'])],
               'handoff_after': [{'frames': h.get('frames'), 'hp': h.get('hp', {})} for h in turn['meta']['handoffs']]},
            ensure_ascii=False) + '\n',
            encoding='utf-8')
        row.update(original_actions=len(turn['actions']), stop=turn['meta']['stop'], cache=turn['meta']['opening']['cache'],
                   opening_frame=turn['meta']['opening']['frame'], board_diff=board_diff(level, opening),
                   install_diff=board_diff(level, turn['meta']['install_board']),
                   unnamed=turn['meta']['unnamed'], original_seconds=round(time.time() - started, 1))
    except Exception as error:   # a level the referee cannot enter yet: reported, not fatal to the batch
        row.update(error=f'{type(error).__name__}: {error}', original_seconds=round(time.time() - started, 1))
    return row


def batch_main(args) -> int:
    from concurrent.futures import ProcessPoolExecutor
    args.out.mkdir(parents=True, exist_ok=True)
    levels = [int(x) for x in args.levels.split(',')]
    seeds = [int(x) for x in args.seeds.split(',')]
    board = args.board
    if board is None:   # growth false, the remake's template roster, for every level
        board = args.out / 'board_growth_false.json'
        board.write_text('{"growth": false}\n', encoding='utf-8')
    started = time.time()
    # Build each level's round-1 cache once (serially per level, in parallel across levels) before the seeds fan out.
    menus = dict(MENU_CHOICES, **{int(level): tuple(int(n) for n in picks.split('/'))
                                  for level, picks in (item.split('=') for item in args.select)})
    job = lambda level, seed: (str(args.exe), level, seed, args.turns, str(board), args.board_key, str(args.out), True, args.align,
                               menus.get(level, ()), args.mix)
    with ProcessPoolExecutor(max_workers=args.jobs) as pool:
        if args.no_original:   # keep the original side's rows of an earlier run in --out
            previous = json.loads((args.out / 'batch.json').read_text()) if (args.out / 'batch.json').exists() else []
            kept = {(row['level'], row['seed']): {k: v for k, v in row.items() if not k.startswith('remake_')} for row in previous}
            rows = [kept.get((level, seed), {'level': level, 'seed': seed}) for level in levels for seed in seeds]
        else:
            warm = list(pool.map(batch_one, [job(level, seeds[0]) for level in levels]))
            broken = {row['level'] for row in warm if 'error' in row}   # a level the referee cannot enter: once is enough
            rows = warm + list(pool.map(batch_one, [job(level, seed) for level in levels if level not in broken for seed in seeds[1:]]))
            rows += [dict(level=level, seed=seed, error='level not entered (seed %d)' % seeds[0]) for level in sorted(broken)
                     for seed in seeds[1:]]
    original_seconds = round(time.time() - started, 1)

    def remake(row: dict) -> None:
        remake_out = args.out / f'L{row["level"]:03d}_s{row["seed"]}_remake.jsonl'
        remake_out.unlink(missing_ok=True)
        t0 = time.time()
        try:
            result = subprocess.run(remake_export(row['level'], row['seed'], args.turns, board, args.board_key, remake_out),
                                    cwd=ROOT, capture_output=True, text=True, timeout=REMAKE_TIMEOUT)
            (args.out / f'L{row["level"]:03d}_s{row["seed"]}_remake.log').write_text(result.stdout + result.stderr, encoding='utf-8')
            if result.returncode or not remake_out.exists():
                row['remake_error'] = ((result.stdout + result.stderr).strip().splitlines()[-1:] or [f'exit {result.returncode}'])[0]
        except subprocess.TimeoutExpired:
            row['remake_error'] = f'timeout {REMAKE_TIMEOUT}s'
        row['remake_seconds'] = round(time.time() - t0, 1)
    if not args.no_remake:
        from concurrent.futures import ThreadPoolExecutor
        with ThreadPoolExecutor(max_workers=args.jobs) as pool:
            list(pool.map(remake, rows))
    for row in rows:
        stem = f'L{row["level"]:03d}_s{row["seed"]}'
        remake_out = args.out / f'{stem}_remake.jsonl'
        original_out = args.out / f'{stem}_original.jsonl'
        if original_out.exists() and remake_out.exists():
            _, totals = compare(load_lines(original_out), load_lines(remake_out))
            row.update(agree=totals.get('agree', 0), order=totals.get('order', 0), draws_same=totals.get('draws_same', 0),
                       draws_empty=totals.get('draws_empty', 0),
                       remake_actions=totals.get('total', 0), extra=totals.get('extra', 0))
    (args.out / 'batch.json').write_text(json.dumps(rows, indent=1) + '\n', encoding='utf-8')
    print(f'| level | seed | original actions | remake actions | agree | order | draw sites same (both empty) | original s | remake s | note |')
    print('|---|---|---|---|---|---|---|---|---|---|')
    for row in sorted(rows, key=lambda r: (r['level'], r['seed'])):
        print(f'| {row["level"]:03d} | {row["seed"]} | {row.get("original_actions", "-")} | {row.get("remake_actions", "-")} | '
              f'{row.get("agree", "-")} | {row.get("order", "-")} | {row.get("draws_same", "-")} ({row.get("draws_empty", "-")}) | {row.get("original_seconds")} | '
              f'{row.get("remake_seconds", "-")} | {row.get("error") or row.get("remake_error") or row.get("cache", "")} |')
    print(f'BATCH levels={len(levels)} seeds={len(seeds)} jobs={args.jobs} original_wall={original_seconds}s '
          f'total_wall={round(time.time() - started, 1)}s')
    return 0


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    if argv[:1] == ['compare']:
        parser = argparse.ArgumentParser(prog='_enemy_level.py compare')
        parser.add_argument('original', type=Path)
        parser.add_argument('remake', type=Path)
        return compare_main(parser.parse_args(argv[1:]))
    if argv[:1] == ['batch']:
        parser = argparse.ArgumentParser(prog='_enemy_level.py batch')
        parser.add_argument('--exe', type=Path, default=ORIGINAL_EXE)
        parser.add_argument('--levels', required=True, help='comma list of level numbers')
        parser.add_argument('--seeds', default='1,2,3', help='comma list; original global state (s, s), remake --seed s')
        parser.add_argument('--mix', type=int, default=0, metavar='N',
                            help='original global state N 0x458c10 steps past (s, s) (default 0: (s, s) itself, whose first '
                                 'round-1 draws are mostly even; see mixed_seed); N > 0 also writes the damage words (s + 7777) '
                                 'stepped N times, else every seed shares the halt cache damage state')
        parser.add_argument('--turns', type=int, default=1)
        parser.add_argument('--board', type=Path, help='board file for both sides (default {"growth": false})')
        parser.add_argument('--board-key')
        parser.add_argument('--jobs', type=int, default=3)
        parser.add_argument('--no-remake', action='store_true', help='original side only')
        parser.add_argument('--no-original', action='store_true', help='remake side only (original jsonl already in --out)')
        parser.add_argument('--align', action='store_true',
                            help='write the remake scenario\'s hp／max_hp／speed／cell over the original\'s units (the remake keeps --board)')
        parser.add_argument('--select', action='append', default=[], metavar='LEVEL=N[/N..]',
                            help=f'opening menu options of a level, 1-based, in order (default {MENU_CHOICES})')
        parser.add_argument('--out', type=Path, required=True)
        return batch_main(parser.parse_args(argv[1:]))
    parser = argparse.ArgumentParser(description='Enter a level in the original, inject a board at the round-1 queue sort, '
                                                 'run N rounds and print enemy_turn_v1 JSON.')
    add_level_arguments(parser)
    return run_main(parser.parse_args(argv))


def add_level_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument('--exe', type=Path, default=ORIGINAL_EXE)
    parser.add_argument('--level', type=int, required=True)
    parser.add_argument('--board', type=Path, help='board JSON (recorded_round_boards.json form)')
    parser.add_argument('--board-key', help='take the board from FILE[KEY]')
    parser.add_argument('--turns', type=int, default=1)
    parser.add_argument('--plan', help='player turns; only "wait" is supported')
    parser.add_argument('--seed', nargs=2, metavar=('S1', 'S2'), help='global RNG start 0x4795d4 0x4795d8 at the round-1 sort')
    parser.add_argument('--damage-seed', nargs=2, metavar=('D1', 'D2'), help='damage RNG start 0x4c3044 0x4c3040')
    parser.add_argument('--set', dest='edits', action='append', type=et.parse_edit, default=[], metavar='ID.FIELD=VALUE',
                        help='board edit on top of --board (hp/max_hp/level/speed raw, cell=X/Y, target=ID|none, dead=1)')
    parser.add_argument('--frames', type=int, help=f'frame limit after the halt (default {ROUND_FRAMES} per round)')
    parser.add_argument('--no-cache', action='store_true')
    parser.add_argument('--out', type=Path)
    parser.add_argument('--lines', type=Path, help='one enemy_turn_v1 line per round, draws named by enemy_turn.SITE_MAP (compare input)')
    parser.add_argument('--bare-lines', type=Path, help='the same with draws emptied (export_enemy_turns.gd --expect／--search input)')
    parser.add_argument('--brief', action='store_true')
    parser.add_argument('--align', action='store_true', help='write the remake scenario\'s hp／max_hp／speed／cell over the installed units first')
    parser.add_argument('--select', type=int, nargs='+', metavar='N',
                        help=f'option N (1-based) in each opening menu (actSelectInsertEvent), in order; default MENU_CHOICES {MENU_CHOICES}')


if __name__ == '__main__':
    raise SystemExit(main())
