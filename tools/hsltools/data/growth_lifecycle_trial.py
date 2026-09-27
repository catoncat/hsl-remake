"""Authored playable growth training, using source role/skill/equipment mechanics.

Registry task growth_lifecycle_trial (family trials): outputs content/battles/growth_lifecycle_trial.json,
content/generated/hsl/development/growth_lifecycle_progression.json and growth_lifecycle_inventory.json.
Bodies moved verbatim from the former hsl_growth_lifecycle_trial.py.
"""
from __future__ import annotations
import copy
import json
from pathlib import Path

from hsltools.data import json_bytes
from hsltools.registry import Context, GeneratedFilesTask

OUT=Path('content/battles/growth_lifecycle_trial.json')
PROGRESSION=Path('content/generated/hsl/development/growth_lifecycle_progression.json')
INVENTORY=Path('content/generated/hsl/development/growth_lifecycle_inventory.json')


def build():
    scenario=json.loads(Path('content/battles/priest_trial.json').read_text())
    scenario['id']='growth_lifecycle_trial'
    scenario['title']='成長與學技演練'
    scenario['status']='authored_development_trial'
    scenario['development_note']='先讓緹娜兩次待機、同伴待機承受毒傷；緹娜治療同伴升到六級後，第二次獨立行動可用剛習得的驅毒。劍士同伴接近升級，確認基礎力量達26可學絕技。可換裝、F5/F9與在東北標記撤離。初始毒、近門檻經驗、耐久和道具為演練設定，技能門檻與結算採原作證據。'
    scenario['resources']['progression']='res://'+PROGRESSION.as_posix()
    scenario['resources']['consumables']='res://'+INVENTORY.as_posix()
    progression=json.loads(Path('content/imported/hsl/chapter01/progression.json').read_text())
    progression.update(evidence_tier='provisional',note='Authored progression setup: priest5 EXP299 and source001 swordsman9 EXP499; levels agree with initial base-attribute inference, not source first-control stats.')
    progression['actors']['002'].update(level=5,exp=299)
    progression['actors']['001'].update(level=9,exp=499)
    inventory=json.loads(Path('content/generated/hsl/development/priest_inventory.json').read_text())
    first=json.loads(Path('content/battles/first_battle.json').read_text())
    swordsman=next(row for row in first['playable_units'] if row['actor_id']=='001')
    for actor in scenario['playable_units']:
        if actor['id']=='tina':
            actor['grid_coord']=[10,16]
            actor['combat_profile'].update(str=20,dex=16,mind=21,con=15)
            actor['growth_profile']['source'].update(hit_point=350,magic_point=160,speed=250)
            actor['equipment'].append(dict(slot='accessory2',item_code=227,name='白光之翼'))
        elif actor['id']=='companion':
            actor.clear()
            actor.update(copy.deepcopy(swordsman))
            actor.update(id='companion',player_commandable=True,battle_actor_role='player_controlled')
            actor['grid_coord']=[10,15]
            actor['combat_profile'].update(str=25,dex=20,mind=20,con=24)
            actor['growth_profile']['source'].update(hit_point=450,speed=180)
            actor['status_flags']=1
            actor['status_counters']={'poison':(16<<16)|3,'no_magic':0,'paralysis':0}
        else:
            actor['grid_coord']=[13,16]
            actor['growth_profile']['source'].update(hit_point=650,attack_power=100,speed=0)
        actor['coord']=copy.deepcopy(actor['grid_coord'])
        actor['position_source']={'kind':'authored_growth_training'}
        actor['position_note']='Source051 terrain, training starting cells.'
    inventory['initial_inventory']['002']=[232,247,244,241,253,227,0,0]
    inventory['initial_inventory']['001']=[232,247,244,241,253,0,0,0]
    inventory['inventory_contract']='Authored growth-training inventory, not a new source or campaign initial grant.'
    scenario['unresolved_semantics'].append('Training EXP/durability/inventory and source001 companion initial poison are authored. Initial roster callback scheduling and persistent independent RNG remain remake policies; source learner/grant functions do not use RNG.')
    return {OUT:scenario,PROGRESSION:progression,INVENTORY:inventory}


class GrowthLifecycleTrialTask(GeneratedFilesTask):
    name = 'growth_lifecycle_trial'
    family = 'trials'
    inputs = ('content/battles/priest_trial.json', 'content/imported/hsl/chapter01/progression.json', 'content/generated/hsl/development/priest_inventory.json')
    outputs = (OUT.as_posix(), PROGRESSION.as_posix(), INVENTORY.as_posix())
    replaces = ('tools/hsl_growth_lifecycle_trial.py --check',)
    scripts = ('tools/hsltools/data/growth_lifecycle_trial.py',)

    def render(self, ctx: Context) -> dict[str, bytes]:
        return {path.as_posix(): json_bytes(data) for path, data in build().items()}

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        return 'GROWTH_LIFECYCLE_TRIAL_PASS'


def tasks() -> list[GrowthLifecycleTrialTask]:
    return [GrowthLifecycleTrialTask()]
