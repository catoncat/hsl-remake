import copy
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from hsltools.probes.status_roll import PACKET, check_packet, independent
from hsltools.probes.status_lifecycle import PACKET as LIFECYCLE_PACKET, check_packet as check_lifecycle


class StatusRollProbeTests(unittest.TestCase):
    def test_application_prefix_and_counter_returns_cannot_be_conflated(self):
        packet = json.loads(LIFECYCLE_PACKET.read_text())
        check_lifecycle(packet)
        bad = copy.deepcopy(packet)
        bad['application_cases'][0]['normal_return'] = True
        with self.assertRaisesRegex(ValueError, 'boundary'):
            check_lifecycle(bad)
        bad = copy.deepcopy(packet)
        bad['tick_cases'][1]['native']['status_flags'] ^= 2
        with self.assertRaisesRegex(ValueError, 'output'):
            check_lifecycle(bad)

    def test_saved_original_returns_and_scoped_execution(self):
        packet = json.loads(PACKET.read_text())
        check_packet(packet)
        self.assertTrue(packet['cases'])
        self.assertTrue(packet['immunity_cases'])
        self.assertTrue(all(row['instructions'] < 4096 for row in packet['cases']))

    def test_modified_output_or_random_order_cannot_pass(self):
        packet = json.loads(PACKET.read_text())
        bad = copy.deepcopy(packet)
        bad['cases'][0]['native']['value'] += 1
        with self.assertRaisesRegex(ValueError, 'conflicts'):
            check_packet(bad)
        row = copy.deepcopy(packet['cases'][0])
        row['draws'][0]['bound'] = 99
        with self.assertRaisesRegex(ValueError, 'sequence'):
            independent(row['input'], row['draws'])

    def test_immunity_union_and_normal_return_are_required(self):
        packet = json.loads(PACKET.read_text())
        bad = copy.deepcopy(packet)
        bad['immunity_cases'][1]['native'] = 0
        with self.assertRaisesRegex(ValueError, 'immunity'):
            check_packet(bad)
        bad = copy.deepcopy(packet)
        bad['cases'][0]['normal_return'] = False
        with self.assertRaisesRegex(ValueError, 'conflicts'):
            check_packet(bad)


if __name__ == '__main__': unittest.main()
