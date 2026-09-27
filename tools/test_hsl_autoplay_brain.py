"""hsltools.checks.autoplay_brain: the autoplay brain comparison check (levels follow the selection
rule over results.json, one row per mode per level, run counts and summary add up)."""
from __future__ import annotations

import copy
import sys
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))

from hsltools.checks import autoplay_brain  # noqa: E402


def campaign() -> dict:
    return {"battles": {
        "1": {"scenario": "res://content/battles/battle_001.json"},
        "2": {"scenario": "res://content/battles/battle_002.json"},
        "60": {"kind": "story", "scenario": "res://content/battles/story_060.json"},
        "3": {"scenario": "res://content/battles/battle_003.json"},
        "501": {"scenario": "res://content/battles/battle_501.json"},
    }}


def results() -> dict:
    levels = {"1": {"outcome": "fail"}, "2": {"outcome": "win"}, "3": {"outcome": "fail"}, "501": {"outcome": "fail"}}
    return {"schema": "hsl_autoplay_results.v1", "battles": len(levels), "levels": levels}


def run(outcome: str, mode: str) -> dict:
    row = {"outcome": outcome, "battle_outcome": {"result": "victory", "reason": "script"} if outcome == "win" else {"result": "defeat", "reason": "fallen"} if outcome == "fail" else {}, "rounds": 4, "seconds": 2.5}
    if outcome == "dead_end":
        row["reason"] = "round_limit"
    if mode != "greedy":
        row["plans"] = 4
    return row


def mode_row(mode: str, outcomes: list[str]) -> dict:
    return {"runs": [run(outcome, mode) for outcome in outcomes], "win": outcomes.count("win"), "fail": outcomes.count("fail"),
            "dead_end": outcomes.count("dead_end"), "plan_kinds": {}}


def comparison() -> dict:
    battles = {"1": {"greedy": mode_row("greedy", ["fail", "fail"]), "scored": mode_row("scored", ["win", "fail"])},
               "3": {"greedy": mode_row("greedy", ["fail", "win"]), "scored": mode_row("scored", ["dead_end", "win"])}}
    return {"schema": "hsl_autoplay_brain_comparison.v1", "modes": ["greedy", "scored"], "levels": ["1", "3"], "repeats": 2,
            "summary": {"greedy": {"runs": 4, "win": 1, "fail": 3, "dead_end": 0, "seconds": 10.0},
                        "scored": {"runs": 4, "win": 2, "fail": 1, "dead_end": 1, "seconds": 10.0}},
            "battles": battles}


class AutoplayBrainCheckTests(unittest.TestCase):
    def test_selection_rule_skips_story_wins_and_encounters_in_campaign_order(self):
        self.assertEqual(autoplay_brain.greedy_lost_main_line(results(), campaign(), 20), ["1", "3"])
        self.assertEqual(autoplay_brain.greedy_lost_main_line(results(), campaign(), 1), ["1"])

    def test_consistent_comparison_passes(self):
        self.assertEqual(autoplay_brain.check_brain_comparison(comparison(), results(), campaign()), [])
        self.assertEqual(autoplay_brain.summary_line(comparison()),
                         "PASS hsl_autoplay_brain_comparison battles=2 repeats=2 greedy=win:1/fail:3/dead_end:0 scored=win:2/fail:1/dead_end:1")

    def test_levels_must_follow_the_selection_rule(self):
        wrong = comparison()
        wrong["levels"] = ["1", "2"]
        wrong["battles"]["2"] = wrong["battles"].pop("3")
        errors = autoplay_brain.check_brain_comparison(wrong, results(), campaign())
        self.assertTrue(any("greedy-lost main-line battles" in error for error in errors), errors)

    def test_every_level_needs_one_row_per_mode_with_repeats_runs(self):
        missing_mode = comparison()
        del missing_mode["battles"]["3"]["scored"]
        errors = autoplay_brain.check_brain_comparison(missing_mode, results(), campaign())
        self.assertTrue(any("level 3: one row per mode" in error for error in errors), errors)
        short = comparison()
        short["battles"]["1"]["greedy"]["runs"].pop()
        errors = autoplay_brain.check_brain_comparison(short, results(), campaign())
        self.assertTrue(any("level 1 greedy: runs must list exactly repeats=2" in error for error in errors), errors)

    def test_unknown_mode_fails(self):
        unknown = comparison()
        unknown["modes"] = ["greedy", "oracle"]
        errors = autoplay_brain.check_brain_comparison(unknown, results(), campaign())
        self.assertTrue(any("modes must be a non-empty list" in error for error in errors), errors)

    def test_counts_and_summary_must_add_up(self):
        miscounted = copy.deepcopy(comparison())
        miscounted["battles"]["1"]["scored"]["win"] = 2
        errors = autoplay_brain.check_brain_comparison(miscounted, results(), campaign())
        self.assertTrue(any("level 1 scored: win must equal the run count 1" in error for error in errors), errors)
        drifted = comparison()
        drifted["summary"]["greedy"]["fail"] = 2
        errors = autoplay_brain.check_brain_comparison(drifted, results(), campaign())
        self.assertTrue(any("summary greedy: fail must equal the recount 3" in error for error in errors), errors)

    def test_brain_runs_record_plans_and_dead_ends_need_a_reason(self):
        no_plans = comparison()
        del no_plans["battles"]["1"]["scored"]["runs"][0]["plans"]
        errors = autoplay_brain.check_brain_comparison(no_plans, results(), campaign())
        self.assertTrue(any("records its plans count" in error for error in errors), errors)
        no_reason = comparison()
        del no_reason["battles"]["3"]["scored"]["runs"][0]["reason"]
        errors = autoplay_brain.check_brain_comparison(no_reason, results(), campaign())
        self.assertTrue(any("dead_end reason must be one of" in error for error in errors), errors)


if __name__ == "__main__":
    unittest.main()
