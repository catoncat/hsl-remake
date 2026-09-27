"""Playable authored learn-Water-Strike then cast at a real empty cross center.

Registry task water_strike_trial (family trials): outputs content/battles/water_strike_trial.json,
content/generated/hsl/development/water_strike_progression.json and water_strike_inventory.json. Bodies moved
verbatim from the former hsl_water_strike_trial.py.
"""
import copy
import json
from pathlib import Path
from hsltools.data import json_bytes
from hsltools.data import growth_lifecycle_trial as Growth
from hsltools.registry import Context, GeneratedFilesTask

OUT=Path('content/battles/water_strike_trial.json')
PROGRESSION=Path('content/generated/hsl/development/water_strike_progression.json')
INVENTORY=Path('content/generated/hsl/development/water_strike_inventory.json')


def build():
    source=Growth.build()
    scenario=copy.deepcopy(source[Growth.OUT])
    scenario.update(id='water_strike_trial',title='水剎・十字範圍演練',
        development_note='緹娜先兩次待機、同伴待機受到毒傷；治療同伴升至四級後學會水剎。在第二行動點兩敵中間的空格，可一次8MP攻擊十字內兩敵。敵人的起始麻痺用於保留站位；位置、經驗、耐久、毒與裝備為演練配置。F5/F9、換裝、離場與重開均可操作。')
    scenario['resources']['progression']='res://'+str(PROGRESSION)
    scenario['resources']['consumables']='res://'+str(INVENTORY)
    progress=copy.deepcopy(source[Growth.PROGRESSION])
    progress['actors']['002'].update(level=3,exp=199)
    progress['note']='Authored level3/EXP199 learning trial. Initial attributes imply level3; first actual final EXP award learns source Water01 at level4.'
    for actor in scenario['playable_units']:
        if actor['id']=='tina':
            actor['combat_profile'].update(str=16,dex=14,mind=18,con=14)
            actor['growth_profile']['source'].update(hit_point=400,magic_point=200)
        elif actor['id']!='companion':
            actor['coord']=actor['grid_coord']=[12,16]
            actor['growth_profile']['source'].update(hit_point=500,attack_power=40)
            actor['status_flags']=4
            actor['status_counters']={'poison':0,'no_magic':0,'paralysis':3}
        actor['position_source']={'kind':'authored_water_strike_training'}
    enemy=next(a for a in scenario['playable_units'] if a['id']=='enemy021_1')
    other=copy.deepcopy(enemy)
    other.update(id='enemy021_2',coord=[11,15],grid_coord=[11,15])
    scenario['playable_units'].append(other)
    inventory=copy.deepcopy(source[Growth.INVENTORY])
    inventory['initial_inventory']['021']=[0]*8
    inventory['inventory_contract']='Authored Water Strike training; no original first-battle grants changed.'
    scenario['unresolved_semantics'].append('Water01 effect_range is the real source cross. Enemy initial paralysis, injuries produced by ally poison, attributes/EXP and equipment are explicit training setup; no runtime ability grant or effect substitution.')
    return {OUT:scenario,PROGRESSION:progress,INVENTORY:inventory}


class WaterStrikeTrialTask(GeneratedFilesTask):
    name = 'water_strike_trial'
    family = 'trials'
    inputs = Growth.GrowthLifecycleTrialTask.inputs
    outputs = (OUT.as_posix(), PROGRESSION.as_posix(), INVENTORY.as_posix())
    replaces = ('tools/hsl_water_strike_trial.py --check',)
    scripts = ('tools/hsltools/data/water_strike_trial.py', 'tools/hsltools/data/growth_lifecycle_trial.py')

    def render(self, ctx: Context) -> dict[str, bytes]:
        return {path.as_posix(): json_bytes(data) for path, data in build().items()}

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        return 'WATER_STRIKE_TRIAL_PASS'


def tasks() -> list[WaterStrikeTrialTask]:
    return [WaterStrikeTrialTask()]
