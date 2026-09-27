"""Assemble a formal battle scenario for a registered main-line level from tracked data.

One assembly path for every level: the story preview (content/battles/story_NNN.json)
supplies the compiled opening, bindings, resources and the EVEF cast; the battle seed
supplies the STORY walk endpoints, the winfail scripts (interpreted live by
WinfailScenarioRules) and the object header; the reviewed source actor templates
(first_battle.json playable_units, content/generated/hsl/actors/NNN.json) supply the
units. What differs per level (output name, labels, focus, role exceptions, optionally the
expected roster size, unit id patterns) is the `battle`
section of content/battles/levels/NNN.json (docs/architecture/LEVEL_PROFILES.md). The registry task level_battle:N (tools/hsl.py generate|check level_battle:N) writes content/battles/
battle_NNN.json plus content/generated/hsl/treasures/battle_NNN.json and checks them
byte-for-byte against the tracked files.

Roles: an EVEF player install or a unit installed by obj_Story_PlayerN is player_controlled;
every other actor is AI, friendly_ai when its installed player mode carries the pmPlayer bit
(pmPlayer / pmNPCPlayer / pmPlayerEnemy village NPCs), enemy_ai otherwise (pmEnemy / pmNPC);
the profile's role_overrides name the exceptions. The installed player mode (unit key
`player_mode`, the live +0x28 word the actor constructor 0x407ec0 leaves: PLAYERS mode,
swapped pmPlayer<->pmEnemy by obj_Data9, overridden by obj_X1) is what the runtime side
mask reads (ActorRoleRules.side_mask); the object's obj_HitPoint word is added to the
growth source hit_point (`object_hit_point`); the object's obj_Data5 word installs the
status-panel 稱號 / name (`title`, `display_name`, live +0x1c / +0x04); the object's obj_Data8
word installs the unit's own death line (`dead_message`, live +0x14). Positions are the STORY endpoints after the opening walks (the
presentation still starts at the original insert/EVEF pixel), quantized only when the
source coordinates already sit on the 32 px grid. A unit installed by obj_Story_PlayerN is
that registered slot's PLAYERS row (PARTY_SLOTS) whatever sprite the preview draws; a STORY
insert's actSetPrevInsertObjectAdjustLevel pair is pre-baked as `script_insert.adjust_level`;
EVEF actors the opening deletes stay in the scenario as opening-only `story_actors`.
"""
from __future__ import annotations

import copy
import json
import re
from collections.abc import Mapping
from pathlib import Path

from hsltools.assets.portraits import NAMES as RESOURCE_TEXT, panel_name, resource_defines
from hsltools.data.combat_aftermath import speaker_id
from hsltools.data.equipment import build as equipment_data
from hsltools.data.treasures import chest_hidden
from hsltools.legacy import ENCOUNTER_RANGE, assembled_battle_levels
from hsltools.levels import profile as level_profile
from hsltools.levels.scenario import SHARED_RESOURCES, apply_terrain_overrides, impassable, status_timelines, terrain_overrides
from hsltools.levels.timeline import level_table_music
from hsltools.model.jobs import ATTRIBUTES, calculate
from hsltools.native.sources import sources
from hsltools.paths import ROOT
from hsltools.registry import CheckFailed, GeneratedFilesTask, Context
from hsltools.schema import unit as unit_schema
from hsltools.sources.tables import digest, parse_table
from hsltools.sources.actor_walk_frames import object_actor_code

FIRST = ROOT / 'content/battles/first_battle.json'
CELL = 32
# actMove* (ACTION.H 52-55) slide the object without its walk cycle to the same kind of
# target as actWalk*; the endpoint reading is identical (STORY053 rope descent).
WALK_ABSOLUTE = ('actWalk', 'actWalkWait', 'actMove', 'actMoveWait')
WALK_RELATIVE = ('actWalkDisp', 'actWalkDispWait', 'actMoveDisp', 'actMoveDispWait')
WALK_PREV = ('actWalkPrevInsertObject', 'actWalkPrevInsertObjectWait')
INSERT_OBJECT = ('actInsertObject', 'actInsertObjectWait', 'actInsertObjectRandomPos')
DELETE = ('actWalkAndDelete', 'actWalkAndDeleteWait', 'actDeleteObject')

# obj_Story_PlayerN installs registered party slot N-1 (OBJ-ALL.H codes 6..14); unit ids
# follow the story previews' bindings (tools/hsltools/levels/story_scene.py).
PARTY_SLOTS: dict[int, tuple[str, str, str]] = {
    1: ('001', 'leonard', 'SID_雷歐納德'), 2: ('002', 'tina', 'SID_緹娜'), 3: ('003', 'hu', 'SID_琥'),
    4: ('004', 'hanks', 'SID_漢克斯'), 5: ('005', 'shera', 'SID_雪拉'), 6: ('006', 'rett', 'SID_雷特'),
    7: ('007', 'howl', 'SID_嚎'), 8: ('008', 'gulu', 'SID_咕嚕'), 9: ('009', 'claudie', 'SID_克羅蒂'),
}
PARTY_TOKENS = {token: actor_id for actor_id, _unit, token in PARTY_SLOTS.values()}

# The per-level battle profile (content/battles/levels/NNN.json `battle`, hsltools.levels.profile).
LEVELS: dict[int, dict] = level_profile.section('battle')

# Random encounters (levels 501-578): a visited big-map point rolls its encounter ratio and
# opens <point event> + 0..2 (WorldMapRules.arrival, static-derived 0x427ab3). Each 5NN
# EVEF installs all nine registered slots as 有才產生 (conditional: only the members the
# party actually carries take the field) and places its monsters; the STORY is
# actPlayDefaultLevelMusic N (the base level's table track, resolved at generation time),
# a delay and 雷歐納德's dead message, the winfail is "every enemy defeated -> back to the
# big map" / "雷歐納德 falls". The scenarios are assembled from the seed alone (no story
# preview): map / terrain of the base level, the shared actor pool battle500/ and the
# level's own timeline / message evidence / map objects.
ENCOUNTER_POOL = 'res://content/imported/hsl/chapter01/battle500'
# The registered party slots have reviewed source templates, portraits and panel titles;
# 008 is fieldable once its source range is compiled from ITEM.TXT/RANGE.TXT.
ENCOUNTER_PARTY_SLOTS = ('001', '002', '003', '004', '005', '006', '007', '008', '009')

WORLD_MAP_PATH = ROOT / 'content/imported/hsl/global/world_map/world_map.json'
STORY_CORPUS_SCRIPTS = ROOT / 'content/imported/hsl/story_corpus/scripts'


def _encounter_assignments() -> dict[int, dict]:
    """Derive encounter point/title pairs from tracked WINFAIL and map data.

    The original scripts set a visited point's encounter event to the first 5NN level;
    the next two levels are selected by the world-map offset. Keeping this join here
    prevents the campaign title from drifting from the source point name.
    """
    world_map = json.loads(WORLD_MAP_PATH.read_text())
    names = {int(point['id']): str(point['name_text']) for point in world_map['points']}
    first_assignments: dict[int, set[int]] = {}

    def visit(value: object) -> None:
        if isinstance(value, dict):
            if value.get('name') == 'actBMSetPointEvent':
                args = value.get('args', [])
                if (len(args) >= 3 and str(args[0]).isdigit() and str(args[1]).isdigit()
                        and 501 <= int(args[1]) <= 578 and args[2] == 'bmpmVisit'):
                    first_assignments.setdefault(int(args[1]), set()).add(int(args[0]))
            for child in value.values():
                visit(child)
        elif isinstance(value, list):
            for child in value:
                visit(child)

    for path in sorted(STORY_CORPUS_SCRIPTS.glob('WINFAIL*.json')):
        visit(json.loads(path.read_text()))
    assignments: dict[int, set[int]] = {}
    for first_level, point_ids in first_assignments.items():
        for level in range(first_level, first_level + 3):
            if level in assignments and assignments[level] != point_ids:
                raise ValueError(f'encounter {level} maps to conflicting points')
            assignments[level] = point_ids
    expected = set(range(501, 579))
    if set(assignments) != expected:
        missing = sorted(expected - set(assignments))
        extra = sorted(set(assignments) - expected)
        raise ValueError(f'encounter point derivation mismatch: missing={missing} extra={extra}')
    result = {}
    for level in sorted(expected):
        point_ids = assignments[level]
        if len(point_ids) != 1:
            raise ValueError(f'encounter {level} maps to multiple points: {sorted(point_ids)}')
        point_id = next(iter(point_ids))
        if point_id not in names:
            raise ValueError(f'encounter {level} references unknown world-map point {point_id}')
        result[level] = {'point_id': point_id, 'title': f'{names[point_id]} · 遭遇戰'}
    return result


class _Encounters(Mapping):
    """{level: {'point_id', 'title'}} for the encounter levels 501..578 (the key set is fixed and
    _encounter_assignments proves it); the titles are joined from the imported world map on first
    use, so the task list loads while original-derived content is absent (hsltools.original_content)."""

    _data: dict[int, dict] | None = None

    def _load(self) -> dict[int, dict]:
        if self._data is None:
            self._data = _encounter_assignments()
        return self._data

    def __getitem__(self, level: int) -> dict:
        return self._load()[level]

    def __iter__(self):
        return iter(ENCOUNTER_RANGE)

    def __len__(self) -> int:
        return len(ENCOUNTER_RANGE)

    def __contains__(self, level: object) -> bool:
        return level in ENCOUNTER_RANGE


ENCOUNTERS: Mapping[int, dict] = _Encounters()


def _check_encounter_titles() -> None:
    derived = _encounter_assignments()
    actual = {level: {'point_id': profile['point_id'], 'title': profile['title']}
              for level, profile in ENCOUNTERS.items()}
    if actual != derived:
        raise ValueError(f'encounter titles differ from source point derivation: {actual} != {derived}')


def _load(path: Path) -> dict:
    return json.loads(path.read_text())


def templates() -> dict[str, dict]:
    first = _load(FIRST)
    result: dict[str, dict] = {}
    for unit in first['playable_units']:
        result.setdefault(unit['actor_id'], unit)
    for path in sorted((ROOT / 'content/generated/hsl/actors').glob('*.json')):
        data = _load(path)
        actor = data['actor']
        result[path.stem] = actor
    return result


def conditional_installs(seed: dict) -> dict[str, dict]:
    """EVEF defProcPlayerInstall records flagged obj_Data8 = 1 (有才產生) by unit id:
    {unit_id: {slot, actor_id, token, evef_record_index, placement_xy, object_name}}.
    The story preview leaves these registered slots out of its cast; the formal battle
    fields them install_if_carried (ConditionalPartyRules), the same reading as the
    encounter slots. A record off the 32 px grid or on an unknown slot fails the
    assembly instead of being dropped."""
    result: dict[str, dict] = {}
    for record in seed['placements']['records']:
        fields = record.get('object_data_fields', {})
        if record.get('role_from_process') != 'player_install' or str(fields.get('obj_Data8', '')) != '1':
            continue
        slot = int(fields['obj_Data9']) + 1
        if slot not in PARTY_SLOTS:
            raise ValueError(f'conditional install record {record["record_index"]} names unknown party slot {slot}')
        actor_id, unit_id, token = PARTY_SLOTS[slot]
        xy = record['placement_xy_candidate']
        if any(v % CELL for v in xy):
            raise ValueError(f'conditional install {unit_id} (EVEF record {record["record_index"]}) is not on the 32 px grid: {xy}')
        if unit_id in result:
            raise ValueError(f'conditional install {unit_id} appears twice in the EVEF')
        result[unit_id] = {'slot': slot, 'actor_id': actor_id, 'token': token, 'evef_record_index': record['record_index'],
                           'placement_xy': list(xy), 'object_name': record['object_name']}
    return result


def trace_opening(seed: dict, preview: dict) -> dict:
    """Endpoints of every actor after the STORY opening: EVEF cast at their placement,
    conditional 有才產生 installs at their EVEF placement (bound to their party token so
    their walks resolve), obj_Story_PlayerN installs and actInsertObject inserts at their
    insert pixel, all moved by the walk tokens. Movements of a party token with neither
    a preview binding nor an EVEF record are listed in 'skipped' rather than failing the
    assembly. Returns {state, traces, wait_rounds, adjust_levels, deleted, inserted, skipped,
    conditional, bindings, insert_order, readjusted}; adjust_levels holds the
    actSetPrevInsertObjectAdjustLevel [range, disp range] pair of an insert (opcode 56 writes
    the previous insert's live +0x1f8 halves before its install adjusts the level);
    insert_order numbers the actor-producing inserts 1.. in script order (obj_Story_PlayerN
    installs and bound actInsertObject); readjusted lists the units alive when
    actAdjustAllPlayerLevel runs (opcode 73 sets 0x4c1d48 at 0x452408, so every other object
    re-runs 0x40e870 once on that tick: 0x43f3a5 general objects, 0x4438d4 players)."""
    bindings = dict(preview['opening']['actor_bindings'])
    story_objects = preview['opening'].get('story_objects', {})
    state = {a['id']: list(a['placement_xy']) for a in preview['story_actors']}
    conditional = conditional_installs(seed)
    for unit_id, install in conditional.items():
        key = f"{install['token']}/1"
        if unit_id in state or key in bindings:
            raise ValueError(f'conditional install {unit_id} is already in the preview cast')
        bindings[key] = {'unit_id': unit_id, 'actor_id': install['actor_id'], 'placement_xy': list(install['placement_xy'])}
        state[unit_id] = list(install['placement_xy'])
    traces: dict[str, list] = {key: [] for key in state}
    wait_rounds: dict[str, int] = {}
    adjust_levels: dict[str, list[int]] = {}
    inserted: dict[str, dict] = {}
    deleted: set[str] = set()
    skipped: list[dict] = []
    counters: dict[str, int] = {}
    insert_order: dict[str, int] = {}
    readjusted: list[str] = []
    last_insert = ''

    def move(unit: str, xy: list, name: str, args: list) -> None:
        before = state.get(unit, [0, 0]).copy()
        state[unit] = xy
        traces.setdefault(unit, []).append({'action': name, 'args': args, 'before': before, 'after': xy.copy()})

    for section in seed['scripts']['story']['sections']:
        for action in section.get('actions', []):
            for command in action.get('chain', []):
                name, args = command['name'], command['args']
                if name == 'actInsertStoryObject':
                    spec = story_objects.get(args[0], {})
                    unit = str(spec.get('spawns_unit_id', ''))
                    if spec.get('kind') != 'player_slot_install' or not unit:
                        continue
                    inserted[unit] = {'symbol': args[0], 'insert_xy': [int(args[1]), int(args[2])], 'kind': 'player_slot_install'}
                    insert_order.setdefault(unit, len(insert_order) + 1)
                    move(unit, [int(args[1]), int(args[2])], name, args)
                    last_insert = unit
                elif name in INSERT_OBJECT:
                    counters[args[0]] = counters.get(args[0], 0) + 1
                    binding = bindings.get(f'{args[0]}/insert{counters[args[0]]}')
                    if binding is None:
                        # A defProcEnemy object with no walk group is a rendered map
                        # object, not a PlayLoop actor. Its object_fields obj_Data6
                        # token can still resolve the static binding used by
                        # actDeleteObject (STORY018's gate re-insert).
                        object_spec = story_objects.get(args[0], {})
                        fields = object_spec.get('object_fields', {}) if isinstance(object_spec, dict) else {}
                        static_token = str(fields.get('obj_Data6', ''))
                        static_binding = bindings.get(static_token + '/1', {})
                        if static_binding.get('kind') != 'static_object':
                            static_binding = next((candidate for candidate in bindings.values()
                                                   if candidate.get('kind') == 'static_object'
                                                   and candidate.get('object_symbol') == args[0]), {})
                        if static_binding.get('kind') == 'static_object':
                            inserted[static_binding['unit_id']] = {'symbol': args[0], 'insert_xy': [int(args[1]), int(args[2])], 'kind': 'static_object_insert'}
                            last_insert = ''
                            continue
                        raise ValueError(f'unbound opening insert {args[0]} #{counters[args[0]]}')
                    unit = binding['unit_id']
                    # actInsertObjectRandomPos args are [code][disp x][disp y][slot]: the story scene
                    # resolved the slot + disp pixel into the binding.
                    xy = list(binding['insert_xy']) if name == 'actInsertObjectRandomPos' else [int(args[1]), int(args[2])]
                    inserted[unit] = {'symbol': args[0], 'insert_xy': xy, 'kind': 'object_insert'}
                    insert_order.setdefault(unit, len(insert_order) + 1)
                    move(unit, xy, name, args)
                    last_insert = unit
                elif name in WALK_PREV:
                    if not last_insert:
                        raise ValueError('actWalkPrevInsertObject without a previous insert')
                    move(last_insert, [int(args[0]), int(args[1])], name, args)
                elif name == 'actSetPrevInsertObjectWaitRound':
                    wait_rounds[last_insert] = int(args[0])
                elif name == 'actChangePrevInsertObjectID':
                    # 0x450840 case 0x20 writes the id into the previous insert's roster
                    # word +0x84, the code 0x44fa80 hands 0x44fad0 — so actCheckEnemy／
                    # actMessage name the insert by the new id (STORY028's four Enemy50
                    # door guards 5000..5003, WINFAIL028 events 3..6).
                    if not last_insert or not args:
                        raise ValueError('actChangePrevInsertObjectID without a previous insert or an id')
                    bindings[f'{args[0]}/1'] = {'unit_id': last_insert, 'object_id': int(args[0]),
                                                'source': 'STORY actChangePrevInsertObjectID (0x450840 case 0x20 -> roster +0x84, read by 0x44fa80)'}
                elif name == 'actChangePlayerID':
                    # 0x450840 case 0x5a (0x450d86) resolves [old id][serial] through 0x44fad0 and
                    # writes the new id into that object's roster word +0x84, the word case 0x20
                    # writes: STORY029 renames 梅爾／凱文 (SID_ENEMY023 serials 1／2) to the
                    # 1000／1001 its WINFAIL029 death events check.
                    old = bindings.get(f'{args[0]}/{args[1]}', {}) if len(args) >= 3 else {}
                    if 'unit_id' not in old:
                        raise ValueError(f'actChangePlayerID names no bound unit: {args}')
                    bindings[f'{args[2]}/1'] = {'unit_id': old['unit_id'], 'object_id': int(args[2]),
                                                'source': 'STORY actChangePlayerID (0x450840 case 0x5a -> roster +0x84, read by 0x44fa80)'}
                elif name == 'actSetPrevInsertObjectAdjustLevel':
                    if not last_insert or len(args) < 2:
                        raise ValueError('actSetPrevInsertObjectAdjustLevel without a previous insert or its two halves')
                    adjust_levels[last_insert] = [int(args[0]), int(args[1])]
                elif name == 'actAdjustAllPlayerLevel':
                    # Only STORY006 writes opcode 73; a second one would re-adjust twice,
                    # which InitialRosterGrowthRules does not model.
                    if readjusted:
                        raise ValueError('a second actAdjustAllPlayerLevel in one opening')
                    readjusted = [unit for unit in state if unit not in deleted]
                elif name in WALK_ABSOLUTE or name in WALK_RELATIVE or name in DELETE:
                    key = f'{args[0]}/{args[1]}'
                    if args[0] == '-1':
                        # Object id -1 names the object inserted last (STORY013 / winfail015 / 021),
                        # read like actWalkPrevInsertObject (BattleOpeningCoordinator._bound_actor).
                        if not last_insert:
                            raise ValueError('object -1 without a previous insert')
                        key = last_insert
                    elif key not in bindings:
                        if args[0] in PARTY_TOKENS:
                            skipped.append({'action': name, 'args': args, 'reason': 'uninstalled conditional party member'})
                            continue
                        raise ValueError('unbound opening movement actor ' + key)
                    unit = last_insert if args[0] == '-1' else bindings[key]['unit_id']
                    if name in DELETE:
                        deleted.add(unit)
                        continue
                    xy = [int(args[2]), int(args[3])]
                    if name in WALK_RELATIVE:
                        xy = [p + d for p, d in zip(state[unit], xy)]
                    move(unit, xy, name, args)
    return {'state': state, 'traces': traces, 'wait_rounds': wait_rounds, 'adjust_levels': adjust_levels, 'deleted': deleted,
            'inserted': inserted, 'skipped': skipped, 'conditional': conditional, 'bindings': bindings,
            'insert_order': insert_order, 'readjusted': readjusted}


def unit_id_renames(profile: dict, trace: dict, preview: dict) -> dict[str, str]:
    """{preview unit id: battle unit id} from the profile's `unit_ids`: {EVEF token or STORY
    insert symbol: id pattern}, a pattern with `{n}` counting the units it names in opening
    order (EVEF record order, then STORY inserts); patterns sharing one string share the
    counter (level 53: the EVEF gate guard and the two pursuers are enemy023_1..3). Units the
    table does not name keep the preview's id. A token the opening never fields is an error."""
    patterns: dict[str, str] = dict(profile.get('unit_ids', {}))
    if not patterns:
        return {}
    by_id = {actor['id']: actor for actor in preview['story_actors']}
    counters: dict[str, int] = {}
    seen: set[str] = set()
    renames: dict[str, str] = {}
    for unit_id in trace['state']:
        if unit_id in by_id:
            key = str(by_id[unit_id]['token'])
        elif unit_id in trace['inserted']:
            key = str(trace['inserted'][unit_id]['symbol'])
        elif unit_id in trace['conditional']:
            key = str(trace['conditional'][unit_id]['token'])
        else:
            continue
        if key not in patterns:
            continue
        seen.add(key)
        pattern = patterns[key]
        counters[pattern] = counters.get(pattern, 0) + 1
        renames[unit_id] = pattern.format(n=counters[pattern])
    unfielded = sorted(set(patterns) - seen)
    if unfielded:
        raise ValueError(f'unit_ids name tokens the opening never fields: {unfielded}')
    if len(set(renames.values())) != len(renames) or set(renames.values()) & (set(trace['state']) - set(renames)):
        raise ValueError(f'unit_ids produce a duplicate unit id: {renames}')
    return renames


def _renamed_trace(trace: dict, renames: dict[str, str]) -> dict:
    """The opening trace with every unit id mapped through `renames` (keys and binding targets)."""
    if not renames:
        return trace

    def new(unit_id: str) -> str:
        return renames.get(unit_id, unit_id)

    result = dict(trace)
    for key in ('state', 'traces', 'wait_rounds', 'adjust_levels', 'inserted', 'conditional', 'insert_order'):
        result[key] = {new(unit_id): value for unit_id, value in trace[key].items()}
    result['deleted'] = {new(unit_id) for unit_id in trace['deleted']}
    result['readjusted'] = [new(unit_id) for unit_id in trace['readjusted']]
    bindings = {}
    for key, binding in trace['bindings'].items():
        binding = dict(binding)
        if 'unit_id' in binding:
            binding['unit_id'] = new(str(binding['unit_id']))
        bindings[key] = binding
    result['bindings'] = bindings
    return result


def _actor_instance(seed: dict, record_index: int | None) -> dict | None:
    """The unit's EVEF instance words as the seed decoded them (hsltools/levels/seed.py
    _actor_instance): item slots and per-instance AI overrides applied by the original
    install callback 0x42bd50 on top of the PLAYERS template. None when the record has
    no non-zero instance word."""
    if record_index is None:
        return None
    for record in seed['placements']['records']:
        if record['record_index'] == record_index and record.get('actor_instance'):
            return {'evidence_tier': 'resource-derived', 'record_index': record_index, **copy.deepcopy(record['actor_instance'])}
    return None


def _footprint_cells(cell: tuple[int, int], radius: int) -> set[tuple[int, int]]:
    x, y = cell
    return {(x + dx, y + dy) for dy in range(-radius, radius + 1) for dx in range(-radius, radius + 1)}


# The original installs an actor on its EVEF (or STORY actInsertObject) pixel without a
# terrain test: 0x46be17 → 0x45e307 stores the record X/Y unchanged, the enemy init
# 0x407cc0 and the player installer 0x4080b0 only round to the cell centre, and 0x411a30
# ORs the occupant side into the map word (static-derived,
# docs/evidence_packets/static_reverse/actor_placement_initialization.md#install-has-no-terrain-test);
# level 6's villager 061_1 stands on the 0xff cell (25,15) at the 宣戰 card
# (runtime-measured, docs/evidence_packets/runtime_observations/battle_006/README.md).
INSTALL_ON_BLOCKED_NOTE = ('Source placement is a blocked cell in the WRD reading; the original installs the actor there without a terrain test '
                           '(0x45e307 / 0x407cc0 / 0x4080b0 round to the cell centre only), so the unit starts on it.')

STORY_ENDPOINT_ON_BLOCKED_NOTE = ('STORY walk endpoint is a blocked cell in the WRD reading; the original leaves the walker on its endpoint '
                                  '(opening snapshot at the round-1 halt, runtime-measured), so the unit starts on it.')

SCRIPT_LANDING_NOTE = ('STORY walk endpoint is a 0xff cell for a ground walker; the original walk-destination fix 0x44fbd0 moves it to the nearest '
                       'cell its mode-1 flood reaches (docs/evidence_packets/static_reverse/original_script_entry.md).')


STORY_WALK_STOP_NOTE = ('STORY walk endpoint is a 0xff cell no ground route reaches; the original walker 0x453b90 registers the cell its '
                        'route chain stops on (0x4541a1, docs/evidence_packets/static_reverse/original_script_walk_path.md).')

WALK_RADII = (18, 16, 14, 12)
WALK_STEP = {1: (0, -1), 2: (0, 1), 3: (-1, 0), 4: (1, 0)}


def script_walk_stop(grid: list, start: tuple[int, int], dest: tuple[int, int], flying: bool) -> tuple[int, int]:
    """The cell the original walker 0x453b90 stops on (ScriptWalkPath.route's chain): each
    0x411080 call floods 18／16／14／12 from the walker (0x40f350 → 0x40ed50, script mode
    without the map-bound test), moves the destination to the flooded cell nearest by
    Manhattan distance in row-major order (0x413740), descends strictly (0x410a50／0x410730)
    and is called again from the segment's end until the destination is reached or no
    segment comes back; the walker registers the cell it stands on (0x411a30 at 0x4541a1)."""
    height, width = len(grid), len(grid[0])

    def inside(c):
        return 0 <= c[0] < width and 0 <= c[1] < height

    def level(c):
        tile = grid[c[1]][c[0]]
        return 255 if tile['b'] else int(tile['h'])

    def flood(origin, radius):
        size = 2 * radius + 1
        values = [0] * (size * size)
        values[radius * size + radius] = radius + 1

        def step(cell, budget, direction, previous):
            while True:
                bx, by = cell[0] - origin[0] + radius, cell[1] - origin[1] + radius
                if not (0 <= bx < size and 0 <= by < size):
                    return
                index = by * size + bx
                ins = inside(cell)
                if ins and int(grid[cell[1]][cell[0]]['t']) & 0x4000:
                    return
                h = level(cell) if ins else previous
                extra = 0
                if not flying:
                    gap = h - previous
                    extra = gap if gap >= 0 else (-gap if -gap >= 3 else 0)
                    if previous == 0x80:
                        extra = 0x10 if h == 0xff else 0
                    if extra > 2:
                        return
                if budget <= values[index]:
                    return
                values[index] = budget
                budget -= 1 + extra
                if budget < 1:
                    return
                if direction in (0, 1):
                    step((cell[0], cell[1] + (-1 if direction == 0 else 1)), budget, direction, h)
                    step((cell[0] - 1, cell[1]), budget, 2, h)
                    cell, direction = (cell[0] + 1, cell[1]), 3
                elif direction == 2:
                    step((cell[0], cell[1] - 1), budget, 0, h)
                    step((cell[0], cell[1] + 1), budget, 1, h)
                    cell = (cell[0] - 1, cell[1])
                else:
                    step((cell[0], cell[1] - 1), budget, 0, h)
                    step((cell[0], cell[1] + 1), budget, 1, h)
                    cell = (cell[0] + 1, cell[1])
                previous = h

        source = level(origin) if inside(origin) else 0x80
        for direction, (dx, dy) in enumerate(((0, -1), (0, 1), (-1, 0), (1, 0))):
            step((origin[0] + dx, origin[1] + dy), radius, direction, source)
        return origin, radius, size, values

    def value(fl, cell):
        origin, radius, size, values = fl
        bx, by = cell[0] - origin[0] + radius, cell[1] - origin[1] + radius
        return values[by * size + bx] if 0 <= bx < size and 0 <= by < size else -1

    def nearest(fl, target):
        origin, radius, size, values = fl
        best, found = 600000, None
        for by in range(size):
            for bx in range(size):
                if values[by * size + bx]:
                    cell = (origin[0] - radius + bx, origin[1] - radius + by)
                    d = abs(cell[0] - target[0]) + abs(cell[1] - target[1])
                    if d < best:
                        best, found = d, cell
        return found

    def descend(fl, target):
        origin = fl[0]
        floor = value(fl, target)
        if floor <= 0 or target == origin:
            return []
        dx, dy = target[0] - origin[0], target[1] - origin[1]
        if dx < 1:
            order = ((3, 1, 4, 2) if dy < dx else (1, 3, 2, 4)) if dy < 1 else ((3, 2, 4, 1) if dy < dx else (2, 3, 1, 4))
        else:
            order = ((4, 1, 3, 2) if dy < dx else (1, 4, 2, 3)) if dy < 1 else ((4, 2, 3, 1) if dy < dx else (2, 4, 1, 3))
        horizontal = (4, 3) if origin[0] < target[0] else (3, 4)
        vertical = (2, 1) if origin[1] < target[1] else (1, 2)
        failed = set()

        def go(cell, direction, depth, previous):
            if depth > 99:
                return []
            v = value(fl, cell)
            if v < floor or v >= previous:
                return []
            if cell == target:
                return [cell]
            if (cell, direction) in failed:
                return []
            for turn in (direction,) + (horizontal if direction <= 2 else vertical):
                path = go((cell[0] + WALK_STEP[turn][0], cell[1] + WALK_STEP[turn][1]), turn, depth + 1, v)
                if path:
                    return [cell] + path
            failed.add((cell, direction))
            return []

        start_value = value(fl, origin)
        for direction in order:
            path = go((origin[0] + WALK_STEP[direction][0], origin[1] + WALK_STEP[direction][1]), direction, 1, start_value)
            if path:
                return path
        return []

    current, seen = start, {start}
    for _ in range(64):
        if current == dest:
            break
        goal, fl = dest, None
        for radius in WALK_RADII:
            fl = flood(current, radius)
            found = nearest(fl, goal)
            if radius == WALK_RADII[-1] or found is not None:
                goal = found
        if goal is None:
            break
        segment = descend(fl, goal)
        if not segment:
            break
        current = segment[-1]
        if current in seen:
            break
        seen.add(current)
    return current


def script_landing(grid: list, cell: tuple[int, int], taken: set) -> tuple[int, int] | None:
    """0x44fbd0 for a ground walker whose STORY endpoint is a 0xff／hard-block cell: the cell's
    word is cleared to its low 12 bits for the flood (0x411940: height 0, no flags), a mode-1
    flood of 12 (0x40f440 → 0x40f02a: only 0x4000 and a height step of 3 or more block, each
    step costs 1 plus the climb, units do not block) runs from it, and 0x413740 takes the
    flooded cell without a unit nearest by Manhattan distance in row-major order. None when
    no cell is reached (the walker stays on its endpoint). The original breaks an equal
    distance with rand() & 1 (0x413862); this static opening takes the later cell, as the
    original's four LEVEL038 snapshots show (provisional), and skips the 0x40d800 rejection."""
    height, width = len(grid), len(grid[0])
    x0, y0 = cell
    best = {cell: 12}
    frontier = [(12, x0, y0, 0)]
    while frontier:
        frontier.sort(key=lambda row: -row[0])
        left, x, y, level = frontier.pop(0)
        if best.get((x, y), -1) > left:
            continue
        for dx, dy in ((0, -1), (-1, 0), (1, 0), (0, 1)):
            nx, ny = x + dx, y + dy
            if not (0 <= nx < width and 0 <= ny < height) or (nx, ny) == cell:
                continue
            target = grid[ny][nx]
            if int(target['t']) & 0x4000:
                continue
            new_level = 255 if target['b'] else int(target['h'])
            step = new_level - level
            if abs(step) >= 3:
                continue
            remaining = left - 1 - max(0, step)
            if remaining > 0 and remaining > best.get((nx, ny), 0):
                best[(nx, ny)] = remaining
                frontier.append((remaining, nx, ny, new_level))
    pick, distance = None, None
    for y in range(height):
        for x in range(width):
            if (x, y) == cell or (x, y) not in best or (x, y) in taken:
                continue
            d = abs(x - x0) + abs(y - y0)
            if distance is None or d <= distance:
                pick, distance = (x, y), d
    return pick


def nearest_free(grid: list, cell: tuple[int, int], taken: set, footprint_radius: int = 0) -> tuple[int, int]:
    """Nearest legal center whose complete actor footprint is free."""
    x0, y0 = cell
    for radius in range(1, max(len(grid), len(grid[0]))):
        for dy in range(-radius, radius + 1):
            for dx in range(-radius, radius + 1):
                if max(abs(dx), abs(dy)) != radius:
                    continue
                candidate = (x0 + dx, y0 + dy)
                footprint = _footprint_cells(candidate, footprint_radius)
                if all(0 <= y < len(grid) and 0 <= x < len(grid[0]) and not impassable(grid[y][x]) and (x, y) not in taken for x, y in footprint):
                    return candidate
    raise ValueError(f'no free footprint near {cell}')


PM_PLAYER = 0x10000
PM_ENEMY = 0x20000
# Object processes the actor constructor 0x407ec0 builds (defProcPlayerInstall records
# carry the registered slot in obj_Data9 and take the install path 0x4080b0 instead).
ACTOR_PROCESSES = ('defProcPlayer', 'defProcEnemy')


def object_row(actor_id: str, fields: dict) -> str:
    """The PLAYERS row the constructor copies for this object: its obj_Data7 (the unit's
    template, also when the preview draws it in another row's shape — level 30's
    Enemy053(克羅蒂) in SHAPE\009-*)."""
    return object_actor_code(fields.get('obj_Data7', '')) or actor_id


def install_word(actor_id: str, fields: dict, name: str) -> int:
    """One OBJ template install word as the loader 0x45dc5c stores it: a decimal or 0x-hex
    integer (obj_Data8 packs two ids as 0x08d708d8); 0 when the object does not declare it."""
    raw = str(fields.get(name, '0')).strip()
    try:
        return int(raw, 0) if raw.lower().startswith(('0x', '-0x')) else int(raw, 10)
    except ValueError:
        raise ValueError(f'{name} {raw!r} of actor {actor_id} is not an integer') from None


_RESOURCE_TEXTS: dict[str, str] = {}


def resource_texts() -> dict[str, str]:
    """RESOURCE.TXT id → text (the table the panel names, 稱號 and death lines resolve through)."""
    if not _RESOURCE_TEXTS:
        _RESOURCE_TEXTS.update(parse_table(RESOURCE_TEXT.read_bytes()))
    return _RESOURCE_TEXTS


def install_title_name(actor_id: str, fields: dict, players: dict) -> dict:
    """The panel 稱號 / name of an actor built from this object record (static-derived,
    0x407ec0 at 0x408004..0x408036): a non-zero obj_Data5 writes its low word to live +0x1c
    (稱號 id, the PLAYERS job_show_name slot) and its non-zero high word to live +0x04 (name
    id). The panel name is the installed record's +0x04 text verbatim (portraits.panel_name:
    a row left on 306 prints ???, as 0x434d10 does). Returns {} when the object leaves both
    words to the row."""
    word = install_word(actor_id, fields, 'obj_Data5')
    if word == 0:
        return {}
    word &= 0xffffffff
    title_id, name_id = word & 0xffff, word >> 16
    names = resource_texts()
    row = players[object_row(actor_id, fields)]
    result = {'display_name': panel_name(row, names, resource_defines(), name_id=str(name_id) if name_id else None),
              'name_source': f'obj_Data5 {fields["obj_Data5"]}: low word {title_id} → live +0x1c 稱號'
                             + (f', high word {name_id} → live +0x04 name' if name_id else '') + ' (0x407ec0)'}
    if title_id:
        result['title'] = names[str(title_id)]
    return result


def dead_message_ids(word: int) -> list[int]:
    """The message ids a live +0x14 word offers at death, as the death branches read it
    (static-derived, 0x43ef91 in 0x43ea30 and 0x4434b2 in 0x442a90): 0 → no line; first =
    high word, second = low word, a zero half copies the other; `0x458c10() & 1` then picks
    the second else the first. Returned in that order, one entry when both halves agree."""
    word &= 0xffffffff
    if word == 0:
        return []
    high, low = word >> 16, word & 0xffff
    first, second = high or low, low or high
    return [first] if first == second else [first, second]


def install_dead_message(actor_id: str, fields: dict, players: dict, title: str | None) -> dict:
    """The death line of an actor built from this object record (static-derived, 0x407ec0 at
    0x407fd0..0x407fe7): a non-zero obj_Data8 replaces the PLAYERS dead_message pair at live
    +0x14 verbatim, −1 writes 0 (the unit falls silently). The death branches read that word
    (dead_message_ids) and show the line as the unit's own dialogue (0x4072b0, the actMessage
    box) under its installed 稱號 — the combat_aftermath speaker rule over live +0x1c.
    actSetDeadMessage (STORY／WINFAIL opcode 60, handler 0x452197) writes the same word
    (msg1 << 16 | msg2), so a script line registered after install replaces the object's:
    script_dead_message applies the STORY opening's writes here, WinfailActions the WINFAIL
    ones at run time. Returns {} when the object leaves the row's pair."""
    raw = install_word(actor_id, fields, 'obj_Data8')
    if raw == 0:
        return {}
    ids = [] if raw == -1 else dead_message_ids(raw)
    names = resource_texts()
    row = players[object_row(actor_id, fields)]
    speaker = (title or names[speaker_id(row)]) if ids else ''
    source = f'obj_Data8 {fields["obj_Data8"]} → live +0x14 (0x407ec0)'
    source += '; −1 clears the PLAYERS dead_message pair' if raw == -1 else f'; death read 0x43ef91／0x4434b2 offers {ids} (0x458c10 & 1 picks between two)'
    return {'dead_message': {'speaker': speaker, 'messages': [{'id': str(message_id), 'text': names[str(message_id)]} for message_id in ids]},
            'dead_message_source': source}


def script_dead_message(unit: dict, row: str, msg1: int, msg2: int, players: dict, writer: str) -> dict:
    """The death line after a script actSetDeadMessage (STORY／WINFAIL opcode 60, jump table
    0x4537f4[60] → 0x452197; 0x44fad0(code, serial) finds the object): it writes live +0x14 =
    msg1 << 16 | msg2 verbatim — the last writer, over the constructor's obj_Data8 word and the
    PLAYERS pair alike (docs/evidence_packets/static_reverse/original_field_coverage.md §4). The
    death read (dead_message_ids) is unchanged; the speaker stays the installed 稱號 (live +0x1c),
    else the object row's speaker. `row` is the PLAYERS row the object was built from."""
    word = ((msg1 & 0xffff) << 16) | (msg2 & 0xffff)
    ids = dead_message_ids(word)
    names = resource_texts()
    speaker = (unit.get('title') or names[speaker_id(players[row])]) if ids else ''
    return {'dead_message': {'speaker': speaker, 'messages': [{'id': str(message_id), 'text': names[str(message_id)]} for message_id in ids]},
            'dead_message_source': f'{writer} → live +0x14 = {word:#x} (0x452197, after install: last writer wins); death read 0x43ef91／0x4434b2 offers {ids}'}


def script_title_name(unit: dict, row: str, name_id: int, title_id: int, players: dict, writer: str) -> dict:
    """The panel name / 稱號 after a script actSetPlayerName (STORY／WINFAIL opcode 89, jump table
    0x4537f4[89] → 0x451590, static-derived): 0x44fad0(code, serial) finds the object and the
    handler writes [name] to its live +0x04 and [job name] to +0x1c verbatim (0x4515d2／0x4515d9)
    — the same two words the constructor installs from obj_Data5, so the script line is the
    last writer. The panel name is the installed +0x04 text verbatim (portraits.panel_name)."""
    names = resource_texts()
    return {'display_name': panel_name(players[row], names, resource_defines(), name_id=str(name_id)),
            'title': names[str(title_id)],
            'name_source': f'{writer} → live +0x04 name {name_id}, +0x1c 稱號 {title_id} (0x451590, after install: last writer wins)'}


## The STORY opening's writers of the live actor words, in source order: (opcode, token, serial, args).
STORY_WORD_WRITERS = {'actSetDeadMessage': 4, 'actSetPlayerName': 4}


def story_word_writes(seed: dict) -> list[tuple[str, str, str, list[int]]]:
    """Every actSetDeadMessage／actSetPlayerName of the STORY opening in source order as
    (name, token, serial, [numbers]); the opening script is one unconditional section, so all
    of them execute before the first death (WinfailCompiler._story_dead_messages folds the
    same dead-message lines for the fail page)."""
    writes = []
    for section in seed['scripts']['story']['sections']:
        for action in section.get('actions', []):
            for command in action.get('chain', []):
                if command['name'] in STORY_WORD_WRITERS:
                    args = [str(value) for value in command['args']]
                    if len(args) < STORY_WORD_WRITERS[command['name']]:
                        raise ValueError(f'{command["name"]} needs code, serial and two words: {args}')
                    writes.append((command['name'], args[0], args[1], [int(value) for value in args[2:4]]))
    return writes


def apply_story_word_writes(level: int, seed: dict, roster: list[dict], bindings: dict, object_rows: dict[str, str], players: dict) -> None:
    """The STORY opening's actSetDeadMessage / actSetPlayerName lines execute after every
    constructor: the last writers of live +0x14 and +0x04／+0x1c, resolved through the same
    token/serial bindings as the opening walks, in source order (STORY029 names each 023 before
    giving it its farewell, so the farewell's speaker is the installed 稱號). A unit the opening
    deleted is skipped; an unbound token is an assembly error."""
    by_unit = {actor['id']: actor for actor in roster}
    for name, token, serial, words in story_word_writes(seed):
        binding = bindings.get(f'{token}/{serial}')
        if binding is None:
            raise ValueError(f'level {level}: STORY {name} names an unbound object {token}/{serial}')
        if binding['unit_id'] not in by_unit:
            continue
        unit = by_unit[binding['unit_id']]
        writer = f'STORY{level:03d} {name} {token},{serial},{words[0]},{words[1]}'
        if name == 'actSetDeadMessage':
            unit.update(script_dead_message(unit, object_rows[unit['id']], words[0], words[1], players, writer))
        else:
            unit.update(script_title_name(unit, object_rows[unit['id']], words[0], words[1], players, writer))


def install_player_mode(actor_id: str, fields: dict, players: dict, defines: dict) -> tuple[int, str]:
    """The live +0x28 player mode an actor built from this object record starts with
    (static-derived, actor constructor 0x407ec0 in
    docs/evidence_packets/static_reverse/original_field_coverage.md §4): the PLAYERS row's
    mode, swapped pmPlayer<->pmEnemy when the object's obj_Data9 is non-zero, then replaced
    verbatim by obj_X1 when the object declares it. Returns (mode, source note)."""
    row = object_row(actor_id, fields)
    token = players[row]['mode']
    mode = int(defines[token])
    note = f'PLAYERS {row} {token}' if row != actor_id else f'PLAYERS {token}'
    swap = str(fields.get('obj_Data9', '0'))
    if side_swapped(fields):
        if mode == PM_PLAYER:
            mode = PM_ENEMY
        elif mode == PM_ENEMY:
            mode = PM_PLAYER
        note += f', obj_Data9 {swap} swaps pmPlayer<->pmEnemy'
    override = str(fields.get('obj_X1', ''))
    if override:
        if override not in defines:
            raise ValueError(f'obj_X1 {override!r} of actor {actor_id} is not a TYPE.H player mode')
        mode = int(defines[override])
        note += f', obj_X1 {override} overrides'
    return mode, note + ' (0x407ec0)'


def side_swapped(fields: dict) -> bool:
    """The constructor's side-swap word (static-derived, 0x407ec0): a non-zero obj_Data9 swaps
    pmPlayer<->pmEnemy; only that swap sets live +0xa0 |= 8 (0x407fc3 — a PLAYERS mode other
    than pmPlayer／pmEnemy is left alone and the bit stays clear), the flag 0x446be0 reads to
    mirror the actor's close-up objects (x zoom −1, aniSetXYDisp x negated, hit move flag
    exchanged)."""
    swap = str(fields.get('obj_Data9', '0'))
    return swap.isdigit() and int(swap) != 0


def align_birth_hp(actor: dict, level: int) -> None:
    """Re-base the template max_hp／hp snapshot on the installed `player_mode`: the birth
    refresh 0x448840 runs after the constructor has applied obj_Data9／obj_X1 and counts the
    HP level term only when the live +0x28 carries pmPlayer (0x448851), while the template
    snapshot was refreshed at the PLAYERS row's mode. The difference is taken at the
    snapshot's own pre-birth `level` (the template row's declared level, else 1) so the
    template's other terms and the obj_HitPoint bonus stay as they are."""
    profile = actor['growth_profile']
    if profile.get('model') != 'native_job_stats_v1' or not (int(profile['source']['mode']) ^ int(actor['player_mode'])) & PM_PLAYER:
        return
    attrs = {key: int(actor['combat_profile'][key]) for key in ATTRIBUTES}
    gear = [int(slot['item_code']) for slot in actor.get('equipment', [])]
    items = equipment_data()['items']
    args = (profile, attrs, level, gear, items, 0, 0, int(actor.get('base_move_point', 0)))
    delta = calculate(*args, mode=int(actor['player_mode']))['max_hp'] - calculate(*args)['max_hp']
    full = int(actor['hp']) == int(actor['max_hp'])
    actor['max_hp'] = max(1, int(actor['max_hp']) + delta)
    actor['hp'] = actor['max_hp'] if full else min(int(actor['hp']), actor['max_hp'])


def _apply_object_install(actor: dict, actor_id: str, fields: dict, players: dict, defines: dict) -> None:
    """Write the constructor-applied object words onto an assembled unit: player_mode /
    player_mode_source, the obj_HitPoint word added to the growth source hit_point
    (+0x1b6, before the shared refresh) and to the template max_hp / hp snapshot, the
    obj_Data5 稱號 / name (title, display_name), the obj_Data8 death line (dead_message) and
    an additive obj_Mode display mode (draw_mode engADDCOLOR: the level-37 gems, level 80's
    怨念體 — resource-derived; the remake draws the sprite additively like the map glows) and
    side_swapped when obj_Data9 swapped pmPlayer／pmEnemy (0x407fc3 +0xa0 |= 8, read by
    0x446be0); the max_hp／hp snapshot follows the installed mode (align_birth_hp)."""
    actor['player_mode'], actor['player_mode_source'] = install_player_mode(actor_id, fields, players, defines)
    template_mode = int(defines[players[object_row(actor_id, fields)]['mode']])
    if side_swapped(fields) and template_mode in (PM_PLAYER, PM_ENEMY):
        actor['side_swapped'] = True
    if str(fields.get('obj_Mode', '')).startswith('engADDCOLOR'):
        actor['draw_mode'] = str(fields['obj_Mode'])
    bonus = install_word(actor_id, fields, 'obj_HitPoint')
    if bonus:
        actor['object_hit_point'] = bonus
        actor['growth_profile']['source']['hit_point'] = int(actor['growth_profile']['source']['hit_point']) + bonus
        actor['max_hp'] = int(actor['max_hp']) + bonus
        actor['hp'] = int(actor['hp']) + bonus
    if install_word(actor_id, fields, 'obj_Data7') & 0x80000000:
        # 0x42bdb0..0x42be0b: the first flagged object builds the live record, the rest take
        # its index — one record (HP pool) per row (docs/evidence_packets/static_reverse/
        # original_player_mode_sides.md).
        actor['shared_record'] = object_row(actor_id, fields)
    actor.update(install_title_name(actor_id, fields, players))
    actor.update(install_dead_message(actor_id, fields, players, actor.get('title')))
    align_birth_hp(actor, int(players[actor_id].get('level', 1)))


def _role(unit_id: str, mode: int, inserted: dict, overrides: dict, placed: dict | None = None) -> str:
    """An explicit profile override, else the placement: an EVEF player install (the story
    preview's story_actors role `player`) or an obj_Story_PlayerN insert is player_controlled;
    every other actor is AI — friendly_ai when its installed player mode carries the pmPlayer
    bit (pmPlayer / pmNPCPlayer / pmPlayerEnemy), enemy_ai otherwise (pmEnemy / pmNPC).
    Overrides are for the exceptions only (level 3's 漢克斯 fights as an enemy)."""
    if unit_id in overrides:
        return overrides[unit_id]
    if (placed or {}).get('role') == 'player':
        return 'player_controlled'
    if inserted.get(unit_id, {}).get('kind') == 'player_slot_install':
        return 'player_controlled'
    return 'friendly_ai' if mode & PM_PLAYER else 'enemy_ai'


def script_templates(level: int, seed: dict, source: dict[str, dict], preview: dict) -> dict:
    """Winfail inserts create PlayLoop units at runtime: one npc template per object
    symbol the winfail sections insert (obj_Story_PlayerN installs stay registered_player).
    An inserted actor goes through the same constructor as a placed one, so its object's
    install words set its player_mode / role and HP bonus (level 34's 023 arrive pmPlayer
    and are turned pmEnemy by WINFAIL034 event 4; level 24's 049/053/054 arrive pmNPC)."""
    players, _, defines = sources()
    symbols: list[str] = []
    installs: list[str] = []
    for section in seed['scripts']['winfail']['sections']:
        for action in section.get('actions', []):
            for command in action.get('chain', []):
                if command['name'] in INSERT_OBJECT and command['args'][0] not in symbols:
                    symbols.append(command['args'][0])
                if command['name'] == 'actInsertStoryObject' and command['args'][0].startswith('obj_Story_Player') and command['args'][0] not in installs:
                    installs.append(command['args'][0])
    objects = {o['symbol']: o for o in seed['script_objects']}
    # Story light/wall inserts are presentation objects, not PlayLoop actors. Only
    # object symbols with a resolved SID token can become script actor templates;
    # symbols without a joined row fall through to the special-level OBJ-ALL join below.
    symbols = [symbol for symbol in symbols
               if symbol not in objects or str(objects[symbol]['object_data_fields'].get('obj_Data6', '')).startswith('SID_')]
    result = {}
    for symbol in installs:
        slot = int(symbol[len('obj_Story_Player'):])
        actor_id, unit_id, token = PARTY_SLOTS[slot]
        if actor_id not in source:
            raise ValueError(f'level {level}: no reviewed template for registered slot {slot} (actor {actor_id})')
        actor = copy.deepcopy(source[actor_id])
        _apply_object_install(actor, actor_id, {}, players, defines)
        actor.update(id=unit_id, class_id='Player' + actor_id, battle_actor_role='player_controlled',
                     player_commandable=True, source_object_kind=3, coord=[0, 0])
        result[symbol] = {'kind': 'registered_player', 'actor': actor, 'token': token, 'aliases': [f'SID_PLAYER{slot - 1}'],
                          'source_actor_id': actor_id, 'evidence': 'docs/evidence_packets/static_reverse/original_player_install.md'}
    # A profile may declare that a scripted install is recorded as an explicit skip.
    # The PlayLoop keeps the raw template and ScriptActorCreationRules records
    # skipped_<reason> when the insert fires.
    for symbol, reason in LEVELS[level].get('template_insert_skips', {}).items():
        if symbol not in result:
            raise ValueError(f'level {level}: template_insert_skips names unknown install {symbol}')
        result[symbol]['insert_skip'] = reason
    for symbol in symbols:
        record = objects.get(symbol)
        if record is None:
            # Some special levels include OBJ-ALL.H before a chapter object header, so
            # the seed can retain a script symbol without a joined script_objects row.
            # Enemy template symbols carry the actor code explicitly; recover only this
            # narrow join rather than inventing placement or rule data.
            match = re.search(r'Enemy(\d+)$', symbol)
            if match is None:
                raise ValueError(f'level {level}: script object {symbol} has no joined definition')
            actor_id = match.group(1).zfill(3)
            record = {'object_data_fields': {'obj_Data6': f'SID_ENEMY{actor_id}', 'obj_Data7': actor_id}}
        token = str(record['object_data_fields'].get('obj_Data6', ''))
        actor_id = str(record['object_data_fields'].get('obj_Data7', '')).zfill(3)
        evidence = 'battle seed script_objects (OBJ header obj_Data6/obj_Data7, obj_Data9/obj_X1/obj_HitPoint install words) and the reviewed source actor template'
        actor = copy.deepcopy(source[actor_id])
        if 'object_name' in record:
            _apply_object_install(actor, actor_id, record['object_data_fields'], players, defines)
            role = 'friendly_ai' if actor['player_mode'] & PM_PLAYER else 'enemy_ai'
        else:
            # The narrow symbol-name join above has no object record: the install words are
            # unknown, so the unit keeps the enemy-process default side (provisional).
            actor['player_mode'] = PM_ENEMY
            actor['player_mode_source'] = 'no joined object definition for %s; enemy-process default pmEnemy (provisional)' % symbol
            align_birth_hp(actor, int(players[actor_id].get('level', 1)))
            role = 'enemy_ai'
        actor.update(id=f'level{level}_{symbol.rsplit("_", 1)[-1].lower()}', class_id='Enemy' + actor_id, battle_actor_role=role,
                     player_commandable=False, source_object_kind=5, coord=[0, 0])
        result[symbol] = {'kind': 'npc', 'actor': actor, 'token': token, 'aliases': [], 'source_actor_id': actor_id,
                          'evidence': evidence}
    return result


def treasure_path(level: int) -> Path:
    return ROOT / f'content/generated/hsl/treasures/battle_{level:03d}.json'


def treasures(level: int, seed: dict, preview: dict) -> dict:
    """hsl_battle_treasures.v1 for this level from the seed's EVEF chest records: the
    eight per-instance override words compacted to their non-zero item codes (the
    original copy at 0x42bd50 keeps that order; levels 1/2 stay on the native packet's
    content/generated/hsl/treasures/battles.json)."""
    items = equipment_data()['items']
    manifest = _load(ROOT / preview['resources']['map_objects'].removeprefix('res://'))
    width, height = seed['terrain']['grid_size']
    rows = []
    skipped = []
    exclusions = LEVELS[level].get('treasure_exclusions', {})
    for record in seed['placements']['records']:
        if record.get('object_process') != 'defProcTreasureBox':
            continue
        if 'treasure_words' not in record:
            raise ValueError(f'level {level}: seed chest record {record["record_index"]} lacks treasure_words (rebuild the seed)')
        drawn = next((p for p in manifest['placements'] if p['record_index'] == record['record_index']), None)
        if drawn is None or drawn.get('role') != 'treasure_box':
            raise ValueError(f'level {level}: chest record {record["record_index"]} has no drawn treasure_box placement')
        codes = [int(v) for v in record['treasure_words'] if v]
        unknown = [c for c in codes if str(c) not in items]
        if unknown:
            raise ValueError(f'level {level}: unknown chest item codes {unknown}')
        coord = [v // CELL for v in record['placement_xy_candidate']]
        if not (0 <= coord[0] < width and 0 <= coord[1] < height):
            reason = exclusions.get(str(record['record_index']))
            if reason is None:
                raise ValueError(f'level {level}: chest {record["record_index"]} lies outside the map')
            skipped.append(dict(record_index=record['record_index'], coord=coord, items=codes, reason=reason, status='skipped_out_of_bounds'))
            continue
        rows.append(dict(id=f'{level}:{record["record_index"]}', record_index=record['record_index'], coord=coord,
                         items=codes, shape_resource_id=drawn['shape_resource_id'], hidden=chest_hidden(record)))
    result = dict(schema='hsl_battle_treasures.v1', evidence_tier='resource-derived',
                levels={str(level): dict(level=level, level_sha256=seed['sources']['level']['sha256'],
                                         obs_sha256=seed['sources']['objects']['sha256'], chests=rows)},
                evidence='docs/evidence_packets/static_reverse/original_treasure.json',
                limits=['Contents are the eight original EVEF override words of each chest instance, compacted like the original copy; no drop tables.',
                        'hidden: the template obj_Attribute lacks objattrATTACKFLAG, so 0x415730 draws no box and contact plays sfxGetTreasure before collection.'])
    if skipped:
        result['skipped'] = skipped
    return result


def missing_portraits(level: int, seed: dict, preview: dict) -> list[str]:
    """Actors who speak in the winfail sections (played as battle cutscenes) but have no
    portrait in the level's manifest — content/battles/levels/NNN.json cast.speakers
    must list them, otherwise BattleDialogue asserts at runtime."""
    manifest = _load(ROOT / preview['resources']['portraits'].removeprefix('res://'))
    have = set(manifest.get('actors', {}).keys())
    by_token = {key.split('/')[0]: b['actor_id'] for key, b in preview['opening']['actor_bindings'].items() if 'actor_id' in b}
    speakers: list[str] = []
    for section in seed['scripts']['winfail']['sections']:
        for action in section.get('actions', []):
            for command in action.get('chain', []):
                if command['name'] not in ('actMessage', 'actMessageIfExist') or not command['args']:
                    continue
                token = command['args'][0]
                if not token.startswith('SID_'):
                    continue  # numeric speaker (narration row, e.g. WINFAIL012's 10000): no portrait
                actor_id = by_token.get(token) or PARTY_TOKENS.get(token) or (token[len('SID_ENEMY'):].zfill(3) if token.startswith('SID_ENEMY') else None)
                if actor_id is None:
                    raise ValueError(f'level {level}: winfail speaker {token} has no actor binding')
                if actor_id not in have and actor_id not in speakers:
                    speakers.append(actor_id)
    return speakers


def escape_zone_from_seed(seed: dict) -> list[list[int]]:
    """Derive inclusive grid cells from scripted player-arrival conditions."""
    cells: list[list[int]] = []
    for section in seed['scripts']['winfail']['sections']:
        for action in section.get('actions', []):
            for command in action.get('chain', []):
                name = command.get('name')
                args = command.get('args', [])
                if name == 'actCheckPlayerArrivePos' and len(args) >= 6:
                    x1, y1, x2, y2 = (int(args[index]) for index in range(2, 6))
                elif name == 'actCheckAnyPlayerArrivePos' and len(args) >= 4:
                    x1, y1, x2, y2 = (int(args[index]) for index in range(4))
                else:
                    continue
                for y in range(min(y1, y2), max(y1, y2) + CELL, CELL):
                    for x in range(min(x1, x2), max(x1, x2) + CELL, CELL):
                        cell = [x // CELL, y // CELL]
                        if cell not in cells:
                            cells.append(cell)
    return cells


def build(level: int) -> dict:
    profile = LEVELS[level]
    seed = _load(ROOT / f'content/generated/hsl/chapter01/battle{level:03d}_seed.json')
    preview_path = ROOT / f'content/battles/story_{level:03d}.json'
    preview = _load(preview_path)
    first = _load(FIRST)
    source = templates()
    players, _, defines = sources()
    missing = missing_portraits(level, seed, preview)
    if missing:
        raise ValueError(f'level {level}: winfail speakers without a portrait in the level manifest: {missing} (add them to the cast.speakers of content/battles/levels/{level:03d}.json)')
    trace = trace_opening(seed, preview)
    renames = unit_id_renames(profile, trace, preview)
    trace = _renamed_trace(trace, renames)
    state, traces, wait_rounds, deleted, inserted = trace['state'], trace['traces'], trace['wait_rounds'], trace['deleted'], trace['inserted']
    adjust_levels: dict[str, list[int]] = trace['adjust_levels']
    insert_order: dict[str, int] = trace['insert_order']
    readjusted: list[str] = trace['readjusted']
    conditional: dict[str, dict] = trace['conditional']
    by_id = {renames.get(a['id'], a['id']): a for a in preview['story_actors']}
    bindings = trace['bindings']
    actor_ids = {b['unit_id']: b['actor_id'] for b in bindings.values() if 'unit_id' in b and 'actor_id' in b}
    # obj_Story_PlayerN installs registered slot N-1: the unit is that slot's PLAYERS row
    # (static-derived, docs/evidence_packets/static_reverse/original_player_install.md), whatever
    # sprite the story preview draws for it (STORY053's preview shows the cinematic 029 for 緹娜).
    slot_actor_ids: dict[str, str] = {}
    for unit_id, insert in inserted.items():
        if insert.get('kind') == 'player_slot_install':
            slot = int(str(insert['symbol'])[len('obj_Story_Player'):])
            if slot not in PARTY_SLOTS:
                raise ValueError(f'level {level}: {insert["symbol"]} names an unknown party slot')
            slot_actor_ids[unit_id] = PARTY_SLOTS[slot][0]
    actor_ids.update(slot_actor_ids)
    overrides = terrain_overrides(level, seed)
    grid = apply_terrain_overrides(_load(ROOT / preview['resources']['terrain'].removeprefix('res://'))['grid'], overrides)
    roster = []
    object_rows: dict[str, str] = {}
    taken: set[tuple[int, int]] = set()
    escape_zone = escape_zone_from_seed(seed) if profile.get('derive_escape_zone', False) else []
    placement_fields = {record['record_index']: record.get('object_data_fields', {}) for record in seed['placements']['records']
                        if record.get('object_process') in ACTOR_PROCESSES}
    script_object_fields = {entry['symbol']: entry.get('object_data_fields', {}) for entry in seed['script_objects']
                            if entry.get('object_process') in ACTOR_PROCESSES}
    for unit_id, xy in state.items():
        if unit_id in deleted:
            continue
        actor_id = actor_ids.get(unit_id) or by_id[unit_id]['actor_id']
        # A preview that draws an EVEF enemy in another row's shape keeps its obj_Data7 as
        # source_actor_code (level 30's Enemy053(克羅蒂) wears SHAPE\009-*): the actor
        # constructor 0x407ec0 copies PLAYERS row obj_Data7, so the unit is that row's template;
        # its walk frames come from the row's own SHAPEDEF block (SID_ENEMY053 -> SHAPE\009-*).
        actor_id = str(by_id.get(unit_id, {}).get('source_actor_code') or actor_id)
        if actor_id not in source:
            raise ValueError(f'level {level}: no reviewed template for actor {actor_id} ({unit_id})')
        unaligned = any(v % CELL for v in xy)
        # The original's cell is the pixel >> 5 (0x411a30 takes (+4 >> 5, +8 >> 5)); an off-grid
        # STORY endpoint floors onto its cell (runtime-measured, opening_snapshot_diff cell:offgrid).
        cell_xy = [(v // CELL) * CELL for v in xy] if unaligned else xy
        placed = by_id.get(unit_id) or ({'record_index': conditional[unit_id]['evef_record_index'], 'placement_xy': conditional[unit_id]['placement_xy']} if unit_id in conditional else None)
        # The object record this unit is built from: its EVEF placement, else the STORY
        # insert symbol (the constructor reads the same template words either way).
        object_fields = placement_fields.get(placed['record_index'], {}) if placed and 'record_index' in placed else script_object_fields.get(inserted.get(unit_id, {}).get('symbol', ''), {})
        actor = copy.deepcopy(source[actor_id])
        _apply_object_install(actor, actor_id, object_fields, players, defines)
        object_rows[unit_id] = object_row(actor_id, object_fields)
        # A 有才產生 record is a defProcPlayerInstall of a registered slot: always the party's.
        role = 'player_controlled' if unit_id in conditional else _role(unit_id, actor['player_mode'], inserted, profile.get('role_overrides', {}), by_id.get(unit_id))
        if role == 'player_controlled' and not actor['player_mode'] & PM_PLAYER or role == 'enemy_ai' and actor['player_mode'] & PM_PLAYER:
            # A profile role override stands in for a scripted mode change (level 3's 漢克斯:
            # STORY003 actSetPlayerMode pmEnemy); the side follows the role it names. The
            # constructor's word stays as birth_player_mode: the birth refresh 0x448840 ran on
            # it (hp_level from +0x28 & 0x10000 at 0x448851) before 0x450710 rewrote +0x28,
            # which does not refresh (lane HANKS3 emulator trace: L7 50/50 at pmPlayer, kept).
            actor['birth_player_mode'] = actor['player_mode']
            actor['player_mode'] = PM_PLAYER if role == 'player_controlled' else PM_ENEMY
            actor['player_mode_source'] += f'; profile role_overrides {role}'
        actor.update(id=unit_id, class_id=('Player' if role == 'player_controlled' else 'Enemy') + actor_id,
                     battle_actor_role=role, player_commandable=role == 'player_controlled',
                     source_object_kind=3 if role == 'player_controlled' else 5,
                     coord=[v // CELL for v in cell_xy], position_evidence_tier='resource-derived',
                     position_source={'story_endpoint': xy, 'story_movements': traces.get(unit_id, []),
                                      **({'evef_record_index': placed['record_index'], 'placement_world': placed['placement_xy']} if placed else {}),
                                      **({'opening_insert': inserted[unit_id]} if unit_id in inserted else {})},
                     position_note='Source EVEF/STORY aligned endpoint; the opening still starts at the original EVEF or insert pixel.')
        if unit_id in conditional:
            actor['install_if_carried'] = True
            actor['install_source'] = ('EVEF 有才產生 (defProcPlayerInstall slot %d, obj_Data8 = 1, record %d): installed only when the party carries this member'
                                       % (conditional[unit_id]['slot'] - 1, conditional[unit_id]['evef_record_index']))
        instance = _actor_instance(seed, placed['record_index'] if placed else None)
        if instance:
            actor['evef_instance'] = instance
        if unit_id in adjust_levels:
            # The pre-baked insert keeps the token's +0x1f8 halves so InitialRosterGrowthRules
            # births it like a runtime insert (0,0 = no level adjustment: level 53's two
            # pursuers are L1, runtime-measured in battle_053/original_units.json).
            halves = adjust_levels[unit_id]
            actor['script_insert'] = {
                'adjust_level': list(halves),
                'source': f'STORY{level:03d} actSetPrevInsertObjectAdjustLevel,{halves[0]},{halves[1]} '
                          '(opcode 56 handler 0x450840 → 0x450ba4 writes the previous actInsertObject live +0x1f8 range／disp halves; 0/0 = no level adjustment at install)',
                'evidence_tier': 'resource-derived',
            }
        if unit_id in insert_order or unit_id in readjusted:
            # Birth order for the entry level adjustment (docs/evidence_packets/static_reverse/
            # original_auto_growth.md): an object adjusts on its first tick against the players
            # registered in 0x4c34c0 by then, EVEF objects on frame 1 (after the EVEF-installed
            # players), a STORY insert after the inserts before it; opcode 73 re-adjusts once.
            actor['opening_birth'] = {
                **({'story_insert': insert_order[unit_id]} if unit_id in insert_order else {}),
                **({'adjust_all_level': True} if unit_id in readjusted else {}),
                'source': (f'STORY{level:03d} opening: '
                           + (f'actor insert #{insert_order[unit_id]} in script order' if unit_id in insert_order else 'EVEF placement (frame 1)')
                           + ('; alive at actAdjustAllPlayerLevel (opcode 73 -> 0x4c1d48, one 0x40e870 re-adjust)' if unit_id in readjusted else '')),
                'evidence_tier': 'static-derived',
            }
        for state_key, state_value in profile.get('initial_unit_state', {}).get(unit_id, {}).items():
            if state_key == 'coord':
                # Start cells are the traced STORY endpoints read like every other level; a
                # profile does not pin them (levels 52's four rear 021 used to, R35 removed it).
                raise ValueError(f'level {level}: initial_unit_state.{unit_id}.coord is not a profile key; the start cell is the traced STORY endpoint')
            actor[state_key] = copy.deepcopy(state_value)
        if unaligned:
            actor['position_source']['unaligned_story_endpoint'] = xy
            actor['position_note'] = ('STORY endpoint %s is not on the 32 px grid; the unit starts on its cell %s '
                                      '(pixel >> 5 as the original 0x411a30).' % (xy, [v // CELL for v in cell_xy]))
        if unit_id in wait_rounds:
            # Live value comes from the opening timeline (ScriptWaitRules.initial_source); recorded here as provenance only.
            actor['position_source']['opening_wait_round'] = wait_rounds[unit_id]
        cell = (actor['coord'][0], actor['coord'][1])
        footprint_radius = int(profile.get('footprint_radius_overrides', {}).get(actor_id, 0))
        footprint = _footprint_cells(cell, footprint_radius)
        outside = any(not (0 <= y < len(grid) and 0 <= x < len(grid[0])) for x, y in footprint)
        on_blocked = not outside and any(impassable(grid[y][x]) for x, y in footprint)
        # The original installs without a terrain test: a unit with no STORY movement starts on
        # its install pixel (STORY037's gems sit on their pillars), a flying STORY walker on its
        # 0xff walk endpoint (the opening snapshot at the original's round-1 halt, runtime-measured).
        install_start = all(step['action'] in INSERT_OBJECT for step in traces.get(unit_id, []))
        # A large footprint keeps it too (13 關 051 ×4, 59 關 060, 80 關 068 at the original's round-1
        # halt); ActorTraversalRules.placement_error checks only occupancy for a standing actor.
        # A ground walker's endpoint goes through the original walk-destination fix 0x44fbd0;
        # a flying one keeps its 0xff endpoint (0xff only triggers it for ground, 0x44fc19).
        flying = bool(int(players[object_rows[unit_id]].get('move_fly', 0) or 0))
        landed = (script_landing(grid, cell, taken) if on_blocked and not install_start and not flying and not footprint_radius
                  and not any(point in taken for point in footprint) else None)
        if landed:
            actor['coord'] = [landed[0], landed[1]]
            footprint = _footprint_cells(landed, footprint_radius)
            actor['position_evidence_tier'] = 'static-derived'
            actor['position_source']['story_endpoint_landing_from'] = [cell[0], cell[1]]
            actor['position_note'] = SCRIPT_LANDING_NOTE
        elif on_blocked and not any(point in taken for point in footprint):
            if install_start:
                actor['position_source']['install_on_blocked_cell'] = True
                actor['position_note'] = INSTALL_ON_BLOCKED_NOTE
            else:
                moves = actor['position_source'].get('story_movements') or []
                start = tuple(v // CELL for v in moves[-1]['before']) if moves else cell
                stop = script_walk_stop(grid, start, cell, flying) if moves and not footprint_radius else cell
                if stop != cell and stop not in taken:
                    actor['coord'] = [stop[0], stop[1]]
                    footprint = _footprint_cells(stop, footprint_radius)
                    actor['position_evidence_tier'] = 'static-derived'
                    actor['position_source']['story_walk_stop_from'] = [cell[0], cell[1]]
                    actor['position_note'] = STORY_WALK_STOP_NOTE
                else:
                    actor['position_source']['story_endpoint_on_blocked_cell'] = True
                    actor['position_note'] = STORY_ENDPOINT_ON_BLOCKED_NOTE
        elif outside or on_blocked or any(point in taken for point in footprint):
            moved = nearest_free(grid, cell, taken, footprint_radius)
            actor['coord'] = [moved[0], moved[1]]
            footprint = _footprint_cells(moved, footprint_radius)
            actor['position_evidence_tier'] = 'provisional'
            actor['position_source']['blocked_source_cell'] = [cell[0], cell[1]]
            if footprint_radius:
                actor['position_note'] = ('Source placement %s is blocked or footprint-occupied in the remake terrain reading; the unit starts on the nearest '
                                          'free footprint %s (explicit remake placement, provisional until the original standing rule for that cell is located).' % (list(cell), list(moved)))
            else:
                actor['position_note'] = ('Source placement %s is a blocked cell in the remake terrain reading; the unit starts on the nearest '
                                          'free cell %s (explicit remake placement, provisional until the original standing rule for that cell is located).' % (list(cell), list(moved)))
        taken.update(_footprint_cells((actor['coord'][0], actor['coord'][1]), footprint_radius))
        roster.append(actor)
    apply_story_word_writes(level, seed, roster, bindings, object_rows, players)
    opening = copy.deepcopy(preview['opening'])
    for key in ['mode', 'end_event_id', 'end_behavior', 'end_card', 'preview_of_battle_level', 'end_exit', 'next_level_event', 'skip_battle', 'end_routes']:
        opening.pop(key, None)
    opening.update(first_control_event_id='first_control_ready', initial_focus_unit_id=profile['initial_focus_unit_id'])
    for binding in opening['actor_bindings'].values():
        binding.pop('coord', None)
        if 'unit_id' in binding:
            binding['unit_id'] = renames.get(str(binding['unit_id']), str(binding['unit_id']))
            if binding['unit_id'] in slot_actor_ids:
                binding['actor_id'] = slot_actor_ids[binding['unit_id']]
    for key, binding in bindings.items():
        if 'object_id' in binding:  # an id the STORY gave an object (actChangePrevInsertObjectID／actChangePlayerID)
            opening['actor_bindings'][key] = copy.deepcopy(binding)
            opening['actor_bindings'][key]['unit_id'] = renames.get(str(binding['unit_id']), str(binding['unit_id']))
    for spec in opening.get('story_objects', {}).values():
        if 'spawns_unit_id' in spec:
            spec['spawns_unit_id'] = renames.get(str(spec['spawns_unit_id']), str(spec['spawns_unit_id']))
            if spec['spawns_unit_id'] in slot_actor_ids:
                spec['actor_id'] = slot_actor_ids[spec['spawns_unit_id']]
    if profile['initial_focus_unit_id'] not in state or profile['initial_focus_unit_id'] in deleted:
        raise ValueError(f'level {level}: initial_focus_unit_id {profile["initial_focus_unit_id"]!r} is not a fielded unit')
    # Opening-only cast: EVEF actors the STORY deletes before first control (STORY053's
    # cinematic 緹娜) stand beside the roster for the opening and never join the grid
    # (OpeningStoryObjects._spawn_story_actors skips entries that are PlayLoop units).
    story_actors = [copy.deepcopy(actor) for actor in preview['story_actors'] if renames.get(actor['id'], actor['id']) in deleted]
    for actor in story_actors:
        actor['id'] = renames.get(actor['id'], actor['id'])
        actor['battle_unit'] = False
    fielded_conditional = [a['id'] for a in roster if a.get('install_if_carried')]
    for unit_id in fielded_conditional:
        # The opening walks / lines and the winfail tokens of the conditional member
        # resolve through the same binding table as the rest of the cast; when the
        # carry does not hold the member the bound unit is absent and the coordinator
        # records the token as unbound_actor.
        opening['actor_bindings'][f"{conditional[unit_id]['token']}/1"] = copy.deepcopy(bindings[f"{conditional[unit_id]['token']}/1"])
    resources = copy.deepcopy(preview['resources'])
    for key in ['attack_ranges', 'progression', 'consumables', 'combat_animation', 'interface_audio', 'fire_animation']:
        resources[key] = first['resources'].get(key, SHARED_RESOURCES[key])
    resources['battle_seed'] = f'res://content/generated/hsl/chapter01/battle{level:03d}_seed.json'
    if profile.get('treasures', True):
        resources['treasures'] = 'res://' + treasure_path(level).relative_to(ROOT).as_posix()
    evidence = _load(ROOT / resources['message_text_evidence'].removeprefix('res://'))
    timelines = status_timelines(level, seed, evidence)
    # Winfail inserts are script actor templates (ScriptActorCreationRules births them at
    # the insert point and walks them to the actWalkPrevInsertObject target); as in
    # gol_road_battle.json, the coordinator renders the interpreter's already committed
    # creations in source action order and never installs a second actor.
    for program in timelines.values():
        for event in program['events']:
            if event.get('script_action_name') in ['actInsertObject', 'actWalkPrevInsertObject', 'actWalkPrevInsertObjectWait']:
                event.pop('cutscene_skip', None)
        program['playable_event_count'] = sum(not e.get('cutscene_skip', False) for e in program['events'])
    script_actor_templates = script_templates(level, seed, source, preview)
    result = dict(schema='hsl_level_battle.v1', id=profile['id'], level=level, level_kind='battle', title=profile['title'],
                  status='product-opening-source-adapted', rule_adapter='winfail',
                  player_unit_id=profile['initial_focus_unit_id'], resources=resources,
                  # What loading this level's battle record plays (original_music.md §3.1).
                  level_table_music=level_table_music(level),
                  view=copy.deepcopy(preview['view']), commands=copy.deepcopy(first['commands']),
                  # No skill_rules: each actor starts at its PLAYERS template stamina, a carried
                  # player at 0 (ActorInitializationRules／CampaignCarryRules, original_stamina.md).
                  opening=opening, playable_units=roster,
                  **({'terrain_overrides': overrides} if overrides else {}),
                  **({'story_actors': story_actors} if story_actors else {}),
                  script_actor_templates=script_actor_templates,
                  **({'conditional_party': {
                      'policy': 'install_if_carried',
                      'evidence_tier': 'static-derived',
                      'basis': 'EVEF 有才產生 records (defProcPlayerInstall, obj_Data8 = 1, obj_Data9 = slot) reach the constructor only for an existing, enabled registered slot and take the placeholder-deletion path otherwise (docs/evidence_packets/static_reverse/original_player_install.md, 0x4080b0 / OBJ-012 codes 180-188); the remake fields those members only when the campaign carry holds them and applies their STORY opening walks like the rest of the cast',
                      'claim_limit': 'the carry stands in for the registered-and-enabled slot table: a registered-but-disabled member is not modelled; a launch without a campaign hand-off fields every slot (dev / test)',
                      'slots': fielded_conditional,
                      'unavailable_slots': [],
                      'records': [{'unit_id': unit_id, **conditional[unit_id]} for unit_id in fielded_conditional],
                  }} if fielded_conditional else {}),
                  result_labels=profile['result_labels'],
                  # EVEF actors the story scene spec leaves out on purpose (with the reason) are recorded, not fielded.
                  **({'excluded_source_actors': copy.deepcopy(preview['excluded_source_actors'])} if preview.get('excluded_source_actors') else {}),
                  scenario_rules={'initial_objective_phase': profile['initial_objective_phase'], 'allow_optional_clear_after_switch': False,
                                  'events': {}, 'reinforcements': [], 'reinforcement_spawn_cells': [],
                                  'script_fallback': {'escape_zone': escape_zone}, 'status_timelines': timelines,
                                  **({'initial_status_overrides': copy.deepcopy(profile['initial_status_overrides'])}
                                     if profile.get('initial_status_overrides') else {}),
                                  **({'job_up_targets': copy.deepcopy(profile['job_up_targets']),
                                      'job_up_templates': {target_id: copy.deepcopy(source[target_id]) for target_id in profile['job_up_targets'].values()}}
                                     if profile.get('job_up_targets') else {})},
                  provenance={'seed_sha256': digest((ROOT / f'content/generated/hsl/chapter01/battle{level:03d}_seed.json').read_bytes()),
                              'preview_sha256': digest(preview_path.read_bytes()),
                              'assembly': f'python3 tools/hsl.py generate level_battle:{level} (tools/hsltools/levels/battle.py build): preview opening/bindings/resources, seed STORY endpoints and winfail, reviewed source templates; roles from obj_Story_PlayerN installs and the installed player mode (PLAYERS mode, obj_Data9 swap, obj_X1 override); obj_HitPoint added to the growth source hit_point.'},
                  unresolved_semantics=[
                      *profile.get('unresolved_semantics', []),
                      *([f"STORY movements of uninstalled conditional party members are skipped: {sorted({s['args'][0] for s in trace['skipped']})}"] if trace['skipped'] else []),
                      'Original per-object registration and growth callees are independently proven; the complete original scheduler, global RNG and wall clock are not.',
                      'Source scripted cells occupied or blocked in live play use a recorded nearest legal landing; this is an explicit remake placement policy.',
                      'Treasure contents come from original EVEF instances; action-tail collection and deferred reward persistence are explicit remake integration choices.',
                  ])
    seen = set()
    for actor in roster:
        x, y = actor['coord']
        on_blocked = 0 <= y < len(grid) and 0 <= x < len(grid[0]) and impassable(grid[y][x])
        kept_on_blocked = actor['position_source'].get('install_on_blocked_cell') or actor['position_source'].get('story_endpoint_on_blocked_cell')
        if not (0 <= y < len(grid) and 0 <= x < len(grid[0])) or on_blocked and not kept_on_blocked or (x, y) in seen:
            raise ValueError(f'level {level}: invalid endpoint for {actor["id"]}: {actor["coord"]}')
        seen.add((x, y))
    # A profile may pin the roster size it expects (a guard against seed / preview drift).
    expected = profile.get('expected')
    if expected and (len(roster) != expected['units'] or sum(a['player_commandable'] for a in roster) != expected['players']):
        raise ValueError(f'level {level}: roster {len(roster)} units / {sum(a["player_commandable"] for a in roster)} players differs from the profile')
    if not script_actor_templates:
        result.pop('script_actor_templates')
    return result


def _base_scenario(base_level: int) -> dict:
    """The registered scenario of the encounter's base level (its formal battle or story
    preview) supplies the view contract, which is per map."""
    campaign = _load(ROOT / 'content/battles/campaign.json')
    entry = campaign['battles'].get(str(base_level))
    if entry is None:
        raise ValueError(f'base level {base_level} is not registered in campaign.json')
    return _load(ROOT / str(entry['scenario']).removeprefix('res://'))


def build_encounter(level: int) -> dict:
    profile = ENCOUNTERS[level]
    seed_path = ROOT / f'content/generated/hsl/chapter01/battle{level:03d}_seed.json'
    seed = _load(seed_path)
    base_level = seed['map']['alias_of_level']
    if base_level is None:
        raise ValueError(f'encounter {level}: the seed names no base level map')
    base = _base_scenario(int(base_level))
    first = _load(FIRST)
    source = templates()
    players, _, defines = sources()
    grid = _load(ROOT / str(seed['terrain']['packet']).removeprefix('res://'))['grid']
    roster = []
    object_rows: dict[str, str] = {}
    unavailable = []
    # Fielded registered slots bound to their EXTRAS.H token (SID_雷歐納德 = slot 0 …),
    # the same reading trace_opening gives the main-line 有才產生 installs. Without
    # these the WINFAIL5NN fail section `actCheckPlayer 1 SID_雷歐納德` names a token
    # WinfailScenarioRules cannot resolve and the encounter can never be lost.
    bindings: dict[str, dict] = {}
    taken: set[tuple[int, int]] = set()
    counters: dict[str, int] = {}
    for record in seed['placements']['records']:
        role = record.get('role_from_process')
        if role not in ('player_install', 'enemy_object'):
            continue
        xy = record['placement_xy_candidate']
        if role == 'player_install':
            slot = int(record['object_data_fields']['obj_Data9']) + 1
            actor_id, unit_id, token = PARTY_SLOTS[slot]
            if actor_id not in ENCOUNTER_PARTY_SLOTS:
                reason = 'no reviewed source template / shared portrait yet'
                unavailable.append({'slot': slot, 'actor_id': actor_id, 'unit_id': unit_id, 'token': token,
                                    'evef_record_index': record['record_index'], 'placement_xy': xy,
                                    'reason': reason})
                continue
            battle_role = 'player_controlled'
        else:
            actor_id = str(record['object_data_fields']['obj_Data7']).zfill(3)
            counters[actor_id] = counters.get(actor_id, 0) + 1
            unit_id = f'actor{actor_id}_{counters[actor_id]}'
            battle_role = ''
        if actor_id not in source:
            raise ValueError(f'encounter {level}: no reviewed template for actor {actor_id} ({record["object_name"]})')
        if any(v % CELL for v in xy):
            raise ValueError(f'encounter {level}: EVEF placement of {unit_id} is not on the 32 px grid: {xy}')
        actor = copy.deepcopy(source[actor_id])
        object_fields = record['object_data_fields'] if role == 'enemy_object' else {}
        _apply_object_install(actor, actor_id, object_fields, players, defines)
        object_rows[unit_id] = object_row(actor_id, object_fields)
        if not battle_role:
            battle_role = 'friendly_ai' if actor['player_mode'] & PM_PLAYER else 'enemy_ai'
        actor.update(id=unit_id, class_id=('Player' if battle_role == 'player_controlled' else 'Enemy') + actor_id,
                     battle_actor_role=battle_role, player_commandable=battle_role == 'player_controlled',
                     source_object_kind=3 if battle_role == 'player_controlled' else 5,
                     coord=[v // CELL for v in xy], position_evidence_tier='resource-derived',
                     position_source={'evef_record_index': record['record_index'], 'placement_world': xy, 'object_name': record['object_name']},
                     position_note='Source EVEF placement (no STORY movement in encounter openings).')
        instance = _actor_instance(seed, record['record_index'])
        if instance:
            actor['evef_instance'] = instance
        if battle_role == 'player_controlled':
            actor['install_if_carried'] = True
            actor['install_source'] = 'EVEF 有才產生 (defProcPlayerInstall slot %d): installed only when the party carries this member (provisional reading of the conditional install)' % (slot - 1)
            if f'{token}/1' in bindings:
                raise ValueError(f'encounter {level}: registered slot {slot - 1} ({token}) is installed twice in the EVEF')
            bindings[f'{token}/1'] = {'unit_id': unit_id, 'actor_id': actor_id, 'placement_xy': list(xy)}
        cell = (actor['coord'][0], actor['coord'][1])
        if impassable(grid[cell[1]][cell[0]]):
            actor['position_source']['install_on_blocked_cell'] = True
            actor['position_note'] = INSTALL_ON_BLOCKED_NOTE
        if cell in taken:
            raise ValueError(f'encounter {level}: two EVEF actors share the cell {list(cell)}')
        taken.add((actor['coord'][0], actor['coord'][1]))
        roster.append(actor)
    if not any(a['id'] == 'leonard' for a in roster):
        raise ValueError(f'encounter {level}: 雷歐納德 (slot 0) must be installable')
    apply_story_word_writes(level, seed, roster, bindings, object_rows, players)
    folder = f'res://content/imported/hsl/chapter01/battle{level}'
    resources = {
        'map_texture': seed['map']['decoded_png'],
        'terrain': seed['terrain']['packet'],
        'actor_walk_manifest': ENCOUNTER_POOL + '/actor_walk_frames/actor_walk_manifest.json',
        'actor_audio': ENCOUNTER_POOL + '/actor_audio.json',
        'portraits': ENCOUNTER_POOL + '/portraits/manifest.json',
        'opening_timeline': folder + '/opening_timeline.json',
        'message_text_evidence': folder + '/message_text_evidence.json',
        'map_objects': folder + '/map_objects.json',
        'map_object_alignment': folder + '/map_object_alignment.json',
    }
    for key in ['attack_ranges', 'progression', 'consumables', 'combat_animation', 'interface_audio', 'fire_animation']:
        resources[key] = first['resources'].get(key, SHARED_RESOURCES[key])
    resources['battle_seed'] = 'res://' + seed_path.relative_to(ROOT).as_posix()
    for key in ('map_texture', 'terrain', 'opening_timeline', 'message_text_evidence', 'map_objects'):
        if not (ROOT / str(resources[key]).removeprefix('res://')).exists():
            raise ValueError(f'encounter {level}: missing resource {key}: {resources[key]}')
    evidence = _load(ROOT / resources['message_text_evidence'].removeprefix('res://'))
    timelines = status_timelines(level, seed, evidence)
    for program in timelines.values():
        program['playable_event_count'] = sum(not e.get('cutscene_skip', False) for e in program['events'])
    timeline = _load(ROOT / resources['opening_timeline'].removeprefix('res://'))
    opening = {
        'source_script': f'story{level}', 'status': 'coordinator_driven_remake_pacing',
        # Only 雷歐納德 speaks (dead message 741 / fail line 122): EXTRAS.H slot 0 = resource 0.
        'actor_bindings': bindings, 'speaker_resource_ids': {'SID_雷歐納德': '0'},
        'story_objects': {}, 'first_control_event_id': timeline['events'][-1]['id'], 'initial_focus_unit_id': 'leonard',
        'claim_limit': 'Encounter openings have no walks or dialogue: actPlayDefaultLevelMusic (the table track of the base level), a delay and the dead-message registration run before first control.',
    }
    return dict(schema='hsl_level_battle.v1', id=f'encounter_{level}', level=level, level_kind='battle', title=profile['title'],
                status='product-opening-source-adapted', rule_adapter='winfail', player_unit_id='leonard', resources=resources,
                # Levels >= 100 have no table track: loading a 5NN battle record stays silent (original_music.md §3.1).
                level_table_music=level_table_music(level),
                view=copy.deepcopy(base['view']), commands=copy.deepcopy(first['commands']),
                # No script_actor_templates key: encounters insert nothing (PlayLoop rejects an empty table).
                opening=opening, playable_units=roster,
                conditional_party={
                    'policy': 'install_if_carried',
                    'evidence_tier': 'static-derived',
                    'basis': 'every 5NN EVEF installs the nine registered slots as 有才產生 (defProcPlayerInstall, obj_Data8 = 1, obj_Data9 = slot); the original lets only an existing, enabled registered slot reach the constructor and deletes the placeholder otherwise (docs/evidence_packets/static_reverse/original_player_install.md, 0x4080b0 / OBJ-012 codes 180-188), so the remake fields only the members the campaign carry holds',
                    'claim_limit': 'the carry stands in for the registered-and-enabled slot table: a registered-but-disabled member is not modelled, and slots without a reviewed template / shared portrait are refused explicitly (unavailable_slots)',
                    'slots': [a['id'] for a in roster if a.get('install_if_carried')],
                    'unavailable_slots': unavailable,
                },
                result_labels={'win_0': profile['title'].split(' · ')[0] + ' · 敵軍已清除', 'fail_0': '雷歐納德 陣亡'},
                scenario_rules={'initial_objective_phase': 'clear', 'allow_optional_clear_after_switch': False,
                                'events': {}, 'reinforcements': [], 'reinforcement_spawn_cells': [],
                                'script_fallback': {'escape_zone': []}, 'status_timelines': timelines},
                provenance={'seed_sha256': digest(seed_path.read_bytes()), 'base_level': int(base_level), 'base_scenario': str(base.get('id', '')),
                            'assembly': f'python3 tools/hsl.py generate level_battle:{level} (tools/hsltools/levels/battle.py build_encounter): seed EVEF placements (player installs by obj_Data9 slot, monsters by obj_Data7), seed winfail, base level map / terrain / view, shared encounter actor pool.'},
                unresolved_semantics=[
                    'The conditional install (有才產生) is read as "field the member when the party carries it"; the original defProcPlayerInstall branch is not located (provisional).',
                    *([f"Slots without a reviewed template or shared portrait are not fielded yet: {sorted({u['actor_id'] for u in unavailable})}; a party carrying one of them cannot enter this encounter (explicit card)."] if unavailable else []),
                    'Encounter difficulty scaling (actAdjustAllPlayerLevel is absent from 5NN scripts) and reward gold follow the reviewed templates, not a located encounter rule.',
                    'Original per-object registration and growth callees are independently proven; the complete original scheduler, global RNG and wall clock are not.',
                ])


def output_path(level: int) -> Path:
    return ROOT / f'content/battles/battle_{level:03d}.json'


SHARED_UP_TITLE_WALK = ROOT / 'content/imported/hsl/shared/actor_walk_frames/actor_walk_manifest.json'
SHARED_JOB_UP_AUDIO = ROOT / 'content/imported/hsl/shared/actor_audio.json'
AFTERMATH = ROOT / 'content/generated/hsl/combat/aftermath.json'


def placed_actor_ids(document: dict) -> set[str]:
    """Every PLAYERS row the assembled scenario can field as a PlayLoop unit: the opening
    roster (conditional party members included) and the script-inserted templates."""
    ids = {str(unit['actor_id']) for unit in document['playable_units']}
    ids |= {str(spec['actor']['actor_id']) for spec in document.get('script_actor_templates', {}).values() if 'actor' in spec}
    return ids


def cast_gaps(level: int, document: dict) -> list[str]:
    """Presentation cast contract of one assembled scenario: every fieldable actor has walk
    frames in the level's manifest (or the shared up-title manifest, e.g. the 052 guardian),
    every fieldable actor whose PLAYERS row declares a walk sound has it bound in the level's
    audio manifest (or the shared job-up audio manifest beside those frames — ActorSpriteKey.
    audio_binding reads the same two), and every fieldable actor with a source death line
    (aftermath.json `messages`) has its portrait in the level's portrait manifest — otherwise the
    runtime would draw the single-frame fallback / walk silently / report a missing death-line
    face. Fix by adding the row to cast.actors of content/battles/levels/NNN.json (speakers
    derive automatically)."""
    from hsltools.levels.actors import _players
    resources = document['resources']
    walk = _load(ROOT / str(resources['actor_walk_manifest']).removeprefix('res://'))
    shared_walk = _load(SHARED_UP_TITLE_WALK)
    audio = _load(ROOT / str(resources['actor_audio']).removeprefix('res://'))['characters']
    shared_audio = _load(SHARED_JOB_UP_AUDIO)['characters']
    players = _players()
    portraits = _load(ROOT / str(resources['portraits']).removeprefix('res://'))
    death_lines = {code for code, actor in _load(AFTERMATH)['actors'].items() if actor['messages']}
    gaps = []
    for actor_id in sorted(placed_actor_ids(document)):
        if actor_id not in walk['actors'] and actor_id not in shared_walk['actors']:
            gaps.append(f'{actor_id}: no walk frames in {resources["actor_walk_manifest"]}')
        code = str(int(actor_id))
        if players.get(int(actor_id), {}).get('sound_walk') and not any('walk' in table.get(code, {}) for table in (audio, shared_audio)):
            gaps.append(f'{actor_id}: PLAYERS walk sound without a binding in {resources["actor_audio"]}')
        if actor_id in death_lines and actor_id not in portraits['actors']:
            gaps.append(f'{actor_id}: death-line speaker without a portrait in {resources["portraits"]}')
    return gaps


def render_level(level: int) -> dict[str, dict]:
    """{repository-relative output path: document} for one registered level."""
    result = build_encounter(level) if level in ENCOUNTERS else build(level)
    gaps = cast_gaps(level, result)
    if gaps:
        raise ValueError(f'level {level}: fieldable actors outside the level cast (add to cast.actors of content/battles/levels/{level:03d}.json): ' + '; '.join(gaps))
    if level in ENCOUNTERS:
        return {output_path(level).relative_to(ROOT).as_posix(): result}
    outputs = {output_path(level).relative_to(ROOT).as_posix(): result}
    if LEVELS[level].get('treasures', True):
        seed = _load(ROOT / f'content/generated/hsl/chapter01/battle{level:03d}_seed.json')
        preview = _load(ROOT / f'content/battles/story_{level:03d}.json')
        outputs[treasure_path(level).relative_to(ROOT).as_posix()] = treasures(level, seed, preview)
    return outputs


def summary_line(level: int, documents: dict[str, dict], tag: str) -> str:
    result = documents[output_path(level).relative_to(ROOT).as_posix()]
    units = result['playable_units']
    treasure_key = treasure_path(level).relative_to(ROOT).as_posix()
    if treasure_key in documents:
        tail = f'chests={sum(len(v["chests"]) for v in documents[treasure_key]["levels"].values())}'
    elif level in ENCOUNTERS:
        tail = f'conditional_slots={len(result["conditional_party"]["slots"])} unavailable={len(result["conditional_party"]["unavailable_slots"])}'
    else:
        tail = 'no_treasure_source'
    return (f'{tag} level={level} units={len(units)} players={sum(u["player_commandable"] for u in units)} '
            f'templates={len(result.get("script_actor_templates", {}))} statuses={len(result["scenario_rules"]["status_timelines"])} ' + tail)


def encode(document: dict) -> bytes:
    return (json.dumps(document, ensure_ascii=False, indent=2) + '\n').encode('utf-8')


def unit_schema_errors(document: dict, schema: dict) -> list[str]:
    """Every playable unit and script actor template of one rendered scenario against the
    tracked unit schema (content/schema/unit.schema.json); [] when all pass."""
    errors = []
    for index, unit in enumerate(document.get('playable_units', [])):
        found = unit_schema.unit_error(unit, schema, f'playable_units[{index}]')
        if found:
            errors.append(found)
    for symbol, spec in document.get('script_actor_templates', {}).items():
        found = unit_schema.unit_error(spec['actor'], schema, f'script_actor_templates.{symbol}.actor')
        if found:
            errors.append(found)
    return errors


class LevelBattleTask(GeneratedFilesTask):
    family = 'level_battle'
    replaces_command = 'tools/hsl_level_battle.py --level {level} --check'

    def __init__(self, level: int) -> None:
        self.level = level
        self.name = f'level_battle:{level}'
        tag = f'{level:03d}'
        self.outputs = tuple(sorted({output_path(level).relative_to(ROOT).as_posix()}
                                    | ({treasure_path(level).relative_to(ROOT).as_posix()} if level in LEVELS and LEVELS[level].get('treasures', True) else set())))
        # Encounters (ENCOUNTERS, 5NN) assemble from the seed alone: they have no story preview.
        story = () if level in ENCOUNTERS else (f'content/battles/story_{tag}.json',)
        self.inputs = (f'content/generated/hsl/chapter01/battle{tag}_seed.json', *story, *level_profile.input_path(level),
                       f'content/imported/hsl/chapter01/battle{tag}/', 'content/battles/first_battle.json', unit_schema.SCHEMA_PATH,
                       'content/battles/campaign.json', 'content/generated/hsl/actors/', 'content/imported/hsl/global/tables/',
                       'content/authored/roles/job_formulas.json',
                       'content/imported/hsl/global/world_map/world_map.json', 'content/imported/hsl/story_corpus/scripts/',
                       SHARED_UP_TITLE_WALK.relative_to(ROOT).as_posix(), SHARED_JOB_UP_AUDIO.relative_to(ROOT).as_posix(), AFTERMATH.relative_to(ROOT).as_posix(),
                       *(('content/imported/hsl/chapter01/battle500/',) if level in ENCOUNTERS else ()))
        self.replaces = (self.replaces_command.format(level=level),)
        self.scripts = ('tools/hsltools/levels/battle.py', 'tools/hsltools/levels/scenario.py', 'tools/hsltools/data/treasures.py', 'tools/hsltools/model/jobs.py')

    def render(self, ctx: Context) -> dict[str, bytes]:
        _check_encounter_titles()
        documents = render_level(self.level)
        schema = unit_schema.load(ctx.root)
        errors = unit_schema_errors(documents[output_path(self.level).relative_to(ROOT).as_posix()], schema)
        if errors:
            raise CheckFailed(f'{self.name}: unit schema violation(s): ' + '; '.join(errors[:5]))
        return {path: encode(document) for path, document in documents.items()}

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        documents = {path: json.loads(data) for path, data in rendered.items()}
        return summary_line(self.level, documents, 'LEVEL_BATTLE_CHECK_PASS' if mode == 'check' else 'LEVEL_BATTLE_BUILD_PASS')


def registered_levels() -> list[int]:
    """Every content/battles/battle_NNN.json the assembler knows a profile for (authored
    levels are assembled by hsltools.levels.authored from content/authored/levelNNN/)."""
    tracked = assembled_battle_levels()
    unknown = [level for level in tracked if level not in LEVELS and level not in ENCOUNTERS]
    if unknown:
        raise ValueError(f'tracked battle scenarios without a `battle` section in content/battles/levels/NNN.json: {unknown}')
    return tracked


def tasks() -> list[LevelBattleTask]:
    return [LevelBattleTask(level) for level in registered_levels()]
