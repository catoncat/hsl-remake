"""Unit tests for hsltools.evidence.index (packet header grammar, checks, rendering, module command line)."""
from __future__ import annotations

import io
import contextlib
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import hsltools.evidence.index as index  # noqa: E402

HEADER = "> evidence: static-derived; provisional: synthetic init · status: live · functions: 0x448840, 0x450840 · tools: hsl_probe.py, run_x_tests.gd · updated: 2026-09-10"


def packet(title: str, header: str, body: str = "\n## Section\n\nprose\n") -> str:
    return f"# {title}\n\n{header}\n{body}"


class TempRepo:
    def __init__(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        (self.root / "docs" / "evidence_packets" / "static_reverse").mkdir(parents=True)
        (self.root / "docs" / "evidence_packets" / "runtime_observations" / "case").mkdir(parents=True)
        (self.root / "docs" / "evidence_packets" / "resource_inventory").mkdir(parents=True)
        (self.root / "docs" / "evidence_packets" / "README.md").write_text("# Evidence Packets\n", encoding="utf-8")
        (self.root / "docs" / "KNOWLEDGE_INDEX.md").write_text(
            f"# Index\n\nintro\n\n{index.START_MARK}\nstale\n{index.END_MARK}\n\n## After\n", encoding="utf-8")

    def write(self, relative: str, text: str) -> Path:
        path = self.root / "docs" / "evidence_packets" / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def cleanup(self) -> None:
        self.directory.cleanup()


class HeaderGrammarTests(unittest.TestCase):
    def test_parses_all_fields(self) -> None:
        header = index.parse_header_line(HEADER)
        self.assertEqual([term["tier"] for term in header["evidence"]], ["static-derived", "provisional"])
        self.assertEqual(header["evidence"][1]["scope"], "synthetic init")
        self.assertEqual(header["status"], "live")
        self.assertEqual(header["functions"], ["0x448840", "0x450840"])
        self.assertEqual(header["tools"], ["hsl_probe.py", "run_x_tests.gd"])
        self.assertEqual(header["updated"], "2026-09-10")
        self.assertEqual(index.format_header(header), HEADER)

    def test_rejects_unknown_tier(self) -> None:
        with self.assertRaisesRegex(index.HeaderError, "not one of"):
            index.parse_header_line("> evidence: measured · status: live · updated: 2026-09-10")

    def test_rejects_bad_addresses_and_order(self) -> None:
        with self.assertRaisesRegex(index.HeaderError, "address"):
            index.parse_header_line("> evidence: static-derived · status: live · functions: 0x80000000 · updated: 2026-09-10")
        with self.assertRaisesRegex(index.HeaderError, "ordered"):
            index.parse_header_line("> evidence: static-derived · updated: 2026-09-10 · status: live")

    def test_header_must_follow_title(self) -> None:
        title, line, header = index.split_header("# T\n\nprose first\n> evidence: x\n")
        self.assertEqual((title, line, header), ("T", 2, None))
        title, line, header = index.split_header("# T\n\n" + HEADER + "\n")
        self.assertEqual((title, line), ("T", 2))
        self.assertEqual(header, HEADER)


class RepositoryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.repo = TempRepo()
        self.addCleanup(self.repo.cleanup)

    def run_main(self, *argv: str) -> tuple[int, str, str]:
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = index.main(["--root", str(self.repo.root), *argv])
        return code, out.getvalue(), err.getvalue()

    def test_check_reports_missing_header_and_superseded_target(self) -> None:
        self.repo.write("static_reverse/a.md", "# A\n\nno header here\n")
        self.repo.write("static_reverse/b.md", packet("B", "> evidence: static-derived · status: superseded: gone.md · updated: 2026-09-10"))
        code, _, err = self.run_main("--check")
        self.assertEqual(code, 1)
        self.assertIn("static_reverse/a.md: missing header", err)
        self.assertIn("static_reverse/b.md: superseded target is not a packet: gone.md", err)

    def test_write_then_check_roundtrip_and_json(self) -> None:
        self.repo.write("static_reverse/a.md", packet("Alpha | pipe", HEADER))
        self.repo.write("runtime_observations/case/README.md", packet("Case", "> evidence: runtime-measured · status: superseded: ../../static_reverse/a.md · updated: 2026-09-11"))
        self.repo.write("resource_inventory/r.md", packet("R", "> evidence: resource-derived · status: record-only · updated: 2026-09-12"))
        code, _, err = self.run_main("--check")
        self.assertEqual(code, 1, err)
        self.assertIn("stale", err)
        code, out, _ = self.run_main("--write")
        self.assertEqual(code, 0)
        self.assertIn("EVIDENCE_INDEX_WRITTEN packets=3", out)
        document = (self.repo.root / "docs" / "KNOWLEDGE_INDEX.md").read_text(encoding="utf-8")
        self.assertTrue(document.startswith("# Index\n\nintro\n\n"))
        self.assertTrue(document.endswith("\n\n## After\n"))
        self.assertIn("| [Alpha \\| pipe](evidence_packets/static_reverse/a.md) | static-derived; provisional: synthetic init | live | `0x448840`, `0x450840` | `hsl_probe.py`, `run_x_tests.gd` |", document)
        self.assertIn("| [Case](evidence_packets/runtime_observations/case/README.md) | runtime-measured | superseded → ../../static_reverse/a.md | — | — |", document)
        self.assertIn("### resource_inventory (1)", document)
        code, out, _ = self.run_main("--check")
        self.assertEqual(code, 0)
        self.assertIn("EVIDENCE_INDEX_PASS packets=3", out)
        code, out, _ = self.run_main("--write")
        self.assertEqual(document, (self.repo.root / "docs" / "KNOWLEDGE_INDEX.md").read_text(encoding="utf-8"), "--write must be idempotent")
        code, out, _ = self.run_main("--json")
        self.assertEqual(code, 0)
        self.assertIn('"path": "docs/evidence_packets/static_reverse/a.md"', out)
        self.assertIn('"superseded_by": "../../static_reverse/a.md"', out)

    def test_lint_hints_but_passes(self) -> None:
        self.repo.write("static_reverse/a.md", packet("A", HEADER, "\nBody says runtime-measured and resource-derived.\n"))
        code, out, _ = self.run_main("--lint")
        self.assertEqual(code, 0)
        self.assertIn("tool not found under tools/ or tests/: hsl_probe.py", out)
        self.assertIn("body mentions tiers not in header: resource-derived, runtime-measured", out)
        self.assertIn("EVIDENCE_INDEX_LINT packets=1 hints=", out)

    def test_directory_readme_is_not_a_packet(self) -> None:
        self.repo.write("static_reverse/a.md", packet("A", HEADER))
        self.assertEqual([path.as_posix() for path in index.packet_paths(self.repo.root)], ["docs/evidence_packets/static_reverse/a.md"])


if __name__ == "__main__":
    unittest.main()
