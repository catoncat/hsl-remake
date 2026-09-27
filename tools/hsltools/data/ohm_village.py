"""Ohm Village: source roster and STORY endpoints on the existing battle owner.

This is a new level provider, not a competing progression/runtime model. Existing
preview bindings and source-backed status-timeline compilation remain read-only.

Registry task ohm_village_data (family scenarios): outputs content/battles/ohm_village_battle.json and
content/generated/hsl/actors/003.json, 061.json, 062.json. Bodies moved verbatim from the former hsl_ohm_village_data.py.
"""
from __future__ import annotations
import copy
import json
from pathlib import Path
from hsltools.probes.ohm_growth import PACKET, check as check_native
from hsltools.levels.battle import apply_story_word_writes
from hsltools.levels.scenario import impassable, status_timelines, SHARED_RESOURCES
from hsltools.levels.timeline import level_table_music
from hsltools.data import json_bytes
from hsltools.data.first_battle_formation import actor_templates
from hsltools.native.sources import sources
from hsltools.paths import ROOT
from hsltools.registry import Context, GeneratedFilesTask
from hsltools.sources.tables import digest

OUT=ROOT/'content/battles/ohm_village_battle.json'
SEED=ROOT/'content/generated/hsl/chapter01/battle001_seed.json'
PREVIEW=ROOT/'content/battles/story_001.json'
ACTORS=['003','061','062']

def templates():
    check_native(json.loads(PACKET.read_text()))
    players,_,defines=sources();source=actor_templates(ACTORS)
    original=json.loads((ROOT/'content/battles/first_battle.json').read_text())
    baseline=next(a for a in original['playable_units'] if a['actor_id']=='001')
    result={}
    for code in ACTORS:
        row=players[code];stats=source[code];actor=copy.deepcopy(baseline)
        role='player_controlled' if defines[row['mode']]==0x10000 else 'friendly_ai'
        actor.update(id='hu' if code=='003' else f'actor{code}_1',actor_id=code,class_id='Player003' if code=='003' else 'Enemy'+code,
                     battle_actor_role=role,player_commandable=role=='player_controlled',source_object_kind=3 if code=='003' else 5,
                     hp=stats['max_hp'],max_hp=stats['max_hp'],mp=stats['max_mp'],max_mp=stats['max_mp'],
                     live_speed=stats['live_speed'],weapon_code=int(row.get('weapon_equip',0)),equipment=stats['equipment'],
                     growth_profile=stats['growth_profile'],base_move_point=stats['base_move_point'],move_point=stats['move_point'],
                     no_attack=stats['no_attack'],status_flags=0,status_counters={'poison':0,'paralysis':0,'no_magic':0},
                     coord=[0,0],position_evidence_tier='provisional',position_source={'kind':'unplaced_source_template'},
                     position_note='Template has no encounter placement; the level provider supplies the source STORY endpoint.',
                     combat_stats_evidence_tier='static-derived',combat_stats_source='original_ohm_growth full native refresh on own PLAYERS fields.',
                     vitals_evidence_tier='static-derived',vitals_source='Original source template before encounter birth adjustment.',
                     live_speed_evidence_tier='static-derived',live_speed_source='Own job and current equipment; no encounter-speed override.',
                     attack_range_evidence={'evidence_tier':'static-derived','source':'original_bow_range and original_ohm_growth: bow61 signed shoot3; no weapon uses range0.'})
        for key in actor['combat_profile']:
            if key in stats:actor['combat_profile'][key]=stats[key]
        result[code]={'schema':'hsl_source_actor_template.v1','actor':actor,'evidence':'docs/evidence_packets/static_reverse/original_ohm_growth.json',
                      'limits':['Source job/mode, gear and abilities stay independent; this unplaced template is not a final battle level.',
                                'Villager kind5 is general AI on the player side; no weapon means no normal hostile attack target.']}
    return result

def endpoints(seed,preview):
    state={a['id']:list(a['placement_xy']) for a in preview['story_actors']}
    traces={key:[] for key in state}
    bindings=preview['opening']['actor_bindings']
    for section in seed['scripts']['story']['sections']:
        for action in section.get('actions',[]):
            for command in action.get('chain',[]):
                name,args=command['name'],command['args']
                if name not in ['actWalkDisp','actWalkDispWait','actWalk','actWalkWait']:continue
                key=f'{args[0]}/{args[1]}'
                if key not in bindings:raise ValueError('Unresolved Ohm movement actor '+key)
                identity=bindings[key]['unit_id'];xy=list(map(int,args[2:4]))
                before=state[identity].copy()
                state[identity]=[p+d for p,d in zip(before,xy)] if 'Disp' in name else xy
                traces[identity].append({'action':name,'args':args,'before':before,'after':state[identity].copy()})
    return state,traces

def build():
    seed=json.loads(SEED.read_text());preview=json.loads(PREVIEW.read_text())
    first=json.loads((ROOT/'content/battles/first_battle.json').read_text())
    source=templates();players,_,defines=sources()
    points,traces=endpoints(seed,preview);roster=[]
    for placed in preview['story_actors']:
        code=placed['actor_id']
        if code in source:actor=copy.deepcopy(source[code]['actor'])
        elif code=='001':actor=copy.deepcopy(next(a for a in first['playable_units'] if a['actor_id']==code))
        else:actor=copy.deepcopy(json.loads((ROOT/f'content/generated/hsl/actors/{code}.json').read_text())['actor'])
        row=players[code];mode=defines[row['mode']]
        role={0x10000:'player_controlled',0x50000:'friendly_ai',0x20000:'enemy_ai'}.get(mode)
        if role is None:raise ValueError('Unreviewed source Ohm actor mode')
        xy=points[placed['id']]
        if any(v%32 for v in xy):raise ValueError('Ohm endpoint needs a new nonaligned-grid reading')
        # The constructor 0x407ec0 writes the PLAYERS mode to live +0x28 (the villagers' pmNPCPlayer
        # 0x50000, runtime-measured in the opening snapshot); no EVEF record here swaps or overrides it.
        actor.update(player_mode=int(mode),player_mode_source='PLAYERS '+row['mode']+' (0x407ec0)')
        actor.update(id=placed['id'],class_id=('Player'+code if role=='player_controlled' else 'Enemy'+code),
                     battle_actor_role=role,player_commandable=role=='player_controlled',source_object_kind=3 if role=='player_controlled' else 5,
                     coord=[v//32 for v in xy],position_evidence_tier='resource-derived',
                     position_source={'evef_record_index':placed['record_index'],'placement_world':placed['placement_xy'],
                                      'story_endpoint':xy,'story_movements':traces[placed['id']]},
                     position_note='32px-aligned EVEF/STORY endpoints. Presentation starts at original EVEF; battle begins at this final cell.')
        instance=next((r.get('actor_instance') for r in seed['placements']['records'] if r['record_index']==placed['record_index']),None)
        if instance:
            # EVEF instance words the original install callback 0x42bd50 applies on top of the
            # PLAYERS template (level 1: villagers wait then run to the north-west corner).
            actor['evef_instance']={'evidence_tier':'resource-derived','record_index':placed['record_index'],**copy.deepcopy(instance)}
        roster.append(actor)
    # STORY001's actSetDeadMessage lines (雷歐納德 743, 琥 742) are the last writers of live +0x14.
    apply_story_word_writes(1,seed,roster,preview['opening']['actor_bindings'],{a['id']:a['actor_id'] for a in roster},players)
    opening=copy.deepcopy(preview['opening'])
    for key in ['mode','end_event_id','end_behavior','end_card','preview_of_battle_level','end_exit','next_level_event','skip_battle']:opening.pop(key,None)
    opening.update(first_control_event_id='first_control_ready',initial_focus_unit_id='hu',
                   claim_limit='Original STORY001 token order and source EVEF bindings; existing remake walk/camera clock, no native timing-equivalence claim.')
    # Unlike preview coord metadata, a battle binding must not replace the final
    # PlayLoop cell with the initial EVEF cell. Placement is read by the coordinator.
    for binding in opening['actor_bindings'].values():binding.pop('coord',None)
    resources=copy.deepcopy(preview['resources'])
    for key in ['attack_ranges','progression','consumables','combat_animation','interface_audio','fire_animation']:
        resources[key]=first['resources'][key] if key in first['resources'] else SHARED_RESOURCES[key]
    resources['battle_seed']='res://content/generated/hsl/chapter01/battle001_seed.json'
    resources['treasures']='res://content/generated/hsl/treasures/battles.json'
    evidence=json.loads((ROOT/'content/imported/hsl/chapter01/battle001/message_text_evidence.json').read_text())
    result=dict(schema='hsl_ohm_village_battle.v1',id='battle_004_level1',level=1,level_kind='battle',title='歐姆村 · 獸族的襲擊',
                status='product-opening-source-adapted',rule_adapter='winfail',player_unit_id='leonard',resources=resources,
                level_table_music=level_table_music(1),view=copy.deepcopy(preview['view']),
                commands=dict(first['commands']),
                opening=opening,playable_units=roster,
                result_labels={'win_0':'歐姆村 · 敵軍已清除','win_1':'歐姆村 · 敵軍撤退'},
                scenario_rules={'initial_objective_phase':'protect_village','allow_optional_clear_after_switch':False,'events':{},
                                'reinforcements':[],'reinforcement_spawn_cells':[],'script_fallback':{'escape_zone':[]},
                                'status_timelines':status_timelines(1,seed,evidence)},
                provenance={'seed_sha256':digest(SEED.read_bytes()),'preview_sha256':digest(PREVIEW.read_bytes()),'source_roles':'PLAYERS exact mode; 003 registered slot2, 061/062 general kind5.'},
                unresolved_semantics=['Own source role/gear/initial ability and native job/growth are integrated; full original dispatcher and global RNG remain separate.',
                                      'Original level1 has no reinforcement insertion or player escape trigger. Independent insertion tests are explicit fixtures, not added original events.',
                                      'Winfail and source grid/AI use existing reviewed adapters; movement, result wording and presentation clock remain remake choices. Treasure uses original instance contents, with explicit action-tail collection and shared pending-item handling.'])
    grid=json.loads((ROOT/resources['terrain'].removeprefix('res://')).read_text())['grid'];seen=set()
    for actor in roster:
        x,y=actor['coord']
        if not 0<=y<len(grid) or not 0<=x<len(grid[0]) or impassable(grid[y][x]) or (x,y) in seen:raise ValueError('Invalid actual Ohm endpoint '+actor['id']+': '+str([x,y]))
        seen.add((x,y))
    if len(roster)!=18 or sum(a['player_commandable'] for a in roster)!=2:raise ValueError('Source Ohm roster differs')
    return source,result


class OhmVillageDataTask(GeneratedFilesTask):
    name = 'ohm_village_data'
    family = 'scenarios'
    inputs = ('content/imported/hsl/global/tables/', 'docs/evidence_packets/static_reverse/original_ohm_growth.json',
              'content/battles/first_battle.json', SEED.relative_to(ROOT).as_posix(), PREVIEW.relative_to(ROOT).as_posix(),
              'content/imported/hsl/chapter01/battle001/', 'content/generated/hsl/roles/profiles.json', 'content/generated/hsl/equipment/items.json')
    outputs = (OUT.relative_to(ROOT).as_posix(), *(f'content/generated/hsl/actors/{code}.json' for code in ACTORS))
    replaces = ('tools/hsl_ohm_village_data.py --check',)
    scripts = ('tools/hsltools/data/ohm_village.py', 'tools/hsltools/probes/ohm_growth.py', 'tools/hsltools/levels/scenario.py', 'tools/hsltools/data/first_battle_formation.py')

    def render(self, ctx: Context) -> dict[str, bytes]:
        actors,scenario=build()
        return {OUT.relative_to(ROOT).as_posix(): json_bytes(scenario),
                **{f'content/generated/hsl/actors/{code}.json': json_bytes(value) for code,value in actors.items()}}

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        return 'OHM_VILLAGE_DATA_PASS actors=18 controlled=2 villagers=8 default_grants=source'


def tasks() -> list[OhmVillageDataTask]:
    return [OhmVillageDataTask()]
