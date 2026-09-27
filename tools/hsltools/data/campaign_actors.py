"""Compile unplaced campaign actor templates and their source declarations.

Registry task campaign_actor_data (family actors): outputs content/generated/hsl/actors/NNN.json for every
CAMPAIGN_ACTORS code; the per-actor detail lines the script printed after its PASS line are still printed, the
PASS line itself is the task summary. Bodies moved verbatim from the former hsl_campaign_actor_data.py.
"""
from __future__ import annotations
import json
from pathlib import Path

from hsltools.data import json_bytes
from hsltools.data.ai_profiles import build as ai_profiles
from hsltools.data.equipment import build as equipment_data
from hsltools.data.first_battle_formation import actor_templates
from hsltools.data.growth_lifecycle import build as learning_data
from hsltools.data.role_profiles import build as roles
from hsltools.data.skill_book import build as skill_book
from hsltools.model.jobs import CAMPAIGN_ACTORS, CAMPAIGN_PROOF, SLOTS
from hsltools.native.sources import sources
from hsltools.registry import Context, GeneratedFilesTask
from hsltools.sources.tables import blocks, digest

OUT=Path('content/generated/hsl/actors')
PLAYERS={'005':'shera','007':'howl','008':'gulu','009':'claudie',
         # PLAYERS 010-020: the town job-up targets (obj_Player1Up1..9Up1, 1Up2/2Up2); the id is the
         # base member's unit id because JobUpRules merges the target row into the registered unit's record.
         '010':'leonard','011':'tina','012':'hu','013':'hanks','014':'shera','015':'rett','016':'howl','017':'gulu','018':'claudie','019':'leonard','020':'tina'}
COMBAT_KEYS=['str','dex','mind','con','live_attack_damage','live_defense','live_hit_ratio','live_magic_attack',
             'resist_by_type','avoid_hit_ratio','attack_back','attack_damagex2','base_steal_ratio','steal_ratio',
             'weapon_magic_attack_type','weapon_damage_variance_lo','weapon_damage_variance_hi']


def process_sources():
    """Retain distinct source object declarations, not an inferred global AI class."""
    result={code:[] for code in CAMPAIGN_ACTORS};seen={code:set() for code in result}
    def visit(node,path,source):
        if isinstance(node,list):
            for value in node:visit(value,path,source)
        elif isinstance(node,dict):
            data=node.get('object_data_fields',{});raw=data.get('obj_Data7','')
            process=str(node.get('object_process',''))
            if str(raw).isdigit() and (process.startswith('defProcEnemy') or process=='defProcPlayer'):
                code=str(raw).zfill(3)
                if code in result:
                    key=(node['object_process'],data.get('obj_Data6'),raw)
                    if key not in seen[code]:
                        seen[code].add(key)
                        result[code].append(dict(process=node['object_process'],sid_token=data.get('obj_Data6'),source_actor=int(raw),
                            object_code=node.get('object_code'),example=path.as_posix(),source=source,evidence_tier='resource-derived'))
            for value in node.values():
                if isinstance(value,(list,dict)):visit(value,path,source)
    for path in sorted(Path('content/generated/hsl/chapter01').glob('battle*_seed.json')):
        seed=json.loads(path.read_text());visit(seed,path,seed.get('sources',{}).get('objects'))
    global_path=Path('content/imported/hsl/shared/first_skill/global.obs');raw=global_path.read_bytes()
    for row in blocks(raw,'Object'):
        code=row.get('obj_Data7','').zfill(3)
        if code in result and row.get('obj_Process_Code')=='defProcPlayer':
            result[code].append(dict(process=row['obj_Process_Code'],sid_token=row.get('obj_Data6'),source_actor=int(code),
                object_code=int(row['obj_code']),example=global_path.as_posix(),source=dict(sha256=digest(raw)),evidence_tier='resource-derived'))
    return result


def build():
    players,_,defs=sources();stats=actor_templates(CAMPAIGN_ACTORS);profiles=roles()['actors']
    ai=ai_profiles()['actors'];book=skill_book()['actors'];learning=learning_data();objects=process_sources();catalog=equipment_data()['items'];out={}
    for code in CAMPAIGN_ACTORS:
        row=players[code];s=stats[code]
        unsupported=[int(row[k]) for k in SLOTS if int(row.get(k,0)) and not catalog[str(int(row[k]))]['supported']]
        blockers=[dict(kind='unsupported_equipment',item_code=item,fields=catalog[str(item)]['unsupported_fields'],
            replacement='Implement and validate the original weapon range/effect before registering a playable battle using this unchanged equipment.') for item in unsupported]
        role='player_controlled' if code in PLAYERS else 'enemy_ai' if row['mode']=='pmEnemy' else 'friendly_ai'
        actor=dict(id=PLAYERS.get(code,'enemy'+code+'_1'),actor_id=code,battle_actor_role=role,coord=[0,0],
                   hp=s['max_hp'],max_hp=s['max_hp'],mp=s['max_mp'],max_mp=s['max_mp'],live_speed=s['live_speed'],
                   action_ready=True,player_commandable=code in PLAYERS,combat_profile={k:s[k] for k in COMBAT_KEYS},
                   class_id='Player'+str(int(code)) if code in PLAYERS else 'Enemy'+code,weapon_code=int(row.get('weapon_equip',0)),
                   equipment=s['equipment'],growth_profile=s['growth_profile'],status_flags=0,
                   status_counters=dict(poison=0,paralysis=0,no_magic=0),no_attack=s['no_attack'],
                   # PLAYERS no_showshape (0x44c33c, +0xa0 bit 0x20): the enemy process never draws the object (0x4420ef).
                   **({'no_showshape':True} if int(row.get('no_showshape',0)) else {}),
                   position_evidence_tier='provisional',position_source=dict(kind='unplaced_source_template'),
                   position_note='The assembling scenario must replace coord with a reviewed placement; this is not an encounter position.',
                   combat_stats_evidence_tier='static-derived',combat_stats_source=CAMPAIGN_PROOF,
                   live_speed_evidence_tier='static-derived',live_speed_source=CAMPAIGN_PROOF,
                   vitals_evidence_tier='static-derived',vitals_source='Bounded pre-birth refresh; final level comes from initial-roster/entry growth.',
                   attack_range_evidence=dict(evidence_tier='resource-derived',source='This actor weapon_equip -> ITEM.attack_range -> RANGE'))
        for key in ['base_move_point','move_point','move_point_evidence_tier','move_point_source']:actor[key]=s[key]
        record=profiles[code]['source_record']
        out[code]=dict(schema='hsl_source_actor_template.v1',actor=actor,evidence=CAMPAIGN_PROOF,
            source=dict(evidence_tier='resource-derived',record={k:record[k] for k in ['path','sha256','start_line','end_line']},
                job=profiles[code]['job_source'],initial_level=profiles[code]['initial_level'],traversal=book[code]['traversal'],
                traversal_declared={k:k in row for k in ['move_fly','no_block','size_type']},ai=ai[code],object_processes=objects[code],
                skill_declarations={k:v for k,v in row.items() if k.startswith(('magic_','special_')) and k not in ['magic_point','magic_attack_power']},
                skill_masks=learning['actors'][code],supported_initial_ids=book[code]['supported_initial_ids'],
                learning_job=defs[row['job']],learning_path='content/generated/hsl/roles/growth_lifecycle.json',runtime_blockers=blockers),
            limits=['Unplaced source template. Battle assembly supplies position, battle role and reviewed entry-growth inputs.',
                    'Source mode does not alone grant player control. Player slot binding and scenario role are separate inputs.',
                    'Missing AI declarations stay missing; an automatic role lacking a required strategy must fail explicitly.',
                    'Object process declarations are resource-derived examples; they do not prove every defProcEnemy callback or global dispatcher.',
                    'Unsupported initial/learned abilities remain unavailable. Replace missing effects with independently reviewed native handlers, never another skill.',
                    'No complete battle or original encounter-level equality is claimed.'])
    return out


class CampaignActorDataTask(GeneratedFilesTask):
    name = 'campaign_actor_data'
    family = 'actors'
    inputs = ('content/imported/hsl/global/tables/', CAMPAIGN_PROOF, 'content/battles/first_battle.json', 'content/generated/hsl/ai/profiles.json',
              'content/generated/hsl/roles/profiles.json', 'content/generated/hsl/roles/growth_lifecycle.json',
              'content/generated/hsl/skills/initial_book.json', 'content/generated/hsl/equipment/items.json',
              'content/generated/hsl/chapter01/')
    outputs = tuple((OUT/(code+'.json')).as_posix() for code in CAMPAIGN_ACTORS)
    replaces = ('tools/hsl_campaign_actor_data.py --check',)
    scripts = ('tools/hsltools/data/campaign_actors.py', 'tools/hsltools/data/first_battle_formation.py', 'tools/hsltools/data/role_profiles.py', 'tools/hsltools/data/ai_profiles.py', 'tools/hsltools/data/growth_lifecycle.py')

    def render(self, ctx: Context) -> dict[str, bytes]:
        return {(OUT/(code+'.json')).as_posix(): json_bytes(template) for code, template in build().items()}

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        for path, raw in rendered.items():
            code, source = Path(path).stem, json.loads(raw)['source']
            print(code,'job='+str(source['job']['code']),'missing_ai='+','.join(source['ai']['missing_required']),
                  'equipment_blockers='+','.join(str(r['item_code']) for r in source['runtime_blockers']),
                  'processes='+','.join(sorted({r['process'] for r in source['object_processes']})),
                  'traversal='+json.dumps(source['traversal'],sort_keys=True))
        return 'CAMPAIGN_ACTOR_DATA_PASS actors='+str(len(rendered))


def tasks() -> list[CampaignActorDataTask]:
    return [CampaignActorDataTask()]
