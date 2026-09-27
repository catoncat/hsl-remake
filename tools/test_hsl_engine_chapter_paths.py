"""engine:chapter_paths — a chapter01 path in engine code, a doc comment or a provenance note
must fail; a provenance term's cited path must pass and be counted."""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from hsltools.checks.engine_chapter_paths import engine_files, scan  # noqa: E402

HEADER = """extends Node
## provenance:
##   rules: n/a
##   layout: resource-derived content/imported/hsl/chapter01/battle052/opening_timeline.json (EVEF pixels)
##   strings: n/a
##   timing: n/a
##   audio: resource-derived content/imported/hsl/shared/interface_audio/manifest.json
"""


class EngineChapterPathsTests(unittest.TestCase):
    def scan(self, files: dict[str, str]) -> tuple[list[str], int]:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name, text in files.items():
                (root / name).parent.mkdir(parents=True, exist_ok=True)
                (root / name).write_text(text, encoding="utf-8")
            (root / "game" / "A.gd.uid").write_text("uid://chapter01/ignored")
            return scan(root, engine_files(root))

    def test_provenance_term_path_is_a_counted_citation(self) -> None:
        self.assertEqual(self.scan({"game/A.gd": HEADER + "const X := 1\n"}), ([], 1))

    def test_code_literal_fails(self) -> None:
        issues, _ = self.scan({"game/A.gd": HEADER + 'const X := "res://content/imported/hsl/chapter01/portraits/manifest.json"\n'})
        self.assertEqual(len(issues), 1)
        self.assertTrue(issues[0].startswith("game/A.gd:8: const X"), issues)

    def test_built_path_fails(self) -> None:
        issues, _ = self.scan({"game/A.gd": HEADER + 'var dir := "res://content/imported/hsl/%s" % "chapter01"\n'})
        self.assertEqual(len(issues), 1)

    def test_doc_comment_and_provenance_note_fail(self) -> None:
        noted = HEADER.replace("(EVEF pixels)", "(see chapter01/battle051 too)")
        issues, citations = self.scan({"game/A.gd": noted + "## loads content/imported/hsl/chapter01/scripts\n"})
        self.assertEqual([issue.split(":")[1] for issue in issues], ["4", "8"])
        self.assertEqual(citations, 0)


if __name__ == "__main__":
    unittest.main()
