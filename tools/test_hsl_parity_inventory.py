"""Unit tests for hsltools.checks.parity_inventory (source extraction, classification)."""
from __future__ import annotations

import copy
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import hsltools.checks.parity_inventory as inventory  # noqa: E402
from hsltools.paths import ROOT  # noqa: E402


def live() -> tuple[dict, dict, list]:
    curation = inventory.load_curation(ROOT)
    sources = inventory.live_sources(ROOT, curation)
    items, errors = inventory.validate_items(ROOT, curation)
    assert not errors, errors
    return curation, sources, items


class SentenceExtractionTests(unittest.TestCase):
    def test_packet_sentences_skip_header_code_and_own_output(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            packet = root / "docs/evidence_packets/static_reverse/sample.md"
            packet.parent.mkdir(parents=True)
            packet.write_text("# 样例\n\n> evidence: provisional: 未读的范围 · status: live · updated: 2026-09-25\n\n"
                              "镜头跟随未复刻。已照做。\n\n```\n代码块里未读\n```\n| 行 | 表现层未读 |\n", encoding="utf-8")
            own = root / inventory.OUTPUT_DOC
            own.write_text("# 清单\n\n清单引用的句子未读。\n", encoding="utf-8")
            texts = sorted(source["text"] for source in inventory.sentence_sources(root).values())
            self.assertEqual(texts, ["表现层未读", "镜头跟随未复刻。"])


class ClassificationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.curation, self.sources, self.items = live()

    def test_a_new_source_without_classification_is_reported(self) -> None:
        sources = dict(self.sources)
        sources["provenance:game/sim/New.gd|layout|remake-invented|"] = {"kind": "provenance", "module": "game/sim/New.gd",
                                                                        "dimension": "layout", "tag": "remake-invented", "note": ""}
        _, unclassified, _ = inventory.classify(ROOT, self.curation, sources, self.items)
        self.assertEqual(unclassified, ["provenance:game/sim/New.gd|layout|remake-invented|"])

    def test_a_classification_for_a_vanished_source_is_an_error(self) -> None:
        curation = copy.deepcopy(self.curation)
        curation["sources"]["matrix:不存在的机制"] = {"no_visible_effect": "test"}
        _, _, errors = inventory.classify(ROOT, curation, self.sources, self.items)
        self.assertIn("classification for a source that no longer exists: matrix:不存在的机制", errors)

    def test_item_fields_and_code_refs_are_validated(self) -> None:
        curation = copy.deepcopy(self.curation)
        curation["items"][0]["visibility"] = "sometimes"
        curation["items"][1]["remake_code"] = ["game/battle/scene/BattleDialogue.gd:no_such_function"]
        _, errors = inventory.validate_items(ROOT, curation)
        self.assertTrue(any("visibility 'sometimes'" in error for error in errors), errors)
        self.assertTrue(any("'no_such_function' is not defined" in error for error in errors), errors)


if __name__ == "__main__":
    unittest.main()
