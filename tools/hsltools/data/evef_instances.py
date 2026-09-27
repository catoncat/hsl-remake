"""Per-level table of the EVEF actor instance words the original applies on top of the
PLAYERS template (items, per-unit AI strategy overrides, fixed run points), so the
behaviour difference between an actor code and its placed instances can be reviewed
without reading level*.BIN.

Registry task evef_instances (family static): output
content/generated/hsl/development/evef_instances.json, rebuilt from every tracked
battle seed (hsltools/levels/seed.py `_actor_instance` decodes the words; the
install callback is 0x42bd50, docs/evidence_packets/static_reverse/original_ai_navigation.md).
The table is review data: the runtime reads the same words from the unit's
`evef_instance` in content/battles/*.json.
"""
from __future__ import annotations

import json
from collections import Counter
from pathlib import Path

from hsltools.data import json_bytes
from hsltools.levels.seed import ACTOR_INSTANCE_OVERRIDE_FIELDS
from hsltools.paths import ROOT
from hsltools.registry import Context, GeneratedFilesTask

SEEDS = ROOT / 'content/generated/hsl/chapter01'
OUTPUT = 'content/generated/hsl/development/evef_instances.json'
RUNTIME_APPLIED = ('gold', 'find_type', 'find_flag', 'find_range', 'ai_call_range', 'ai_fixed', 'ai_check_dying', 'ai_check_hp',
                   'ai_help_otherhp', 'ai_help_status', 'ai_help_attack', 'ai_lock', 'ai_att_special', 'ai_att_magic',
                   'wait_round', 'fixed_point', 'level_adjust_range', 'level_adjust_disp_range', 'stamina')
RECORDED_ONLY = tuple(name for name in ACTOR_INSTANCE_OVERRIDE_FIELDS.values() if name not in RUNTIME_APPLIED)


def seed_paths() -> list[Path]:
    return sorted(SEEDS.glob('battle[0-9][0-9][0-9]_seed.json'))


def build() -> dict:
    levels: dict[str, dict] = {}
    field_counts: Counter[str] = Counter()
    units_with_items = 0
    for path in seed_paths():
        seed = json.loads(path.read_text(encoding='utf-8'))
        rows = []
        for record in seed['placements']['records']:
            instance = record.get('actor_instance')
            if not instance:
                continue
            fields = record.get('object_data_fields', {})
            row = {
                'record_index': record['record_index'],
                'object_code': record['object_code'],
                'object_name': record.get('object_name'),
                'actor_id': str(fields['obj_Data7']).zfill(3) if 'obj_Data7' in fields else None,
                'sid_token': fields.get('obj_Data6'),
                'placement_cell': [value // 32 for value in record['placement_xy_candidate']],
            }
            if instance.get('items'):
                row['items'] = list(instance['items'])
                units_with_items += 1
            if instance.get('overrides'):
                row['overrides'] = dict(instance['overrides'])
                field_counts.update(instance['overrides'].keys())
            if instance.get('unknown_override_words'):
                row['unknown_override_words'] = dict(instance['unknown_override_words'])
            rows.append(row)
        if rows:
            levels[str(seed['level'])] = {
                'level': seed['level'],
                'level_sha256': seed['sources']['level']['sha256'],
                'units': rows,
                'wait_round_units': sum('wait_round' in row.get('overrides', {}) for row in rows),
                'fixed_point_units': sum('fixed_point' in row.get('overrides', {}) for row in rows),
                'item_units': sum('items' in row for row in rows),
            }
    return {
        'schema': 'hsl_evef_actor_instances.v1',
        'evidence_tier': 'resource-derived',
        'decoder': 'tools/hsltools/levels/seed.py _actor_instance (install callback 0x42bd50, jump table 0x42c0a8)',
        'evidence': 'docs/evidence_packets/static_reverse/original_ai_navigation.md',
        'runtime_applied_fields': list(RUNTIME_APPLIED),
        'recorded_only_fields': list(RECORDED_ONLY),
        'totals': {
            'levels': len(levels),
            'units': sum(len(entry['units']) for entry in levels.values()),
            'units_with_items': units_with_items,
            'override_fields': dict(sorted(field_counts.items())),
        },
        'levels': levels,
        'limits': [
            'Words 0x10..0x2C are item codes compacted into the first empty slots after the PLAYERS inventory; zeros are skipped.',
            'wait_round seeds the live wait counter (0x43f603 branch); a later STORY/WINFAIL wait token replaces it like the original setter.',
            'fixed_point: object flag 0x4000, ai_fixed 8 and the point as home; the guard walks toward it each turn without a legal target and is released on arrival. The route approximation is documented in the packet.',
            'gold (word 0 -> live +0x98) is the kill gold BattleRewardRules.kill_gold reads over the PLAYERS template; the six equipment words are recorded but not applied (0 units carry them).',
        ],
    }


class EvefInstancesTask(GeneratedFilesTask):
    name = 'evef_instances'
    family = 'static'
    outputs = (OUTPUT,)
    replaces = ()  # born after the migration: no historical command to replace
    scripts = ('tools/hsltools/data/evef_instances.py', 'tools/hsltools/levels/seed.py')

    def __init__(self) -> None:
        self.inputs = tuple(path.relative_to(ROOT).as_posix() for path in seed_paths())

    def render(self, ctx: Context) -> dict[str, bytes]:
        return {OUTPUT: json_bytes(build())}

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        table = json.loads(rendered[OUTPUT])
        totals = table['totals']
        tag = 'EVEF_INSTANCES_CHECK_PASS' if mode == 'check' else 'EVEF_INSTANCES_BUILD_PASS'
        fields = totals['override_fields']
        return (f"{tag} levels={totals['levels']} units={totals['units']} items={totals['units_with_items']} "
                f"wait_round={fields.get('wait_round', 0)} fixed_point={fields.get('fixed_point', 0)}")


def tasks() -> list[EvefInstancesTask]:
    return [EvefInstancesTask()]
