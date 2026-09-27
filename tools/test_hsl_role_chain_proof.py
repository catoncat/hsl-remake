"""The native receipts still pin the table-driven role chain: a changed generated initial value or an
edited original learning row fails the proof checks, while a job tagged `authored` needs no receipt."""
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from hsltools.checks import role_chain_proof as proof
from hsltools.paths import ROOT


class RoleChainProofTests(unittest.TestCase):
    def test_changed_initial_value_fails(self):
        profiles = json.loads((ROOT / proof.PROFILES).read_text())
        profiles['actors']['001']['initial']['max_hp'] += 1
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / proof.PROFILES).parent.mkdir(parents=True)
            (root / proof.PROFILES).write_text(json.dumps(profiles))
            (root / proof.STATIC_REVERSE).parent.mkdir(parents=True)
            os.symlink(ROOT / proof.STATIC_REVERSE, root / proof.STATIC_REVERSE.rstrip('/'))
            with self.assertRaises(ValueError) as failure:
                proof.check_role_profiles(root)
            self.assertIn('001: initial.max_hp', str(failure.exception))

    def test_edited_original_learning_row_fails_and_authored_job_needs_no_receipt(self):
        table = json.loads(json.dumps(proof.learning_tables()))
        table['85']['magic'][0]['level'] += 1
        with mock.patch.object(proof, 'learning_tables', return_value=table):
            with self.assertRaises(ValueError) as failure:
                proof.check_learning_tables(ROOT)
        self.assertIn('job 85: magic levels differ', str(failure.exception))
        table = json.loads(json.dumps(proof.learning_tables()))
        table['100'] = dict(tier=1, magic=[], special=[], evidence_tier='authored')
        with mock.patch.object(proof, 'learning_tables', return_value=table):
            self.assertTrue(proof.check_learning_tables(ROOT).startswith('LEARNING_TABLES_PROOF_PASS'))
        table['100'].pop('evidence_tier')
        with mock.patch.object(proof, 'learning_tables', return_value=table):
            with self.assertRaises(ValueError) as failure:
                proof.check_learning_tables(ROOT)
        self.assertIn("jobs ['100'] have no native learning receipt", str(failure.exception))


if __name__ == '__main__':
    unittest.main()
