import copy
import json
from pathlib import Path
import sys
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parent))
from hsltools.probes.turn_select import PACKET, check_packet


class TurnSelectorEvidenceTests(unittest.TestCase):
    def test_saved_original_returns(self):
        check_packet(json.loads(PACKET.read_text()))

    def test_wrong_successor_or_round_is_rejected(self):
        source = json.loads(PACKET.read_text())
        for field, value in [('index', 199), ('round', 8)]:
            changed = copy.deepcopy(source)
            changed['cases'][1]['native'][field] = value
            with self.assertRaisesRegex(ValueError, 'fixture/output'):
                check_packet(changed)

    def test_budget_overrun_or_missing_return_cannot_be_evidence(self):
        source = json.loads(PACKET.read_text())
        for field, value in [('instructions', 4097), ('normal_return', False)]:
            changed = copy.deepcopy(source)
            changed['cases'][0][field] = value
            with self.assertRaisesRegex(ValueError, 'normal return'):
                check_packet(changed)
