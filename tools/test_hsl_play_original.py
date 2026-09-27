"""Offline tests for tools/play_original.sh: installing the 回憶錄 preset and then --restore leaves
the original's SAVES directory byte-for-byte as it was before the install, including the HSL.CFG the
original writes when it exits. The launcher runs from a scratch copy of the repository layout with a
stub original (it writes HSL.CFG and changes row 1 the way a played session does) and a stub pgrep, so
no Wine process is started and a real original running on this machine does not block the test."""
from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PRESET_DIR = Path("content/generated/hsl/development/original_saves")


def snapshot(saves: Path) -> dict[str, bytes]:
    return {path.name: path.read_bytes() for path in sorted(saves.iterdir()) if path.is_file()}


@unittest.skipIf(os.name == "nt", "bash Wine launcher for macOS/Linux (bash on Windows is the WSL launcher)")
class PlayOriginalRestoreTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self.root = base / "repo"
        (self.root / "tools").mkdir(parents=True)
        shutil.copy2(ROOT / "tools" / "play_original.sh", self.root / "tools" / "play_original.sh")
        self.saves = base / "prefix" / "drive_c" / "hsl" / "SAVES"
        self.saves.mkdir(parents=True)
        stub = self.root / "tools" / "run_original_hsl.sh"
        stub.write_text(
            "#!/usr/bin/env bash\n"
            "# stands in for a played session: the game rewrites row 1 and writes HSL.CFG on exit\n"
            'printf "played" >> "$WINEPREFIX/drive_c/hsl/SAVES/HSL00.SAV"\n'
            'printf "\\377\\000\\000\\000" > "$WINEPREFIX/drive_c/hsl/SAVES/HSL.CFG"\n',
            encoding="utf-8",
        )
        stub.chmod(0o755)
        (self.root / PRESET_DIR).mkdir(parents=True)
        (self.root / PRESET_DIR / "level06_pre_battle.SAV").write_bytes(b"PRESET-ROW")
        bin_dir = base / "bin"
        bin_dir.mkdir()
        (bin_dir / "pgrep").write_text("#!/usr/bin/env bash\nexit 1\n", encoding="utf-8")
        (bin_dir / "pgrep").chmod(0o755)
        self.env = dict(os.environ)
        self.env.update(
            WINEPREFIX=str(base / "prefix"),
            HSL_ORIGINAL_BACKUPS=str(base / "backups"),
            PATH=f"{bin_dir}{os.pathsep}{os.environ.get('PATH', '')}",
        )

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def run_launcher(self, *args: str) -> subprocess.CompletedProcess[str]:
        result = subprocess.run(
            ["bash", str(self.root / "tools" / "play_original.sh"), *args],
            env=self.env, capture_output=True, text=True, timeout=60,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def test_restore_moves_away_the_config_the_original_wrote(self) -> None:
        (self.saves / "HSL00.SAV").write_bytes(b"USER-ROW-1")
        (self.saves / "HSL01.SAV").write_bytes(b"USER-ROW-2")
        before = snapshot(self.saves)
        self.run_launcher()
        self.assertIn("HSL.CFG", snapshot(self.saves), "the stub original wrote its config")
        self.run_launcher("--restore")
        self.assertEqual(snapshot(self.saves), before)

    def test_restore_puts_back_an_existing_config(self) -> None:
        (self.saves / "HSL00.SAV").write_bytes(b"USER-ROW-1")
        (self.saves / "HSL.CFG").write_bytes(b"MINE")
        before = snapshot(self.saves)
        self.run_launcher()
        self.assertNotEqual(snapshot(self.saves)["HSL.CFG"], b"MINE")
        self.run_launcher("--restore")
        self.assertEqual(snapshot(self.saves), before)

    def test_restore_of_an_empty_row_removes_the_preset(self) -> None:
        self.run_launcher()
        self.run_launcher("--restore")
        self.assertEqual(snapshot(self.saves), {})


if __name__ == "__main__":
    unittest.main()
