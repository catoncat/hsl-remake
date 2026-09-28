"""Derive the one unit dictionary contract: content/schema/unit.schema.json.

The Python assemblers (hsltools/levels/battle.py) and the GDScript runtime
(BattleScenario.units, BattlePlayLoop.create, CampaignCarryRules.apply) used to
assume the same unit shape independently; two real bugs came from that drift
(job_up_templates read at the wrong level, equipment written as an int list where the
runtime expects six {slot, item_code, name} entries). The schema describes what the
data is now — every tracked unit must pass — and both sides validate against it
(hsltools/schema/validate.py, game/sim/UnitSchema.gd).

Sources of the description: every unit the level_battle assembler renders (playable_units
and script_actor_templates[*].actor of all registered levels, rendered in-process so
the schema never reads its own consumers' tracked outputs), every hand-curated
content/battles/*.json scenario with playable_units, the source actor templates
content/generated/hsl/actors/*.json, plus RUNTIME_PROPERTIES for keys the runtime adds
after loading. Every top-level key is classified explicitly: RULE_KEYS (a rule module
reads it — required where every observed unit has it), PROVENANCE_KEYS (evidence ledgers
that pass through untouched — never required, so an authored unit needs none of them)
and RUNTIME_PROPERTIES; an unclassified observed key fails the build. Enums are emitted
for the closed vocabularies listed in ENUM_PATHS and for every *evidence_tier key
(CONTEXT.md tiers plus `authored` for content written for the remake).

Registry task unit_schema: `hsl generate unit_schema` after changing what the assembler
writes to a unit, then `hsl generate level_battle`; `hsl check unit_schema` is
regen-and-compare like every generated file.
"""
from __future__ import annotations

import json
from pathlib import Path

from hsltools.paths import ROOT
from hsltools.registry import GeneratedFilesTask, Context
from hsltools.schema.validate import error, json_type

SCHEMA_PATH = 'content/schema/unit.schema.json'
SCHEMA_ID = 'hsl_unit.v1'
ACTOR_TEMPLATES = 'content/generated/hsl/actors/'
# CONTEXT.md evidence tiers plus the tier of content authored for the remake (no original
# to compare against); observed legacy composite labels are appended per key.
AUTHORED_TIER = 'authored'
EVIDENCE_TIERS = ('resource-derived', 'static-derived', 'runtime-measured', 'user-confirmed',
                  'user-hypothesis', 'provisional', 'negative-evidence', AUTHORED_TIER)
# Top-level unit keys a rule module reads (key → the first consumer, by module). A key is
# required only when it is here and every tracked unit carries it; the ones marked
# optional are read with a default where present.
RULE_KEYS: dict[str, str] = {
    'id': 'BattlePlayLoop.unit_ref / CoreTurnQueue.rebuild slot identity',
    'actor_id': 'ActorInitializationRules.prepare (skill book, ai profile, progression, inventory rows)',
    'battle_actor_role': 'ActorRoleRules / ActorTraversalRules (role-implied side) / BattleRewardRules eligibility',
    'player_commandable': 'BattlePlayLoop menus and hand-off, WinfailScenarioRules, TreasureRules',
    'coord': 'BattleScenario.units → ActorTraversalRules.placement_error (Vector2i cell)',
    'hp': 'CoreCombatRules.input_error / BattlePresenceRules.living',
    'max_hp': 'CoreCombatRules.input_error / ProgressionRules refresh',
    'mp': 'SkillResourceRules (magic cost) / CoreCombatRules.input_error',
    'max_mp': 'JobStatsRules / ResourceRecoveryRules / CoreCombatRules.input_error',
    'live_speed': 'CoreTurnQueue.rebuild (queue order) / StatMagicRules',
    'action_ready': 'CoreTurnQueue.rebuild / BattlePresenceRules',
    'move_point': 'MobilityRules.prepare / ActorTraversalRules',
    'base_move_point': 'MobilityRules.prepare / ProgressionRules refresh / JobUpRules',
    'no_attack': 'AINavigationRules / WinfailScenarioRules / SpecialDamageRules (attack-less units)',
    'weapon_code': 'BattlePlayLoop._load_attack_ranges (weapon_ranges) / PositionCapabilityRules',
    'equipment': 'EquipmentRules / ProgressionRules refresh / StaminaRules / MobilityRules',
    'combat_profile': 'CoreCombatRules.input_error (live attack／defense／hit／magic, resist_by_type)',
    'growth_profile': 'ProgressionRules.refresh_input_error / JobStatsRules / EntryGrowthRules',
    'status_flags': 'StatusEffectRules.input_error / StatusApplicationRules',
    'status_counters': 'StatusEffectRules.input_error / TurnEndRules decay',
    # optional rule inputs
    'class_id': 'ProgressionRules / ScriptActorCreationRules / WinfailScenarioRules class tokens (optional)',
    'evef_instance': 'AINavigationRules / ReinforcementGrowthRules / ActorInitializationRules per-unit EVEF words (optional)',
    'script_insert': 'InitialRosterGrowthRules.prepare → ReinforcementGrowthRules.prepare insertion words of a pre-baked STORY actInsertObject: adjust_level = actSetPrevInsertObjectAdjustLevel [range, disp range] (optional; absent = the PLAYERS template halves)',
    'opening_birth': 'InitialRosterGrowthRules.prepare birth order of the entry level adjustment: story_insert = 1-based STORY actor insert number (absent = EVEF, frame 1), adjust_all_level = alive at actAdjustAllPlayerLevel (optional)',
    'install_if_carried': 'ConditionalPartyRules.apply (optional; encounter slots fielded only when carried)',
    'source_object_kind': 'ScriptActorCreationRules / TreasureRules / ReinforcementGrowthRules (optional)',
    'undead': 'WinfailScenarioRules actCheck tokens (optional)',
    'player_mode': 'ActorRoleRules.side_mask (installed +0x28 side bits: hostile／same_side／counts_as_*; optional, role-implied side when absent)',
    'birth_player_mode': 'InitialRosterGrowthRules.prepare_player birth refresh side (the constructor\'s +0x28 when level assembly pre-baked a later scripted mode change into player_mode: level 3 漢克斯 born pmPlayer, STORY003 actSetPlayerMode pmEnemy; 0x448840 reads +0x28 at birth, 0x450710 does not refresh; optional, player_mode when absent)',
    'object_hit_point': 'the placed object\'s obj_HitPoint word, already added to growth_profile.source.hit_point and max_hp／hp (optional; record of the add)',
    'title': 'BattleVitals status-panel 稱號 (the placed object\'s obj_Data5 low word installed at live +0x1c; optional, the PLAYERS job_show_name row title when absent)',
    'display_name': 'BattleVitals status-panel name: the installed live +0x04 text verbatim (portraits.panel_name, 306 → ???; obj_Data5／actSetPlayerName); optional, roles/actor_panels.json name when absent',
    'dead_message': 'BattleAftermath death line {speaker, messages[{id, text}]} (the placed object\'s obj_Data8 word at live +0x14, [] = −1 cleared; optional, the PLAYERS row\'s aftermath.json template when absent)',
    'draw_mode': 'BattleSceneStage.sync_actor_row additive sprite (the placed object\'s obj_Mode display mode engADDCOLOR: the level-37 gems, level 80\'s 怨念體; optional, ordinary draw when absent)',
    'no_showshape': 'BattleSceneStage.spawn_actor_node → ActorRuntime.hide_shape (PLAYERS no_showshape, +0xa0 bit 0x20 read at 0x4420ef: the object is never drawn — the level-12／26 hull pieces 101; optional, drawn when absent)',
    'shared_record': 'SharedRecordRules.sync pools the HP of every living unit carrying the same value (the PLAYERS row of an obj_Data7 with bit 31: the level-12／26 hull pieces share one live record, 0x42bdb0; optional, own HP when absent)',
    'side_swapped': 'CutinLayout.side_swapped → every close-up object of the unit mirrors: ordinary／special attacker and its attack flash, the cast lead, the defender with its hit move flag exchanged (0x446be0 reads live +0xa0 & 8: set by the obj_Data9 swap 0x407fc3, flipped by each actSetPlayerMode 0x45073c — WinfailActions; optional, false when absent)',
}
# Evidence ledgers carried as data for the reader and the evidence checks, by JSON path;
# no rule reads them, so they are never required at any level. An authored unit simply
# omits them (the runtime reports `authored` where a tier is asked for).
PROVENANCE_KEYS: dict[str, str] = {
    '$.vitals_evidence_tier': 'tier of hp／max_hp／mp／max_mp', '$.vitals_source': 'where the vitals were read',
    '$.combat_stats_evidence_tier': 'tier of combat_profile', '$.combat_stats_source': 'where the combat profile was read',
    '$.move_point_evidence_tier': 'tier of move_point／base_move_point', '$.move_point_source': 'where the move points were read',
    '$.live_speed_evidence_tier': 'tier of live_speed', '$.live_speed_source': 'where the speed was read',
    '$.position_evidence_tier': 'tier of coord', '$.position_source': 'where the placement was read',
    '$.position_note': 'free-text placement note (blocked source cell moved, …)',
    '$.attack_range_evidence': 'attack range evidence pointer',
    '$.install_source': 'which script action／slot installs the unit',
    '$.player_mode_source': 'how the installed player mode was derived (PLAYERS row, obj_Data9 swap, obj_X1 override, role override)',
    '$.name_source': 'which obj_Data5 words installed title／display_name (low word → live +0x1c 稱號, high word → live +0x04 name)',
    '$.dead_message_source': 'which obj_Data8 word installed dead_message and how the death read unpacks it (−1 = cleared)',
    '$.growth_profile.evidence': 'evidence packet the job row was read from (JobUpRules copies it when present)',
    '$.evef_instance.evidence_tier': 'tier of the per-unit EVEF instance words',
    '$.script_insert.source': 'which STORY token wrote the pre-baked insert words',
    '$.script_insert.evidence_tier': 'tier of the pre-baked insert words',
    '$.opening_birth.source': 'which STORY opening step fixed the birth order',
    '$.opening_birth.evidence_tier': 'tier of the birth order',
}
# String properties whose observed values form a closed vocabulary; extra values a
# runtime rule assigns are listed so an initialized unit passes too.
ENUM_PATHS = {
    '$.battle_actor_role': (),
    '$.equipment[].slot': (),
    '$.growth_profile.model': (),
    '$.growth_profile.allocation': ('automatic',),  # ActorInitializationRules.prepare
}

INTEGER = {'type': 'integer'}
STRING = {'type': 'string'}
BOOLEAN = {'type': 'boolean'}
OBJECT = {'type': 'object'}
CELL = {'type': 'array', 'items': INTEGER, 'minItems': 2, 'maxItems': 2}
# Keys the GDScript runtime adds to a loaded unit, all optional, by the object path they
# land in. The value shapes belong to the rules that write them; the schema only names
# the key and its top-level type.
RUNTIME_PROPERTIES: dict[str, dict[str, dict]] = {'$': {
    # game/sim/BattleScenario.gd units()
    'grid_coord': CELL, 'speed': INTEGER, 'defeated': BOOLEAN,
    # game/sim/ActorInitializationRules.gd prepare() (+ progression data merge, AINavigationRules.initialize)
    'traversal': OBJECT, 'ai_call_target_id': STRING, 'ai_target_id': STRING, 'ai_home_coord': CELL,
    'ai_wait_remaining': INTEGER, 'ai_fixed_point_pending': BOOLEAN, 'hit_bonus_accum': INTEGER, 'level': INTEGER, 'exp': INTEGER, 'kill_exp': INTEGER,
    'pending_stat_points': INTEGER, 'kill_chain_word': INTEGER, 'kill_count': INTEGER, 'revive_count': INTEGER, 'permanent_gains': OBJECT,
    'learned_skills': {'type': 'array'}, 'stamina': INTEGER, 'inventory': {'type': 'array', 'items': INTEGER},
    # game/sim/InitialRosterGrowthRules.gd / EntryGrowthRules
    'entry_growth': OBJECT, 'entry_readjust': OBJECT,
    # game/sim/JobUpRules.gd merge_source_template()
    'job_up_flags': INTEGER, 'job_up_target_actor_id': STRING, 'job_up_policy': STRING,
    'job_up_history': {'type': 'array', 'items': OBJECT},
    # game/sim/ScriptActorCreationRules.gd
    'script_creation': OBJECT,
    # game/sim/WinfailActions.gd (actSetPlayerExecMode / actSetPlayerFixPos distance -> live ai_fixed)
    'player_exec_mode': INTEGER, 'player_exec_mode_native': INTEGER, 'ai_fixed_radius': INTEGER,
    # game/sim/ActorRoleRules.gd battle_actor_role()
    'battle_actor_role_evidence_tier': {'type': 'string', 'enum': list(EVIDENCE_TIERS)},
}, '$.status_counters': {
    # game/sim/StatusEffectRules.gd ALL_FLAGS / StatEnhancementRules.gd FLAGS counter words
    'weaken': INTEGER, 'attack_up': INTEGER, 'defense_up': INTEGER, 'resist_up': INTEGER,
}}


def _load(path: Path) -> dict:
    return json.loads(path.read_text(encoding='utf-8'))


def curated_scenarios(root: Path = ROOT) -> list[Path]:
    """Hand-curated content/battles/*.json scenarios with a roster (not assembler outputs)."""
    result = []
    for path in sorted((root / 'content/battles').glob('*.json')):
        if path.name.startswith(('battle_', 'story_')):
            continue
        document = _load(path)
        if isinstance(document, dict) and 'playable_units' in document:
            result.append(path)
    return result


def assembler_inputs() -> set[str]:
    """Everything the level_battle tasks read (story previews, seeds, imported battle
    folders, tables, ...) except this schema, so `hsl affected` on any of them names
    unit_schema too."""
    from hsltools.levels import battle  # lazy: battle imports this module for its render-time validation
    return {path for task in battle.tasks() for path in task.inputs if path != SCHEMA_PATH}


def _document_units(document: dict) -> list[dict]:
    units = [unit for unit in document.get('playable_units', []) if isinstance(unit, dict)]
    units += [spec['actor'] for spec in document.get('script_actor_templates', {}).values()]
    return units


def source_units(root: Path = ROOT) -> list[dict]:
    """Every unit dictionary the schema describes, in a stable order."""
    from hsltools.levels import battle  # lazy: battle imports this module for its render-time validation
    units: list[dict] = []
    for level in battle.registered_levels():
        for path, document in sorted(battle.render_level(level).items()):
            if path.startswith('content/battles/battle_'):
                units += _document_units(document)
    for path in curated_scenarios(root):
        units += _document_units(_load(path))
    for path in sorted((root / ACTOR_TEMPLATES).glob('*.json')):
        units.append(_load(path)['actor'])
    return units


def _describe_values(values: list, path: str) -> dict:
    kinds = sorted({json_type(value) for value in values})
    if kinds == ['integer', 'number']:
        kinds = ['number']
    if path.endswith('evidence_tier'):
        extra = sorted({value for value in values if isinstance(value, str) and value not in EVIDENCE_TIERS})
        return {'type': 'string', 'enum': list(EVIDENCE_TIERS) + extra}
    if kinds == ['object']:
        return _describe_objects(values, path)
    if kinds == ['array']:
        return _describe_arrays(values, path)
    schema: dict = {'type': kinds[0] if len(kinds) == 1 else kinds}
    if path in ENUM_PATHS and kinds == ['string']:
        schema['enum'] = sorted({*values, *ENUM_PATHS[path]})
    return schema


def _describe_arrays(values: list, path: str) -> dict:
    items = [item for value in values for item in value]
    schema: dict = {'type': 'array'}
    if not items:
        return schema
    item_kinds = {json_type(item) for item in items}
    if item_kinds <= {'integer', 'number'} or len(item_kinds) == 1:
        schema['items'] = _describe_values(items, path + '[]')
    lengths = {len(value) for value in values}
    if item_kinds <= {'integer', 'number'} and len(lengths) == 1:
        schema['minItems'] = schema['maxItems'] = lengths.pop()
    return schema


def _describe_objects(values: list, path: str) -> dict:
    keys = sorted({key for value in values for key in value})
    properties = {key: _describe_values([value[key] for value in values if key in value], f'{path}.{key}') for key in keys}
    required = [key for key in keys if all(key in value for value in values) and f'{path}.{key}' not in PROVENANCE_KEYS]
    if path == '$':
        unclassified = sorted(key for key in keys if key not in RULE_KEYS and f'$.{key}' not in PROVENANCE_KEYS and key not in RUNTIME_PROPERTIES['$'])
        if unclassified:
            raise ValueError(f'unit keys without a RULE_KEYS / PROVENANCE_KEYS / RUNTIME_PROPERTIES entry: {unclassified}')
        required = [key for key in required if key in RULE_KEYS]
    for key, runtime in RUNTIME_PROPERTIES.get(path, {}).items():
        properties.setdefault(key, runtime)
    return {'type': 'object', 'required': required, 'properties': dict(sorted(properties.items())), 'additionalProperties': False}


def build(units: list[dict]) -> dict:
    schema = _describe_objects(units, '$')
    return {
        '$schema': 'https://json-schema.org/draft/2020-12/schema',
        '$id': SCHEMA_ID,
        'title': 'HSL battle unit',
        'description': ('One unit of playable_units / script_actor_templates[*].actor / content/generated/hsl/actors/*.json '
                        'actor, plus the optional keys the runtime adds after loading. Derived by tools/hsltools/schema/unit.py '
                        f'from {len(units)} tracked units; validated by hsltools/schema/validate.py and game/sim/UnitSchema.gd.'),
        **schema,
    }


def encode(schema: dict) -> bytes:
    return (json.dumps(schema, ensure_ascii=False, indent=2) + '\n').encode('utf-8')


def load(root: Path = ROOT) -> dict:
    return _load(root / SCHEMA_PATH)


def unit_error(unit: dict, schema: dict, label: str = '$') -> str:
    return error(unit, schema, label)


class UnitSchemaTask(GeneratedFilesTask):
    name = 'unit_schema'
    family = 'schema'
    outputs = (SCHEMA_PATH,)
    replaces = ()  # born after the migration: no historical command to replace
    scripts = ('tools/hsltools/schema/unit.py', 'tools/hsltools/schema/validate.py', 'tools/hsltools/levels/battle.py')

    def __init__(self) -> None:
        # The assembler's upstream sources (every level_battle input except this schema —
        # not its outputs, which validate against this schema) plus the hand-curated rosters
        # and the source actor templates.
        self.inputs = tuple(sorted({*assembler_inputs(), ACTOR_TEMPLATES, *(path.relative_to(ROOT).as_posix() for path in curated_scenarios())}))

    def render(self, ctx: Context) -> dict[str, bytes]:
        return {SCHEMA_PATH: encode(build(source_units(ctx.root)))}

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        schema = json.loads(rendered[SCHEMA_PATH])
        tag = 'UNIT_SCHEMA_CHECK_PASS' if mode == 'check' else 'UNIT_SCHEMA_BUILD_PASS'
        return (f'{tag} required={len(schema["required"])} properties={len(schema["properties"])} '
                f'rule_keys={len(RULE_KEYS)} provenance_keys={len(PROVENANCE_KEYS)} '
                f'runtime_keys={sum(len(keys) for keys in RUNTIME_PROPERTIES.values())}')


def tasks() -> list[UnitSchemaTask]:
    return [UnitSchemaTask()]
