import copy
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hsltools.probes.physical as physical
import hsltools.probes.special_damage as special
from hsltools.data.equipment import build, weapon_magic


class PhysicalSpecialEvidenceTests(unittest.TestCase):
    def test_native_packets_and_false_return_claims(self):
        for tool, group in [(physical, 'cases'), (special, 'applications')]:
            packet = json.loads(tool.PACKET.read_text())
            tool.check(packet)
            broken = copy.deepcopy(packet)
            row = next(r for r in broken[group] if not r['normal_return'])
            row['normal_return'] = True
            with self.assertRaises(ValueError): tool.check(broken)

    def test_native_draw_and_stop_tampering_rejected(self):
        for tool, group in [(physical, 'cases'), (special, 'rolls')]:
            packet = json.loads(tool.PACKET.read_text())
            for key in ['random', 'stop']:
                broken = copy.deepcopy(packet)
                row = next(r for r in broken[group] if r['draws'])
                if key == 'random': row['draws'][0]['bound'] += 1
                else: row['stop_address'] = '0x0'
                with self.assertRaises(ValueError): tool.check(broken)

    def test_source_weapon_and_critical_are_supported_without_enabling_unknowns(self):
        items = build()['items']
        self.assertEqual(items['6']['weapon_magic'], {'element': 2, 'low': 5, 'high': 10})
        self.assertEqual(items['7']['effects']['attack_damagex2'], 10)
        self.assertTrue(items['6']['supported'] and items['7']['supported'] and items['216']['supported'])
        with self.assertRaises(ValueError): weapon_magic({'code': '6', 'magic_attack_type': 'magicAir,5,10'}, {'magicAIR':2})
        with self.assertRaises(ValueError): weapon_magic({'code': '6', 'magic_attack_type': 'magicAIR,-1,10'}, {'magicAIR':2})


if __name__ == '__main__': unittest.main()
