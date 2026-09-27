"""Compile current equipment effects/eligibility; unsupported passives stay explicit.

build() joins ITEM.TXT, TYPE.H and the RESOURCE names into content/generated/hsl/equipment/
items.json; initial_physical_fields / initial_mobility_fields derive an actor's
equipment-adjusted starting rates. Registry task equipment_data (family items). Bodies
moved verbatim from the former hsl_equipment_data.py.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

from hsltools.data import json_bytes
from hsltools.registry import GeneratedFilesTask, Context
from hsltools.sources.tables import TABLES, RESOURCE_TXT, blocks, digest, parse_table

OUTPUT = Path('content/generated/hsl/equipment/items.json')
NAMES = RESOURCE_TXT
NUMERIC = {'add_weapon_hit': 'hit_rate', 'add_attack_power': 'attack',
           'add_magic_power': 'magic_attack', 'add_hp': 'max_hp', 'add_mp': 'max_mp',
           'add_speed': 'speed', 'add_defense': 'defense', 'add_miss_hit': 'avoid_hit_ratio',
           'add_attack_back': 'attack_back', 'add_weapon_dmgx2': 'attack_damagex2', 'add_move': 'move_point',
           'add_steal_ratio': 'steal_ratio'}
METADATA = {'code', 'name', 'cost', 'type', 'icon', 'get_ratio', 'important', 'use_job',
            'attack_range', 'attack_damage', 'hit_ratio', 'take_off', 'add_resist', 'magic_attack_type'}
STAMINA_FLAGS = {'st_x2': 0x40, 'no_addst': 0x400}
EXPERIENCE_FIELDS = {'exp_x2'}
# ITEM loader 0x447e7c: gold_x2 -> item flag 0x20, applied to live +0x18c and read by 0x40e2d0 (0x442720 state 2 doubles the gold).
GOLD_FIELDS = {'gold_x2'}
# ITEM loader 0x4477c0 -> item+0xa0 bits; 0x4092d0 (cancel), 0x409310 (status word incl. random pick), 0x409460 (mana).
WEAPON_EFFECTS = {'attack_cancel': 0x10000, 'attack_weaken': 0x20000, 'random_status_error': 0x40000, 'attack_nomagic': 0x80000,
                  'attack_paralysis': 0x100000, 'attack_poison': 0x200000, 'attack_decmp': 0x400000}
COMBAT_FIELDS = {'double_attack', 'action_twice', *WEAPON_EFFECTS}
RESOURCE_FIELDS = {'mp_use_half', 'hp_auto_restore', 'mp_auto_restore', 'hp_transfer_mp'}
CASTING_FIELDS = {'add_magic_hit', 'keep_status_good', 'avoid_poison', 'avoid_nomagic', 'avoid_weaken', 'avoid_paralysis', 'move_magic_use', 'add_attack_range'}
# itemTypeUse cure bits (loader 0x447f8f..0x447fe2 -> item+0xa0 0x80000000/0x40000000/0x20000000/0x10000000);
# consumables.py carries them into ItemUseRules, so they are not unsupported passives.
CURE_FIELDS = {'cure_poison', 'cure_no_magic', 'cure_paralysis', 'cure_weaken'}
RESISTS = {0: [0], 1: [1], 2: [2], 3: [3], 4: [4], 7: [0, 1, 2, 3, 4],
           8: [0, 1, 2, 3], 9: [1, 3], 10: [0, 3], 11: [2, 3], 12: [3, 4],
           13: [0, 1], 14: [1, 2], 15: [1, 4], 16: [0, 2], 17: [0, 4], 18: [2, 4]}


def weapon_magic(row, constants):
    """The original weapon triple is not an inclusive final-damage interval."""
    if 'magic_attack_type' not in row:
        return {'element': -1, 'low': 0, 'high': 0}
    parts = [part.strip() for part in row['magic_attack_type'].split(',')]
    if len(parts) != 3 or constants.get(parts[0], -1) not in range(6):
        raise ValueError('Unsupported weapon element: ' + row['code'])
    low, high = map(int, parts[1:])
    if not 0 <= low <= 10000 or not 0 <= high <= 10000:
        raise ValueError('Invalid weapon magnitude: ' + row['code'])
    return {'element': constants[parts[0]], 'low': low, 'high': high}


def initial_physical_fields(player, catalog):
    """Source base rates -> native zero defaults -> equipment working-rate adds (0x448840 +0x196/+0x19a/
    +0x19e/+0x1a2 = PLAYERS word or its default 12/0/12/8, then 0x448420 adds item +0x40/+0x44/+0x48/+0x4c).
    base_steal_ratio keeps the PLAYERS word itself: the job-up merge 0x4348f0 sums that word, not the work value."""
    base_steal_ratio = int(player.get('steal_ratio', 0))
    rates = {'avoid_hit_ratio': int(player.get('avoid_hit_ratio', 0)),
             'attack_back': int(player.get('attack_back', 0)) or 12,
             'attack_damagex2': int(player.get('attack_damagex2', 0)) or 8,
             'steal_ratio': base_steal_ratio or 12}
    for field in ['weapon_equip', 'head_equip', 'armor_equip', 'foot_equip', 'other1_equip', 'other2_equip']:
        code = player.get(field, '0')
        if code != '0':
            for key in rates: rates[key] += catalog[code]['effects'][key]
    rates['base_steal_ratio'] = base_steal_ratio
    weapon = catalog[player['weapon_equip']]['weapon_magic'] if int(player.get('weapon_equip', 0)) else {'element': -1, 'low': 0, 'high': 0}
    return dict(rates, weapon_magic_attack_type=weapon['element'],
                weapon_damage_variance_lo=weapon['low'], weapon_damage_variance_hi=weapon['high'])


def initial_mobility_fields(player, catalog):
    base = int(player.get('move_point', 0))
    bonus = sum(catalog[str(int(player[field]))]['effects']['move_point']
                for field in ['weapon_equip','head_equip','armor_equip','foot_equip','other1_equip','other2_equip']
                if int(player.get(field,0)))
    if not 0 <= base <= 10000: raise ValueError('Invalid source base movement')
    return {'base_move_point': base, 'move_point': max(0,min(12,base+bonus)),
            'move_point_evidence_tier': 'static-derived',
            'move_point_source': 'PLAYERS base + equipped ITEM.add_move, clamped 0..12 by native stat refresh'}


def job_mask(text, constants):
    result = 0
    for token in filter(None, (part.strip() for part in text.split(','))):
        code = int(token) if token.isdecimal() else constants[token]
        if code == 0:
            continue  # Original job lookup returns -1; no eligibility bit is added.
        if code == 1000:
            result = 0xffffffff
        elif code == 1001:
            result = 0xffffffff & ~(1 << 16) & ~(1 << 17)
        elif 80 <= code <= 100:
            result |= 1 << (code - 80)
        else:
            raise ValueError(f'Unsupported use_job token: {token}')
    return result


def build():
    constants = {key: int(value, 0) for key, value in re.findall(
        r'^\s*#define\s+(\w+)\s+(0x[0-9a-fA-F]+|\d+)\b',
        (TABLES/'TYPE.H').read_bytes().decode('cp950'), re.M)}
    names = parse_table(NAMES.read_bytes())
    items = {}
    for row in blocks((TABLES/'ITEM.TXT').read_bytes(), 'item'):
        code, kind = row['code'], constants[row['type']]
        effects = {key: 0 for key in NUMERIC.values()}
        for field, key in NUMERIC.items():
            effects[key] += int(row.get(field, 0))
        base = int(row.get('attack_damage', 0))
        if kind == 2:
            effects['attack'] += base
            effects['hit_rate'] += int(row.get('hit_ratio', 0))
        elif kind in (3, 4):
            effects['defense'] += base
        elif kind == 5:
            effects['speed'] += base
        unsupported = [key for key, value in row.items()
                       if key not in METADATA and key not in NUMERIC and key not in STAMINA_FLAGS and key not in EXPERIENCE_FIELDS and key not in GOLD_FIELDS and key not in COMBAT_FIELDS and key not in RESOURCE_FIELDS and key not in CASTING_FIELDS and key not in CURE_FIELDS and value != '0']
        weapon = weapon_magic(row, constants)
        if weapon['element'] != -1 and kind != 2:
            unsupported.append('magic_attack_type')
        effects['resist_by_type'] = {str(i): 0 for i in range(5)}
        if 'add_resist' in row:
            element, amount = (part.strip() for part in row['add_resist'].split(','))
            type_code = constants.get(element, -1)
            if type_code not in RESISTS:
                unsupported.append('add_resist')
            else:
                for index in RESISTS[type_code]:
                    effects['resist_by_type'][str(index)] += int(amount)
        if kind == 2 and row.get('attack_range') not in ('range0Cell', 'range1Cell', 'range2Cell', 'range3CellShoot', 'range4CellShoot', 'range5CellShoot',
                                                            'range3CellCircle', 'range3CellThrust', 'range5CellCircle'):
            unsupported.append('attack_range')
        items[code] = {'name': names[row['name']], 'icon': row['icon'], 'type_code': kind,
                       'job_mask': job_mask(row.get('use_job', ''), constants),
                       'unequip_blocked': int(row.get('take_off', 0)) != 0,
                       'important': int(row.get('important', 0)) != 0,
                       'mp_use_half': int(row.get('mp_use_half', 0)) != 0,
                       'hp_auto_restore': int(row.get('hp_auto_restore', 0)) != 0,
                       'mp_auto_restore': int(row.get('mp_auto_restore', 0)) != 0,
                       'hp_transfer_mp': int(row.get('hp_transfer_mp', 0)) != 0,
                       'action_twice': int(row.get('action_twice', 0)) != 0,
                       'experience_double': int(row.get('exp_x2', 0)) != 0,
                       'gold_double': int(row.get('gold_x2', 0)) != 0,
                       'double_attack': int(row.get('double_attack', 0)) != 0,
                       'weapon_effect_flags': sum(bit for key, bit in WEAPON_EFFECTS.items() if int(row.get(key, 0))),
                       'move_magic_use': int(row.get('move_magic_use', 0)) != 0,
                       'add_attack_range': int(row.get('add_attack_range', 0)) != 0,
                       'magic_hit_bonus': int(row.get('add_magic_hit', 0)),
                       'status_effect_flags': sum(bit for field, bit in [('keep_status_good', 0x80), ('avoid_poison', 0x800000), ('avoid_nomagic', 0x1000000), ('avoid_weaken', 0x2000000), ('avoid_paralysis', 0x4000000)] if int(row.get(field, 0))),
                       'stamina_effect_flags': sum(bit for field, bit in STAMINA_FLAGS.items() if int(row.get(field, 0))),
                       'attack_range': row.get('attack_range', ''), 'effects': effects, 'weapon_magic': weapon,
                       'supported': kind in range(2, 7) and not unsupported,
                       'unsupported_fields': sorted(unsupported)}
    return {'schema': 'hsl_equipment_items.v1', 'evidence_tier': 'static-derived',
            'table_evidence_tier': 'resource-derived',
            'sources': {str(path): digest(path.read_bytes()) for path in (TABLES/'ITEM.TXT', TABLES/'TYPE.H', NAMES)},
            'evidence': 'docs/evidence_packets/static_reverse/original_inventory_equipment.md',
            'items': items,
            'limits': ['Numeric effects, st_x2/no_addst, exp_x2, gold_x2, double_attack/action_twice, mp_use_half, HP/MP automatic restoration, HP transfer, magic hit/protection, moved casting, normal-weapon range extension, ordinary-series cancellation, the 0x409310 status word (weaken/no-magic/paralysis/poison and the random_status_error pick), weaken/poison/no-magic/paralysis protection and consumable cure bits have independent live contracts; other nonzero fields reject equip.',
                       'Live base-stat refresh supports independently proven job80/85/90/94. Source job eligibility still restricts individual equipment.',
                       'Unknown fields and unrecognized element/resistance constants remain unsupported, not silently discarded.']}


class EquipmentDataTask(GeneratedFilesTask):
    name = 'equipment_data'
    family = 'items'
    inputs = ('content/imported/hsl/global/tables/', RESOURCE_TXT.as_posix())
    outputs = (OUTPUT.as_posix(),)
    replaces = ('tools/hsl_equipment_data.py --check',)
    scripts = ('tools/hsltools/data/equipment.py',)

    def render(self, ctx: Context) -> dict[str, bytes]:
        return {OUTPUT.as_posix(): json_bytes(build())}

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        return f'EQUIPMENT_DATA_PASS items={len(json.loads(rendered[OUTPUT.as_posix()])["items"])}'


def tasks() -> list[EquipmentDataTask]:
    return [EquipmentDataTask()]
