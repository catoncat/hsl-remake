"""Source level2 two-stage battle; uninstalled actors are templates, never a roster.

Reuse the reviewed role templates, original preview bindings and status compiler.
No synthetic skills, inventory, levels, reinforcements or escape condition are
added to the formal encounter. Scripted movements use the live transaction owner.

Registry task gol_road_data (family scenarios): output content/battles/gol_road_battle.json. Bodies moved
verbatim from the former hsl_gol_road_data.py.
"""
from __future__ import annotations

import copy
import json
from pathlib import Path

from hsltools.levels.battle import apply_story_word_writes
from hsltools.levels.scenario import SHARED_RESOURCES, combat_backdrop_resource, impassable, status_timelines
from hsltools.native.sources import sources
from hsltools.levels.timeline import level_table_music
from hsltools.probes.player_install import PACKET as INSTALL_PACKET, check as check_install
from hsltools.data import json_bytes
from hsltools.data.ohm_village import endpoints
from hsltools.paths import ROOT
from hsltools.registry import Context, GeneratedFilesTask
from hsltools.sources.tables import digest

OUT = ROOT / 'content/battles/gol_road_battle.json'
SEED = ROOT / 'content/generated/hsl/chapter01/battle002_seed.json'
PREVIEW = ROOT / 'content/battles/story_002.json'


def build() -> dict:
    installation = json.loads(INSTALL_PACKET.read_text())
    check_install(installation)
    objects = next(r['objects'] for r in installation['sources'] if r['level'] == 2)
    tina_object = next(r for r in objects if r.get('obj_code') == '7')
    if tina_object.get('obj_Data9') != '1' or int(tina_object.get('obj_Data8', '0')) != 0:
        raise ValueError('The source Tina installer is no longer unconditional slot1')
    seed = json.loads(SEED.read_text())
    preview = json.loads(PREVIEW.read_text())
    first = json.loads((ROOT / 'content/battles/first_battle.json').read_text())
    originals = {a['actor_id']: a for a in first['playable_units']}
    for code in ['002', '003', '028']:
        originals[code] = json.loads((ROOT / f'content/generated/hsl/actors/{code}.json').read_text())['actor']
    points, traces = endpoints(seed, preview)
    roster = []
    for placed in preview['story_actors']:
        code = placed['actor_id']
        actor = copy.deepcopy(originals[code])
        player = code in ['001', '003']
        xy = points[placed['id']]
        if any(v % 32 for v in xy):
            raise ValueError('Unreviewed Gol opening grid endpoint: ' + str(xy))
        actor.update(id=placed['id'], class_id=('Player' if player else 'Enemy') + code,
                     battle_actor_role='player_controlled' if player else 'enemy_ai',
                     player_commandable=player, source_object_kind=3 if player else 5,
                     coord=[v // 32 for v in xy], position_evidence_tier='resource-derived',
                     position_source={'evef_record_index': placed['record_index'],
                                      'placement_world': placed['placement_xy'],
                                      'story_endpoint': xy, 'story_movements': traces[placed['id']]},
                     position_note='Source EVEF/STORY002 aligned endpoint; opening still begins at the original EVEF pixel.')
        roster.append(actor)
    # STORY002's actSetDeadMessage lines (雷歐納德 741, 琥 743) are the last writers of live +0x14.
    apply_story_word_writes(2, seed, roster, preview['opening']['actor_bindings'], {a['id']: a['actor_id'] for a in roster}, sources()[0])
    opening = copy.deepcopy(preview['opening'])
    for key in ['mode', 'end_event_id', 'end_behavior', 'end_card', 'preview_of_battle_level',
                'end_exit', 'next_level_event', 'skip_battle']:
        opening.pop(key, None)
    opening.update(first_control_event_id='first_control_ready', initial_focus_unit_id='leonard')
    for binding in opening['actor_bindings'].values():
        binding.pop('coord', None)
    # These are source templates and symbol bindings, not pre-existing actors.
    # Event0 installs Tina first; the four following guards use the resulting
    # registered party for their own birth adjustment.
    tina = copy.deepcopy(originals['002'])
    tina.update(id='tina', class_id='Player002', battle_actor_role='player_controlled',
                player_commandable=True, source_object_kind=3, coord=[0, 0])
    guard = copy.deepcopy(originals['023'])
    guard.update(id='gol_guard', class_id='Enemy023', battle_actor_role='enemy_ai',
                 player_commandable=False, source_object_kind=5, coord=[0, 0])
    templates = {
        'obj_Story_Player2': {'kind': 'registered_player', 'actor': tina, 'token': 'SID_緹娜',
                              'aliases': ['SID_PLAYER1'], 'source_actor_id': '002',
                              'evidence': 'docs/evidence_packets/static_reverse/original_priest.md'},
        'obj_Story_Level2_Enemy23': {'kind': 'npc', 'actor': guard, 'token': 'SID_ENEMY023',
                                   'aliases': [], 'source_actor_id': '023',
                                   'evidence': 'docs/evidence_packets/static_reverse/original_auto_growth.md'},
    }
    resources = copy.deepcopy(preview['resources'])
    for key in ['attack_ranges', 'progression', 'consumables',
                'combat_animation', 'interface_audio', 'fire_animation']:
        resources[key] = first['resources'].get(key, SHARED_RESOURCES[key])
    resources['battle_seed'] = 'res://' + SEED.relative_to(ROOT).as_posix()
    resources['combat_backdrop'] = combat_backdrop_resource(2, seed)
    resources['treasures'] = 'res://content/generated/hsl/treasures/battles.json'
    evidence = json.loads((ROOT / resources['message_text_evidence'].removeprefix('res://')).read_text())
    timelines = status_timelines(2, seed, evidence)
    # The existing coordinator renders these already-committed creations in the
    # source action order. It never installs a second gameplay actor.
    for program in timelines.values():
        for event in program['events']:
            if event.get('script_action_name') in ['actInsertObject', 'actWalkPrevInsertObject', 'actWalkPrevInsertObjectWait']:
                event.pop('cutscene_skip', None)
        program['playable_event_count'] = sum(not e.get('cutscene_skip', False) for e in program['events'])
    result = dict(schema='hsl_gol_road_battle.v1', id='battle_005_level2', level=2, level_kind='battle',
                  title='戈爾山道 · 緹娜的追兵', status='product-opening-source-adapted',
                  rule_adapter='winfail', player_unit_id='leonard', resources=resources,
                  level_table_music=level_table_music(2),
                  view=copy.deepcopy(preview['view']), commands=copy.deepcopy(first['commands']),
                  opening=opening, playable_units=roster, script_actor_templates=templates,
                  result_labels={'win_0': '戈爾山道 · 追兵已擊退'},
                  scenario_rules={'initial_objective_phase': 'raiders', 'allow_optional_clear_after_switch': False,
                                  'events': {}, 'reinforcements': [], 'reinforcement_spawn_cells': [],
                                  'script_fallback': {'escape_zone': []}, 'status_timelines': timelines},
                  provenance={'seed_sha256': digest(SEED.read_bytes()), 'preview_sha256': digest(PREVIEW.read_bytes())},
                  unresolved_semantics=[
                      'Source STORY002 and WINFAIL002 define two phases, Player2 installation, four guards, raider departure and next55; no player escape zone.',
                      'Original per-object registration and growth callees are independently proven; complete original scheduler/global RNG and wall clock are not.',
                      'Source scripted cells occupied or blocked in live play use a recorded nearest legal landing; this is an explicit remake placement policy.',
                      'Treasure contents come from original EVEF instances; action-tail collection, visible hints and deferred reward persistence are explicit remake integration choices.',
                  ])
    grid = json.loads((ROOT / resources['terrain'].removeprefix('res://')).read_text())['grid']
    seen = set()
    for actor in roster:
        x, y = actor['coord']
        if not (0 <= y < len(grid) and 0 <= x < len(grid[0])) or impassable(grid[y][x]) or (x, y) in seen:
            raise ValueError('Invalid source Gol endpoint: ' + actor['id'])
        seen.add((x, y))
    if len(roster) != 7 or sum(a['player_commandable'] for a in roster) != 2:
        raise ValueError('Gol initial roster must contain two players and five raiders')
    return result


class GolRoadDataTask(GeneratedFilesTask):
    name = 'gol_road_data'
    family = 'scenarios'
    inputs = ('content/imported/hsl/global/tables/', 'docs/evidence_packets/static_reverse/original_player_install.json',
              'content/battles/first_battle.json', SEED.relative_to(ROOT).as_posix(), PREVIEW.relative_to(ROOT).as_posix(),
              'content/imported/hsl/chapter01/battle002/', 'content/generated/hsl/actors/', SHARED_RESOURCES['combat_animation'].removeprefix('res://'))
    outputs = (OUT.relative_to(ROOT).as_posix(),)
    replaces = ('tools/hsl_gol_road_data.py --check',)
    scripts = ('tools/hsltools/data/gol_road.py', 'tools/hsltools/probes/player_install.py', 'tools/hsltools/levels/scenario.py', 'tools/hsltools/data/ohm_village.py')

    def render(self, ctx: Context) -> dict[str, bytes]:
        return {OUT.relative_to(ROOT).as_posix(): json_bytes(build())}

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        return 'GOL_ROAD_DATA_PASS initial_actors=7 pending_templates=2 default_grants=source'


def tasks() -> list[GolRoadDataTask]:
    return [GolRoadDataTask()]
