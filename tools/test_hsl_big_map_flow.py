"""Offline unit tests for hsltools.data.big_map_flow (tracked report only, no PAK)."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

import hsltools.data.big_map_flow as flow  # noqa: E402

REPORT = ROOT / "content/generated/hsl/static/hsl01/big_map_flow.json"


class BigMapFlowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.report = json.loads(REPORT.read_text(encoding="utf-8"))
        cls.table = flow.symbols()

    def test_tracked_report_checks_offline(self) -> None:
        self.assertEqual(flow.check(self.report, self.table), [])
        self.assertEqual(self.report["schema"], flow.SCHEMA)
        self.assertEqual(self.table["gameBigMapLevel"], 49)
        self.assertEqual(self.table["bmpmVisit"], 0x10000000)

    def test_symbol_resolution(self) -> None:
        self.assertEqual(flow.resolve("gameBigMapLevel", self.table), 49)
        self.assertEqual(flow.resolve("town_歐姆村", self.table), 1)
        self.assertEqual(flow.resolve("501", self.table), 501)
        self.assertIsNone(flow.resolve("SID_PLAYER0", self.table))

    def test_level_two_chain_reads_event_as_next_level(self) -> None:
        events = {(e["kind"], e["level"]): e for e in self.report["next_level_events"]}
        self.assertEqual((events[("winfail", 2)]["level_arg"], events[("winfail", 2)]["event_arg"]), (2, 55))
        self.assertEqual((events[("story", 55)]["level_arg"], events[("story", 55)]["event_arg"]), (2, 56))
        self.assertEqual((events[("story", 56)]["level_arg"], events[("story", 56)]["event_arg"]), (2, 49))
        self.assertTrue(events[("story", 56)]["to_big_map"])
        self.assertEqual(self.report["level_return_points"]["56"], 2)

    def test_same_id_conventions_hold_for_every_battle_and_encounter(self) -> None:
        same = self.report["battle_return_point_equals_level"]
        self.assertEqual(same["same"], same["total"])
        self.assertGreaterEqual(same["total"], 17)
        enc = self.report["encounter_return_matches_assigned_point"]
        self.assertEqual(enc["same"], enc["total"])
        self.assertGreaterEqual(enc["total"], 28)
        self.assertIn(2, self.report["post_clear_visit_writes"])

    def test_point_event_writes_carry_flags(self) -> None:
        writes = [(w["level"], w["point"], w["event"], w["flag"]) for w in self.report["point_event_writes"] if w["kind"] == "story" and w["level"] == 8]
        self.assertIn((8, 9, 9, "bmpmBattle"), writes)
        winfail002 = [(w["point"], w["event"], w["flag"]) for w in self.report["point_event_writes"] if w["kind"] == "winfail" and w["level"] == 2]
        self.assertEqual(winfail002, [(2, 501, "bmpmVisit")])

    def test_derive_rejects_tampered_summary(self) -> None:
        tampered = json.loads(json.dumps(self.report))
        tampered["level_return_points"]["56"] = 3
        self.assertTrue(any("level_return_points" in error for error in flow.check(tampered, self.table)))


if __name__ == "__main__":
    unittest.main()
