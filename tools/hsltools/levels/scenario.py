"""Shared winfail-script readers of the scenario assemblers (no task of its own).

hsltools.levels.battle (level_battle:N), hsltools.levels.authored and the two hand-registered
scenarios (hsltools.data.ohm_village / gol_road) import from here:

  SHARED_RESOURCES   the chapter-wide resource paths every battle scenario points at
  combat_backdrop_resource
                     the level's close-up backdrop PNG (resources.combat_backdrop) from the seed's
                     obj-NNN.obs binding and the combat manifest's backdrops table
  status_timelines   per winfail status, the result action chain compiled into opening-timeline
                     events for BattleOpeningCoordinator's cutscene mode

Winfail inserts reach the PlayLoop only as script_actor_templates (hsltools.levels.battle
script_templates → ScriptActorCreationRules): no scenario carries a win / fail / event mirror
of its WINFAIL any more; the interpreter reads the seed (WinfailScenarioRules).
"""
from __future__ import annotations

import json

from hsltools.data.winfail_coverage import support_sets
from hsltools.paths import ROOT
from hsltools.levels.timeline import _event_from_action, canonical_action_name

CHAPTER = 'res://content/imported/hsl/chapter01'
SHARED_RESOURCES = {
    'attack_ranges': 'res://content/generated/hsl/chapter01/attack_ranges.json',
    'actor_walk_manifest': f'{CHAPTER}/actor_walk_frames/actor_walk_manifest.json',
    'actor_audio': f'{CHAPTER}/actor_audio.json',
    'consumables': f'{CHAPTER}/consumables.json',
    'portraits': f'{CHAPTER}/portraits/manifest.json',
    'progression': f'{CHAPTER}/progression.json',
    'combat_animation': f'{CHAPTER}/combat_animation/manifest.json',
    'interface_audio': f'{CHAPTER}/interface_audio/manifest.json',
    'fire_animation': f'{CHAPTER}/fire_animation/manifest.json',
}


def combat_backdrop_resource(level: int, seed: dict) -> str:
    """The res:// path of the level's close-up backdrop: the ANIMAL\\BGnnn.SHP its obj-NNN.obs binds
    to object 199 `BG` (seed `cutin_backdrop`, hsltools.levels.seed._cutin_backdrop) resolved through
    the chapter combat manifest's `backdrops` table (hsltools.assets.combat_animation). A battle seed
    without a binding, or a member the manifest did not import, is an error — no scenario falls back
    to another level's backdrop."""
    binding = seed.get('cutin_backdrop')
    if not binding:
        raise ValueError(f'level {level}: the seed records no cutin_backdrop (obj-{level:03d}.obs binds no ANIMAL\\BG shape)')
    manifest = json.loads((ROOT / SHARED_RESOURCES['combat_animation'].removeprefix('res://')).read_text(encoding='utf-8'))
    members = manifest.get('backdrops', {}).get('members', {})
    member = str(binding['source_member'])
    if member not in members:
        raise ValueError(f'level {level}: the combat manifest imports no backdrop {member}; regenerate the combat_animation task')
    return str(members[member]['res_path'])


# WRD cell word: bits 24..31 the source height (255 = cliff), bits 12..23 map flags.
# 0x74000 refuses entry to every ground mode and 0x4000 even to flying (static-derived,
# docs/evidence_packets/static_reverse/original_movement.md and original_actor_traversal.md);
# the level WRDs set 0x4000 under houses, cave voids and walls.
WRD_HARD_BLOCK_FLAGS = 0x74000


def impassable(cell: dict) -> bool:
    """A tracked terrain cell no unit may stand on or enter: 0xff height or a hard-block map flag."""
    return bool(cell['b']) or bool(int(cell['t']) & WRD_HARD_BLOCK_FLAGS)


# Stand objects whose obj_Data9 edits the map word when the object is created (the
# creation path 0x42eb70 sends message -3 to the process; defProcStandObject 0x43ccf0
# case 10 mapobjBlock ORs 0xff000000 into the cell — height 0xff, a cliff for ground
# walkers — and case 15 mapobjClearWall clears 0x4000; static-derived, see
# docs/evidence_packets/static_reverse/original_story_object_terrain.md).
STORY_OBJECT_TERRAIN = {'mapobjBlock': {'height': 255}, 'mapobjClearWall': {'clear_flags': 0x4000}}


def story_object_terrain_inserts(seed: dict) -> list[dict]:
    """Every actInsertStoryObject(XRange) of a terrain-editing stand object in the level's
    STORY and WINFAIL scripts: {source, section, token, symbol, cells, edit}."""
    objects = {row['symbol']: row for row in seed.get('script_objects', [])}
    found = []
    for source in ('story', 'winfail'):
        for section in (seed.get('scripts', {}).get(source) or {}).get('sections', []):
            name = section['name'] + ('_' + section['codes'][0] if section.get('codes') else '')
            for action in section.get('actions', []):
                for step in action.get('chain', []):
                    token, args = step.get('name'), step.get('args', [])
                    if token not in ('actInsertStoryObject', 'actInsertStoryObjectXRange') or len(args) < 3:
                        continue
                    kind = objects.get(args[0], {}).get('object_data_fields', {}).get('obj_Data9')
                    if kind not in STORY_OBJECT_TERRAIN:
                        continue
                    x, y = int(args[1]) >> 5, int(args[2]) >> 5
                    count = int(args[3]) if token == 'actInsertStoryObjectXRange' and len(args) > 3 else 1
                    found.append({'source': source, 'section': name, 'token': token, 'symbol': args[0], 'kind': kind,
                                  'cells': [[x + offset, y] for offset in range(count)], 'edit': STORY_OBJECT_TERRAIN[kind]})
    return found


def terrain_overrides(level: int, seed: dict) -> list[dict]:
    """The terrain edits a battle applies when it loads its WRD (WrdTerrainTiles): the
    STORY inserts. A STORY insert happens in the opening, before first control, so its edit
    holds for the whole battle as in the original (static-derived). A WINFAIL insert is
    not an override: the winfail interpreter records it as a loop terrain edit when its
    event fires (game/sim/TerrainEditRules.gd) — WINFAIL039's mapobjBlock rows
    (actInsertStoryObjectXRange) close the collapse, WINFAIL028／080's mapobjClearWall doors
    (actInsertStoryObject) open their 0x4000 walls, as the original does then."""
    overrides = []
    for insert in story_object_terrain_inserts(seed):
        if insert['source'] != 'story':
            continue
        for cell in insert['cells']:
            overrides.append({'cell': cell, **insert['edit'],
                              'source': f"STORY{level:03d} {insert['section']} {insert['token']} {insert['symbol']} ({insert['kind']})",
                              'evidence_tier': 'static-derived'})
    return overrides


def apply_terrain_overrides(grid: list, overrides: list[dict]) -> list:
    """A copy of a tracked terrain grid with the overrides applied (the generator's own
    placement checks see the same map the runtime loads)."""
    edited = [[dict(cell) for cell in row] for row in grid]
    for override in overrides:
        x, y = override['cell']
        if not (0 <= y < len(edited) and 0 <= x < len(edited[0])):
            raise ValueError(f'terrain override outside the map: {override}')
        cell = edited[y][x]
        if 'height' in override:
            cell['h'], cell['b'] = int(override['height']), int(int(override['height']) == 255)
        if 'clear_flags' in override:
            cell['t'] = int(cell['t']) & ~int(override['clear_flags'])
    return edited


CUTSCENE_PLAYED_APPLIED = {'actMessage', 'actMessageIfExist', 'actWalkAndDelete', 'actWalkAndDeleteWait', 'actDeleteObject'}


def status_timelines(level: int, seed: dict, message_evidence: dict) -> dict[str, dict]:
    """Per winfail status (key `<kind>_<code>`, the WinfailScenarioRules key): the result
    action chain compiled into opening-timeline events for BattleOpeningCoordinator's
    cutscene mode. Tokens the interpreter applies to the loop (statuses, inserts,
    hand-off, carry) are kept in order but flagged `cutscene_skip` so the coordinator
    records instead of replaying them; the leading condition prefix is not an event."""
    sets = support_sets()
    conditions = set(sets['SUPPORTED_CONDITIONS']) | set(sets['KNOWN_UNSUPPORTED_CONDITIONS'])
    # Applied by the interpreter AND shown by the cutscene in script order: messages
    # (the presentation de-duplicates them by key) and departures (the walk-off is
    # the visible part; the roster record is the interpreter's).
    rule_owned = set(sets['APPLIED_ACTIONS']) - CUTSCENE_PLAYED_APPLIED
    result: dict[str, dict] = {}
    for section in seed['scripts']['winfail']['sections']:
        name = str(section.get('name', ''))
        if name not in ('win', 'fail', 'event'):
            continue
        codes = [str(code) for code in section.get('codes', [])]
        code = int(codes[0]) if codes else 0
        key = f'{name}_{code}'
        script_id = f'winfail{level:03d}_{key}'
        source_file = f'WINFAIL{level:03d}.txt'
        chain = [command for action in section.get('actions', []) for command in action.get('chain', [])]
        events: list[dict] = []
        in_prefix = True
        for index, command in enumerate(chain):
            cname = canonical_action_name(str(command.get('name', '')))
            if in_prefix and cname in conditions:
                continue
            in_prefix = False
            action = {
                'index': index, 'script_id': script_id, 'source_file': source_file,
                'section_index': int(section.get('index', 0)), 'section_name': name,
                'action_index': index, 'chain_index': 0, 'primary': cname, 'name': str(command.get('name', '')),
                'args': [str(arg) for arg in command.get('args', [])],
                'evidence_tier': str(seed.get('evidence_tier', 'resource-derived')),
                'unresolved_semantics': ['winfail result action preserves original order and args; handler timing is remake pacing'],
            }
            event = _event_from_action(action, script_id, source_file, message_evidence)
            if cname in rule_owned:
                event['cutscene_skip'] = True
                event['presentation_status'] = 'applied_by_winfail_interpreter'
            events.append(event)
        playable = [event for event in events if not event.get('cutscene_skip')]
        result[key] = {
            'status_key': key, 'section': name, 'code': code, 'source_file': source_file,
            'event_count': len(events), 'playable_event_count': len(playable),
            'evidence_tier': 'resource-derived',
            'claim_limit': 'result-action order and arguments are the source script; the coordinator plays them with remake pacing after the interpreter fired the status',
            'events': events,
        }
    return result
