"""Unit tests for hsltools.checks.provenance (module header grammar, check, generated block)."""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import hsltools.checks.provenance as provenance  # noqa: E402
from hsltools import registry  # noqa: E402

PACKET = "docs/evidence_packets/static_reverse/original_growth_lifecycle.md"
TABLE = "content/imported/hsl/global/tables/OBJ-ALL.H"


def block(rules: str = f"static-derived {PACKET}", layout: str = "n/a", strings: str = f"resource-derived {TABLE}",
          timing: str = "remake-invented (fade lengths chosen for the remake)", audio: str = "n/a") -> str:
    return "\n".join([
        "## provenance:",
        f"##   rules: {rules}",
        f"##   layout: {layout}",
        f"##   strings: {strings}",
        f"##   timing: {timing}",
        f"##   audio: {audio}",
    ])


def module(header: str, prologue: str = "extends RefCounted\n## One-line description.\n", body: str = "\n\nfunc run() -> void:\n\tpass\n") -> str:
    return prologue + header + body


class TempRepo:
    def __init__(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        for relative in (PACKET, TABLE):
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("# evidence\n", encoding="utf-8")
        (self.root / "docs" / "PROVENANCE.md").write_text(
            f"# Provenance\n\nintro\n\n{provenance.START_MARK}\nstale\n{provenance.END_MARK}\n\n## After\n", encoding="utf-8")

    def write(self, relative: str, text: str) -> Path:
        path = self.root / "game" / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def cleanup(self) -> None:
        self.directory.cleanup()


class HeaderGrammarTests(unittest.TestCase):
    def setUp(self) -> None:
        self.repo = TempRepo()
        self.addCleanup(self.repo.cleanup)

    def parse(self, text: str, name: str = "sim/Rules.gd") -> dict:
        self.repo.write(name, text)
        return provenance.parse_module(self.repo.root, Path("game") / name)

    def test_parses_tags_paths_anchors_and_notes(self) -> None:
        parsed = self.parse(module(block(layout=f"runtime-reference {PACKET}#16; provisional (spacing eyeballed)")))
        self.assertEqual(parsed["path"], "game/sim/Rules.gd")
        self.assertEqual(parsed["dimensions"]["rules"], [{"tag": "static-derived", "path": PACKET, "anchor": None, "note": None}])
        self.assertEqual(parsed["dimensions"]["layout"][0], {"tag": "runtime-reference", "path": PACKET, "anchor": "16", "note": None})
        self.assertEqual(parsed["dimensions"]["layout"][1], {"tag": "provisional", "path": None, "anchor": None, "note": "spacing eyeballed"})
        self.assertEqual(parsed["dimensions"]["timing"][0]["note"], "fade lengths chosen for the remake")
        self.assertEqual(parsed["dimensions"]["audio"], [])

    def test_rejects_unknown_tag_and_dimension_order(self) -> None:
        with self.assertRaisesRegex(provenance.HeaderError, "not one of"):
            self.parse(module(block(rules="measured")))
        with self.assertRaisesRegex(provenance.HeaderError, "in that order"):
            self.parse(module("## provenance:\n##   layout: n/a\n##   rules: remake-invented\n##   strings: n/a\n##   timing: n/a\n##   audio: n/a"))

    def test_derived_tags_need_an_existing_repository_path(self) -> None:
        with self.assertRaisesRegex(provenance.HeaderError, "requires a repository path"):
            self.parse(module(block(rules="static-derived")))
        with self.assertRaisesRegex(provenance.HeaderError, "does not exist"):
            self.parse(module(block(rules="static-derived docs/evidence_packets/static_reverse/missing.md")))


class TaskTests(unittest.TestCase):
    def setUp(self) -> None:
        self.repo = TempRepo()
        self.addCleanup(self.repo.cleanup)
        self.ctx = registry.Context(root=self.repo.root)
        self.task = provenance.ProvenanceTask()

    def test_check_fails_naming_missing_and_invalid_modules(self) -> None:
        self.repo.write("sim/Good.gd", module(block()))
        self.repo.write("sim/NoHeader.gd", module("## plain description"))
        self.repo.write("world/Bad.gd", module(block(rules="guess")))
        with self.assertRaises(registry.CheckFailed) as caught:
            self.task.check(self.ctx)
        message = str(caught.exception)
        self.assertIn("PROVENANCE_FAIL modules=3 missing=1 invalid=1", message)
        self.assertIn("game/sim/NoHeader.gd: missing", message)
        self.assertIn("game/world/Bad.gd: line 4 (rules): tag 'guess'", message)

    def test_generate_then_check_round_trips_and_lists_remake_invented(self) -> None:
        self.repo.write("sim/Good.gd", module(block()))
        self.repo.write("battle/View.gd", module(block(rules="n/a", layout="runtime-reference " + PACKET + "#frame_001",
                                                        strings="n/a", timing="provisional (settle frames guessed)",
                                                        audio="remake-invented docs/evidence_packets/static_reverse/original_growth_lifecycle.md (remake music)")))
        # A stale document is a warning, not a failure (it is re-rendered at merge time).
        self.assertEqual(self.task.check(self.ctx), "PROVENANCE_PASS modules=2 missing=0 invalid=0 stale_document=1")
        self.assertEqual(self.task.generate(self.ctx), "PROVENANCE_WRITTEN modules=2 file=docs/PROVENANCE.md")
        self.assertEqual(self.task.check(self.ctx), "PROVENANCE_PASS modules=2 missing=0 invalid=0")
        text = (self.repo.root / "docs" / "PROVENANCE.md").read_text(encoding="utf-8")
        self.assertTrue(text.endswith(provenance.END_MARK + "\n\n## After\n"))
        self.assertIn("### remake-invented 清单 (2)", text)


if __name__ == "__main__":
    unittest.main()
