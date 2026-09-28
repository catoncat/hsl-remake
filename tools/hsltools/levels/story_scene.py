"""Generate a story-only scene scenario (no PlayLoop battle) from a tracked level seed (story_scene:N).

The scene lists its cast from EVEF placements (token/instance bindings follow record
order, as in the second battle), points at the level's compiled STORY timeline,
dialogue evidence, per-level actor manifests, sounds and script objects, and
declares the campaign follow-up token. What differs per level (id, title, player
installs / slot inserts, token overrides, end card / exit, per-level unresolved sentences)
is the `story_scene` section of content/battles/levels/NNN.json (hsltools.levels.profile,
docs/architecture/LEVEL_PROFILES.md); battle levels register an opening preview that stops
at first control. Registry task (tools/hsl.py check|generate story_scene:N): the task regenerates the scene and compares
the tracked content/battles/story_NNN.json byte for byte.
"""
from __future__ import annotations

import functools
import json
from pathlib import Path

from hsltools.levels import actor_chain_levels, encode_json, legacy_failures, profile
from hsltools.levels.message_text import SPEAKER_IDS
from hsltools.levels.timeline import _event_from_action, canonical_action_name, level_table_music, movie_name_for_code
from hsltools.sources.actor_walk_frames import is_walking_shape, object_actor_code, standing_actor_code
from hsltools.paths import ROOT
from hsltools.registry import Context, GeneratedFilesTask

SCHEMA = 'hsl_story_scene.v1'
# The per-level scene spec (content/battles/levels/NNN.json `story_scene`).
LEVELS: dict[int, dict] = profile.section('story_scene')

LEVEL_SYMBOLS = {'gameBigMapLevel': 49}



def seed_path(level: int) -> Path:
    return ROOT / f'content/generated/hsl/chapter01/battle{level:03d}_seed.json'


def output_path(level: int) -> Path:
    return ROOT / f'content/battles/story_{level:03d}.json'


def level_root(level: int) -> str:
    return f'res://content/imported/hsl/chapter01/battle{level:03d}'


def _cell(xy: list[int], cell: int = 32) -> list[int]:
    return [int(xy[0]) // cell, int(xy[1]) // cell]


# Script tokens that write the shared town / big-map state (the inverse of
# game/world/WorldScriptActions.gd STORY_KIND_ACTIONS); TownEventRules applies them.
WORLD_ACTION_NAMES = (
    'actSetTownExecEvent', 'actSetTownExitExecEvent', 'actAddTE', 'actDeleteTE',
    'actSetBMWalkToPoint', 'actSetBMWalkerPlayerID', 'actBMSetPointMode', 'actBMSetTrackMode',
    'actBMSetPointFlag', 'actBMSetTrackFlag', 'actBMClearPointFlag', 'actBMClearTrackFlag',
    'actBMSetPointEvent', 'actBMSetPointEncounterRatio', 'actBMSetShowTrackPoint',
    # campaign-wide ending inputs (WorldScriptActions -> TownEventRules teAddOverScore / teSetOverFlag)
    'actAddOverScore', 'actSetOverFlag',
)


def _next_level_event(command: dict, level: int) -> list[int]:
    # TYPE.H symbol gameBigMapLevel (49): "N, gameBigMapLevel" returns to the big map
    # standing at point N (WorldMapRules.BIG_MAP_LEVEL).
    values = [LEVEL_SYMBOLS.get(str(v), None) if not str(v).lstrip('-').isdigit() else int(v) for v in command.get('args', [])[:2]]
    if None in values:
        raise SystemExit(f'level {level}: unknown level symbol in actSetNextPlayLevelEvent {command.get("args")}')
    return values


def _select_event_timelines(seed: dict, level: int, message_evidence: dict) -> dict:
    """actSelectInsertEvent in the STORY: the winfail event chains the player's choice
    inserts (event sections by code), compiled into opening-timeline events for the
    coordinator to splice in after the choice — without cutscene_skip flags, since no
    interpreter runs in a preview (statuses are recorded, world writes and the next
    level event reach the hand-off as in any story scene). {} when the STORY has no
    select token."""
    choices: set[int] = set()
    for section in seed['scripts']['story']['sections']:
        for action in section.get('actions', []):
            for command in action.get('chain', []):
                if command.get('name') == 'actSelectInsertEvent':
                    args = [str(v) for v in command.get('args', [])]
                    # id, serial, num, (message_id, event_code) * num
                    for k in range(int(args[2]) if len(args) > 2 else 0):
                        if len(args) > 4 + 2 * k:
                            choices.add(int(args[4 + 2 * k]))
    if not choices:
        return {}
    result: dict[str, dict] = {}
    # lane ch3: an event chain may end on "actInsertEventStatus N / actExecWinFailProcess"
    # (winfail073 events 0 / 1 both hand over to event 2, which carries the town writes and
    # the next-level token). With no interpreter in a preview, an unconditional (actTRUE)
    # event named that way is appended to the branch so the hand-off reaches the scene end;
    # chains that end otherwise (level 900) are unchanged.
    event_sections = {int(section['codes'][0]): section for section in seed['scripts']['winfail']['sections']
                      if str(section.get('name', '')) == 'event' and section.get('codes')}

    def _chain(section: dict) -> list[dict]:
        return [command for action in section.get('actions', []) for command in action.get('chain', [])]

    def _prefix_is_true(section: dict) -> bool:
        first = _chain(section)[:1]
        return bool(first) and canonical_action_name(str(first[0].get('name', ''))) == 'actTRUE'
    # end lane ch3
    for section in seed['scripts']['winfail']['sections']:
        if str(section.get('name', '')) != 'event':
            continue
        codes = [int(code) for code in section.get('codes', [])]
        if not codes or codes[0] not in choices:
            continue
        key = f'event_{codes[0]}'
        script_id = f'winfail{level:03d}_{key}'
        source_file = f'WINFAIL{level:03d}.txt'
        chain = [command for action in section.get('actions', []) for command in action.get('chain', [])]
        # lane ch3
        chained_codes: list[int] = []
        seen_codes = {codes[0]}
        while (len(chain) >= 2 and canonical_action_name(str(chain[-1].get('name', ''))) == 'actExecWinFailProcess'
               and canonical_action_name(str(chain[-2].get('name', ''))) == 'actInsertEventStatus'
               and str(chain[-2].get('args', [''])[0]).lstrip('-').isdigit()):
            follow = int(chain[-2]['args'][0])
            if follow in seen_codes or follow not in event_sections or not _prefix_is_true(event_sections[follow]):
                break
            seen_codes.add(follow)
            chained_codes.append(follow)
            chain = chain + _chain(event_sections[follow])[1:]
        # end lane ch3
        events: list[dict] = []
        in_prefix = True
        for index, command in enumerate(chain):
            cname = canonical_action_name(str(command.get('name', '')))
            if in_prefix and (cname in ('actTRUE', 'actFALSE') or cname.startswith('actCheck')):
                continue
            in_prefix = False
            action = {
                'index': index, 'script_id': script_id, 'source_file': source_file,
                'section_index': int(section.get('index', 0)), 'section_name': 'event',
                'action_index': index, 'chain_index': 0, 'primary': cname, 'name': str(command.get('name', '')),
                'args': [str(arg) for arg in command.get('args', [])],
                'evidence_tier': str(seed.get('evidence_tier', 'resource-derived')),
                'unresolved_semantics': ['winfail event chain preserves original order and args; handler timing is remake pacing'],
            }
            events.append(_event_from_action(action, script_id, source_file, message_evidence))
        result[key] = {
            'status_key': key, 'section': 'event', 'code': codes[0], 'source_file': source_file,
            'event_count': len(events), 'evidence_tier': 'resource-derived',
            'claim_limit': 'the chosen branch is the winfail event chain in source order, spliced into the scene timeline and played with remake pacing; no battle interpreter runs, so statuses are only recorded',
            'events': events,
        }
        if chained_codes:  # lane ch3
            result[key]['chained_event_codes'] = chained_codes
            result[key]['claim_limit'] += ('; the chain ends on actInsertEventStatus / actExecWinFailProcess, so the unconditional (actTRUE) event(s) it names — '
                                           + ', '.join(f'event_{code}' for code in chained_codes)
                                           + ' — are appended in source order (the original arms the status and lets the winfail process pick it up; the hand-off order is a remake reading)')
    return result


def _skip_battle(seed: dict, level: int) -> dict | None:
    """What the winfail win section does to the campaign, for the not-remade card's
    「略過戰鬥（視為勝利）」 row: the next level event and the town / big-map writes
    (static-derived from the reconstructed winfail text). The first win section is
    used; the others are counted. Dialogue, walks, party changes and rewards of the
    skipped battle are not part of it."""
    sections = [section for section in seed['scripts']['winfail']['sections'] if str(section.get('name', '')).startswith('win')]
    # lane ch3: winfail078 has no win section — the battle ends through event 2 (round 10:
    # the quake, actEnterStorageWindow, actSetNextPlayLevelEvent 79,79). When no win section
    # exists, the event sections that carry a next-level token stand in for it.
    section_label = 'win'
    if not sections:
        def _first_name(section: dict) -> str:
            chain = [command for action in section.get('actions', []) for command in action.get('chain', [])]
            return canonical_action_name(str(chain[0].get('name', ''))) if chain else ''
        # Unconditional (actTRUE) events are select-branch tails (level 73), not battle outcomes.
        sections = [section for section in seed['scripts']['winfail']['sections']
                    if str(section.get('name', '')) == 'event' and _first_name(section) != 'actTRUE'
                    and any(command.get('name') == 'actSetNextPlayLevelEvent'
                            for action in section.get('actions', []) for command in action.get('chain', []))]
        section_label = 'event (no win section; the battle-time event that carries actSetNextPlayLevelEvent)'
    # end lane ch3
    if not sections:
        return None
    variants: list[tuple] = []
    for section in sections:
        next_level = None
        world_actions: list[dict] = []
        for action in section.get('actions', []):
            for command in action.get('chain', []):
                name = command.get('name')
                if name == 'actSetNextPlayLevelEvent':
                    next_level = _next_level_event(command, level)
                elif name in WORLD_ACTION_NAMES:
                    world_actions.append({'name': name, 'args': [str(v) for v in command.get('args', [])]})
        variants.append((json.dumps(next_level), json.dumps(world_actions, ensure_ascii=False)))
    first = sections[0]
    next_level = None
    world_actions = []
    movie: dict | None = None
    for action in first.get('actions', []):
        for command in action.get('chain', []):
            name = command.get('name')
            if name == 'actSetNextPlayLevelEvent':
                next_level = _next_level_event(command, level)
            elif name in WORLD_ACTION_NAMES:
                world_actions.append({'name': name, 'args': [str(v) for v in command.get('args', [])]})
            elif name == 'actPlayMovie' and movie is None:
                # The section's film (winfail059: the ending, movie.pak end.ani) plays before
                # the skip row's hand-off; see hsl_opening_timeline_compile.MOVIE_BY_CODE.
                args = [str(v) for v in command.get('args', [])]
                movie = {'movie': movie_name_for_code(args[0]) if args else '', 'movie_source': 'actPlayMovie ' + ','.join(args)}
    distinct = len(set(variants))
    return {
        'source': f'winfail{level:03d} {section_label} section 1 of {len(sections)}' + ('' if distinct == 1 else f' ({distinct} distinct outcomes; the first is offered)'),
        'evidence_tier': 'static-derived',
        'next_level_event': next_level,
        'world_actions': world_actions,
        **(movie or {}),
        'claim_limit': 'The win section\'s next level and town / big-map writes, offered by the not-remade card as 略過戰鬥（視為勝利） when the destination is registered (CampaignProgress.start_skip_battle_handoff applies the writes after the scene\'s own records); the section\'s dialogue, walks, party changes (actSetPlayerMode, ...) and the battle\'s rewards / experience are not applied.',
    }


def _object_player_mode(actor_id: str, fields: dict) -> int:
    """The side word +0x28 an object-built story actor starts with (constructor 0x407ec0:
    PLAYERS mode, obj_Data9 swap, obj_X1 override); 0x40ba20 reads it back for the map
    highlight colour, whether or not the actor is a PlayLoop unit."""
    from hsltools.levels.battle import install_player_mode
    players, defines = _player_tables()
    return install_player_mode(actor_id, fields, players, defines)[0]


@functools.cache
def _player_tables() -> tuple[dict, dict]:
    from hsltools.native.sources import sources
    players, _, defines = sources()
    return players, defines


def build(level: int) -> dict:
    spec = LEVELS[level]
    seed = json.loads(seed_path(level).read_text(encoding='utf-8'))
    preview = bool(spec.get('battle_opening_preview'))
    if seed.get('level_kind') != 'story' and not preview:
        raise SystemExit(f'level {level} seed is not a story-only level')
    root = level_root(level)
    map_objects = json.loads((ROOT / f'content/imported/hsl/chapter01/battle{level:03d}/map_objects.json').read_text(encoding='utf-8'))
    alignment = json.loads((ROOT / f'content/imported/hsl/chapter01/battle{level:03d}/map_object_alignment.json').read_text(encoding='utf-8'))
    actors: list[dict] = []
    bindings: dict[str, dict] = {}
    counts: dict[str, int] = {}
    conditional_skips: list[str] = []
    # EVEF tokens the spec leaves out on purpose (each row names its reason; the battle
    # assembler records the list as excluded_source_actors). A token no record carries is an error.
    excluded = {str(row['source_sid']): row for row in spec.get('excluded_source_actors', [])}
    excluded_seen: set[str] = set()
    for row in sorted(seed['placements']['records'], key=lambda item: int(item['record_index'])):
        role = row.get('role_from_process')
        source_actor_code = None  # lane ch2b
        if role not in ('player_install', 'enemy_object'):
            continue
        fields = row.get('object_data_fields', {})
        if role == 'enemy_object' and str(fields.get('obj_Data6', '')) in excluded:
            excluded_seen.add(str(fields.get('obj_Data6', '')))
            continue
        standing_code = standing_actor_code(row) if role == 'enemy_object' else ''
        if role == 'enemy_object' and row.get('shape_resource') and not is_walking_shape(str(row['shape_resource'])) and not standing_code:
            continue  # static shape (no SHAPEDEF walk groups): drawn by map_objects.json as a stand object
        if role == 'player_install' and '(有才產生)' in str(row.get('object_name', '')):
            # "有才產生": the slot is installed only when that member is in the party;
            # party membership at this point is not modelled, so the preview leaves it out.
            conditional_skips.append(str(row.get('object_name', '')))
            continue
        if role == 'player_install':
            installs = spec.get('player_installs') or {}
            if str(row.get('object_name', '')) in installs:
                install = installs[str(row.get('object_name', ''))]
                token, actor_id, unit_id = install['token'], install['actor_id'], install['unit_id']
            elif spec['player_token'] is not None:
                token, actor_id, unit_id = spec['player_token'], '001', 'leonard'
            else:
                raise SystemExit(f"level {level} scene has a player install {row.get('object_name')!r} but no player token configured")
        else:
            token = str(fields.get('obj_Data6', ''))
            actor_id = object_actor_code(fields.get('obj_Data7', 0))
            # lane ch2b: an enemy object may wear another character's walk shapes (level 30 / 71
            # Enemy053(克羅蒂) is SHAPE\009-*): the sprite prefix is what the scene draws, the
            # PLAYERS code stays as source_actor_code. Levels whose shapes match are unchanged.
            sprite_id = str(row.get('shape_resource') or '').split('\\')[-1].split('-')[0]
            if sprite_id.isdigit() and sprite_id != actor_id and not standing_code:
                source_actor_code, actor_id = actor_id, sprite_id
            # end lane ch2b
        counts[token] = counts.get(token, 0) + 1
        instance = counts[token]
        if role != 'player_install':
            unit_id = f'actor{actor_id}_{instance}'
        xy = [int(v) for v in row['placement_xy_candidate']]
        actors.append({
            'id': unit_id, 'actor_id': actor_id, 'token': token, 'instance': instance,
            'record_index': int(row['record_index']), 'placement_xy': xy, 'coord': _cell(xy),
            'role': 'player' if role == 'player_install' else 'story_npc',
            'evidence': {'placement': 'EVEF record placement candidate', 'identity': 'obj_Data6/obj_Data7 fields', 'tier': 'resource-derived'},
        })
        if role == 'enemy_object':
            actors[-1]['player_mode'] = _object_player_mode(source_actor_code or actor_id, fields)
        bindings[f'{token}/{instance}'] = {'unit_id': unit_id, 'actor_id': actor_id, 'coord': _cell(xy), 'placement_xy': xy}
        if source_actor_code is not None:  # lane ch2b
            actors[-1]['source_actor_code'] = source_actor_code
            actors[-1]['evidence']['sprite'] = 'obs shape_resource prefix differs from obj_Data7; the shape prefix is drawn, obj_Data7 kept as source_actor_code'
            bindings[f'{token}/{instance}']['source_actor_code'] = source_actor_code
    if set(excluded) - excluded_seen:
        raise SystemExit(f'level {level}: excluded_source_actors name tokens no EVEF enemy record carries: {sorted(set(excluded) - excluded_seen)}')
    # STORY-section actInsertObject tokens spawn script actors (defProcEnemy objects
    # from the level header) at off-map pixels; they are bound by insert order like
    # the level-52 Enemy021 inserts, but here they exist only as presentation.
    inserted: list[dict] = []
    header_objects = {obj['symbol']: obj for obj in seed.get('script_objects', [])}
    insert_counts: dict[str, int] = {}
    token_counts: dict[str, int] = {}
    random_slots: list[list[int]] = []
    for section in seed['scripts']['story']['sections']:
        for action in section.get('actions', []):
            for command in action.get('chain', []):
                if command.get('name') == 'actSetRandomPos':
                    # [num][x1][y1]...: 0x451d0f stores up to five slots, then swaps slot i with
                    # slot (i+2) mod 5 on each odd draw of 0x458c10 (static-derived). The scene
                    # keeps the table order — the outcome of all-even draws, one of the native
                    # permutations (provisional: the native stream is not reproduced).
                    args = [int(v) for v in command.get('args', [])]
                    random_slots = [args[1 + 2 * i:3 + 2 * i] for i in range(min(args[0], 5))] if args else []
                    continue
                if command.get('name') == 'actInsertObjectRandomPos' and len(command.get('args', [])) >= 4:
                    # [code][disp x][disp y][pos id]: 0x450f2c installs the object at slot + disp
                    # (0x407ec0), the STORY037 guardians 067 / 066. An object whose PLAYERS row has a
                    # generated actor template is a cast actor bound by insert order, and its
                    # token/serial binding follows the same order (0x44fad0 serial lookup).
                    symbol = str(command['args'][0])
                    obj = header_objects.get(symbol) or {}
                    fields = obj.get('object_data_fields', {})
                    code = str(fields.get('obj_Data7', ''))
                    token = str(fields.get('obj_Data6', ''))
                    if not code.isdigit() or not (ROOT / f'content/generated/hsl/actors/{int(code):03d}.json').is_file():
                        continue
                    slot = int(command['args'][3])
                    if not 0 <= slot < len(random_slots):
                        raise SystemExit(f'level {level}: actInsertObjectRandomPos {symbol} names random slot {slot} before actSetRandomPos fills it')
                    actor_id = f'{int(code):03d}'
                    insert_counts[symbol] = insert_counts.get(symbol, 0) + 1
                    token_counts[token] = token_counts.get(token, 0) + 1
                    pixel = [random_slots[slot][0] + int(command['args'][1]), random_slots[slot][1] + int(command['args'][2])]
                    # The enemy constructor places the object in the cell holding that pixel
                    # ((v & ~31) + 16, 0x407d1a..0x407d4e); the slots are cell centres (240 = 7*32+16).
                    xy = [v // 32 * 32 for v in pixel]
                    unit_id = f'guard{actor_id}_{token_counts[token]}'
                    bindings[f'{symbol}/insert{insert_counts[symbol]}'] = {
                        'unit_id': unit_id, 'actor_id': actor_id, 'insert_xy': xy, 'insert_pixel': pixel, 'random_slot': slot,
                        'object_code': obj['object_code'], 'object_name': obj.get('object_name'), 'process': obj.get('object_process'),
                    }
                    bindings[f'{token}/{token_counts[token]}'] = {'unit_id': unit_id, 'actor_id': actor_id, 'insert_xy': xy}
                    inserted.append({'id': unit_id, 'actor_id': actor_id, 'symbol': symbol, 'insert_xy': xy, 'random_slot': slot, 'role': 'script_insert',
                                     'player_mode': _object_player_mode(actor_id, fields),
                                     'evidence': {'placement': 'STORY actSetRandomPos slot + actInsertObjectRandomPos disp (table order, provisional)',
                                                  'identity': 'object header obj_Data6/obj_Data7', 'tier': 'resource-derived'}})
                    continue
                if command.get('name') != 'actInsertObject' or len(command.get('args', [])) < 3:
                    continue
                symbol = str(command['args'][0])
                obj = header_objects.get(symbol)
                shape = str((obj or {}).get('shape_resource') or '')
                actor_id = shape.split('\\')[-1].split('-')[0] if shape else ''
                standing_spec = (spec.get('standing_actor_inserts') or {}).get(symbol)
                if standing_spec is not None:
                    insert_counts[symbol] = insert_counts.get(symbol, 0) + 1
                    xy = [int(command['args'][1]), int(command['args'][2])]
                    unit_id = str(standing_spec['unit_id'])
                    token = str(standing_spec['token'])
                    standing_actor_id = str(standing_spec['actor_id']).zfill(3)
                    bindings[f'{symbol}/insert{insert_counts[symbol]}'] = {
                        'unit_id': unit_id, 'actor_id': standing_actor_id, 'insert_xy': xy,
                        'object_code': obj['object_code'], 'object_name': obj.get('object_name'),
                        'process': obj.get('object_process'), 'standing_only': True,
                    }
                    # An EVEF object of the token keeps serial 1 (level 18's door 門1, deleted by
                    # actDeleteObject SID_ENEMY100/1 before the obj_Story_Level_Door re-insert).
                    bindings.setdefault(f'{token}/1', {'unit_id': unit_id, 'actor_id': standing_actor_id,
                                                       'insert_xy': xy, 'standing_only': True})
                    inserted.append({'id': unit_id, 'actor_id': standing_actor_id, 'symbol': symbol,
                                     'insert_xy': xy, 'role': 'standing_actor_insert',
                                     'player_mode': _object_player_mode(standing_actor_id, obj.get('object_data_fields', {})),
                                     'evidence': {'placement': 'STORY actInsertObject args', 'identity': 'obj_Data6/obj_Data7 + standing SHP source', 'tier': 'resource-derived'}})
                    continue
                if not actor_id.isdigit() or not is_walking_shape(shape):
                    continue
                insert_counts[symbol] = insert_counts.get(symbol, 0) + 1
                unit_id = f"guard{actor_id}_{insert_counts[symbol]}"
                xy = [int(command['args'][1]), int(command['args'][2])]
                bindings[f'{symbol}/insert{insert_counts[symbol]}'] = {
                    'unit_id': unit_id, 'actor_id': actor_id, 'insert_xy': xy, 'object_code': obj['object_code'],
                    'object_name': obj.get('object_name'), 'process': obj.get('object_process'),
                }
                inserted.append({'id': unit_id, 'actor_id': actor_id, 'symbol': symbol, 'insert_xy': xy, 'role': 'script_insert',
                                 'player_mode': _object_player_mode(actor_id, obj.get('object_data_fields', {})),
                                 'evidence': {'placement': 'STORY actInsertObject args (off-map pixels)', 'identity': 'object header shape resource', 'tier': 'resource-derived'}})
    for symbol, slot in (spec.get('player_slot_inserts') or {}).items():
        bindings[f"{slot['token']}/1"] = {'unit_id': slot['unit_id'], 'actor_id': slot['actor_id'], 'spawn_on_story_object': symbol}
    for key, static_binding in (spec.get('static_bindings') or {}).items():
        bindings[key] = {'unit_id': str(static_binding['unit_id']), 'kind': 'static_object',
                         'object_symbol': str(static_binding.get('object_symbol', '')),
                         'evidence_tier': str(static_binding.get('evidence_tier', 'resource-derived'))}
    for key, unit_id in (spec.get('token_overrides') or {}).items():
        target = next((b for b in bindings.values() if b['unit_id'] == unit_id), None)
        if target is None:
            raise SystemExit(f'token override {key} -> {unit_id} has no bound unit')
        bindings[key] = {'unit_id': unit_id, 'actor_id': target['actor_id'], 'override': 'remake token binding; original instance lookup unresolved'}
    story_objects = {}
    for obj in map_objects.get('script_objects', []):
        shape_id = obj.get('shape_resource_id')
        if shape_id is None or shape_id not in map_objects.get('previews', {}):
            continue  # header symbol without a matching object in this level's .obs
        entry = {
            'object_code': obj['object_code'], 'object_name': obj.get('object_name'), 'process': obj.get('process'),
            'shape_resource_id': shape_id, 'preview': map_objects['previews'][shape_id]['res_path'],
            'draw_origin': alignment['shapes'][shape_id]['draw_origin'],
            'evidence_tier': 'provisional', 'claim_limit': 'sprite and insert point only; the object process (motion, effect, sound) is a remake reading of the obj_* fields',
        }
        # obj_Shape_Number frame runs, obj_Mode/obj_Zoom*/obj_Data* fields and plane token
        # let the coordinator's effect readings stay data-driven (levels 10+).
        if obj.get('frame_shape_ids'):
            entry['frames'] = [map_objects['previews'][frame]['res_path'] for frame in obj['frame_shape_ids']]
            entry['frame_draw_origins'] = [alignment['shapes'][frame]['draw_origin'] for frame in obj['frame_shape_ids']]
        for key in ('shape_number', 'shape_delay', 'plane', 'definition_source'):
            if obj.get(key) is not None:
                entry[key] = obj[key]
        fields = {key: value['value'] for key, value in (obj.get('object_fields') or {}).items()}
        if fields:
            entry['object_fields'] = fields
        story_objects[obj['symbol']] = entry
    for symbol, code in (spec.get('shapeless_objects') or {}).items():
        story_objects[symbol] = {'object_code': code, 'kind': 'shapeless_no_draw', 'evidence_tier': 'provisional',
                                 'claim_limit': 'OBJ-ALL.H symbol without a shape resource; recorded at its insert point, nothing is drawn and no collision is modelled in the preview'}
    for symbol, slot in (spec.get('player_slot_inserts') or {}).items():
        story_objects[symbol] = {'object_code': slot['object_code'], 'kind': 'player_slot_install', 'spawns_unit_id': slot['unit_id'],
                                 'actor_id': slot['actor_id'], 'evidence_tier': 'resource-derived',
                                 'claim_limit': 'OBJ-ALL.H obj_Story_PlayerN installs controlled slot N-1 at the insert point; presentation spawns the bound actor there'}
    next_level = None
    for section in seed['scripts']['story']['sections']:
        for action in section.get('actions', []):
            for command in action.get('chain', []):
                if command.get('name') == 'actSetNextPlayLevelEvent':
                    # TYPE.H symbol gameBigMapLevel (49): "N, gameBigMapLevel" returns to
                    # the big map standing at point N (WorldMapRules.BIG_MAP_LEVEL).
                    next_level = [LEVEL_SYMBOLS.get(str(v), None) if not str(v).lstrip('-').isdigit() else int(v) for v in command.get('args', [])[:2]]
                    if None in next_level:
                        raise SystemExit(f'level {level}: unknown level symbol in actSetNextPlayLevelEvent {command.get("args")}')
    timeline = f'{root}/opening_timeline.json'
    resources_extra = {}
    if (ROOT / f'content/imported/hsl/chapter01/battle{level:03d}/actor_shape_sets/manifest.json').is_file():
        resources_extra['actor_shape_sets'] = f'{root}/actor_shape_sets/manifest.json'
    opening_extra = {}
    unresolved_extra = []
    alias_note = None
    if seed['map'].get('alias_of_level') is not None:
        # The spec says how the alias reads: a level with a shape of its own whose obs
        # 地圖管理員 names the other level's shape (only that one matches the WRD grid), a
        # level without a shape, or no sentence at all (level 60's tracked scene predates it).
        alias_kind = spec.get('map_alias_note', 'no_shape')
        if alias_kind == 'shape_of_its_own':
            alias_note = f"map alias: level {level}'s obs 地圖管理員 names level {seed['map']['alias_of_level']}'s shape and only that shape matches the WRD grid; the scene plays on it — {seed['map']['alias_evidence']}"
        elif alias_kind == 'no_shape':
            alias_note = f"map alias: level {level} has no level{level}.shp; the scene plays on level {seed['map']['alias_of_level']}'s map — {seed['map']['alias_evidence']}"
        elif alias_kind != 'none':
            raise SystemExit(f'level {level}: unknown map_alias_note {alias_kind!r}')
        if alias_note:
            unresolved_extra.append(alias_note)
    if not preview and spec.get('end_card'):
        # A complete story scene whose next level is not registered yet ends on a
        # card (instead of the chapter-end restart) and, with end_exit, returns to
        # the big map after its recorded big-map writes have been applied.
        opening_extra['end_card'] = spec['end_card']
        if spec.get('end_exit'):
            opening_extra['end_exit'] = spec['end_exit']
        if spec.get('end_routes'):
            # actSetNextPlayLevelGetOverEvent: the finals the dispatch can return; the runtime
            # shows the one EndingDispatchRules picks from the campaign's over score / flag.
            opening_extra['end_routes'] = spec['end_routes']
            if spec.get('end_routes_evidence'):
                opening_extra['end_routes_evidence'] = spec['end_routes_evidence']
        if next_level is None:  # lane ch2b: STORY071 ends on big-map writes without a next-level token
            unresolved_extra.append(
                'the scene has no actSetNextPlayLevelEvent: it ends on an explicit card and returns to the big map after its recorded big-map writes')
        elif not spec.get('end_exit'):  # lane ch3: level 82's game-clear token has no big-map return
            unresolved_extra.append(
                f'the scene chains to level {next_level[1] if len(next_level) > 1 else "?"} (actSetNextPlayLevelEvent), which is not registered: the scene ends on an explicit card whose confirm restarts the campaign')
        else:
            unresolved_extra.append(
                f'the scene chains to level {next_level[1] if len(next_level) > 1 else "?"} (actSetNextPlayLevelEvent); while the campaign registers no scene for that level the scene ends on this card (with end_exit it returns to the big map) — campaign.json decides, the scene file does not know')
    if preview:
        opening_extra = {'end_event_id': 'first_control_ready', 'end_behavior': 'battle_not_remade_card', 'end_card': spec['end_card'],
                         'preview_of_battle_level': level}
        if spec.get('end_exit'):
            opening_extra['end_exit'] = spec['end_exit']
        unresolved_extra = [
            f'level {level} is a battle level (winfail{level:03d}); only the STORY opening is remade, the scene stops at first player control with an explicit not-remade card',
        ]
        if alias_note:
            unresolved_extra.append(alias_note)
        message_evidence = json.loads((ROOT / f'content/imported/hsl/chapter01/battle{level:03d}/message_text_evidence.json').read_text(encoding='utf-8'))
        select_events = _select_event_timelines(seed, level, message_evidence)
        if select_events:
            opening_extra['select_event_timelines'] = select_events
            unresolved_extra.append(
                'the STORY ends on actSelectInsertEvent: the chosen winfail event chain (' + ', '.join(sorted(select_events)) +
                ') is spliced into the timeline and played by the coordinator; a branch that starts the not-remade battle ends on the card')
        skip_battle = _skip_battle(seed, level) if spec.get('end_exit') else None
        if skip_battle:
            # Product previews (entered from the big map) also offer to skip the battle
            # as a victory: the win section's next level and world writes.
            opening_extra['skip_battle'] = skip_battle
            target = skip_battle['next_level_event']
            # lane ch3: winfail078 has no win section; the label names the battle-time event that stands in.
            section_words = 'win section' if skip_battle['source'].split(' ')[1] == 'win' else 'battle-time event section (no win section)'
            unresolved_extra.append(
                f'skip_battle offers the winfail {section_words} as a victory (' + (f'next {target[0]},{target[1]}' if target else 'no next level: back to the big map at the level\'s own point')
                + f', {len(skip_battle["world_actions"])} town / big-map write(s)); its dialogue, walks, party changes and rewards are not applied')
        if conditional_skips:
            unresolved_extra.append(
                'conditional installs left out (party membership at this point is not modelled): ' + ', '.join(conditional_skips))
        treasure_records = [str(item['record_index']) for item in map_objects.get('placements', []) if item.get('role') == 'treasure_box']
        if treasure_records:
            unresolved_extra.append(
                f'the {len(treasure_records)} 寶藏 treasure box(es) (defProcTreasureBox, EVEF record(s) {"/".join(treasure_records)}) are drawn closed at their EVEF anchors by map_objects.json; '
                'opening, pickup and the box contents belong to the not-yet-remade battle')
    # The level's own sentences follow the derived ones; story-only levels also record
    # their conditional installs.
    unresolved_extra += list(spec.get('notes', []))
    if not preview and conditional_skips:
        unresolved_extra.append(
            'conditional installs left out (party membership at this point is not modelled): ' + ', '.join(conditional_skips))
    # end lane ch2c
    return {
        'schema': SCHEMA,
        'id': spec['id'],
        'title': spec['title'],
        'level': level,
        'level_kind': 'story',
        'status': 'opening-preview-provisional' if preview else 'story-scene-provisional',
        'rule_adapter': 'story_scene',
        # Leonard leads the party when installed (level 2's EVEF lists 琥 first); a spec may
        # name another lead (lane ch2b: level 34's EVEF lists 琥 before 緹娜, who leads there).
        'player_unit_id': next((a['id'] for a in actors if a['role'] == 'player' and a['id'] == spec.get('lead_unit_id', 'leonard')),
                               next((a['id'] for a in actors if a['role'] == 'player'), None)),
        'resources': {
            'map_texture': seed['map']['decoded_png'],
            'terrain': seed['terrain']['packet'],
            'actor_walk_manifest': f'{root}/actor_walk_frames/actor_walk_manifest.json',
            'actor_audio': f'{root}/actor_audio.json',
            'portraits': f'{root}/portraits/manifest.json',
            'opening_timeline': timeline,
            'message_text_evidence': f'{root}/message_text_evidence.json',
            'script_sounds': f'{root}/sounds/manifest.json',
            'map_objects': f'{root}/map_objects.json',
            'map_object_alignment': f'{root}/map_object_alignment.json',
            'interface_audio': 'res://content/imported/hsl/shared/interface_audio/manifest.json',
            **resources_extra,
        },
        # What loading this level's battle record plays (original_music.md §3.1); the
        # opening's own music comes from the timeline's music events.
        'level_table_music': level_table_music(level),
        'view': {
            'logical_viewport': [640, 480],
            'grid_projection': {'origin': [0, 0], 'cell_size': [32, 32],
                                'evidence_id': f'battle{level:03d}_map_wrd_dimension_candidate',
                                'evidence_tier': 'provisional', 'provisional': True},
        },
        'commands': {'has_magic': False, 'has_special': False},
        'opening': {
            'source_script': f'story{level:03d}',
            'mode': 'story_scene',
            'status': 'coordinator_driven_remake_pacing',
            'end_event_id': 'scene_end_ready',
            **opening_extra,
            'actor_bindings': bindings,
            'speaker_resource_ids': dict(SPEAKER_IDS[level]),
            'story_objects': story_objects,
            'next_level_event': next_level,
            'claim_limit': 'Token-to-unit bindings follow EVEF record order; positions are script/EVEF pixels on the 32px grid. BattleOpeningCoordinator plays the compiled timeline with explicit remake pacing; original walk speed, follow offsets, fade timing and object motion are not proven.',
        },
        'story_actors': actors,
        **({'script_inserted_actors': inserted} if inserted else {}),
        **({'excluded_source_actors': [dict(row) for row in spec['excluded_source_actors']]} if excluded else {}),
        'unresolved_semantics': unresolved_extra + [
            'story-only level: no PlayLoop, no combat; the scene ends with actSetNextPlayLevelEvent and hands the carried party to the campaign',
            'actWalkFollow keeps the follower offset relative to its leader at follow start (remake reading)',
            'obj_Story_Level58_Star (defProcObjectMove) is shown as a static sprite at its insert point',
        ],
    }


class StorySceneTask(GeneratedFilesTask):
    family = 'story_scene'

    def __init__(self, level: int) -> None:
        self.level = level
        self.name = f'story_scene:{level}'
        self.output: Path = output_path(level)
        self.outputs = (self.output.relative_to(ROOT).as_posix(),)
        self.inputs = (seed_path(level).relative_to(ROOT).as_posix(), f'content/imported/hsl/chapter01/battle{level:03d}/', *profile.input_path(level))
        self.replaces = (f'tools/hsl_story_scene.py --level {level} --check',)
        self.scripts = ('tools/hsltools/levels/story_scene.py', 'tools/hsltools/levels/timeline.py', 'tools/hsltools/levels/message_text.py', 'tools/hsltools/sources/actor_walk_frames.py')

    def render(self, ctx: Context) -> dict[str, bytes]:
        with legacy_failures(self.name):
            scenario = build(self.level)
        return {self.outputs[0]: encode_json(scenario)}

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        scenario = json.loads(rendered[self.outputs[0]])
        if mode == 'check':
            return f"STORY_SCENE_CHECK_PASS level={self.level} actors={len(scenario['story_actors'])}"
        return f"STORY_SCENE_BUILD_PASS level={self.level} actors={len(scenario['story_actors'])} output={self.output.relative_to(ROOT)}"


def scene_levels() -> list[int]:
    """Every story level with a per-level chain (not 52); the `story_scene` sections of
    content/battles/levels/NNN.json must cover exactly these."""
    levels = actor_chain_levels()
    missing = [level for level in levels if level not in LEVELS]
    extra = sorted(set(LEVELS) - set(levels))
    if missing or extra:
        raise ValueError(f'story_scene sections of content/battles/levels/ and the imported level folders disagree: missing={missing} extra={extra}')
    return levels


def tasks() -> list[StorySceneTask]:
    return [StorySceneTask(level) for level in scene_levels()]
