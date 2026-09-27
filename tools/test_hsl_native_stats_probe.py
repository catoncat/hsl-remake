import json
import unittest
from pathlib import Path

from tools.hsl_native_stats_probe import DEFAULT_ACTORS


class NativeStatsProbeTests(unittest.TestCase):
    def test_default_actor_set_remains_first_battle_compatible(self):
        self.assertEqual(DEFAULT_ACTORS, ('1', '21', '23', '24', '26'))

    def test_second_battle_packet_extends_without_changing_first_battle_results(self):
        first = json.loads(Path('docs/evidence_packets/static_reverse/first_battle_template_stats.json').read_text())
        second = json.loads(Path('docs/evidence_packets/static_reverse/second_battle_template_stats.json').read_text())
        self.assertEqual(first['exe_sha256'], second['exe_sha256'])
        self.assertEqual(first['inputs_sha256'], second['inputs_sha256'])
        for actor_id in ('001', '021', '023', '024', '026'):
            self.assertEqual(first['actors'][actor_id], second['actors'][actor_id])
        self.assertEqual(second['actors']['025']['equipped']['max_hp'], 91)
        self.assertEqual(second['actors']['025']['equipped']['attack'], 58)
        self.assertEqual(second['actors']['025']['equipped']['defense'], 46)
        self.assertEqual(second['actors']['025']['equipped']['speed'], 16)
        self.assertEqual(second['actors']['025']['equipped']['hit_rate'], 92)
        self.assertEqual(second['actors']['069']['base']['mode'], 'pmPlayer')


if __name__ == '__main__':
    unittest.main()
