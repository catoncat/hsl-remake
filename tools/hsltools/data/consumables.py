"""Build/check current first-battle consumables from original character/item tables.

Registry task consumables (family items): output content/imported/hsl/chapter01/consumables.json.
Bodies moved verbatim from the former hsl_consumables.py.
"""
from pathlib import Path
import re
from hsltools.data import json_bytes
from hsltools.registry import GeneratedFilesTask, Context
from hsltools.sources.tables import AUTHORED_CHARACTERS, character_rows, parse_table

ROOT = Path('content/imported/hsl')
OUTPUT = ROOT / 'chapter01/consumables.json'


def build():
    def table(filename, section):
        text = (ROOT / 'global/tables' / filename).read_bytes().decode('cp950')
        entries = [dict((k, v.strip()) for k, v in re.findall(r'^\s*(\w+)\s*=\s*([^;\r\n]+)', block, re.M)) for block in text.split('[' + section + ']')[1:]]
        return {entry['code']: entry for entry in entries if 'code' in entry}
    items = table('ITEM.TXT', 'item')
    names = parse_table((ROOT / 'chapter01/source_texts/RESOURCE.TXT').read_bytes())
    # Every ITEM.TXT itemTypeUse row (241..263) is a battle-usable item; 303/304 carry add_hp/add_mp but are itemTypeOther.
    # The original gates on type == 1 alone: use 0x409e8e, use window 0x438d83, AI pick 0x40c1d0 (static-derived).
    codes = sorted((code for code, entry in items.items() if entry.get('type') == 'itemTypeUse'), key=int)
    definitions = {}
    for code in codes:
        source = items[code]
        definitions[code] = {'name':names[source['name']], 'heal_hp':int(source.get('add_hp',0)),
                             'heal_mp':int(source.get('add_mp',0)), 'restore_stamina':int(source.get('add_st',0)),
                             'cure_poison':int(source.get('cure_poison',0)), 'cure_paralysis':int(source.get('cure_paralysis',0)),
                             'cure_no_magic':int(source.get('cure_no_magic',0)), 'cure_weaken':int(source.get('cure_weaken',0)),
                             'local_attack':list(map(int,source['local_add_weapon_power'].split(','))) if 'local_add_weapon_power' in source else [],
                             'local_defense':list(map(int,source['local_add_defense'].split(','))) if 'local_add_defense' in source else []}
        definitions[code]['permanent']={key:list(map(int,source[field].split(','))) for key,field in [
            ('attack_power','global_add_weapon_power'),('magic_attack_power','global_add_magic_power'),
            ('defense','global_add_defense'),('speed','global_add_speed'),('resist_0','global_add_resist_earth'),
            ('resist_1','global_add_resist_water'),('resist_2','global_add_resist_air'),('resist_3','global_add_resist_fire'),
            ('resist_4','global_add_resist_mind')] if field in source}
    # Every character row's item1..8 (PLAYERS.TXT, then the authored rows) is that actor's starting bag: 0x44cb10
    # copies the whole template record, bag +0x138 included, for players and NPCs alike (runtime-measured,
    # original_ai_support.md「友军用药与模板背包」).
    template_bags = {row['code'].zfill(3): bag for row, bag in sorted(((row, [int(row.get(f'item{i}', 0)) for i in range(1, 9)])
                                                                      for row in character_rows()), key=lambda pair: int(pair[0]['code'])) if any(bag)}
    return {'schema':'hsl_first_battle_consumables.v4','evidence_tier':'resource-derived','inventory_capacity':8,
            'initial_inventory':template_bags,'items':definitions,
            'use_contract':'Restore HP/MP/ST, cure poison/paralysis/no-magic/weaken, or temporary attack/defense on self/living allied body-edge neighbor. Only useful successful proposals spend inventory/action; no-effect refusal and body-edge adjacency are explicit remake policies. Local boosts sample5..10 only when absent, then extend by3 capped9 without resampling existing strength. Actual draws commit once on the saved independent item stream, not during preview. Cures preserve unrelated status words; paralysis prevents the owner acting but another actor can cure it.',
            'permanent_contract':'Items253..261 add sampled positive source offsets, not STR/DEX/MIND/CON. Persist separately from immutable templates, equipment and temporary statuses. Intrinsic resistance caps at80 independently of displayed job/equipment resistance; previews never draw and no-effect rejection remains an explicit remake policy.',
            'inventory_contract':'Eight ordered slots,0 empty; remove and compact left. Every source character row starts with its own item1..8 (the original copies the whole template, NPCs included); EVEF instance items and the enemy carry roll fill the next empty slots; registering additional catalog items grants no extra initial items.'}


class ConsumablesTask(GeneratedFilesTask):
    name = 'consumables'
    family = 'items'
    inputs = ('content/imported/hsl/global/tables/', 'content/imported/hsl/chapter01/source_texts/RESOURCE.TXT', AUTHORED_CHARACTERS)
    outputs = (OUTPUT.as_posix(),)
    replaces = ('tools/hsl_consumables.py --check',)
    scripts = ('tools/hsltools/data/consumables.py',)

    def render(self, ctx: Context) -> dict[str, bytes]:
        return {OUTPUT.as_posix(): json_bytes(build())}

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        return 'CONSUMABLES_CHECK_PASS'


def tasks() -> list[ConsumablesTask]:
    return [ConsumablesTask()]
