"""Public permanent-source item exercise, with explicitly authored inventory.

Registry task permanent_items_data (family trials): outputs content/battles/permanent_items_trial.json and
content/generated/hsl/development/permanent_items_inventory.json. Bodies moved verbatim from the former hsl_permanent_items_data.py.
"""
from pathlib import Path
from hsltools.data import json_bytes
from hsltools.data.tactical_items import training as tactical_training
from hsltools.registry import Context, GeneratedFilesTask

TRIAL=Path('content/battles/permanent_items_trial.json')
INVENTORY=Path('content/generated/hsl/development/permanent_items_inventory.json')

def training():
    trial,inventory=tactical_training()
    trial.update(id='permanent_item_training',title='永久能力與成長 · 演練')
    trial['resources']['consumables']='res://'+INVENTORY.as_posix()
    inventory['initial_inventory']['002']=[253,254,255,256,257,258,227,232]
    companion=next(actor['actor_id'] for actor in trial['playable_units'] if actor['id']=='companion')
    inventory['initial_inventory'][companion]=[259,260,261,247,250,262,263,0]
    trial['development_note']='Explicit permanent-capability exercise: inherited source002/024/026 art/jobs, source051 terrain and declared prior training HP/MP/speed/spells. Items253..261 are distributed across the actual two controlled actor IDs, with wings/moving-cast ring and tactical items for interaction; no permanent gains are pre-applied. Source campaign inventories and ability ownership are unchanged. Each successful use updates separate acquired source offsets and shared stat refresh, never STR/DEX/MIND/CON.'
    trial['unresolved_semantics']=[trial['development_note']]
    return trial,inventory


class PermanentItemsDataTask(GeneratedFilesTask):
    name = 'permanent_items_data'
    family = 'trials'
    inputs = ('content/battles/priest_trial.json', 'content/battles/first_battle.json', 'content/generated/hsl/development/priest_inventory.json',
              'content/generated/hsl/skills/initial_book.json')
    outputs = (TRIAL.as_posix(), INVENTORY.as_posix())
    replaces = ('tools/hsl_permanent_items_data.py --check',)
    scripts = ('tools/hsltools/data/permanent_items.py', 'tools/hsltools/data/tactical_items.py')

    def render(self, ctx: Context) -> dict[str, bytes]:
        trial, inventory = training()
        return {TRIAL.as_posix(): json_bytes(trial), INVENTORY.as_posix(): json_bytes(inventory)}

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        return 'PERMANENT_ITEMS_DATA_PASS declared_kits_only=True'


def tasks() -> list[PermanentItemsDataTask]:
    return [PermanentItemsDataTask()]
