"""Source039 fixed-template actor and an explicit playable development encounter.

The ordinary first battle is unchanged. Trial placement/party control are remake
development settings, not original039 first-battle initialization or story.

Registry task large_actor_data (family actors): outputs content/generated/hsl/actors/039.json and
content/battles/large_actor_trial.json. Bodies moved verbatim from the former hsl_large_actor_data.py.
"""
import copy
import json
from pathlib import Path
from hsltools.probes.large_actor import PACKET, check
from hsltools.data import json_bytes
from hsltools.data.equipment import build as equipment_data, initial_physical_fields, initial_mobility_fields
from hsltools.native.sources import sources
from hsltools.registry import Context, GeneratedFilesTask

OUT=Path('content/generated/hsl/actors/039.json')
TRIAL=Path('content/battles/large_actor_trial.json')
EVIDENCE='docs/evidence_packets/static_reverse/original_large_actor.json'

def build():
    proof=json.loads(PACKET.read_text());check(proof)
    case=proof['stats'][0];values=case['native'][0]['values'];source=sources()[0]['039'];catalog=equipment_data()['items']
    actor=dict(id='enemy039_1',actor_id='039',battle_actor_role='enemy_ai',coord=[15,15],
               hp=values['max_hp'],max_hp=values['max_hp'],mp=values['max_mp'],max_mp=values['max_mp'],
               move_point=values['move_point'],live_speed=values['speed'],action_ready=True,player_commandable=False,
               no_attack=bool(int(source.get('no_attack',0))),status_flags=0,status_counters=dict(poison=0,paralysis=0,no_magic=0),
               combat_profile=dict(str=case['input']['attributes']['str'],dex=case['input']['attributes']['dex'],
                    mind=case['input']['attributes']['mind'],con=case['input']['attributes']['con'],
                    live_attack_damage=values['attack'],live_hit_ratio=values['hit_rate'],live_defense=values['defense'],
                    live_magic_attack=values['magic_attack'],avoid_hit_ratio=values['avoid_hit_ratio'],attack_back=values['attack_back'],
                    attack_damagex2=values['attack_damagex2'],resist_by_type=values['resist_by_type']),
               growth_profile=dict(case['profile'],allocation='fixed_template',evidence=EVIDENCE),
               position_evidence_tier='provisional',position_note='Authored development placement on original terrain; not original scene039 placement.',
               vitals_evidence_tier='static-derived',vitals_source='Eight full source039 refresh returns; fixed level1 is the existing remake policy, not native level selection.',
               combat_stats_evidence_tier='static-derived',combat_stats_source=EVIDENCE)
    actor['equipment']=[dict(slot=slot,item_code=code,name=catalog[str(code)]['name']) for slot,code in zip(
        ['weapon','head','armor','foot','accessory1','accessory2'],case['input']['equipment']) if code]
    actor['weapon_code']=case['input']['equipment'][0]
    actor['combat_profile'].update(initial_physical_fields(source,catalog))
    actor.update(initial_mobility_fields(source,catalog))
    base=json.loads(Path('content/battles/first_battle.json').read_text())
    trial=copy.deepcopy(base)
    trial.update(id='large_actor_development_trial',title='大型角色 · 空間演練',status='development-playable',
                 development_only=True,development_note='Original first-battle terrain with authored039 placement and control; not a new original campaign encounter.')
    leonard=copy.deepcopy(next(a for a in base['playable_units'] if a['id']=='leonard'))
    leonard['coord']=[9,14]
    friend=copy.deepcopy(actor)
    friend.update(id='large039_friend',battle_actor_role='player_controlled',player_commandable=True,coord=[13,14])
    enemy=copy.deepcopy(next(a for a in base['playable_units'] if a['id']=='enemy021_1'));enemy['coord']=[18,15]
    mage=copy.deepcopy(next(a for a in base['playable_units'] if a['id']=='enemy026_1'));mage['coord']=[19,18]
    trial['playable_units']=[leonard,friend,enemy,mage]
    trial['unresolved_semantics']=['Development encounter only; source039 fixed level and control are explicit remake choices. No first-battle default grant or original story equivalence.']
    return actor,trial


class LargeActorDataTask(GeneratedFilesTask):
    name = 'large_actor_data'
    family = 'actors'
    inputs = ('content/imported/hsl/global/tables/', EVIDENCE, 'content/generated/hsl/equipment/items.json', 'content/battles/first_battle.json')
    outputs = (OUT.as_posix(), TRIAL.as_posix())
    replaces = ('tools/hsl_large_actor_data.py --check',)
    scripts = ('tools/hsltools/data/large_actor.py', 'tools/hsltools/probes/large_actor.py')

    def render(self, ctx: Context) -> dict[str, bytes]:
        actor, trial = build()
        return {OUT.as_posix(): json_bytes(dict(schema='hsl_source_large_actor.v1',evidence_tier='static-derived',source=EVIDENCE,actor=actor)),
                TRIAL.as_posix(): json_bytes(trial)}

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        return 'LARGE_ACTOR_DATA_PASS actor039 job94 source_refresh trial_explicit=True'


def tasks() -> list[LargeActorDataTask]:
    return [LargeActorDataTask()]
