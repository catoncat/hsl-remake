"""Build four independently sourced role templates and a public capability trial.

Registry task mobile_jobs_data (family actors): outputs content/generated/hsl/actors/NNN.json for its four
templates, content/battles/mobile_jobs_trial.json,
content/generated/hsl/development/mobile_jobs_objectives.json and mobile_jobs_inventory.json. Bodies moved
verbatim from the former hsl_mobile_jobs_data.py.
"""
import copy
import json
from pathlib import Path
from hsltools.probes.mobile_jobs import ACTORS, PACKET, check
from hsltools.data import json_bytes
from hsltools.data.first_battle_formation import actor_templates
from hsltools.native.sources import sources
from hsltools.registry import Context, GeneratedFilesTask

SCENARIO=Path('content/battles/mobile_jobs_trial.json')
OBJECTIVES=Path('content/generated/hsl/development/mobile_jobs_objectives.json')
INVENTORY=Path('content/generated/hsl/development/mobile_jobs_inventory.json')

def build():
    packet=json.loads(PACKET.read_text());check(packet)
    first=json.loads(Path('content/battles/first_battle.json').read_text())
    players,_,_=sources();sources_by_actor=actor_templates(ACTORS);records={}
    for code,name,coord in [('004','thief',[11,16]),('006','wing',[12,16]),('028','enemy028_1',[18,16]),('036','enemy036_1',[19,18])]:
        source=sources_by_actor[code];row=players[code]
        actor=copy.deepcopy(next(a for a in first['playable_units'] if a['id']==('leonard' if code in ['004','006'] else 'enemy021_1')))
        actor.update(id=name,actor_id=code,coord=coord,hp=source['max_hp'],max_hp=source['max_hp'],mp=source['max_mp'],max_mp=source['max_mp'],
                     weapon_code=int(row['weapon_equip']),equipment=source['equipment'],growth_profile=source['growth_profile'],
                     live_speed=source['live_speed'],no_attack=source['no_attack'],base_move_point=source['base_move_point'],move_point=source['move_point'],
                     position_evidence_tier='provisional',position_source={'kind':'authored_development_placement'},position_note='Public trial placement, not a source battle formation.',
                     combat_stats_evidence_tier='static-derived',combat_stats_source='Full native job88/92 refresh on exact role-table inputs.',
                     vitals_evidence_tier='static-derived',vitals_source='Bounded native refresh; undeclared initial levels use an explicit level1 policy.',
                     live_speed_evidence_tier='static-derived',live_speed_source='Original profession plus exact current source equipment.',
                     attack_range_evidence={'evidence_tier':'resource-derived','source':'This role weapon_equip -> ITEM.attack_range -> RANGE'})
        for key in actor['combat_profile']:
            if key in source:actor['combat_profile'][key]=source[key]
        records[Path(f'content/generated/hsl/actors/{code}.json')]={'schema':'hsl_source_actor_template.v1','actor':actor,
            'evidence':'docs/evidence_packets/static_reverse/original_mobile_jobs.json',
            'limits':['Source abilities and equipment are unchanged; no substitute for unimplemented specials.',
                      'Initial level1 is source-declared for004 only; other fixed-level templates do not claim the original level_adjust_range loader.']}
    roster=[copy.deepcopy(records[Path(f'content/generated/hsl/actors/{code}.json')]['actor']) for code in ACTORS]
    priest=copy.deepcopy(json.loads(Path('content/generated/hsl/actors/002.json').read_text())['actor'])
    priest.update(coord=[11,17],id='tina',hp=12)
    mage=copy.deepcopy(next(a for a in first['playable_units'] if a['id']=='enemy026_1'))
    mage['coord']=[18,14]
    trial=copy.deepcopy(first)
    trial.update(schema='hsl_development_battle.v1',id='mobile_jobs_development_trial',title='盜賊與翼戰士 · 法力打擊演練',status='development-playable',rule_adapter='development_battle',
                 player_unit_id='thief',playable_units=[*roster,priest,mage],
                 development_note='Original004/006/028/036 jobs/default gear/abilities; authored roster, initial wounded002, level1 policy and extra trial inventory. Not a chapter encounter reconstruction.')
    trial['resources']['consumables']='res://'+INVENTORY.as_posix();trial['resources']['development_objectives']='res://'+OBJECTIVES.as_posix()
    for key in ['opening_timeline','opening_choreography','map_objects','map_object_alignment']:trial['resources'].pop(key,None)
    trial['scenario_rules']={'initial_objective_phase':'escape','allow_optional_clear_after_switch':True,'events':{},'reinforcements':[],
                             'reinforcement_spawn_cells':[],'script_fallback':{'escape_zone':[[14,10]]}}
    trial['unresolved_semantics']=[trial['development_note'],'Silver Hand and Continuous Stab remain hidden pending independent implementation/evidence.']
    inventory=json.loads(Path('content/imported/hsl/chapter01/consumables.json').read_text())
    inventory['initial_inventory'].update({'004':[108,227,218,253,250,241,246,248],'006':[232,227,250,244,249,241,251,252],'002':[241,244,246,247,248,249,250,0]})
    records.update({SCENARIO:trial,OBJECTIVES:{'schema':'hsl_development_objectives.v1','escape_zone':[[14,10]]},INVENTORY:inventory})
    return records


class MobileJobsDataTask(GeneratedFilesTask):
    name = 'mobile_jobs_data'
    family = 'actors'
    inputs = ('content/imported/hsl/global/tables/', 'content/battles/first_battle.json', 'docs/evidence_packets/static_reverse/original_mobile_jobs.json',
              'content/generated/hsl/roles/profiles.json', 'content/generated/hsl/equipment/items.json')
    outputs = (*(f'content/generated/hsl/actors/{code}.json' for code in ACTORS), SCENARIO.as_posix(), OBJECTIVES.as_posix(), INVENTORY.as_posix())
    replaces = ('tools/hsl_mobile_jobs_data.py --check',)
    scripts = ('tools/hsltools/data/mobile_jobs.py', 'tools/hsltools/probes/mobile_jobs.py', 'tools/hsltools/data/first_battle_formation.py')

    def render(self, ctx: Context) -> dict[str, bytes]:
        return {path.as_posix(): json_bytes(value) for path, value in build().items()}

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        return 'MOBILE_JOBS_DATA_PASS templates=4 authored_trial=True'


def tasks() -> list[MobileJobsDataTask]:
    return [MobileJobsDataTask()]
