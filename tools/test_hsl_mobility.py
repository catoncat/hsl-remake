import copy
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hsltools.probes.mobility as probe
from hsltools.data.equipment import build, initial_mobility_fields
from hsltools.data.first_battle_formation import actor_templates


class MobilityEvidenceTests(unittest.TestCase):
    def test_complete_return_and_repeat_refresh_integrity(self):
        packet = json.loads(probe.PACKET.read_text())
        probe.check(packet)
        for key in ['move_point','base','hp','stamina','instructions']:
            broken = copy.deepcopy(packet)
            broken['cases'][0]['native'][1][key] = 13000
            with self.assertRaises(ValueError): probe.check(broken)
        broken = copy.deepcopy(packet)
        broken['cases'][0]['normal_return'] = False
        with self.assertRaises(ValueError): probe.check(broken)

    def test_source_items_and_first_battle_do_not_gain_unowned_equipment(self):
        players, _ = probe.sources()
        catalog = build()['items']
        self.assertEqual([int(code) for code,item in catalog.items() if item['effects']['move_point']], [138,193,194,231,236])
        self.assertTrue(all(catalog[str(code)]['supported'] for code in [138,193,231]))
        self.assertIn('add_defnese', catalog['194']['unsupported_fields'])
        self.assertTrue(catalog['236']['supported'])
        self.assertTrue(catalog['236']['move_magic_use'] and catalog['236']['add_attack_range'])
        self.assertEqual(catalog['236']['effects']['move_point'], 1)
        for code, template in actor_templates().items():
            source = players[code]
            mobility = initial_mobility_fields(source,catalog)
            self.assertEqual(template['base_move_point'],int(source['move_point']))
            self.assertEqual(template['move_point'],mobility['move_point'])
            self.assertEqual(template['move_point'],int(source['move_point']))

    def test_equipment_sources_sum_before_final_clamp(self):
        players, _ = probe.sources()
        source = dict(players['001'], move_point='11', armor_equip='138', foot_equip='193', other1_equip='231', other2_equip='231')
        result = initial_mobility_fields(source,build()['items'])
        self.assertEqual((result['base_move_point'], result['move_point']), (11,12))
        source['move_point'] = '5'
        self.assertEqual(initial_mobility_fields(source,build()['items'])['move_point'], 9)


if __name__ == '__main__': unittest.main()
