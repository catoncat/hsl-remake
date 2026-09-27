"""hsltools.checks.registration_order: the failure paths the gate relies on, on synthetic battlefields."""
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))

from hsltools.checks import registration_order as order  # noqa: E402
from hsltools.paths import ROOT  # noqa: E402

MANUAL = {'allocation': 'manual'}


def evef(index: int, process: str = 'defProcEnemy', data6: str = 'SID_ENEMY024', data9: int = 0) -> dict:
    return {'record_index': index, 'object_process': process,
            'object_data_fields': {'obj_Data6': data6, 'obj_Data9': data9}}


def unit(uid: str, speed: int, record: int | None = None, actor_id: str = '024', manual: bool = False, insert: dict | None = None,
         story_insert: int | None = None) -> dict:
    result = {'id': uid, 'actor_id': actor_id, 'live_speed': speed, 'position_source': {},
              'growth_profile': MANUAL if manual else {'allocation': 'auto'}}
    if record is not None:
        result['position_source']['evef_record_index'] = record
    if insert is not None:
        result['position_source']['opening_insert'] = insert
        result['opening_birth'] = {'story_insert': story_insert}
    return result


def insert_command(symbol: str) -> dict:
    return {'name': 'actInsertStoryObject', 'args': [symbol]}


def arm_command(code: str) -> dict:
    return {'name': 'actInsertEventStatus', 'args': [code]}


class RegistrationOrderSurveyTests(unittest.TestCase):
    def build(self, units: list[dict], records: list[dict], rules: dict | None = None, story: list[dict] | None = None,
              winfail: list[dict] | None = None, objects: list[dict] | None = None) -> Path:
        root = Path(self.tmp.name)
        (root / order.SCENARIOS).mkdir(parents=True, exist_ok=True)
        (root / order.SEEDS).mkdir(parents=True, exist_ok=True)
        scenario = {'schema': 'hsl_level_battle.v1', 'level': 999, 'provenance': {'seed_sha256': 'x'},
                    'playable_units': units, 'scenario_rules': rules or {'reinforcements': []}}
        seed = {'placements': {'records': records}, 'script_objects': objects or [],
                'scripts': {'story': {'sections': [{'name': 'story', 'codes': [], 'actions': [{'chain': story or []}]}]},
                            'winfail': {'sections': winfail or []}}}
        (root / order.SCENARIOS / 'battle_999.json').write_text(json.dumps(scenario), encoding='utf-8')
        (root / order.SEEDS / 'battle999_seed.json').write_text(json.dumps(seed), encoding='utf-8')
        return root

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def survey(self, root: Path) -> tuple[dict, list[str]]:
        rows, issues = order.survey(root)
        self.assertEqual(len(rows), 1)
        return rows[0], issues

    def test_creation_order_roster_passes_and_counts_equal_speed_pairs(self):
        hull = {'symbol': 'obj_Story_Enemy1', 'object_process': 'defProcEnemy', 'plane': 'planeObject1',
                'object_data_fields': {'obj_Data6': 'SID_ENEMY030'}}
        root = self.build([unit('leonard', 14, 0, '001', manual=True), unit('a', 14, 1), unit('b', 14, 2),
                           unit('c', 14, insert={'symbol': 'obj_Story_Enemy1', 'kind': 'object'}, story_insert=1)],
                          [evef(0, 'defProcPlayerInstall', 'SID_PLAYER0', 0), evef(1), evef(2)],
                          story=[insert_command('obj_Story_Enemy1')], objects=[hull])
        row, issues = self.survey(root)
        self.assertEqual(issues, [])
        self.assertEqual((row['players'], row['npcs'], row['npc_pairs'], row['mixed_pairs'], row['inversions']), (1, 3, 3, 3, 0))
        self.assertEqual(row['registrations']['static_total'], 3)

    def test_roster_out_of_creation_order_names_the_equal_speed_inversions(self):
        root = self.build([unit('b', 14, 2), unit('a', 14, 1), unit('c', 12, 3)], [evef(1), evef(2), evef(3)])
        row, issues = self.survey(root)
        self.assertEqual((row['inversions'], row['affected_pairs']), (1, 1))
        self.assertIn('NPC roster order is not creation order (1 inversions, 1 equal-speed)', issues[0])

    def test_reserved_slot_and_class_mismatches_fail(self):
        root = self.build([unit('p', 10, 0, '002', manual=True), unit('q', 10, 1, '004', manual=False), unit('n', 10, 2, '003', manual=True)],
                          [evef(0, 'defProcPlayerInstall', 'SID_PLAYER0', 0), evef(1, 'defProcPlayerInstall', 'SID_PLAYER3', 3), evef(2)])
        _, issues = self.survey(root)
        self.assertEqual(len(issues), 3, issues)
        self.assertIn('p: original reserved slot 0, remake slot 1', issues[0])
        self.assertIn('q: original reserved slot 3, remake unregistered NPC', issues[1])
        self.assertIn('n: original cursor-range NPC, remake reserved slot 2', issues[2])

    def test_class_template_reinforcements_and_unsourced_units_fail(self):
        root = self.build([unit('a', 10, 1), unit('ghost', 10)], [evef(1)], rules={'reinforcements': [{'class_id': 'Enemy024'}]})
        _, issues = self.survey(root)
        self.assertTrue(any('units without a creation source: ghost' in issue for issue in issues), issues)
        self.assertTrue(any('scenario_rules.reinforcements is not empty' in issue for issue in issues), issues)

    def test_written_registrations_reaching_the_wrap_fail_and_refill_cycles_are_counted(self):
        records = [evef(index) for index in range(order.WRAP_AT - 1)]
        grunt = {'symbol': 'obj_Story_Enemy1', 'object_process': 'defProcEnemy', 'plane': 'planeObject1',
                 'object_data_fields': {'obj_Data6': 'SID_ENEMY030'}}
        refill = [{'name': 'event', 'codes': ['0'], 'actions': [{'chain': [insert_command('obj_Story_Enemy1'), arm_command('0')]}]}]
        root = self.build([unit('a', 10, 0)], records, story=[arm_command('0')], winfail=refill, objects=[grunt])
        row, issues = self.survey(root)
        self.assertEqual(issues, [])
        self.assertEqual((row['registrations']['refill_per_cycle'], row['refills_to_wrap']), (1, 1))
        root = self.build([unit('a', 10, 0)], records, story=[insert_command('obj_Story_Enemy1')], objects=[grunt])
        _, issues = self.survey(root)
        self.assertEqual(issues, [f'battle_999.json: written NPC registrations {order.WRAP_AT} reach the cursor wrap ({order.WRAP_AT})'])

    def test_core_contract_pins_the_registration_key_and_the_append(self):
        root = Path(self.tmp.name)
        for path in (order.CORE_TURN_QUEUE, order.SCRIPT_ACTORS):
            (root / path).parent.mkdir(parents=True, exist_ok=True)
            (root / path).write_text((ROOT / path).read_text(encoding='utf-8'), encoding='utf-8')
        self.assertEqual(order._core_contract(root), [])
        core = root / order.CORE_TURN_QUEUE
        core.write_text(core.read_text(encoding='utf-8').replace('"manual"', '"reserved"'), encoding='utf-8')
        actors = root / order.SCRIPT_ACTORS
        actors.write_text(actors.read_text(encoding='utf-8').replace('loop["units"].append(actor)', 'loop["units"].insert(0, actor)'),
                          encoding='utf-8')
        self.assertEqual(len(order._core_contract(root)), 2)


if __name__ == '__main__':
    unittest.main()
