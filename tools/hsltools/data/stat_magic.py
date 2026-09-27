"""Source buff/dispel assets, source ownership, and an explicitly supplied trial.

Registry task stat_magic_data (family skills): tracked outputs the trial content/battles/stat_magic_trial.json
and inventory content/generated/hsl/development/stat_magic_inventory.json (rendered byte for byte), plus the
imported asset folder content/imported/hsl/chapter01/stat_magic/ which check validates and only the legacy
--pak entry re-imports. Bodies moved verbatim from the former hsl_stat_magic_data.py.
"""
from __future__ import annotations
import copy
import json
from pathlib import Path
from hsltools.data import json_bytes
from hsltools.data.skill_book import build as skill_book
from hsltools.data.support_magic import build, check
from hsltools.registry import CheckFailed, Context, GeneratedFilesTask

OUT=Path('content/imported/hsl/chapter01/stat_magic')
TRIAL=Path('content/battles/stat_magic_trial.json')
INVENTORY=Path('content/generated/hsl/development/stat_magic_inventory.json')
# Twelve actual consecutive PAK entries, not filenames01..12. This selects art
# for the remake layout; the native object handler's frame scheduling is separate.
FRAME_MEMBERS={'MAGIC\\MIN12_01.SHP':['MAGIC\\MIN12_%02d.SHP' % (group*10+frame) for group in range(4) for frame in range(1,4)]}

# The three rows with imported effect art (地精守護／灼熱波動／退魔). The area editions 地靈聖護／赤炎波動
# and 魔障壁 (resist_up) share the policy but have no imported art and are not trial grants.
ASSET_ROWS=('magic:magicEARTH:magicCode06','magic:magicFIRE:magicCode05','magic:magicMIND:magicCode06')

def definitions():
    return {entry['magic_key']:dict(skill_id=sid,name=entry['name'],fields=entry['fields'])
            for sid,entry in skill_book()['skills'].items() if entry['damage_policy']=='native_magic_stat' and sid in ASSET_ROWS}

def training():
    trial=json.loads(Path('content/battles/priest_trial.json').read_text())
    trial.update(id='stat_magic_training',title='攻防增益與退魔 · 演練',
                 training_skill_grants={'002':[s['skill_id'] for s in definitions().values()],
                                        '026':[definitions()['dispel']['skill_id']]})
    first=json.loads(Path('content/battles/first_battle.json').read_text())
    caster,ally=trial['playable_units'][:2]
    caster['coord']=[14,16];ally['coord']=[14,15]
    caster['growth_profile']['source']['hit_point']+=240
    caster['growth_profile']['source']['magic_point']+=100
    caster['growth_profile']['source']['speed']+=100
    caster['hp']+=240;caster['max_hp']+=240;caster['mp']+=100;caster['max_mp']+=100;caster['live_speed']+=100
    ally['player_commandable']=True;ally['battle_actor_role']='player_controlled';ally['hp']=ally['max_hp']
    enemy=copy.deepcopy(next(a for a in first['playable_units'] if a['actor_id']=='026'))
    enemy['coord']=[18,16]
    trial['playable_units']=[caster,ally,enemy]
    trial['skill_rules']['initial_stamina']=40
    inventory=json.loads(Path('content/generated/hsl/development/priest_inventory.json').read_text())
    inventory['initial_inventory']['002']=[227,232,228,87,244,241,248,0]
    trial['resources']['consumables']='res://'+INVENTORY.as_posix()
    trial['development_note']='Explicit training grants: source002 receives Earth Guard/Heat Wave/Dispel and source026 receives Dispel for this trial only. Their campaign declarations are unchanged. Authored source051 encounter, 240HP/100MP/100speed additions to the priest, controlled heavy companion, supplied items and40ST. Buff magnitudes/costs/merging/expiry and all actions use shared source rules; this is not original learning or formal encounter parity.'
    trial['unresolved_semantics']=[trial['development_note']]
    return trial,inventory


class StatMagicDataTask(GeneratedFilesTask):
    name = 'stat_magic_data'
    family = 'skills'
    inputs = ('content/imported/hsl/global/tables/', 'content/generated/hsl/skills/initial_book.json', 'content/battles/priest_trial.json',
              'content/battles/first_battle.json', 'content/generated/hsl/development/priest_inventory.json', 'content/imported/hsl/shared/first_skill/')
    outputs = (TRIAL.as_posix(), INVENTORY.as_posix(), OUT.as_posix() + '/')
    replaces = ('tools/hsl_stat_magic_data.py --check',)
    scripts = ('tools/hsltools/data/stat_magic.py', 'tools/hsltools/data/support_magic.py')

    def render(self, ctx: Context) -> dict[str, bytes]:
        trial, inventory = training()
        return {TRIAL.as_posix(): json_bytes(trial), INVENTORY.as_posix(): json_bytes(inventory)}

    def check(self, ctx: Context) -> str:
        line = super().check(ctx)
        try:
            check(definitions(), OUT, FRAME_MEMBERS)
        except AssertionError as error:
            raise CheckFailed(f'{self.name}: stat magic assets differ from their manifest') from error
        return line

    def generate(self, ctx: Context) -> str:
        line = super().generate(ctx)
        check(definitions(), OUT, FRAME_MEMBERS)
        return line

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        return 'STAT_MAGIC_DATA_PASS campaign_grants=source_only training_grants=explicit'


def tasks() -> list[StatMagicDataTask]:
    return [StatMagicDataTask()]
