"""Explicit battle-only training kits, reusing source terrain, roles and art.

Registry task tactical_items_data (family trials): outputs content/battles/tactical_items_trial.json and
content/generated/hsl/development/tactical_items_inventory.json. Bodies moved verbatim from the former hsl_tactical_items_data.py.
"""
from pathlib import Path
from hsltools.data import json_bytes
from hsltools.data.stat_magic import training as stat_training
from hsltools.registry import Context, GeneratedFilesTask

TRIAL=Path('content/battles/tactical_items_trial.json')
INVENTORY=Path('content/generated/hsl/development/tactical_items_inventory.json')

def training():
    trial,inventory=stat_training()
    trial.update(id='tactical_item_training',title='道具解圍與戰內強化 · 演練')
    trial['resources']['consumables']='res://'+INVENTORY.as_posix()
    trial['skill_rules']['initial_stamina']=0
    inventory['initial_inventory']['002']=[247,250,262,263,227,232,244,241]
    inventory['initial_inventory']['023']=[247,248,250,263,0,0,0,0]
    trial['development_note']='Explicit tactical-item exercise: source002/023/026 art/jobs and source051 terrain, with the prior stat-trial durability/speed and three declared training spells. Extra kits on002/023 are supplied for this training only; starting stamina0. Actual random5..10 effects, duration-only repeats, silence cure and20ST cap use shared battle transactions. No permanent stat gain, new campaign ownership or original encounter claim.'
    trial['unresolved_semantics']=[trial['development_note']]
    return trial,inventory


class TacticalItemsDataTask(GeneratedFilesTask):
    name = 'tactical_items_data'
    family = 'trials'
    inputs = ('content/battles/priest_trial.json', 'content/battles/first_battle.json', 'content/generated/hsl/development/priest_inventory.json',
              'content/generated/hsl/skills/initial_book.json')
    outputs = (TRIAL.as_posix(), INVENTORY.as_posix())
    replaces = ('tools/hsl_tactical_items_data.py --check',)
    scripts = ('tools/hsltools/data/tactical_items.py', 'tools/hsltools/data/stat_magic.py')

    def render(self, ctx: Context) -> dict[str, bytes]:
        trial, inventory = training()
        return {TRIAL.as_posix(): json_bytes(trial), INVENTORY.as_posix(): json_bytes(inventory)}

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        return 'TACTICAL_ITEMS_DATA_PASS source_campaign_kits_unchanged=True'


def tasks() -> list[TacticalItemsDataTask]:
    return [TacticalItemsDataTask()]
