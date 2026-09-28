import copy
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from hsltools import registry
from hsltools.levels import battle
from hsltools.paths import ROOT
from hsltools.schema import unit as unit_schema
from hsltools.schema.validate import error, json_type


class ValidatorTests(unittest.TestCase):
    def test_json_types_follow_json_schema_not_python(self):
        self.assertEqual(json_type(True), 'boolean')
        self.assertEqual(json_type(3), 'integer')
        self.assertEqual(json_type(3.0), 'integer')
        self.assertEqual(json_type(3.5), 'number')
        self.assertEqual(json_type(None), 'null')

    def test_supported_keywords(self):
        schema = {'type': 'object', 'required': ['a'], 'additionalProperties': False,
                  'properties': {'a': {'type': 'integer'}, 'b': {'type': 'string', 'enum': ['x', 'y']},
                                 'c': {'type': 'array', 'items': {'type': 'integer'}, 'minItems': 2, 'maxItems': 2},
                                 'd': {'type': ['integer', 'null']}}}
        self.assertEqual(error({'a': 1, 'b': 'x', 'c': [1, 2], 'd': None}, schema), '')
        self.assertEqual(error({'b': 'x'}, schema), "$: missing required key 'a'")
        self.assertEqual(error({'a': True}, schema), '$.a: expected integer, got boolean')
        self.assertEqual(error({'a': 1, 'b': 'z'}, schema), "$.b: 'z' not in enum ['x', 'y']")
        self.assertEqual(error({'a': 1, 'c': [1]}, schema), '$.c: expected at least 2 items, got 1')
        self.assertEqual(error({'a': 1, 'c': [1, 'two']}, schema), '$.c[1]: expected integer, got string')
        self.assertEqual(error({'a': 1, 'zzz': 0}, schema), "$: unexpected key 'zzz'")
        self.assertEqual(error({'a': 1, 'd': 'no'}, schema), '$.d: expected integer|null, got string')
        self.assertEqual(error(5, {'type': 'number'}), '')
        self.assertEqual(error({}, {'type': 'object', 'pattern': 'x'}), "$: unsupported schema keyword(s) ['pattern']")


class UnitSchemaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.schema = unit_schema.load()
        cls.units = unit_schema.source_units()

    def test_every_source_unit_passes(self):
        self.assertGreater(len(self.units), 2600)
        failures = [found for unit in self.units if (found := error(unit, self.schema))]
        self.assertEqual(failures, [])

    def test_closed_vocabularies_and_layered_strictness(self):
        properties = self.schema['properties']
        self.assertEqual(self.schema['additionalProperties'], False)
        self.assertEqual(properties['battle_actor_role']['enum'], ['enemy_ai', 'friendly_ai', 'player_controlled'])
        self.assertEqual(properties['equipment']['items'],
                         {'type': 'object', 'required': ['item_code', 'name', 'slot'], 'additionalProperties': False,
                          'properties': {'item_code': {'type': 'integer'}, 'name': {'type': 'string'},
                                         'slot': {'type': 'string', 'enum': ['accessory1', 'accessory2', 'armor', 'foot', 'head', 'weapon']}}})
        self.assertEqual(properties['vitals_evidence_tier']['enum'], list(unit_schema.EVIDENCE_TIERS))
        self.assertEqual(properties['coord'], {'type': 'array', 'items': {'type': 'integer'}, 'minItems': 2, 'maxItems': 2})
        self.assertEqual(properties['combat_profile']['additionalProperties'], False)
        self.assertIn('resist_by_type', properties['combat_profile']['required'])
        self.assertEqual(properties['growth_profile']['properties']['allocation']['enum'], ['automatic', 'fixed_template', 'manual'])
        for key in unit_schema.RUNTIME_PROPERTIES['$']:
            self.assertIn(key, properties, key)
            self.assertNotIn(key, self.schema['required'], key)
        for key in unit_schema.RUNTIME_PROPERTIES['$.status_counters']:
            self.assertIn(key, properties['status_counters']['properties'], key)

    def test_required_keys_are_rule_inputs_only(self):
        # Evidence ledgers pass through as optional data; an authored unit carries none of them.
        for key in self.schema['required']:
            self.assertIn(key, unit_schema.RULE_KEYS, key)
        for path in unit_schema.PROVENANCE_KEYS:
            parent = self.schema
            *parents, key = path.split('.')[1:]
            for name in parents:
                parent = parent['properties'][name]
            self.assertIn(key, parent['properties'], path)
            self.assertNotIn(key, parent.get('required', []), path)
        self.assertTrue(self.schema['required'])
        self.assertIn(unit_schema.AUTHORED_TIER, self.schema['properties']['position_evidence_tier']['enum'])
        authored = {key: value for key, value in self.units[0].items() if f'$.{key}' not in unit_schema.PROVENANCE_KEYS}
        authored['growth_profile'] = {key: value for key, value in authored['growth_profile'].items() if key != 'evidence'}
        self.assertEqual(error(authored, self.schema), '')
        with self.assertRaises(ValueError):
            unit_schema.build([{**self.units[0], 'unclassified_key': 1}])

    def test_wave_nine_shapes_are_rejected(self):
        unit = copy.deepcopy(self.units[0])
        unit['equipment'] = [82, 15]
        self.assertEqual(error(unit, self.schema), '$.equipment[0]: expected object, got integer')
        unit = copy.deepcopy(self.units[0])
        unit['equipment'] = [{'slot': 'weapon', 'item_code': 82}]
        self.assertEqual(error(unit, self.schema), "$.equipment[0]: missing required key 'name'")
        unit = copy.deepcopy(self.units[0])
        unit['combat_profile']['resist_by_type'] = [0, 0, 0, 0, 0]
        self.assertEqual(error(unit, self.schema), '$.combat_profile.resist_by_type: expected object, got array')
        unit = copy.deepcopy(self.units[0])
        unit['job_up_templates'] = {}
        self.assertEqual(error(unit, self.schema), "$: unexpected key 'job_up_templates'")
        unit = copy.deepcopy(self.units[0])
        del unit['status_counters']
        self.assertEqual(error(unit, self.schema), "$: missing required key 'status_counters'")

    def test_initialized_runtime_unit_passes(self):
        unit = copy.deepcopy(self.units[0])
        unit.update({'grid_coord': [1, 2], 'speed': 5, 'defeated': False, 'traversal': {}, 'ai_call_target_id': '', 'ai_target_id': '',
                     'ai_home_coord': [1, 2], 'ai_wait_remaining': 0, 'hit_bonus_accum': 0, 'level': 1.0, 'exp': 0.0, 'kill_exp': 0,
                     'pending_stat_points': 0, 'kill_chain_word': 0, 'kill_count': 0, 'permanent_gains': {}, 'learned_skills': [],
                     'stamina': 3, 'inventory': [241, 0, 0, 0, 0, 0, 0, 0], 'entry_growth': {}, 'job_up_flags': 1,
                     'job_up_target_actor_id': '052', 'job_up_policy': 'native_job_up_merge_v1', 'job_up_history': [{'flag': 1}],
                     'script_creation': {}, 'player_exec_mode': 0, 'player_exec_mode_native': 3, 'ai_fixed_radius': 1,
                     'battle_actor_role_evidence_tier': 'provisional'})
        unit['status_counters']['attack_up'] = 0
        unit['growth_profile']['allocation'] = 'automatic'
        self.assertEqual(error(unit, self.schema), '')

    def test_level_battle_render_validates_against_the_tracked_schema(self):
        document = battle.render_level(5)[battle.output_path(5).relative_to(ROOT).as_posix()]
        self.assertEqual(battle.unit_schema_errors(document, self.schema), [])
        broken = copy.deepcopy(document)
        broken['playable_units'][1]['equipment'] = [82]
        symbol = sorted(broken['script_actor_templates'])[0]
        broken['script_actor_templates'][symbol]['actor']['coord'] = [1]
        self.assertEqual(battle.unit_schema_errors(broken, self.schema),
                         ['playable_units[1].equipment[0]: expected object, got integer',
                          f'script_actor_templates.{symbol}.actor.coord: expected at least 2 items, got 1'])
        task = battle.LevelBattleTask(5)
        self.assertIn(unit_schema.SCHEMA_PATH, task.inputs)
        original = battle.render_level
        battle.render_level = lambda level: {battle.output_path(level).relative_to(ROOT).as_posix(): broken}
        try:
            with self.assertRaises(registry.CheckFailed) as caught:
                task.render(registry.Context())
        finally:
            battle.render_level = original
        self.assertIn('playable_units[1].equipment[0]', str(caught.exception))

    def test_registry_generates_the_schema_before_its_consumers(self):
        tasks = registry.all_tasks()
        chosen = registry.select(tasks, ['level_battle:37', 'unit_schema'])
        self.assertEqual([task.name for task in registry.generation_order(chosen)], ['unit_schema', 'level_battle:37'])
        task = registry.select(tasks, ['unit_schema'])[0]
        self.assertEqual((task.family, task.outputs), ('schema', (unit_schema.SCHEMA_PATH,)))
        self.assertIn('content/battles/first_battle.json', task.inputs)
        self.assertNotIn('content/battles/', task.inputs)

    def test_unit_schema_inputs_are_the_assembler_sources_so_affected_names_it(self):
        # Every level_battle input except the schema itself (the story previews the
        # assembler renders from included), the actor templates and the curated rosters.
        tasks = registry.all_tasks()
        task = registry.select(tasks, ['unit_schema'])[0]
        level_inputs = {path for other in tasks if other.family == 'level_battle' for path in other.inputs}
        self.assertEqual(set(task.inputs) - {unit_schema.ACTOR_TEMPLATES} - level_inputs,
                         {path.relative_to(ROOT).as_posix() for path in unit_schema.curated_scenarios()} - level_inputs)
        self.assertIn('content/battles/story_037.json', task.inputs)
        self.assertNotIn(unit_schema.SCHEMA_PATH, task.inputs)
        for path in task.inputs:
            self.assertTrue((ROOT / path).exists(), path)
        for changed in ('content/battles/story_037.json', 'content/generated/hsl/chapter01/battle501_seed.json'):
            self.assertIn('unit_schema', {affected.name for affected in registry.affected(tasks, [changed])}, changed)


if __name__ == '__main__':
    unittest.main()
