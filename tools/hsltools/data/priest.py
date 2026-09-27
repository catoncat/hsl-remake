"""Source002 priest and an explicitly authored non-Leonard playable trial.

Registry task priest_data (family actors): outputs content/generated/hsl/actors/002.json, content/battles/priest_trial.json,
content/generated/hsl/development/priest_objectives.json and priest_inventory.json. Bodies moved verbatim from the former hsl_priest_data.py.
"""
import copy
import json
from pathlib import Path
from hsltools.data import json_bytes
from hsltools.data.first_battle_formation import actor_templates
from hsltools.native.sources import sources
from hsltools.registry import Context, GeneratedFilesTask

ACTOR=Path('content/generated/hsl/actors/002.json')
SCENARIO=Path('content/battles/priest_trial.json')
OBJECTIVES=Path('content/generated/hsl/development/priest_objectives.json')
INVENTORY=Path('content/generated/hsl/development/priest_inventory.json')


def build():
    first=json.loads(Path('content/battles/first_battle.json').read_text())
    base=copy.deepcopy(next(a for a in first['playable_units'] if a['id']=='leonard'))
    source=actor_templates(['002'])['002'];players,_,_=sources();row=players['002']
    base.update(id='tina',actor_id='002',coord=[11,16],hp=source['max_hp'],max_hp=source['max_hp'],
                mp=source['max_mp'],max_mp=source['max_mp'],live_speed=source['live_speed'],
                weapon_code=int(row['weapon_equip']),equipment=source['equipment'],growth_profile=source['growth_profile'],
                no_attack=source['no_attack'],base_move_point=source['base_move_point'],move_point=source['move_point'],
                position_evidence_tier='provisional',position_source={'kind':'authored_development_placement'},
                position_note='Not a STORY053 first-control formation.',
                combat_stats_source='Source002 full job85 refresh; player slot1 binds template002. Initial state is not source029.',
                vitals_source='Source002 full job85 refresh.',live_speed_source='Source002 dex and current equipment.',
                attack_range_evidence={'evidence_tier':'resource-derived','source':'Source002 weapon82 -> ITEM range1Cell'})
    for key in base['combat_profile']:
        if key in source:base['combat_profile'][key]=source[key]
    base['status_flags']=0;base['status_counters']={'poison':0,'paralysis':0,'no_magic':0}
    ally=copy.deepcopy(next(a for a in first['playable_units'] if a['id']=='enemy024_1'))
    ally.update(id='companion',coord=[12,16],hp=8)
    foe=copy.deepcopy(next(a for a in first['playable_units'] if a['id']=='enemy021_1'))
    foe.update(coord=[18,16])
    trial=copy.deepcopy(first)
    trial.update(schema='hsl_development_battle.v1',id='priest_development_trial',title='祭司 · 援護演練',status='development-playable',rule_adapter='development_battle',
                 player_unit_id='tina',playable_units=[base,ally,foe],
                 development_note='Source002 priest/gear/healing spell; wounded companion and placement/inventory extras are authored trial settings, not STORY053 battle equivalence.')
    trial['resources']['consumables']='res://'+INVENTORY.as_posix()
    trial['resources']['development_objectives']='res://'+OBJECTIVES.as_posix()
    for k in ['opening_timeline','opening_choreography','map_objects','map_object_alignment']:trial['resources'].pop(k,None)
    trial['scenario_rules']={'initial_objective_phase':'escape','allow_optional_clear_after_switch':True,'events':{},'reinforcements':[],
                             'reinforcement_spawn_cells':[],'script_fallback':{'escape_zone':[[14,10]]}}
    trial['unresolved_semantics']=[trial['development_note'],'No class change, source029 combat or complete winfail053 claim.']
    inventory=json.loads(Path('content/imported/hsl/chapter01/consumables.json').read_text())
    inventory['initial_inventory']['002']=[241,244,87,218,227,232,246,248]
    return ({'schema':'hsl_source_priest_template.v1','actor':base,'evidence':'docs/evidence_packets/static_reverse/original_priest.json'},trial,
            {'schema':'hsl_development_objectives.v1','escape_zone':[[14,10]]},inventory)


class PriestDataTask(GeneratedFilesTask):
    name = 'priest_data'
    family = 'actors'
    inputs = ('content/imported/hsl/global/tables/', 'content/battles/first_battle.json', 'content/imported/hsl/chapter01/consumables.json',
              'content/generated/hsl/roles/profiles.json', 'content/generated/hsl/equipment/items.json')
    outputs = (ACTOR.as_posix(), SCENARIO.as_posix(), OBJECTIVES.as_posix(), INVENTORY.as_posix())
    replaces = ('tools/hsl_priest_data.py --check',)
    scripts = ('tools/hsltools/data/priest.py', 'tools/hsltools/data/first_battle_formation.py')

    def render(self, ctx: Context) -> dict[str, bytes]:
        return {path.as_posix(): json_bytes(data) for path, data in zip([ACTOR,SCENARIO,OBJECTIVES,INVENTORY],build())}

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        return 'PRIEST_DATA_PASS actor002 job85 formal_grants_unchanged=True'


def tasks() -> list[PriestDataTask]:
    return [PriestDataTask()]
