import copy
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hsltools.probes.stamina as probe
from hsltools.data.equipment import build


class StaminaEvidenceTests(unittest.TestCase):
    def test_native_result_and_mutations(self):
        packet = json.loads(probe.PACKET.read_text())
        probe.check(packet)
        self.assertTrue(packet['cases'])
        for change in ['native', 'writes', 'rng_calls', 'normal_return']:
            corrupted = copy.deepcopy(packet)
            corrupted['cases'][0][change] = {'attacker': 999} if change == 'native' else [] if change == 'writes' else 1 if change == 'rng_calls' else False
            with self.subTest(change=change), self.assertRaises(ValueError): probe.check(corrupted)

    def test_actual_equipment_effects_and_other_unsupported_passives(self):
        items = build()['items']
        for code, name, flags in [('225', '凝氣之環', 0x40), ('169', '鬼面', 0x400)]:
            self.assertEqual(items[code]['name'], name)
            self.assertTrue(items[code]['supported'])
            self.assertEqual(items[code]['stamina_effect_flags'], flags)
        # The separate extra-action contract does not add a stamina multiplier.
        self.assertTrue(items['227']['supported'])
        self.assertTrue(items['227']['action_twice'])
        self.assertEqual(items['227']['stamina_effect_flags'], 0)
        self.assertTrue(all(item['stamina_effect_flags'] & ~0x440 == 0 for item in items.values()))
