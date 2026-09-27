"""hsltools.checks.autoplay_results: the autoplay sweep results check (every registered battle has a
row, dead_ends must be known, known entries must still be dead_ends)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))

from hsltools.checks import autoplay_results  # noqa: E402

ROOT = TOOLS.parent
VOCABULARY = autoplay_results.battle_outcome_vocabulary(ROOT)
VICTORY = {"result": "victory", "reason": "escape"}
DEFEAT = {"result": "defeat", "reason": "fallen"}


def check(results_payload: dict, known_payload: dict, campaign_payload: dict) -> list[str]:
    return autoplay_results.check_autoplay_results(results_payload, known_payload, campaign_payload, VOCABULARY)


def campaign() -> dict:
    return {"battles": {
        "51": {"scenario": "res://content/battles/first_battle.json"},
        "501": {"scenario": "res://content/battles/battle_501.json"},
        "60": {"kind": "story", "scenario": "res://content/battles/story_060.json"},
    }}


def row(outcome: str, **overrides) -> dict:
    base = {"outcome": outcome, "battle_outcome": VICTORY if outcome == "win" else DEFEAT if outcome == "fail" else {},
            "rounds": 5, "reason": "", "unit": "", "round": 0, "detail": "", "actions": {}, "result_page": True}
    base.update(overrides)
    return base


def results(**rows) -> dict:
    levels = rows or {"51": row("fail"), "501": row("win")}
    return {"schema": "hsl_autoplay_results.v1", "battles": len(levels), "loop_seed": 1, "levels": levels}


def known(**levels) -> dict:
    return {"schema": "hsl_autoplay_known_dead_ends.v1", "levels": levels}


def known_entry(reason: str = "round_limit") -> dict:
    return {"reason": reason, "unit": "leonard", "round": 61, "first_observed_commit": "b8cb9afa", "note": "greedy never reaches the escape zone"}


class AutoplayResultsCheckTests(unittest.TestCase):
    def test_complete_results_with_no_dead_end_pass(self):
        self.assertEqual(check(results(), known(), campaign()), [])
        self.assertEqual(autoplay_results.summary_line(results(), known()),
                         "PASS hsl_autoplay_results battles=2 win=1 fail=1 dead_end=0 known_hit=0 known_not_hit=0")

    def test_missing_and_unregistered_rows_fail(self):
        errors = check(results(**{"51": row("fail"), "7": row("win")}), known(), campaign())
        self.assertTrue(any("without a result row: ['501']" in error for error in errors), errors)
        self.assertTrue(any("unregistered battles: ['7']" in error for error in errors), errors)

    def test_unknown_dead_end_fails_and_known_dead_end_passes(self):
        dead = results(**{"51": row("dead_end", reason="round_limit", unit="leonard", round=61), "501": row("win")})
        errors = check(dead, known(), campaign())
        self.assertTrue(any("is not listed in known_dead_ends.json" in error for error in errors), errors)
        self.assertEqual(check(dead, known(**{"51": known_entry()}), campaign()), [])

    def test_known_reason_must_match_the_result(self):
        dead = results(**{"51": row("dead_end", reason="no_legal_action", unit="leonard", round=3), "501": row("win")})
        errors = check(dead, known(**{"51": known_entry("round_limit")}), campaign())
        self.assertTrue(any("differs from the result" in error for error in errors), errors)

    def test_known_entry_shape(self):
        entry = known_entry()
        del entry["first_observed_commit"]
        errors = check(
            results(**{"51": row("dead_end", reason="round_limit"), "501": row("win")}), known(**{"51": entry}), campaign())
        self.assertTrue(any("first_observed_commit must be a non-empty string" in error for error in errors), errors)
        errors = check(results(), known(**{"7": known_entry()}), campaign())
        self.assertTrue(any("not a registered battle" in error for error in errors), errors)

    def test_row_shape(self):
        bad = results(**{"51": row("fail", reason="round_limit"), "501": row("win", rounds=-1, seconds=1.2, battle_outcome={})})
        errors = check(bad, known(), campaign())
        self.assertTrue(any("must not carry a reason" in error for error in errors), errors)
        self.assertTrue(any("rows must not carry a wall clock" in error for error in errors), errors)

    def test_battle_outcome_is_the_structure_spelled_by_battle_outcome_gd(self):
        handoff = results(**{"51": row("fail"), "501": row("win", battle_outcome={"result": "victory", "reason": "event_handoff"})})
        self.assertEqual(check(handoff, known(), campaign()), [])
        for bad_outcome, message in (("victory_escape", "must be an object"), ({"result": "victory", "reason": "leonard"}, "reason must be one of")):
            errors = check(results(**{"51": row("fail"), "501": row("win", battle_outcome=bad_outcome)}), known(), campaign())
            self.assertTrue(any(message in error for error in errors), (bad_outcome, errors))
        crossed = results(**{"51": row("fail", battle_outcome=VICTORY), "501": row("win", battle_outcome=DEFEAT)})
        errors = check(crossed, known(), campaign())
        self.assertTrue(any("a win row names a victory battle_outcome" in error for error in errors), errors)


if __name__ == "__main__":
    unittest.main()
