"""Source025 emperor template (the level-52 boss 法蘭克): content/generated/hsl/actors/025.json.

Registry task emperor_data (family actors). PLAYERS row 025 (jobMagician 90, pmEnemy) refreshed
through the shared native 0x448840 recipe (hsltools.data.first_battle_formation.actor_templates)
with its equipped 霸者之劍 5 / 水晶胸鎧 126 / 鋼鐵之靴 182, checked against the static probe
packet docs/evidence_packets/static_reverse/second_battle_template_stats.json (the 025 equipped
refresh: 91 HP / 24 MP / attack 58 / defense 46 / speed 16 / hit 92 / magic 65). The template is
unplaced; level_battle:52 places it from the EVEF record and the STORY052 opening walk. The
initial level is the fixed remake baseline — native level-52 initialization is unresolved
(provisional), the same limit the former second_battle.json carried.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from hsltools.data import json_bytes
from hsltools.data.first_battle_formation import actor_templates
from hsltools.native.sources import sources
from hsltools.registry import CheckFailed, Context, GeneratedFilesTask

ACTOR = '025'
OUT = Path('content/generated/hsl/actors/025.json')
STATS = Path('docs/evidence_packets/static_reverse/second_battle_template_stats.json')
TABLES = Path('content/imported/hsl/global/tables')
COMBAT_KEYS = ['live_attack_damage', 'live_hit_ratio', 'live_defense', 'avoid_hit_ratio', 'str', 'dex', 'attack_back', 'mind', 'con',
               'live_magic_attack', 'resist_by_type', 'attack_damagex2', 'steal_ratio', 'base_steal_ratio',
               'weapon_magic_attack_type', 'weapon_damage_variance_lo', 'weapon_damage_variance_hi']
# probe field -> refreshed template field
PROBE_FIELDS = {'max_hp': 'max_hp', 'max_mp': 'max_mp', 'attack': 'live_attack_damage', 'defense': 'live_defense',
                'speed': 'live_speed', 'hit_rate': 'live_hit_ratio', 'magic_attack': 'live_magic_attack'}


def build() -> dict:
    packet = json.loads(STATS.read_text(encoding='utf-8'))
    for name, expected in packet['inputs_sha256'].items():
        actual = hashlib.sha256((TABLES / name).read_bytes()).hexdigest()
        if actual != expected:
            raise ValueError(f'{STATS}: {name} changed since the probe ({actual} != {expected}); re-run the native stat probe')
    source = actor_templates([ACTOR])[ACTOR]
    probe = packet['actors'][ACTOR]['equipped']
    mismatch = {key: (probe[key], source[field]) for key, field in PROBE_FIELDS.items() if int(probe[key]) != int(source[field])}
    if mismatch:
        raise ValueError(f'source025 refresh differs from the static probe packet: {mismatch}')
    players, _, _ = sources()
    row = players[ACTOR]
    actor = {
        'id': 'emperor025', 'actor_id': ACTOR, 'class_id': 'Enemy' + ACTOR,
        'battle_actor_role': 'enemy_ai', 'player_commandable': False,
        'hp': source['max_hp'], 'max_hp': source['max_hp'], 'mp': source['max_mp'], 'max_mp': source['max_mp'],
        'growth_profile': source['growth_profile'],
        'hit_bonus_accum': 0, 'no_attack': source['no_attack'],
        'status_flags': 0, 'status_counters': {'poison': 0, 'paralysis': 0, 'no_magic': 0},
        'base_move_point': source['base_move_point'], 'move_point': source['move_point'],
        'move_point_evidence_tier': source['move_point_evidence_tier'], 'move_point_source': source['move_point_source'],
        'live_speed': source['live_speed'], 'action_ready': True, 'weapon_code': int(row['weapon_equip']),
        'equipment': source['equipment'],
        'combat_profile': {key: source[key] for key in COMBAT_KEYS},
        'coord': [0, 0],
        'position_evidence_tier': 'provisional', 'position_source': {'kind': 'unplaced_source_template'},
        'position_note': 'The assembling scenario must replace coord with a reviewed placement (level_battle:52: EVEF record 5 plus the STORY052 opening walk).',
        'vitals_evidence_tier': 'provisional',
        'vitals_source': 'Native 0x448840 synthetic equipped template; native level-52 initialization remains unresolved',
        'combat_stats_evidence_tier': 'provisional',
        'combat_stats_source': 'Native job90 refresh with source mode, derived resists and equipped bonuses; fixed initial-level policy remains separate',
        'live_speed_evidence_tier': 'provisional',
        'live_speed_source': 'Native 0x448840 synthetic equipped template',
        'attack_range_evidence': {'evidence_tier': 'resource-derived', 'source': 'This actor weapon_equip -> ITEM.attack_range -> RANGE'},
    }
    return {'schema': 'hsl_source_actor_template.v1', 'actor': actor, 'evidence': STATS.as_posix(),
            'source': {'evidence_tier': 'static-derived', 'probe_entry': packet['entry'], 'exe_sha256': packet['exe_sha256'],
                       'players_row': ACTOR, 'job': row['job'], 'mode': row['mode'], 'equipped_probe': probe},
            'limits': ['Unplaced source template. Battle assembly supplies position, battle role and the EVEF instance words (level_battle:52).',
                       'Fixed initial level: native level-52 boss initialization is not measured (provisional).',
                       *packet['limits']]}


class EmperorDataTask(GeneratedFilesTask):
    name = 'emperor_data'
    family = 'actors'
    inputs = ('content/imported/hsl/global/tables/', STATS.as_posix(), 'content/generated/hsl/roles/profiles.json',
              'content/generated/hsl/equipment/items.json')
    outputs = (OUT.as_posix(),)
    replaces = ()  # the level-52 boss template moved out of the retired hsl_second_battle_scenario.py path
    scripts = ('tools/hsltools/data/emperor.py', 'tools/hsltools/data/first_battle_formation.py', 'tools/hsltools/data/role_profiles.py')

    def render(self, ctx: Context) -> dict[str, bytes]:
        try:
            template = build()
        except ValueError as error:
            raise CheckFailed(f'{self.name}: {error}') from error
        return {OUT.as_posix(): json_bytes(template)}

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        actor = json.loads(rendered[OUT.as_posix()])['actor']
        return f'EMPEROR_DATA_PASS actor={ACTOR} max_hp={actor["max_hp"]} attack={actor["combat_profile"]["live_attack_damage"]} job={actor["growth_profile"]["job_code"]}'


def tasks() -> list[EmperorDataTask]:
    return [EmperorDataTask()]
