"""Exercise the real wrapper without launching Godot or touching local captures."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

WRAPPER = Path(__file__).with_name("godot.sh")


@unittest.skipIf(os.name == "nt", "bash wrapper; Windows runs tools/godot.ps1 (bash there is the WSL launcher)")
class GodotRunnerTests(unittest.TestCase):
    def run_godot(self, diagnostic="", exit_code=0, marker=None):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder) / "checkout with spaces"
            (root / "tools").mkdir(parents=True)
            (root / "ignored").mkdir()
            raw = root / "ignored" / "capture.png"
            raw.write_bytes(b"untouched capture")
            if marker is not None:
                (root / "ignored" / ".gdignore").write_text(marker)
            shutil.copy2(WRAPPER, root / "tools" / WRAPPER.name)
            fake = root / "fake godot"
            fake.write_text('''#!/bin/sh
test -f "$PROJECT_ROOT/ignored/.gdignore" || exit 8
printf '%s\\n' "$@" > "$CALLS"
printf '%s\\n' "$DIAGNOSTIC" 'SUITE_PASS'
exit "$EXIT_CODE"
''')
            fake.chmod(0o700)
            calls = root / "calls"
            env = dict(os.environ, GODOT_BIN=str(fake), PROJECT_ROOT=str(root),
                       CALLS=str(calls), DIAGNOSTIC=diagnostic, EXIT_CODE=str(exit_code))
            result = subprocess.run(
                ["bash", str(root / "tools" / WRAPPER.name), "--headless", "--script",
                 "res://tests/a suite.gd"], cwd=folder, env=env,
                capture_output=True, text=True, timeout=10,
            )
            self.assertEqual(raw.read_bytes(), b"untouched capture")
            self.assertEqual(calls.read_text().splitlines(),
                             ["--path", str(root), "--headless", "--script", "res://tests/a suite.gd"])
            if marker is not None:
                self.assertEqual((root / "ignored" / ".gdignore").read_text(), marker)
            return result

    def test_cold_output_is_excluded_before_running_and_arguments_are_preserved(self):
        result = self.run_godot()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("SUITE_PASS", result.stdout)

    def test_existing_ignore_marker_and_captures_are_preserved(self):
        self.assertEqual(self.run_godot(marker="# user marker\n").returncode, 0)

    def test_nonzero_exit_is_preserved_even_with_a_pass_message(self):
        self.assertEqual(self.run_godot(exit_code=7).returncode, 7)

    def test_diagnostics_override_zero_exit_and_pass_message(self):
        for diagnostic in ("SCRIPT ERROR: parse failed", "ERROR: missing resource",
                           "WARNING: ObjectDB instances were leaked at exit",
                           "ERROR: 2 resources still in use at exit"):
            with self.subTest(diagnostic=diagnostic):
                result = self.run_godot(diagnostic=diagnostic)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(diagnostic, result.stdout)
                self.assertIn("diagnostics failed", result.stderr)


if __name__ == "__main__":
    unittest.main()
