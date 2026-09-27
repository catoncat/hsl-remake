"""Shell scripts must brace a variable that is followed directly by a non-ASCII character.

macOS /bin/bash (3.2) under a UTF-8 locale reads the first byte of a following multibyte character as
part of the variable name: `echo "$CFG_FILE：…"` expands the variable `CFG_FILE\\xef`, and with `set -u`
the script dies with "unbound variable". Which bash runs depends on PATH (Homebrew bash 5 is not
affected), so this broke tools/play_original.sh only under the gate's PATH. Write `${CFG_FILE}：`.
"""
from __future__ import annotations

import re
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UNBRACED = re.compile(r"\$[A-Za-z_][A-Za-z0-9_]*(?=[^\x00-\x7F])")


def unbraced_hits(text: str, name: str) -> list[str]:
    hits = []
    for number, line in enumerate(text.splitlines(), 1):
        if line.lstrip().startswith("#"):
            continue
        hits.extend(f"{name}:{number}: {match.group(0)}" for match in UNBRACED.finditer(line))
    return hits


class ShellVariableBraceTests(unittest.TestCase):
    def test_tracked_shell_scripts_brace_variables_before_non_ascii(self) -> None:
        files = subprocess.run(["git", "ls-files", "*.sh"], cwd=ROOT, capture_output=True, text=True, check=True).stdout.split()
        self.assertTrue(files, "no tracked shell scripts found")
        hits = [hit for name in files for hit in unbraced_hits((ROOT / name).read_text(encoding="utf-8"), name)]
        self.assertEqual(hits, [], "brace these variables (macOS /bin/bash reads the next byte into the name)")

    def test_detector_flags_the_original_bug(self) -> None:
        self.assertEqual(unbraced_hits('echo "装入前没有 $CFG_FILE：已移走"', "x.sh"), ["x.sh:1: $CFG_FILE"])
        self.assertEqual(unbraced_hits('echo "装入前没有 ${CFG_FILE}：已移走"', "x.sh"), [])
        self.assertEqual(unbraced_hits('# $CFG_FILE：in a comment', "x.sh"), [])


if __name__ == "__main__":
    unittest.main()
