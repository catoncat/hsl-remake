from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from tools import hsl_script_runtime_probe_targets
from tools.test_hsl_script_vm_semantics import write_fixture


class ScriptRuntimeProbeTargetsTests(unittest.TestCase):
    def test_checker_accepts_generated_fixture(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            index_path = write_fixture(root)
            path = root / "script_runtime_probe_targets.json"
            path.write_text(
                json.dumps(hsl_script_runtime_probe_targets.build_probe_targets(index_path)),
                encoding="utf-8",
            )

            errors = hsl_script_runtime_probe_targets.check_probe_targets(path)

        self.assertEqual(errors, [])

    def test_checker_rejects_semantic_upgrade_claims(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            index_path = write_fixture(root)
            targets = hsl_script_runtime_probe_targets.build_probe_targets(index_path)
            targets["target_policy"] = "execute_handlers"
            targets["condition_targets"][0]["predicate_status"] = "confirmed"
            path = root / "script_runtime_probe_targets.json"
            path.write_text(json.dumps(targets), encoding="utf-8")

            errors = hsl_script_runtime_probe_targets.check_probe_targets(path)

        self.assertTrue(any("target_policy" in error for error in errors), errors)
        self.assertTrue(any("predicate_status" in error for error in errors), errors)

if __name__ == "__main__":
    unittest.main()
