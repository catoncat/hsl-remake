import copy
import json
import sys
import unittest

from hsltools.sources.tables import authored_characters
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hsltools.probes.job_stats as jobs
import hsltools.probes.recovery as recovery
from hsltools.data.role_profiles import build, OUTPUT
from hsltools.data.equipment import build as equipment


class RoleResourceTests(unittest.TestCase):
    def test_native_packets_and_generated_roles(self):
        jobs.check(json.loads(jobs.PACKET.read_text()))
        recovery.check(json.loads(recovery.PACKET.read_text()))
        self.assertEqual(build(), json.loads(OUTPUT.read_text()))

    def test_mutated_native_results_and_anchors_are_refused(self):
        for module, field in [(jobs, 'cases'), (recovery, 'prefixes')]:
            original = json.loads(module.PACKET.read_text())
            for kind in ('anchor', 'normal_return', 'missing'):
                broken = copy.deepcopy(original)
                if kind == 'anchor':
                    anchor = broken['anchors'][0]
                    anchor['bytes'] = '00' + anchor['bytes'][2:]
                elif kind == 'missing':
                    broken[field].pop()
                elif module is jobs:
                    broken[field][0]['native'][0]['normal_return'] = False
                else:
                    broken[field][0]['normal_return'] = True
                with self.assertRaises(ValueError):
                    module.check(broken)

    def test_recovery_native_draws_cover_all_six_values(self):
        packet = json.loads(recovery.PACKET.read_text())
        self.assertEqual({d['value'] for r in packet['prefixes'] for d in r['draws']}, set(range(6)))
        # Low amounts add, rather than clamp to, their small-resource bonus.
        self.assertEqual(recovery.amount('hp', 39, 1, 0), 4)
        self.assertEqual(recovery.amount('mp', 60, 0, 0), 3)

    def test_live_scope_is_not_all_classes_or_all_equipment(self):
        roles = build()['actors']
        authored = {row['code'].zfill(3) for row in authored_characters()}
        original = {code: r for code, r in roles.items() if code not in authored}
        # Every proved 0x448840 branch: the base jobs plus the town job-up titles 81/82/84/86/87/89/97 (PLAYERS 010-020).
        self.assertEqual({r['profile']['job_code'] for r in original.values()}, {80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95,96,97,98,99})
        self.assertTrue(all(r['profile']['allocation'] == ('manual' if 1 <= int(code) <= 9 else 'fixed_template') for code, r in original.items()))
        # Authored rows declare their allocation and carry no evidence packet.
        self.assertTrue(all(r['profile']['allocation'] in ('manual', 'fixed_template') and 'evidence' not in r['profile'] for code, r in roles.items() if code in authored))
        items = equipment()['items']
        for code in ('218', '223', '224'):
            self.assertTrue(items[code]['supported'])
        self.assertTrue(items['145']['supported'])  # Independent casting-equipment follow-up.
        self.assertTrue(items['145']['hp_transfer_mp'])
        self.assertFalse(items['194']['supported'])


if __name__ == '__main__':
    unittest.main()
