"""Equal-speed action order: every battlefield roster against the original registration-slot order.

hsl01.exe (static-derived, docs/evidence_packets/static_reverse/initial_battle_initiative.md
«Registration order is not simply EVEF order»):

  * 0x407340 builds a round by walking the registration array 0x4c34c0 from slot 0 to 199 and
    stable-sorting by live speed +0xb8 (descending): equal speeds act in slot order.
  * 0x407660 registers one actor. +0xa2 < 20 (0x407cc0 copies +0xa0, the obj_Data6 SID token:
    SID_PLAYERn = n, SID_ENEMYxxx >= 21) writes the reserved slot n; any other actor takes the
    cursor 0x4c1a3c. Only level load resets the cursor to 20 (0x42da60 → 0x42da92 → 0x407260,
    store at 0x407287); 0x407720 frees a slot without moving the cursor; at 200 the cursor wraps
    to 0 and scans upward for the first free slot (0x4076b1..0x4076e1).
  * 0x407660 is reached only from 0x407cc0, which runs on an actor's first process tick (enemy
    init 0x43eef6, player init 0x44343e); objects tick plane by plane in list order (0x45f5f7)
    and a created object is appended to its plane list tail (0x45e307).

  So NPC slots rise in creation order: EVEF record order (every EVEF actor template is
  planeObject1 — `--pak` re-surveys that from the original resources), then the opening
  inserts in STORY order, then runtime inserts in firing／action order — until the 181st NPC
  registration of one battle wraps the cursor and reuses a freed low slot.

Remake: CoreTurnQueue.registration_slot reserves PLAYERS code − 1 for growth_profile.allocation
"manual" and leaves every other unit to roster (loop units) order after the players; the
assembler writes the roster in trace_opening order and runtime inserts append
(ScriptActorCreationRules.install_actor).

Per content/battles scenario with a playable roster this check FAILs when
  - a unit's class differs (original reserved slot ⇔ remake manual allocation) or its reserved
    slot differs (EVEF obj_Data9 / obj_Story_PlayerN − 1 vs actor_id − 1);
  - the NPCs' roster order is not their creation order (EVEF record, then opening insert number);
  - an opening NPC insert or a runtime NPC template is off planeObject1 without a listed reason,
    or an original-derived roster unit has no creation source;
  - two opening insert bindings name one unit (a re-insert takes a fresh slot in the original);
  - the scenario uses the class-template reinforcement path (BattleLoopScript appends by
    template class, not by script order);
  - the written NPC registrations (every EVEF actor incl. static objects such as the Enemy101
    hull, every STORY and WINFAIL actor insert once) reach the wrap.
Refill inserts (WINFAIL sections on or armed from an arming cycle) can repeat; the PASS line
names how many refill cycles the tightest level needs to wrap. Insert sections that several
arming actions can arm are counted once and listed in the table (multi_armed).
Special levels that include OBJ-ALL.H name script objects their seed does not join; those
read the one (plane, process, token) every defining seed agrees on.
Development fixtures whose roster has units without an original creation source, and authored
rosters, have no original order and are listed as skipped.

PASS line: REGISTRATION_ORDER_PASS scenarios=N compared=N skipped=N npcs=N equal_speed_npc_pairs=N
mixed_equal_speed_pairs=N mismatches=0 max_written_npc_registrations=N@level wrap_at=181
refill_insert_levels=N min_refills_to_wrap=N@level multi_armed_insert_levels=N.

Table (all scenarios): PYTHONPATH=tools python3 -m hsltools.checks.registration_order --table [--pak]

Registry task registration_order (family checks, CheckTask, replaces=()).
"""
from __future__ import annotations

import json
import math
import re
from collections import Counter
from pathlib import Path

from hsltools.checks import CheckTask
from hsltools.registry import CheckFailed, Context

SCENARIOS = 'content/battles'
SEEDS = 'content/generated/hsl/chapter01'
CORE_TURN_QUEUE = 'game/sim/CoreTurnQueue.gd'
SCRIPT_ACTORS = 'game/sim/ScriptActorCreationRules.gd'
RESERVED_SLOTS = 20                      # 0x407665 cmp word [edx+0xa2], 0x14
CURSOR_LIMIT = 200                       # 0x4076b1 cmp eax, 0xc8 → 0x4076bd cursor = 0
WRAP_AT = CURSOR_LIMIT - RESERVED_SLOTS + 1   # the 181st NPC registration reuses a freed slot
ACTOR_PROCESSES = ('defProcEnemy', 'defProcPlayer')   # the process inits that call 0x407cc0
NPC_PLANE = 'planeObject1'
INSERTS = ('actInsertObject', 'actInsertObjectRandomPos', 'actInsertRandomObject', 'actInsertStoryObject',
           'actInsertStoryObjectRandomPos', 'actInsertStoryObjectWait', 'actInsertStoryObjectWaitPos',
           'actInsertStoryObjectXRange')
ARMING = {'actInsertEventStatus': 'event', 'actInsertWinStatus': 'win', 'actInsertFailStatus': 'fail'}
PLAYER_INSTALL = re.compile(r'obj_Story_Player(\d+)$')
PLAYER_TOKEN = re.compile(r'SID_PLAYER(\d+)$')
# Runtime NPC templates off planeObject1: allowed only when no other actor insert can share
# their VM tick (a lower plane would tick, and register, ahead of planeObject1 inserts).
PLANE_EXCEPTIONS = {
    ('battle_051.json', 'obj_Story_Level51_Object1'):
        'WINFAIL051 event 3 inserts it alone (actDelay 2 follows) and deletes it in the same chain (actWalkAndDeleteWait 10000)',
}


def _load(path: Path) -> dict:
    return json.loads(path.read_text(encoding='utf-8'))


def _player_token(token: object) -> int | None:
    match = PLAYER_TOKEN.match(str(token or ''))
    return int(match.group(1)) if match and int(match.group(1)) < RESERVED_SLOTS else None


def remake_slot(unit: dict) -> int:
    """Mirror of CoreTurnQueue.registration_slot (the check pins its data key below)."""
    profile = unit.get('growth_profile')
    if not isinstance(profile, dict) or str(profile.get('allocation', '')) != 'manual':
        return -1
    code = str(unit.get('actor_id', ''))
    return int(code) - 1 if code.isdigit() and 1 <= int(code) <= RESERVED_SLOTS else RESERVED_SLOTS


def _level(scenario: dict) -> int | None:
    level = scenario.get('level')
    if isinstance(level, int) or (isinstance(level, str) and level.isdigit()):
        return int(level)
    match = re.search(r'/battle(\d{3})/', str((scenario.get('resources') or {}).get('map_objects', '')))
    return int(match.group(1)) if match else None


def _npc_object(spec: dict | None) -> bool | None:
    """True/False: the object registers in the cursor range / does not; None: not in the seed."""
    if spec is None:
        return None
    if spec.get('object_process') not in ACTOR_PROCESSES:
        return False
    return _player_token((spec.get('object_data_fields') or {}).get('obj_Data6')) is None


def _creation(unit: dict, records: dict, objects: dict) -> tuple[str, object, str]:
    """(class, key, plane) — class 'player' with its reserved slot, or 'npc' with its creation
    key (0, EVEF record) / (1, opening insert number)."""
    source = unit.get('position_source') or {}
    insert = source.get('opening_insert') or {}
    if insert:
        symbol = str(insert.get('symbol', ''))
        if insert.get('kind') == 'player_slot_install':
            match = PLAYER_INSTALL.match(symbol)
            if not match:
                raise ValueError(f'{unit["id"]}: player_slot_install {symbol!r} is not obj_Story_PlayerN')
            return 'player', int(match.group(1)) - 1, ''
        spec = objects.get(symbol)
        if spec is None or spec.get('object_process') not in ACTOR_PROCESSES:
            raise ValueError(f'{unit["id"]}: opening insert {symbol!r} is not an actor object of the seed')
        slot = _player_token((spec.get('object_data_fields') or {}).get('obj_Data6'))
        if slot is not None:
            return 'player', slot, str(spec.get('plane', ''))
        number = (unit.get('opening_birth') or {}).get('story_insert')
        if not isinstance(number, int):
            raise ValueError(f'{unit["id"]}: opening insert {symbol!r} without opening_birth.story_insert')
        return 'npc', (1, number), str(spec.get('plane', ''))
    if 'evef_record_index' in source:
        index = int(source['evef_record_index'])
        record = records.get(index)
        if record is None:
            raise ValueError(f'{unit["id"]}: EVEF record {index} is not in the seed')
        process, fields = record.get('object_process'), record.get('object_data_fields') or {}
        if process == 'defProcPlayerInstall':
            return 'player', int(fields.get('obj_Data9', -1)), ''
        if process in ACTOR_PROCESSES:
            slot = _player_token(fields.get('obj_Data6'))
            return ('player', slot, '') if slot is not None else ('npc', (0, index), '')
        raise ValueError(f'{unit["id"]}: EVEF record {index} is {process}, not an actor')
    return 'none', None, ''


def _sections(seed: dict, kind: str) -> list[dict]:
    return (seed.get('scripts', {}).get(kind) or {}).get('sections', [])


def _chain(section: dict) -> list[dict]:
    return [command for action in section.get('actions', []) for command in action.get('chain', [])]


def static_registrations(seed: dict, objects: dict) -> dict:
    """NPC registrations one battle writes: every EVEF actor (fielded or a static object such
    as the Enemy101 hull), every STORY actor insert and every WINFAIL actor insert once
    ('written'). WINFAIL sections on an arming cycle (a refill event re-arming itself) or armed
    from one can repeat: their inserts are reported per cycle. Sections with inserts that more
    than one arming action can arm are counted once and listed ('multi_armed'): whether they
    fire more than once depends on their conditions, which this static count does not decide."""
    evef = sum(1 for record in seed['placements']['records']
               if record.get('object_process') in ACTOR_PROCESSES
               and _player_token((record.get('object_data_fields') or {}).get('obj_Data6')) is None)
    unknown: set[str] = set()

    def inserts(section: dict) -> int:
        count = 0
        for command in _chain(section):
            if command['name'] in INSERTS and command.get('args'):
                npc = _npc_object(objects.get(command['args'][0]))
                if npc is None:
                    unknown.add(command['args'][0])   # not in the seed: counted, conservatively
                count += 1 if npc in (True, None) else 0
        return count

    story = sum(inserts(section) for section in _sections(seed, 'story'))
    winfail = {(section['name'], code): section for section in _sections(seed, 'winfail')
               for code in section.get('codes', [])}
    arms: dict[tuple, Counter] = {key: Counter() for key in winfail}
    initial: Counter = Counter()
    for section in _sections(seed, 'story'):
        for command in _chain(section):
            if command['name'] in ARMING and command.get('args'):
                initial[(ARMING[command['name']], command['args'][0])] += 1
    for key, section in winfail.items():
        for command in _chain(section):
            if command['name'] in ARMING and command.get('args'):
                target = (ARMING[command['name']], command['args'][0])
                if target in winfail:
                    arms[key][target] += 1

    def reaches(start: tuple) -> set:
        seen: set = set()
        stack = list(arms[start])
        while stack:
            node = stack.pop()
            if node not in seen:
                seen.add(node)
                stack.extend(arms.get(node, ()))
        return seen

    cyclic = {key for key in winfail if key in reaches(key)}
    repeatable = cyclic | {node for key in cyclic for node in reaches(key)}
    once = sum(inserts(winfail[key]) for key in winfail if key not in repeatable)
    per_cycle = sum(inserts(winfail[key]) for key in repeatable)
    multi_armed = sorted(f'{kind}{code}' for (kind, code) in winfail
                         if (kind, code) not in repeatable and inserts(winfail[(kind, code)])
                         and initial[(kind, code)] + sum(arms[src][(kind, code)] for src in winfail) > 1)
    return {'evef': evef, 'story': story, 'winfail_once': once, 'refill_per_cycle': per_cycle,
            'static_total': evef + story + once, 'multi_armed': multi_armed, 'unknown_symbols': sorted(unknown)}


def _pairs(values: list[int]) -> int:
    return sum(count * (count - 1) // 2 for count in Counter(values).values())


def _inversions(keys: list) -> int:
    return sum(1 for i in range(len(keys)) for j in range(i + 1, len(keys)) if keys[i] > keys[j])


def _speed(unit: dict) -> int:
    value = unit.get('live_speed')
    return int(value if value is not None else unit.get('speed', 0) or 0)


def _seeds(root: Path) -> tuple[dict, dict]:
    """Level seeds by level number, and each script symbol's (plane, process) set across all
    seeds: special levels that include OBJ-ALL.H keep script symbols without a joined row
    (battle.py script_actor_templates recovers their actor code from the name), and those
    shared objects are read from the seeds that do define them."""
    seeds: dict[int, dict] = {}
    shared: dict[str, set] = {}
    for path in sorted((root / SEEDS).glob('battle*_seed.json')):
        seed = _load(path)
        seeds[int(path.name[6:9])] = seed
        for entry in seed.get('script_objects', []):
            shared.setdefault(entry['symbol'], set()).add((entry.get('plane'), entry.get('object_process'),
                                                           str((entry.get('object_data_fields') or {}).get('obj_Data6', ''))))
    return seeds, shared


def _script_objects(seed: dict, shared: dict) -> dict:
    """Seed script objects plus unambiguous shared definitions of symbols the seed only names."""
    objects = {entry['symbol']: entry for entry in seed.get('script_objects', [])}
    named = {command['args'][0] for kind in ('story', 'winfail') for section in _sections(seed, kind)
             for command in _chain(section) if command['name'] in INSERTS and command.get('args')}
    for symbol in named - set(objects):
        if len(shared.get(symbol, ())) == 1:
            plane, process, token = next(iter(shared[symbol]))
            objects[symbol] = {'symbol': symbol, 'plane': plane, 'object_process': process,
                               'object_data_fields': {'obj_Data6': token}, 'shared_definition': True}
    return objects


def survey(root: Path) -> tuple[list[dict], list[str]]:
    rows: list[dict] = []
    issues: list[str] = []
    seeds, shared = _seeds(root)
    for path in sorted((root / SCENARIOS).glob('*.json')):
        scenario = _load(path)
        if not isinstance(scenario, dict) or not isinstance(scenario.get('playable_units'), list):
            continue
        name = path.name
        units = [unit for unit in scenario['playable_units'] if isinstance(unit, dict)]
        row = {'scenario': name, 'level': _level(scenario), 'units': len(units), 'status': 'compared', 'issues': []}
        rows.append(row)
        fixture = str(scenario.get('schema', '')) == 'hsl_development_battle.v1'
        provenance = scenario.get('provenance') if isinstance(scenario.get('provenance'), dict) else {}
        if provenance.get('evidence_tier') == 'authored':
            row['status'] = 'skipped: authored roster'
            continue
        seed = seeds.get(row['level'])
        if seed is None:
            row['status'] = 'skipped: no original level seed'
            if not fixture:
                row['issues'].append('original-derived roster without a level seed')
            continue
        records = {int(record['record_index']): record for record in seed['placements']['records']}
        objects = _script_objects(seed, shared)
        try:
            created = [_creation(unit, records, objects) for unit in units]
        except ValueError as error:
            row['status'] = 'error'
            row['issues'].append(str(error))
            continue
        if any(cls == 'none' for cls, _, _ in created):
            if fixture:
                row['status'] = 'skipped: fixture units without an original creation source'
                continue
            row['issues'].append('units without a creation source: '
                                 + ', '.join(unit['id'] for unit, (cls, _, _) in zip(units, created) if cls == 'none'))
        npc_keys: list = []
        npc_speeds: list[int] = []
        player_speeds: list[int] = []
        for unit, (cls, key, plane) in zip(units, created):
            slot = remake_slot(unit)
            if cls == 'player':
                player_speeds.append(_speed(unit))
                if slot < 0:
                    row['issues'].append(f'{unit["id"]}: original reserved slot {key}, remake unregistered NPC')
                elif slot != key:
                    row['issues'].append(f'{unit["id"]}: original reserved slot {key}, remake slot {slot}')
            elif cls == 'npc':
                npc_keys.append(key)
                npc_speeds.append(_speed(unit))
                if slot >= 0:
                    row['issues'].append(f'{unit["id"]}: original cursor-range NPC, remake reserved slot {slot}')
                if key[0] == 1 and plane != NPC_PLANE:
                    row['issues'].append(f'{unit["id"]}: opening NPC insert on {plane or "no plane"}, not {NPC_PLANE}')
        inversions = [(a, b) for i, a in enumerate(zip(npc_keys, npc_speeds)) for b in list(zip(npc_keys, npc_speeds))[i + 1:]
                      if a[0] > b[0]]
        row.update(players=len(player_speeds), npcs=len(npc_keys),
                   npc_pairs=_pairs(npc_speeds),
                   mixed_pairs=sum(npc_speeds.count(speed) for speed in player_speeds),
                   inversions=len(inversions),
                   affected_pairs=sum(1 for a, b in inversions if a[1] == b[1]))
        if inversions:
            order = [f'{"evef" if key[0] == 0 else "insert"}{key[1]}' for key in npc_keys]
            row['issues'].append(f'NPC roster order is not creation order ({len(inversions)} inversions, '
                                 f'{row["affected_pairs"]} equal-speed): {order}')
        # A re-insert of one unit would take a fresh (larger) slot in the original.
        preview_path = root / SCENARIOS / f'story_{row["level"]:03d}.json'
        if preview_path.is_file():
            bindings = _load(preview_path).get('opening', {}).get('actor_bindings', {})
            spawned = Counter(str(value.get('unit_id')) for key, value in bindings.items()
                              if '/insert' in key and isinstance(value, dict))
            reused = sorted(unit for unit, count in spawned.items() if count > 1)
            if reused:
                row['issues'].append(f'opening insert bindings reuse units {reused}')
        rules = scenario.get('scenario_rules') if isinstance(scenario.get('scenario_rules'), dict) else {}
        if rules.get('reinforcements'):
            row['issues'].append('scenario_rules.reinforcements is not empty: BattleLoopScript appends '
                                 'reinforcements by template class, not by script order')
        for symbol, spec in (scenario.get('script_actor_templates') or {}).items():
            actor = spec.get('actor', {}) if isinstance(spec, dict) else {}
            registered = spec.get('kind') == 'registered_player'
            slot = remake_slot(actor)
            if registered:
                match = PLAYER_INSTALL.match(symbol)
                if slot < 0 or (match and slot != int(match.group(1)) - 1):
                    row['issues'].append(f'runtime template {symbol}: registered player with remake slot {slot}')
                continue
            if slot >= 0:
                row['issues'].append(f'runtime template {symbol}: NPC with remake reserved slot {slot}')
            plane = str(objects.get(symbol, {}).get('plane', ''))
            if plane != NPC_PLANE and (name, symbol) not in PLANE_EXCEPTIONS:
                row['issues'].append(f'runtime NPC template {symbol} on {plane or "no plane"}, not {NPC_PLANE}')
        counts = static_registrations(seed, objects)
        row.update(registrations=counts)
        if counts['static_total'] >= WRAP_AT:
            row['issues'].append(f'written NPC registrations {counts["static_total"]} reach the cursor wrap ({WRAP_AT})')
        if counts['refill_per_cycle']:
            row['refills_to_wrap'] = math.ceil((WRAP_AT - counts['static_total']) / counts['refill_per_cycle'])
    for row in rows:
        issues.extend(f'{row["scenario"]}: {issue}' for issue in row['issues'])
    return rows, issues


def _core_contract(root: Path) -> list[str]:
    """The mirror above reads growth_profile.allocation == 'manual'; runtime inserts append."""
    issues = []
    source = (root / CORE_TURN_QUEUE).read_text(encoding='utf-8')
    body = source.split('static func registration_slot', 1)[-1].split('\nstatic func', 1)[0]
    if '"allocation"' not in body or '"manual"' not in body:
        issues.append(f'{CORE_TURN_QUEUE}: registration_slot no longer keys on growth_profile.allocation == "manual"; '
                      'update remake_slot in this check')
    install = (root / SCRIPT_ACTORS).read_text(encoding='utf-8')
    if 'loop["units"].append(actor)' not in install:
        issues.append(f'{SCRIPT_ACTORS}: runtime script actors no longer append to the roster end')
    return issues


def check(root: Path) -> str:
    rows, issues = survey(root)
    issues += _core_contract(root)
    if issues:
        raise ValueError('\n  ' + '\n  '.join(issues))
    compared = [row for row in rows if row['status'] == 'compared']
    heaviest = max(compared, key=lambda row: row['registrations']['static_total'])
    refills = [row for row in compared if 'refills_to_wrap' in row]
    tightest = min(refills, key=lambda row: row['refills_to_wrap']) if refills else None
    return (f'REGISTRATION_ORDER_PASS scenarios={len(rows)} compared={len(compared)} skipped={len(rows) - len(compared)} '
            f'npcs={sum(row["npcs"] for row in compared)} '
            f'equal_speed_npc_pairs={sum(row["npc_pairs"] for row in compared)} '
            f'mixed_equal_speed_pairs={sum(row["mixed_pairs"] for row in compared)} mismatches=0 '
            f'max_written_npc_registrations={heaviest["registrations"]["static_total"]}@{heaviest["level"]} '
            f'wrap_at={WRAP_AT} refill_insert_levels={len({row["level"] for row in refills})} '
            + (f'min_refills_to_wrap={tightest["refills_to_wrap"]}@{tightest["level"]} ' if tightest else 'min_refills_to_wrap=none ')
            + f'multi_armed_insert_levels={len({row["level"] for row in compared if row["registrations"]["multi_armed"]})}')


def table(root: Path) -> str:
    rows, issues = survey(root)
    head = ('scenario', 'level', 'status', 'units', 'players', 'npcs', 'npc_eq_pairs', 'mixed_eq_pairs',
            'inversions', 'affected_eq_pairs', 'written_npc_regs', 'refill_per_cycle', 'refills_to_wrap', 'multi_armed')
    lines = ['\t'.join(head)]
    for row in rows:
        counts = row.get('registrations', {})
        lines.append('\t'.join(str(value) for value in (
            row['scenario'], row['level'] if row['level'] is not None else '-', row['status'], row['units'],
            row.get('players', '-'), row.get('npcs', '-'), row.get('npc_pairs', '-'), row.get('mixed_pairs', '-'),
            row.get('inversions', '-'), row.get('affected_pairs', '-'), counts.get('static_total', '-'),
            counts.get('refill_per_cycle', '-') or '-', row.get('refills_to_wrap', '-'),
            ','.join(counts.get('multi_armed', [])) or '-')))
    lines.append(f'# issues={len(issues)}')
    lines.extend('# ' + issue for issue in issues)
    return '\n'.join(lines)


def pak_planes() -> str:
    """Resource-derived re-survey (original hsl.pak, ~20 s): obj_plane of every EVEF actor
    template and every scripted actor object, per level seed."""
    from hsltools.levels.seed import DEFAULT_PAK, _read_records, parse_text_metadata, record_names
    counts: Counter = Counter()
    root = Path(__file__).resolve().parents[3]
    for seed_path in sorted((root / SEEDS).glob('battle*_seed.json')):
        level = int(seed_path.stem[6:9])
        requested = record_names(level)
        requested.pop('map', None)
        objects = parse_text_metadata(_read_records(DEFAULT_PAK, {'objects': requested['objects']})['objects']['data'])
        by_code = {}
        for entry in objects.get('objects', []):
            try:
                by_code[int(entry.get('obj_code'))] = entry
            except (TypeError, ValueError):
                pass
        for record in _load(seed_path)['placements']['records']:
            if record.get('object_process') in ACTOR_PROCESSES + ('defProcPlayerInstall',):
                entry = by_code.get(int(record['object_code']), {})
                counts[(record['object_process'], entry.get('obj_plane'))] += 1
    return 'EVEF actor planes: ' + ', '.join(f'{process}/{plane}={count}' for (process, plane), count in sorted(counts.items(), key=str))


class RegistrationOrderTask(CheckTask):
    name = 'registration_order'
    family = 'checks'
    inputs = (SCENARIOS + '/', SEEDS + '/', CORE_TURN_QUEUE, SCRIPT_ACTORS)
    replaces = ()  # born as a registry task: no historical command to replace
    scripts = ('tools/hsltools/checks/registration_order.py',)

    def check(self, ctx: Context) -> str:
        try:
            return check(ctx.root)
        except (ValueError, OSError, KeyError) as error:
            raise CheckFailed(f'{self.name}: {error}') from error


def tasks() -> list[RegistrationOrderTask]:
    return [RegistrationOrderTask()]


if __name__ == '__main__':
    import sys
    from hsltools.paths import ROOT
    if '--table' in sys.argv:
        print(table(ROOT))
    if '--pak' in sys.argv:
        print(pak_planes())
    if '--table' not in sys.argv and '--pak' not in sys.argv:
        try:
            print(check(ROOT))
        except ValueError as error:
            print(f'REGISTRATION_ORDER_FAIL {error}', file=sys.stderr)
            raise SystemExit(1)
