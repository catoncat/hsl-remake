"""Rebuild/check level-51 actors from EVEF placements; never infer NPC opening paths.

Registry task first_battle_formation (family scenarios): writes content/battles/first_battle.json from the
hand-written base content/authored/battles/first_battle_base.json (everything a person decided: scenario
rules, resources, notes, and one unit template per actor holding only the reviewed fields — role,
commandability, class, weapon code, attack-range note — with the imported fields left null so the key
order is kept) plus the source formation (playable_units and grid projection), and writes its development
objective (content/generated/hsl/development/first_battle_objectives.json); check is byte-for-byte
against the tracked files. The generator never reads its own output, so the public repository builds it
from an empty content tree (docs/internal/records/OPEN_SOURCE_PLAN.md §8). first_battle.json is the
reviewed template roster the trial generators and the pure-loop mechanics tests build on (rule_adapter
development_battle); the playable first battle is content/battles/battle_051.json (level_battle:51).
actor_templates is shared by the trial generators. Bodies moved verbatim from the former hsl_first_battle_formation.py.
"""
import copy
import json
import re
from pathlib import Path
from hsltools.data import json_bytes
from hsltools.data.equipment import build as equipment_data, initial_physical_fields, initial_mobility_fields
from hsltools.data.role_profiles import build as role_data
from hsltools.paths import ROOT
from hsltools.registry import Context, GeneratedFilesTask
from hsltools.sources.tables import authored_characters, override_rows, parse_table

# The level-51 seed's EVEF placement records (battle_seed:51, from the PAK): the same records, order and
# coordinates the payload inspector's chapter01/map_objects.json lists, without that importer's input.
PLACEMENTS = ROOT / 'content/generated/hsl/chapter01/battle051_seed.json'
STORY = ROOT / 'content/imported/hsl/chapter01/source_texts/STORY051.TXT'
SCENARIO = ROOT / 'content/battles/first_battle.json'
BASE = ROOT / 'content/authored/battles/first_battle_base.json'
OBJECTIVES = ROOT / 'content/generated/hsl/development/first_battle_objectives.json'
# The fixture's development objective: the legacy provisional escape cell the pure-loop tests
# walk Leonard onto. The playable battle derives its arrival cell from WINFAIL051 instead.
FIXTURE_ESCAPE_ZONE = [[14, 10]]
ACTORS = {6: '001', 99: '021', 98: '026', 96: '023', 97: '024'}


def actor_templates(actor_codes=None):
    roles = role_data()['actors']
    def table(name, section):
        raw = (ROOT / 'content/imported/hsl/global/tables' / name).read_bytes().decode('cp950')
        entries = []
        for block in raw.split('[' + section + ']')[1:]:
            entries.append({k: v.strip() for k, v in re.findall(r'^\s*(\w+)\s*=\s*([^;\r\n]+)', block, re.M)})
        return {entry['code']: entry for entry in override_rows(name, entries) if 'code' in entry}
    players = table('PLAYERS.TXT', 'character')
    # Authored characters (content/authored/roles/characters.json) are templates like any PLAYERS row.
    players.update({row['code']: row for row in authored_characters()})
    items = table('ITEM.TXT', 'item')
    names = parse_table((ROOT / 'content/imported/hsl/chapter01/source_texts/RESOURCE.TXT').read_bytes())
    catalog = equipment_data()['items']
    result = {}
    for actor in (ACTORS.values() if actor_codes is None else actor_codes):
        player = players[str(int(actor))]
        # The optional numeric reader preserves the loader's zero default.
        # This is independently checked, not a replacement rule for bad values.
        if 'status' not in player:
            from hsltools.probes.mobile_source import PACKET as optional_packet, check as check_optional
            check_optional(json.loads(optional_packet.read_text()))
        if int(player.get('status','0'), 0) != 0:
            raise ValueError('Initial nonzero status needs explicit original counter evidence: ' + actor)
        vitals = roles[actor]['initial']
        equipment = []
        for field, slot in [('weapon_equip', 'weapon'), ('head_equip', 'head'), ('armor_equip', 'armor'),
                            ('foot_equip', 'foot'), ('other1_equip', 'accessory1'), ('other2_equip', 'accessory2')]:
            item_code = player.get(field, '0')
            if item_code != '0':
                equipment.append({'slot': slot, 'item_code': int(item_code), 'name': names[items[item_code]['name']]})
        result[actor] = {'live_speed': vitals['speed'], 'str': int(player['str']), 'dex': int(player['dex']),
                         'mind': int(player['mind']), 'con': int(player['con']),
                         'max_hp': vitals['max_hp'], 'max_mp': vitals['max_mp'], 'equipment': equipment,
                         'live_attack_damage': vitals['attack'], 'live_defense': vitals['defense'],
                         'live_hit_ratio': vitals['hit_rate'], 'live_magic_attack': vitals['magic_attack'],
                         'resist_by_type': vitals['resist_by_type'],
                         'growth_profile': roles[actor]['profile']}
        result[actor].update(initial_physical_fields(player, catalog))
        result[actor].update(initial_mobility_fields(player, catalog))
        result[actor]['no_attack'] = bool(int(player.get('no_attack', 0)))
    return result


def formation():
    # PlayerInstall and the enemy initializer both use (position & ~31) + 16.
    # Runtime stores grid cells and adds the same half-cell when drawing actors.
    story = STORY.read_text()
    match = re.search(r'^action\s*=\s*actWalkDispWait,SID_PLAYER0,1,(-?\d+),(-?\d+),2', story, re.M)
    if match is None:
        raise ValueError('missing Leonard opening displacement')
    delta = [int(value) for value in match.groups()]
    templates = actor_templates()
    counts = {}
    result = []
    for placement in json.loads(PLACEMENTS.read_text(encoding='utf-8'))['placements']['records']:
        code = placement['object_code']
        if code not in ACTORS:
            continue
        actor = ACTORS[code]
        counts[actor] = counts.get(actor, 0) + 1
        source = list(placement['placement_xy_candidate'])
        world = [(value & ~31) + 16 for value in source]
        if actor == '001':
            world = [value + shift for value, shift in zip(world, delta)]
        result.append({
            'id': 'leonard' if actor == '001' else f'enemy{actor}_{counts[actor]}',
            'actor_id': actor,
            'live_speed': templates[actor]['live_speed'],
            'hp': templates[actor]['max_hp'],
            'max_hp': templates[actor]['max_hp'],
            'status_flags': 0,
            'status_counters': {'poison': 0, 'paralysis': 0, 'no_magic': 0},
            'equipment': templates[actor]['equipment'],
            'no_attack': templates[actor]['no_attack'],
            **{key:templates[actor][key] for key in ['base_move_point','move_point','move_point_evidence_tier','move_point_source']},
            'vitals_evidence_tier': 'provisional',
            'vitals_source': 'Native 0x448840 probe on unadjusted PLAYERS template; adopted remake baseline, not original battle-level NPC initialization',
            'combat_profile': {key: templates[actor][key] for key in ['str', 'dex', 'mind', 'con', 'live_attack_damage', 'live_defense', 'live_hit_ratio', 'live_magic_attack', 'resist_by_type', 'avoid_hit_ratio', 'attack_back', 'attack_damagex2', 'base_steal_ratio', 'steal_ratio', 'weapon_magic_attack_type', 'weapon_damage_variance_lo', 'weapon_damage_variance_hi']},
            'combat_stats_evidence_tier': 'provisional',
            'combat_stats_source': 'Native job80/90/94 refresh including source mode, all derived resists and current equipment. NPC level adjustment remains an explicit fixed-template policy.',
            'live_speed_evidence_tier': 'provisional',
            'live_speed_source': 'Native job/dex, base speed and equipment formula on unadjusted PLAYERS templates; NPC level adjustment remains unresolved',
            'coord': [value // 32 for value in world],
            'position_evidence_tier': 'static-derived',
            'position_source': {'evef_record_index': placement['record_index'],
                                'object_code': code, 'placement_world': source},
            'position_note': ('PlayerInstall centered placement plus STORY051 (0,-96); opening starts before that displacement'
                              if actor == '001' else
                              'Enemy initializer centered level placement; NPC moves before first player control remain unresolved'),
        })
        result[-1]['growth_profile'] = copy.deepcopy(templates[actor]['growth_profile'])
        result[-1]['mp'] = templates[actor]['max_mp']
        result[-1]['max_mp'] = templates[actor]['max_mp']
    # Remake choice: preserve EVEF order; native reserved registration slots differ.
    return result


def scenario_bytes() -> bytes:
    """The hand-written base with the source formation applied."""
    scenario = json.loads(BASE.read_text())
    expected = formation()
    templates = {}
    for unit in scenario['playable_units']:
        templates.setdefault(unit['actor_id'], unit)
    scenario['playable_units'] = []
    for source in expected:
        unit = copy.deepcopy(templates[source['actor_id']])
        combat = unit['combat_profile']
        combat.update(source['combat_profile'])
        unit.update(source)
        unit['combat_profile'] = combat
        scenario['playable_units'].append(unit)
    scenario['view']['grid_projection'].update(
        origin=[0, 0], cell_size=[32, 32], evidence_id='actor_placement_initialization',
        evidence_tier='static-derived', provisional=False)
    return json_bytes(scenario)


class FirstBattleFormationTask(GeneratedFilesTask):
    name = 'first_battle_formation'
    family = 'scenarios'
    inputs = ('content/imported/hsl/global/tables/', 'content/imported/hsl/chapter01/source_texts/RESOURCE.TXT',
              PLACEMENTS.relative_to(ROOT).as_posix(), STORY.relative_to(ROOT).as_posix(),
              'content/generated/hsl/roles/profiles.json', 'content/generated/hsl/equipment/items.json',
              BASE.relative_to(ROOT).as_posix())
    outputs = (SCENARIO.relative_to(ROOT).as_posix(), OBJECTIVES.relative_to(ROOT).as_posix())
    replaces = ('tools/hsl_first_battle_formation.py --check',)
    scripts = ('tools/hsltools/data/first_battle_formation.py',)

    def render(self, ctx: Context) -> dict[str, bytes]:
        return {self.outputs[0]: scenario_bytes(),
                self.outputs[1]: json_bytes({'schema': 'hsl_development_objectives.v1', 'escape_zone': FIXTURE_ESCAPE_ZONE})}

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        return f'FIRST_BATTLE_FORMATION_CHECK_PASS actors={len(json.loads(rendered[self.outputs[0]])["playable_units"])}'


def tasks() -> list[FirstBattleFormationTask]:
    return [FirstBattleFormationTask()]
