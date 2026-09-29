"""The public source launcher must import before opening a window, including cold clones."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

LAUNCHER = Path(__file__).resolve().parent / "play.sh"


@unittest.skipIf(os.name == "nt", "bash launcher; Windows runs tools/play.ps1 (bash there is the WSL launcher)")
class PlayLauncherTests(unittest.TestCase):
    def run_launcher(self, mode):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            project = root / "project with spaces"
            (project / "tools").mkdir(parents=True)
            for name in ("play.sh", "godot.sh"):
                shutil.copy2(LAUNCHER.parent / name, project / "tools" / name)
            launcher = project / "tools" / "play.sh"
            # A complete checkout: the launcher runs `hsl bootstrap` only when this table is missing.
            (project / "content/imported/hsl/global/tables").mkdir(parents=True)
            (project / "content/imported/hsl/global/tables/PLAYERS.TXT").write_bytes(b"")
            executable = root / "fake-godot"
            executable.write_text('''#!/bin/sh
printf '%s\\n' "$*" >> "$CALLS"
case " $* " in
  *" --import "*)
    test -f "$PROJECT_ROOT/ignored/.gdignore" || exit 8
    case "$MODE" in
      diagnostic) echo 'ERROR: missing texture'; exit 0;;
      failure) exit 7;;
    esac;;
  *) echo GAME_STARTED;;
esac
''')
            executable.chmod(0o700)
            calls = root / "calls"
            env = dict(os.environ, GODOT_BIN=str(executable), CALLS=str(calls), MODE=mode,
                       PROJECT_ROOT=str(project))
            result = subprocess.run(["bash", str(launcher), "--screen", "1"], cwd=root,
                                    env=env, capture_output=True, text=True, timeout=10)
            return result, calls.read_text().splitlines()

    def test_import_before_game_and_forward_window_args(self):
        result, calls = self.run_launcher("ok")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(calls), 2)
        self.assertIn("--headless", calls[0])
        self.assertIn("--import", calls[0])
        self.assertIn("project with spaces", calls[0])
        self.assertIn("--screen 1", calls[1])
        self.assertIn("GAME_STARTED", result.stdout)

    def test_diagnostics_fail_even_when_import_exits_zero(self):
        result, calls = self.run_launcher("diagnostic")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(calls), 1)
        self.assertIn("missing texture", result.stderr)
        self.assertNotIn("GAME_STARTED", result.stdout)

    def test_nonzero_import_never_opens_game(self):
        result, calls = self.run_launcher("failure")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(calls), 1)


if __name__ == "__main__":
    unittest.main()
