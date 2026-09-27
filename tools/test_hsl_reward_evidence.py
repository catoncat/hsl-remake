from copy import deepcopy
from pathlib import Path
import tempfile
import unittest

from hsltools.evidence.reward import check, expected


class RewardEvidenceTests(unittest.TestCase):
    def test_changed_branch_or_claim_is_rejected(self):
        packet = expected()
        self.assertEqual(check(packet), 13)
        for key, value in [("bytes", "90"), ("claim", "drop on <=")]:
            changed = deepcopy(packet)
            changed["anchors"][0][key] = value
            with self.assertRaisesRegex(ValueError, "differs"):
                check(changed)

    def test_wrong_original_never_authenticates_recorded_anchors(self):
        with tempfile.TemporaryDirectory() as directory:
            binary = Path(directory) / "wrong.bin"
            binary.write_bytes(b"not the original game")
            with self.assertRaisesRegex(ValueError, "Unsupported EXE"):
                check(expected(), binary)
