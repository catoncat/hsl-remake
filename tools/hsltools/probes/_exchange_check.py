"""Whole-exchange check of an ordinary attack: the original's exchange, value for value, beside
the remake's `BattleLoopCombat._resolve_exchange` from the same exchange-start damage state.

Diagnostic tool beside the damage-random packet (original_damage_random.md, no registry task).
The original side runs a level through the round referee `_enemy_level.run_level` (board and
--set as there; every player turn ends at once, so enemies attack players) with an observer on
the exchange code of the whole-image machine. Per exchange (0x4423c0 phase word 0x4c432c == 0
with the counter bit mode & 1 clear, until the next such start or the actor's hand-over):

- start: the damage words 0x4c3044／0x4c3040 and both participants' live records ([0x4c1bc8] +
  0x1fc x object +0xa4: hp +0xd8, max +0xdc, level +0x9c, exp +0x88, hit bonus +0xb0, attack
  +0xc0, defense +0xb4, hit +0xbc, str +0x4c, dex +0x50, avoid +0x19a, counter +0x19e, crit
  +0x1a2, status +0x24, kill chain +0xa8) and cells (object +4／+8 >> 5);
- every damage-stream draw (site = the wrapper 0x42c780／0x42c720 caller, n, value);
- per series (a phase-0 entry; mode & 1 = counter): per strike the sampled damage (0x409be0
  return at 0x442512), the queued damage [0x4c2ae0] and final hit rate ECX at 0x4425a3 (after
  the x80% counter cut 0x442525, the 0x40e2a0 halving and the +0xb0 bonus cap 0x442599), the base
  rate 0x409a60 (0x442573), the saved hit roll [0x4c1418] against impact +0xa6 at 0x403f39, the
  critical roll + 1 (EAX) against impact +0x4e (EDX) at 0x403f60, the outcome 0x403ff1
  (critical) ／ 0x403ff6 (hit, impact +0xa0 = final damage) ／ 0x4041ea (miss), the new HP and
  contribution [0x4c13fc] at 0x4040bc, the per-strike EXP 0x40a5d0 (EAX at 0x4423f6);
- awards: 0x442720 at 0x4427b8 (EBX = recipient, EBP = amount after the 0x40e2c0 doubling,
  added to live +0x88);
- end: the damage words and both live records again.

`record` writes these as a cases file; tests/export_exchanges.gd replays each case in the remake
(participants' cells／HP／EXP／hit bonus／kill chain from the case start, loop damage_rng = the
start words) and `compare` puts both side by side.

  uv run --no-project --with unicorn==2.1.4 python3 tools/hsltools/probes/_exchange_check.py record \\
      --level 51 --board docs/evidence_packets/runtime_observations/battle_051_ai_moves/recorded_round_boards.json \\
      --board-key r1 --set growth=0 --set 023_1.cell=16/17 --set 023_1.target=leonard --damage-seeds 1,2,3 \\
      --out ignored/dmgcheck/L51_cases.json
  tools/godot.sh --headless --script res://tests/export_exchanges.gd -- --cases ignored/dmgcheck/L51_cases.json \\
      --out ignored/dmgcheck/L51_remake.json
  ... _exchange_check.py compare ignored/dmgcheck/L51_cases.json ignored/dmgcheck/L51_remake.json
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

if __package__ in (None, ''):   # `python3 tools/hsltools/probes/_exchange_check.py`
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from hsltools.paths import ORIGINAL_EXE, ROOT  # noqa: E402
from hsltools.probes import _enemy_level as lv  # noqa: E402
from hsltools.probes import enemy_turn as et  # noqa: E402

SCHEMA = 'hsl_exchange_check.v1'
M32 = 0xffffffff
AFTER_DAMAGE, AFTER_BASE_RATE, RATES = 0x442512, 0x442573, 0x4425a3
IMPACT_CHECK, CRIT_COMPARE, CRIT_EVENT, HIT_END, MISS = 0x403f39, 0x403f60, 0x403ff1, 0x403ff6, 0x4041ea
HP_WRITE, STRIKE_EXP, AWARD = 0x4040bc, 0x4423f6, 0x4427b8
QUEUED, HIT_ROLL, CONTRIBUTION = 0x4c2ae0, 0x4c1418, 0x4c13fc
# live record fields: (offset, width) — width 4 signed dword, 2 signed word, -2 unsigned word
LIVE = {'hp': (0xd8, 4), 'max_hp': (0xdc, 4), 'level': (0x9c, 4), 'exp': (0x88, 4), 'hit_bonus': (0xb0, 4),
        'attack': (0xc0, 4), 'defense': (0xb4, 4), 'hit': (0xbc, 4), 'str': (0x4c, 4), 'dex': (0x50, 4),
        'avoid': (0x19a, 2), 'counter': (0x19e, 2), 'crit': (0x1a2, -2), 'status': (0x24, 4), 'kill_chain': (0xa8, 4)}


def damage_words(seed: int) -> list[int]:
    """A damage-stream start the way a new game seeds it (0x42ca47, DamageRandomStream.seeded): [t, ~t]."""
    return [seed & M32, ~seed & M32]


class ExchangeObserver:
    """Hooks on the exchange, impact and award code; attach() is called by run_level before the run."""

    def __init__(self, stop_after: int | None = None, battle: Path | None = None) -> None:
        self.stop_after = stop_after
        self.playable = json.loads(battle.read_text(encoding='utf-8'))['playable_units'] if battle else []
        self.exchanges: list[dict] = []
        self.open: dict | None = None
        self.series: dict | None = None
        self.strike: dict | None = None
        self.closed_actions = 0
        self.dead: set[int] = set()
        self.late: dict[int, str] = {}
        self.series_defender: int | None = None

    # ---- readers
    def _reg(self, name: str) -> int:
        from unicorn import x86_const
        return self.m.mu.reg_read(getattr(x86_const, f'UC_X86_REG_{name}'))

    def _record(self, obj: int) -> int:
        index = self.run.live_index.get(obj)
        return self.m.get(et.LIVE_TABLE) + et.LIVE_SIZE * (self.m.get(obj + et.OBJ_LIVE) if index is None else index)

    def _unit(self, obj: int) -> dict:
        at = self._record(obj)
        out = {}
        for key, (offset, width) in LIVE.items():
            if width == 4:
                out[key] = self.m.geti(at + offset)
            else:
                value = self.m.get16(at + offset)
                out[key] = value - 0x10000 if width == 2 and value & 0x8000 else value
        out['cell'] = self.run.cell(obj)
        return out

    def _damage(self) -> list[int]:
        return [self.m.get(et.DAMAGE_STATE[0]), self.m.get(et.DAMAGE_STATE[1])]

    def _snapshot(self, exchange: dict, board: bool = False) -> dict:
        out = {'damage': self._damage(), 'units': {self._name(obj): self._unit(obj) for obj in exchange['_objs']}}
        if board:
            # every named unit's cell and live HP. Death is sticky: a dead unit's object is unlinked
            # (0x45e3ed) and a later spawn may take over its object memory and live-record slot
            # (level 51: a summon showed up in a dead unit's record with HP above that unit's max).
            out['board'] = {}
            for obj, name in list(self.names.items()) + list(self.late.items()):
                if obj in self.run.removed or self._unit_hp(obj) <= 0:
                    self.dead.add(obj)
                alive = obj not in self.dead
                out['board'][name] = {'hp': self._unit_hp(obj) if alive else 0, 'cell': self.run.cell(obj) if alive else None}
        return out

    def _unit_hp(self, obj: int) -> int:
        return self.m.geti(self._record(obj) + LIVE['hp'][0])

    # ---- wiring
    def attach(self, machine, run, names: dict[int, str]) -> None:
        self.m, self.run, self.names = machine, run, names
        m = machine
        m.hook(et.EXCHANGE, self._exchange)
        m.hook(AFTER_DAMAGE, lambda: self._strike_field('sampled_damage', m.eax()))
        m.hook(AFTER_BASE_RATE, lambda: self._strike_field('base_hit_rate', m.eax()))
        m.hook(RATES, self._rates)
        m.hook(IMPACT_CHECK, self._impact)
        m.hook(CRIT_COMPARE, self._crit_compare)
        m.hook(CRIT_EVENT, lambda: self._strike_field('critical', True))
        m.hook(HIT_END, self._hit)
        m.hook(MISS, self._miss)
        m.hook(HP_WRITE, self._hp_write)
        m.hook(STRIKE_EXP, self._strike_exp)
        m.hook(AWARD, self._award)
        record, sync = run.record, run.sync

        def record_draw(site: int, stream: str, n, value: int) -> None:
            if stream == 'damage':
                target = self.open['draws'] if self.open is not None else self.stray
                target.append([f'{site:#x}', n, value])
            record(site, stream, n, value)

        def sync_close() -> None:
            if self.open is not None and run.queue_current() != run.current_obj:
                self._close()
            sync()
        self.stray: list[list] = []
        run.record, run.sync = record_draw, sync_close

    def _name_late_objects(self) -> None:
        """Objects made after the round-1 halt take the remaining playable ids of their actor code in
        registry-slot order (as enemy_turn.remake_names names the rest). Level 53: Tina and the two
        chasers come out of the opening script after the halt, where only the exit guard stands."""
        taken = set(self.names.values()) | set(self.late.values())
        pools: dict[int, list[str]] = {}
        for unit in self.playable:
            if unit['id'] not in taken:
                pools.setdefault(int(unit['actor_id']), []).append(unit['id'])
        live = self.m.get(et.LIVE_TABLE)
        for slot in range(et.REGISTRY_SLOTS):
            obj = self.m.get(et.REGISTRY + 4 * slot)
            if obj and obj not in self.names and obj not in self.late and obj not in self.dead:
                code = self.m.get(live + et.LIVE_SIZE * self.m.get(obj + et.OBJ_LIVE))
                if pools.get(code):
                    self.late[obj] = pools[code].pop(0)

    def _name(self, obj: int) -> str | None:
        # the referee's own names stay untouched (its per-action HP diff keys on them)
        return self.late[obj] if obj in self.late else self.run.name(obj)

    def _exchange(self) -> None:
        if self.m.get(et.EXCHANGE_PHASE) != 0:
            return
        # 0x4423c0(striker, defender, &accumulator, mode): mode 0／1 from the player process (0x4445cf／
        # 0x444601), 2／3 from the NPC process (0x4414a0／0x4414d3); bit 1 = the counter series
        striker, defender, flags = self.m.arg(0), self.m.arg(1), self.m.arg(3)
        if not flags & 1:   # a new ordinary exchange (a counter series carries mode & 1)
            if self.open is not None:
                self._close()
            self._name_late_objects()
            self.open = {'index': len(self.exchanges), 'round': self.m.get16(et.ROUND), 'actor': self._name(self.run.queue_current()),
                         'striker': self._name(striker), 'defender': self._name(defender), 'flags': flags,
                         '_objs': [striker, defender], 'series': [], 'awards': [], 'strike_exp': [], 'draws': []}
            self.open['start'] = self._snapshot(self.open, board=True)
        if self.open is None:
            return
        self.series = {'striker': self._name(striker), 'defender': self._name(defender), 'flags': flags, 'strikes': []}
        self.series_defender = defender
        self.open['series'].append(self.series)
        self.strike = None

    def _new_strike(self) -> dict:
        self.strike = {}
        self.series['strikes'].append(self.strike)
        return self.strike

    def _strike_field(self, key: str, value) -> None:
        if self.series is None:
            return
        if key == 'sampled_damage' or self.strike is None:
            self._new_strike()
        self.strike[key] = value

    def _rates(self) -> None:
        if self.strike is not None:
            self.strike.update(queued_damage=self.m.get(QUEUED), hit_rate=self._reg('ECX'))

    def _impact(self) -> None:
        if self.strike is None:
            return
        impact = self._reg('EDI')
        self.strike.update(hit_roll=self.m.get(HIT_ROLL), impact_hit_rate=self.m.get16(impact + 0xa6),
                           impact_damage=self.m.get16(impact + 0xa0), impact_crit_rate=self.m.get16(impact + 0x4e),
                           impact_defender=self._name(self.m.get(impact + 0xac)), critical=False)

    def _crit_compare(self) -> None:
        if self.strike is not None:
            self.strike.update(critical_roll=self._reg('EAX'), critical_rate=self._reg('EDX'))

    def _hit(self) -> None:
        if self.strike is not None:
            self.strike.update(hit=True, damage=self.m.get16(self._reg('EDI') + 0xa0))

    def _miss(self) -> None:
        if self.strike is not None:
            self.strike.update(hit=False, damage=0)

    def _hp_write(self) -> None:
        if self.strike is not None:
            self.strike.update(hp_after=self._reg('EAX'), contribution=self.m.geti(CONTRIBUTION))
            if self._reg('EAX') == 0 and self.series_defender is not None:
                self.dead.add(self.series_defender)

    def _strike_exp(self) -> None:
        if self.open is not None:
            self.open['strike_exp'].append([self._name(self._reg('EDI')), self._reg('EAX')])
            if self.strike is not None:
                self.strike['exp_points'] = self._reg('EAX')

    def _award(self) -> None:
        recipient, amount = self._reg('EBX'), self._reg('EBP')
        row = {'recipient': self._name(recipient), 'amount': amount, 'exp_before': self._unit(recipient)['exp']}
        if self.open is not None:
            self.open['awards'].append(row)
        else:
            self.stray.append(['award', row])

    def _close(self) -> None:
        exchange, self.open = self.open, None
        self.series = self.strike = None
        exchange['end'] = self._snapshot(exchange)
        exchange.pop('_objs')
        self.exchanges.append(exchange)
        if self.stop_after is not None and len(self.exchanges) >= self.stop_after:
            self.m.halt('exchanges_done')

    def result(self) -> dict:
        if self.open is not None:
            self._close()
        return {'exchanges': self.exchanges, 'stray': self.stray}


def record_one(job: tuple) -> dict:
    exe, level, board, edits, global_seed, seed, turns, stop_after = job
    started = time.time()
    observer = ExchangeObserver(stop_after, lv.battle_path(level))
    row = {'damage_seed': seed, 'damage_start': damage_words(seed)}
    try:
        turn = lv.run_level(Path(exe), level, board, turns, global_seed, damage_words(seed), edits, True, None, observer=observer)
        found = observer.result()
        row.update(exchanges=found['exchanges'], stray=found['stray'], stop=turn['meta']['stop'],
                   actions=[f'{a["actor"]} {a["action"]} {a["target"]}' for a in turn['actions']],
                   applied=turn['meta']['board'], rng=turn['rng'])
    except Exception as error:   # reported per seed, not fatal to the batch
        row['error'] = f'{type(error).__name__}: {error}'
    row['seconds'] = round(time.time() - started, 1)
    return row


def parse_seeds(text: str) -> list[int]:
    seeds: list[int] = []
    for part in text.split(','):
        if '-' in part.strip()[1:]:
            low, high = part.split('-', 1)
            seeds.extend(range(int(low, 0), int(high, 0) + 1))
        elif part.strip():
            seeds.append(int(part, 0))
    return seeds


def record_main(args) -> int:
    from concurrent.futures import ProcessPoolExecutor
    board = lv.load_board(args.board, args.board_key)
    edits = [e for e in args.edits if e[1] != 'growth']
    for actor, field, value in args.edits:
        if field == 'growth':
            board['growth'] = bool(value)
    board.setdefault('growth', False)
    seeds = parse_seeds(args.damage_seeds)
    global_seed = et.parse_seed(args.seed)
    started = time.time()
    jobs = [(str(args.exe), args.level, board, edits, global_seed, seed, args.turns, args.stop_after) for seed in seeds]
    # the first run builds the level cache on its own; the rest fan out
    rows = [record_one(jobs[0])]
    with ProcessPoolExecutor(max_workers=args.jobs) as pool:
        rows += list(pool.map(record_one, jobs[1:]))
    merged = dict(board)
    for key, value in et.edits_board(edits).items():
        merged[key] = dict(merged.get(key, {}), **value) if isinstance(value, dict) else list(merged.get(key, [])) + value
    out = {'schema': SCHEMA, 'level': args.level, 'battle': f'{args.level:03d}', 'board': merged,
           'global_seed': list(global_seed) if global_seed else None, 'turns': args.turns, 'runs': rows}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(out, indent=1) + '\n', encoding='utf-8')
    count = sum(len(r.get('exchanges', [])) for r in rows)
    errors = [f'seed {r["damage_seed"]}: {r["error"]}' for r in rows if 'error' in r]
    print(f'EXCHANGE_RECORD level={args.level} seeds={len(seeds)} exchanges={count} errors={len(errors)} '
          f'wall={round(time.time() - started, 1)}s out={args.out}')
    for line in errors:
        print('  ' + line)
    return 1 if errors else 0


# ---- compare
KILL_MARK = 0x10000
COLUMNS = ('hit', 'damage', 'critical', 'counter', 'counter_damage', 'exp')
CHECKED = COLUMNS + ('counter_hit', 'counter_critical', 'hit_rate', 'counter_hit_rate', 'end', 'damage_end', 'draws')


def _series(strikes: list[dict], prefix: str = '') -> dict:
    return {prefix + 'hit': [bool(s.get('hit')) for s in strikes], prefix + 'damage': [int(s.get('damage', 0)) for s in strikes],
            prefix + 'critical': [bool(s.get('critical')) for s in strikes], prefix + 'hit_rate': [s.get('hit_rate') for s in strikes]}


def _end_unit(u: dict) -> dict:
    if u['max_hp'] == 0:
        # the whole live record reads zero: the level ended (a player leader's death — level 53's
        # Tina — tears the battle down before the hand-over the end snapshot waits for); HP only
        return {'hp': 0, 'exp': None, 'hit_bonus': None, 'kill_chain': None}
    # a dead unit's hit bonus and kill chain are not compared (counted apart as dead_bonus): the
    # original leaves +0xb0 on the dead record, the remake's defeat clears it (BattlePlayLoop
    # _set_defeated); nothing living reads it
    alive = u['hp'] > 0
    return {'hp': u['hp'], 'exp': u['exp'], 'hit_bonus': u['hit_bonus'] if alive else None, 'kill_chain': u['kill_chain'] if alive else None}


def original_row(exchange: dict) -> dict:
    """The comparison columns of an original exchange. End state: the live records at the actor's
    hand-over (hp／exp／hit bonus +0xb0; kill chain +0xa8 of a living unit)."""
    counter = next((s for s in exchange['series'][1:] if s['flags'] & 1), None)
    awards = {a['recipient']: a['amount'] for a in exchange['awards']}
    row = {**_series(exchange['series'][0]['strikes']), **_series(counter['strikes'] if counter else [], 'counter_'),
           'counter': counter is not None,
           'exp': {exchange['striker']: awards.get(exchange['striker'], 0), exchange['defender']: awards.get(exchange['defender'], 0)},
           'end': {name: _end_unit(u) for name, u in exchange['end']['units'].items()},
           'damage_end': list(exchange['end']['damage']),
           'draws': [[-1 if d[1] is None else d[1], d[2]] for d in exchange['draws']]}
    row.pop('counter_counter', None)
    return row


def remake_row(case: dict, actor: str | None) -> dict:
    """The same columns from a tests/export_exchanges.gd case. The acting unit's kill chain is read
    as its own action end leaves it (ExperienceRules.after_action: the low word if this action
    killed, else 0) — the original's end snapshot is taken at the hand-over, after that."""
    receipt = case.get('receipt') or {}
    counter = receipt.get('counter') or {}
    strikes = [receipt] + list(receipt.get('followups', [])) if receipt else []
    counters = [counter] + list(counter.get('followups', [])) if counter else []
    exp = {case['striker']: 0, case['defender']: 0}
    for series in (receipt, counter):
        if series:
            settlement = series.get('experience_settlement', {})
            exp[series['attacker_id']] = int(settlement.get('awarded', 0))
    end = {}
    for name, u in case['end']['units'].items():
        chain = u['kill_chain']
        if name == actor:
            chain = chain & 0xffff if chain & KILL_MARK else 0
        alive = u['hp'] > 0
        end[name] = {'hp': u['hp'], 'exp': u['exp'], 'hit_bonus': u['hit_bonus'] if alive else None, 'kill_chain': chain if alive else None}
    return {**_series(strikes), **_series(counters, 'counter_'), 'counter': bool(counter), 'exp': exp, 'end': end,
            'damage_end': list(case['end']['damage']), 'draws': [[int(d[0]), int(d[1])] for d in case.get('draws', [])]}


def cell(row: dict, key: str) -> str:
    value = row[key]
    if key in ('hit', 'critical'):
        return '/'.join('Y' if v else 'N' for v in value) or '-'
    if key == 'counter':
        if not value:
            return 'N'
        return 'Y(' + '/'.join(('C' if c else 'H') if h else 'M' for h, c in zip(row['counter_hit'], row['counter_critical'])) + ')'
    if key in ('damage', 'counter_damage'):
        return '/'.join(str(v) for v in value) or '-'
    if key == 'exp':
        return '/'.join(str(v) for v in value.values())
    return str(value)


def combo(name: str) -> str:
    """A unit's kind: the id without its instance suffix (actor021_3 → actor021)."""
    return name.rsplit('_', 1)[0] if name[-1:].isdigit() and '_' in name else name


def compare(pairs: list[tuple[dict, dict]]) -> tuple[list[str], dict]:
    lines = ['| # | 局面 | 伤害种子 | 回合 | 攻 → 守 | 敌打玩家 | 原版 命中／伤害／暴击／反击／反击伤害／经验 | 重制 同左 | 伤害流抽取 | 交锋末状态 | 一致 |',
             '|---|---|---|---|---|---|---|---|---|---|---|']
    totals = {'rows': 0, 'agree': 0, 'draws_same': 0, 'end_same': 0, 'missing': 0, 'enemy_on_player': 0, 'enemy_on_player_agree': 0,
              'strikes': 0, 'misses_original': 0, 'misses_remake': 0, 'crits_original': 0, 'crits_remake': 0, 'counters_original': 0,
              'counters_remake': 0, 'hit_bonus_rows': 0, 'record_cleared': 0, 'dead_bonus': 0}
    crit: dict[tuple[str, str, str], dict] = {}
    combos: set[tuple[str, str]] = set()
    notes: list[str] = []
    number = 0
    for cases, remake in pairs:
        by_key = {(c['run'], c['index']): c for c in remake['cases']}
        for run_index, run in enumerate(cases['runs']):
            for exchange in run.get('exchanges', []):
                number += 1
                totals['rows'] += 1
                ours = original_row(exchange)
                case = by_key.get((run_index, exchange['index']))
                head = f'| {number} | L{cases["level"]:03d} | {run["damage_seed"]} | {exchange["round"]} | {exchange["striker"]} → {exchange["defender"]} |'
                if case is None or case.get('error'):
                    totals['missing'] += 1
                    lines.append(f'{head} ? | - | {case.get("error") if case else "no remake case"} | - | - | MISSING |')
                    continue
                profiles = case.get('profiles', {})
                on_player = bool(profiles.get(exchange['defender'], {}).get('player')) and not profiles.get(exchange['striker'], {}).get('player')
                theirs = remake_row(case, exchange.get('actor'))
                for name, unit in exchange['end']['units'].items():
                    mine = case['end']['units'].get(name)
                    totals['dead_bonus'] += bool(mine and unit['hp'] <= 0 < unit['max_hp'] and unit['hit_bonus'] != mine['hit_bonus'])
                for name, unit in ours['end'].items():
                    if unit['exp'] is None and name in theirs['end']:   # a torn-down record: HP only
                        totals['record_cleared'] += 1
                        theirs['end'][name] = dict(theirs['end'][name], exp=None, hit_bonus=None, kill_chain=None)
                same = {key: ours[key] == theirs[key] for key in CHECKED}
                agree = all(same.values())
                totals['agree'] += agree
                totals['draws_same'] += same['draws']
                totals['end_same'] += same['end'] and same['damage_end']
                if on_player:
                    totals['enemy_on_player'] += 1
                    totals['enemy_on_player_agree'] += agree
                    combos.add((combo(exchange['striker']), combo(exchange['defender'])))
                totals['strikes'] += len(ours['hit']) + len(ours['counter_hit'])
                totals['misses_original'] += ours['hit'].count(False) + ours['counter_hit'].count(False)
                totals['misses_remake'] += theirs['hit'].count(False) + theirs['counter_hit'].count(False)
                totals['crits_original'] += sum(ours['critical']) + sum(ours['counter_critical'])
                totals['crits_remake'] += sum(theirs['critical']) + sum(theirs['counter_critical'])
                totals['counters_original'] += ours['counter']
                totals['counters_remake'] += theirs['counter']
                totals['hit_bonus_rows'] += any(u['hit_bonus'] for u in list(ours['end'].values()) + list(theirs['end'].values()))
                for side, row in (('original', ours), ('remake', theirs)):
                    for series, prefix, a, d in (('primary', '', exchange['striker'], exchange['defender']),
                                                 ('counter', 'counter_', exchange['defender'], exchange['striker'])):
                        entry = crit.setdefault((combo(a), combo(d), series), {})
                        entry[side + '_strikes'] = entry.get(side + '_strikes', 0) + len(row[prefix + 'hit'])
                        entry[side + '_hits'] = entry.get(side + '_hits', 0) + sum(row[prefix + 'hit'])
                        entry[side + '_crits'] = entry.get(side + '_crits', 0) + sum(row[prefix + 'critical'])
                if case.get('overrides'):
                    notes.append(f'#{number}: remake template overridden from the original live record: '
                                 + '; '.join(f'{u} ' + ', '.join(f'{k} {v[0]}→{v[1]}' for k, v in f.items()) for u, f in case['overrides'].items()))
                if not agree:
                    diffs = '; '.join(f'{k} original={ours[k]} remake={theirs[k]}' for k in CHECKED if not same[k] and k != 'draws')
                    if same['draws']:
                        notes.append(f'#{number}: every damage draw agrees ({len(ours["draws"])}), the state after them differs; {diffs}')
                    else:
                        first = next((i for i, (a, b) in enumerate(zip(ours['draws'], theirs['draws'])) if a != b),
                                     min(len(ours['draws']), len(theirs['draws'])))
                        site = exchange['draws'][first][0] if first < len(exchange['draws']) else 'end'
                        remake_site = case['draws'][first][2] if first < len(case.get('draws', [])) else 'end'
                        notes.append(f'#{number}: first differing damage draw #{first + 1} original {site} '
                                     f'({et.DAMAGE_SITE_MAP.get(site, "?")}) remake {remake_site}; {diffs}')
                text = lambda row: ' ／ '.join(cell(row, k) for k in COLUMNS)
                lines.append(f'{head} {"是" if on_player else "否"} | {text(ours)} | {text(theirs)} | '
                             f'{len(ours["draws"])}／{len(theirs["draws"])} {"同" if same["draws"] else "异"} | '
                             f'{"同" if same["end"] and same["damage_end"] else "异"} | {"✓" if agree else "✗"} |')
    lines += notes
    lines += ['', '| 攻 → 守 | 系列 | 原版 次数／命中／暴击 | 重制 次数／命中／暴击 |', '|---|---|---|---|']
    for (a, d, series), entry in sorted(crit.items()):
        if entry.get('original_strikes') or entry.get('remake_strikes'):
            lines.append(f'| {a} → {d} | {"主攻" if series == "primary" else "反击"} | '
                         f'{entry.get("original_strikes", 0)}／{entry.get("original_hits", 0)}／{entry.get("original_crits", 0)} | '
                         f'{entry.get("remake_strikes", 0)}／{entry.get("remake_hits", 0)}／{entry.get("remake_crits", 0)} |')
    levels = ','.join(sorted({str(cases['level']) for cases, _ in pairs}))
    lines.append(f'EXCHANGE_COMPARE levels={levels} rows={totals["rows"]} agree={totals["agree"]}/{totals["rows"]} '
                 f'enemy_on_player={totals["enemy_on_player_agree"]}/{totals["enemy_on_player"]} combos={len(combos)} '
                 f'draws_same={totals["draws_same"]}/{totals["rows"]} end_same={totals["end_same"]}/{totals["rows"]} '
                 f'missing={totals["missing"]} strikes={totals["strikes"]} misses original={totals["misses_original"]} '
                 f'remake={totals["misses_remake"]} crits original={totals["crits_original"]} remake={totals["crits_remake"]} '
                 f'counters original={totals["counters_original"]} remake={totals["counters_remake"]} '
                 f'hit_bonus_rows={totals["hit_bonus_rows"]} record_cleared={totals["record_cleared"]} dead_bonus={totals["dead_bonus"]}')
    return lines, totals


def compare_main(args) -> int:
    if len(args.files) % 2:
        print('compare wants CASES REMAKE pairs', file=sys.stderr)
        return 2
    pairs = [(json.loads(Path(a).read_text()), json.loads(Path(b).read_text())) for a, b in zip(args.files[::2], args.files[1::2])]
    lines, totals = compare(pairs)
    print('\n'.join(lines))
    return 0 if totals['agree'] == totals['rows'] else 1


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    if argv[:1] == ['compare']:
        parser = argparse.ArgumentParser(prog='_exchange_check.py compare')
        parser.add_argument('files', nargs='+', metavar='CASES REMAKE', help='one or more record／replay file pairs')
        return compare_main(parser.parse_args(argv[1:]))
    if argv[:1] != ['record']:
        print('usage: _exchange_check.py record ... | compare CASES REMAKE [CASES REMAKE ...]', file=sys.stderr)
        return 2
    parser = argparse.ArgumentParser(prog='_exchange_check.py record')
    parser.add_argument('--exe', type=Path, default=ORIGINAL_EXE)
    parser.add_argument('--level', type=int, required=True)
    parser.add_argument('--board', type=Path)
    parser.add_argument('--board-key')
    parser.add_argument('--turns', type=int, default=1)
    parser.add_argument('--seed', nargs=2, default=['1', '2'], metavar=('S1', 'S2'), help='global RNG start (default 1 2)')
    parser.add_argument('--damage-seeds', required=True, help='comma list／ranges; damage start [t, ~t] per seed')
    parser.add_argument('--set', dest='edits', action='append', type=parse_edit, default=[], metavar='ID.FIELD=VALUE',
                        help='as _enemy_level.py --set; also growth=0|1 (default 0: growth words zeroed; births still infer the base level, 0x40e800)')
    parser.add_argument('--stop-after', type=int, help='halt after this many exchanges closed')
    parser.add_argument('--jobs', type=int, default=3)
    parser.add_argument('--out', type=Path, required=True)
    return record_main(parser.parse_args(argv[1:]))


def parse_edit(text: str):
    if text.split('=', 1)[0] == 'growth':
        return ('', 'growth', int(text.split('=', 1)[1]))
    return et.parse_edit(text)


if __name__ == '__main__':
    raise SystemExit(main())
