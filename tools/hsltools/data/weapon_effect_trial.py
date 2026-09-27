"""Author a manual weapon-effects trial using existing source actors and rules.

The added health and starting inventory are declared development choices. Neither
formal battle nor any original table is changed by this generator.

Registry task weapon_effect_trial (family trials): outputs content/battles/weapon_effect_trial.json and
content/generated/hsl/development/weapon_effect_inventory.json. Bodies moved verbatim from the former hsl_weapon_effect_trial.py.
"""
import copy
import json
from pathlib import Path

from hsltools.data import json_bytes
from hsltools.data.equipment import build as equipment_data
from hsltools.data.large_actor import build as large_data
from hsltools.model.jobs import calculate
from hsltools.registry import Context, GeneratedFilesTask

SCENARIO = Path('content/battles/weapon_effect_trial.json')
INVENTORY = Path('content/generated/hsl/development/weapon_effect_inventory.json')


def build():
    large, trial = large_data()
    catalog = equipment_data()['items']
    trial.update(id='weapon_effect_development_trial', title='武器效果 · 交鋒演練',
                 development_note='Authored source039 trial: supplies poison/cancel/protection equipment and medicine; extra HP sustains player experimentation. Not original encounter placement, loadout or campaign balance.')
    leonard = copy.deepcopy(trial['playable_units'][0])
    friend = copy.deepcopy(trial['playable_units'][1])
    enemy = copy.deepcopy(large)
    enemy.update(coord=[16, 20])
    for actor, bonus, weapon in [(leonard, 180, leonard['weapon_code']), (friend, 240, 35), (enemy, 400, 37)]:
        actor['growth_profile']['source']['hit_point'] += bonus
        actor['equipment'] = [s for s in actor['equipment'] if s['slot'] != 'weapon']
        actor['equipment'].insert(0, dict(slot='weapon', item_code=weapon, name=catalog[str(weapon)]['name']))
        actor['weapon_code'] = weapon
        values = calculate(actor['growth_profile'], actor['combat_profile'], 1,
                           [s['item_code'] for s in actor['equipment']], catalog, 100000, 100000, actor['base_move_point'])
        for key in ['max_hp', 'max_mp', 'move_point']:
            actor[key] = values[key]
        actor.update(hp=values['current_hp'], mp=values['current_mp'], live_speed=values['speed'])
        actor['combat_profile'].update(live_attack_damage=values['attack'], live_defense=values['defense'],
                                      live_hit_ratio=values['hit_rate'], live_magic_attack=values['magic_attack'],
                                      resist_by_type=values['resist_by_type'])
        actor['vitals_evidence_tier'] = 'provisional'
        actor['vitals_source'] = 'Source job refresh with explicitly added trial HP; source attributes and level1 unchanged.'
    friend['growth_profile']['allocation'] = 'manual'
    trial['playable_units'] = [leonard, friend, enemy]
    trial['resources']['consumables'] = 'res://' + INVENTORY.as_posix()
    trial['unresolved_semantics'] = [trial['development_note'],
        'Default campaign grants, weapon probabilities, RNG and underlying battle/queue/terminal rules are unchanged.']
    inventory = json.loads(Path('content/imported/hsl/chapter01/consumables.json').read_text())
    inventory['development_note'] = trial['development_note']
    inventory['initial_inventory']['039'] = [29, 35, 37, 229, 227, 246, 248, 0]
    inventory['initial_inventory']['001'] = [144, 229, 241, 246, 248, 0, 0, 0]
    return trial, inventory


class WeaponEffectTrialTask(GeneratedFilesTask):
    name = 'weapon_effect_trial'
    family = 'trials'
    inputs = ('content/generated/hsl/equipment/items.json', 'content/battles/first_battle.json', 'content/imported/hsl/chapter01/consumables.json',
              'docs/evidence_packets/static_reverse/original_large_actor.json')
    outputs = (SCENARIO.as_posix(), INVENTORY.as_posix())
    replaces = ('tools/hsl_weapon_effect_trial.py --check',)
    scripts = ('tools/hsltools/data/weapon_effect_trial.py', 'tools/hsltools/data/large_actor.py')

    def render(self, ctx: Context) -> dict[str, bytes]:
        trial, inventory = build()
        return {SCENARIO.as_posix(): json_bytes(trial), INVENTORY.as_posix(): json_bytes(inventory)}

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        return 'WEAPON_TRIAL_DATA_PASS formal_grants_unchanged=True'


def tasks() -> list[WeaponEffectTrialTask]:
    return [WeaponEffectTrialTask()]
