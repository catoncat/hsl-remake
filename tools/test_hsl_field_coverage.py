"""Unit tests for hsltools.checks.field_coverage citation validation (the measured report itself is the field_coverage gate)."""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import hsltools.checks.field_coverage as field_coverage  # noqa: E402


class CitationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / 'game/sim').mkdir(parents=True)
        (self.root / 'game/sim/Rules.gd').write_text('extends RefCounted\nconst TOKENS := []\nstatic func prepare(a):\n\tpass\nfunc _step():\n\tpass\n', encoding='utf-8')
        (self.root / 'tools').mkdir()
        (self.root / 'tools/gen.py').write_text('OUTPUT = 1\n\ndef build():\n    pass\n\nclass Task:\n    pass\n', encoding='utf-8')

    def test_defined_symbols_resolve(self) -> None:
        for citation in ('game/sim/Rules.gd:prepare', 'game/sim/Rules.gd:_step', 'game/sim/Rules.gd:TOKENS',
                         'tools/gen.py:build', 'tools/gen.py:Task', 'tools/gen.py:OUTPUT'):
            self.assertIsNone(field_coverage.citation_error(self.root, citation), citation)

    def test_missing_symbol_file_or_shape_is_named(self) -> None:
        self.assertIn('not defined', field_coverage.citation_error(self.root, 'game/sim/Rules.gd:resolve'))
        self.assertIn('does not exist', field_coverage.citation_error(self.root, 'game/sim/Other.gd:prepare'))
        self.assertIn('expected path:symbol', field_coverage.citation_error(self.root, 'game/sim/Rules.gd'))


if __name__ == '__main__':
    unittest.main()
