"""hsltools.checks.autoplay_chapter: the chapter autoplay check (rows name registered battles, attempts
run base_seed upward and stop at the first win, a lost battle is the last row and stuck_at, counts add up)."""
from __future__ import annotations

import copy
import sys
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))

from hsltools.checks import autoplay_chapter  # noqa: E402


def campaign() -> dict:
    return {"battles": {
        "51": {"scenario": "res://content/battles/first_battle.json"},
        "52": {"scenario": "res://content/battles/battle_052.json"},
        "58": {"kind": "story", "scenario": "res://content/battles/story_058.json"},
    }}


def attempt(seed: int, outcome: str) -> dict:
    row = {"seed": seed, "outcome": outcome, "battle_outcome": {"result": "victory", "reason": "boss"} if outcome == "win" else {"result": "defeat", "reason": "fallen"} if outcome == "fail" else {}, "rounds": 6, "seconds": 3.0}
    if outcome == "dead_end":
        row["reason"] = "stalemate_no_contact"
    return row


def battle(level: int, outcomes: list[str]) -> dict:
    return {"level": level, "scenario": f"battle_{level}.json", "outcome": outcomes[-1], "battle_outcome": {}, "tries": len(outcomes),
            "party": {"leonard": 1}, "attempts": [attempt(1 + index, outcome) for index, outcome in enumerate(outcomes)]}


def chapter() -> dict:
    battles = [battle(51, ["win"]), battle(52, ["fail", "fail", "dead_end"])]
    return {"schema": "hsl_autoplay_chapter.v1", "start": "campaign", "tries_limit": 3, "base_seed": 1, "game_clear": False,
            "stuck_at": {"level": 52, "outcome": "dead_end", "reason": "stalemate_no_contact"},
            "battles_fought": 2, "battles_won": 1, "retries": 2, "battles": battles}


class AutoplayChapterCheckTests(unittest.TestCase):
    def test_consistent_stuck_chapter_passes(self):
        self.assertEqual(autoplay_chapter.check_chapter(chapter(), campaign()), [])
        self.assertEqual(autoplay_chapter.summary_line(chapter()),
                         "PASS hsl_autoplay_chapter start=campaign brain=scored gold=normal stat_scale=1 game_clear=false stuck_at=52 budget_exhausted_at=none battles=2 won=1 retries=2 tries_limit=3 shops=0 purchases=0")

    def test_knobs_and_shop_receipts_are_checked(self):
        knobbed = chapter()
        knobbed["knobs"] = {"gold": "unlimited", "stat_scale": 1.5}
        knobbed["towns"] = [{"town": 3, "ok": True, "gold_mode": "unlimited", "gold_before": 5000, "gold_after": 5000, "purchases": [{"unit": "leonard", "item": 2, "cost": 500, "slot": "weapon", "equipped": True}], "skipped": []}]
        self.assertEqual(autoplay_chapter.check_chapter(knobbed, campaign()), [])
        bad_gold = copy.deepcopy(knobbed)
        bad_gold["knobs"]["gold"] = "infinite"
        self.assertTrue(any("knobs must name gold" in error for error in autoplay_chapter.check_chapter(bad_gold, campaign())))
        bad_towns = copy.deepcopy(knobbed)
        bad_towns["towns"] = [{"town": 3}]
        self.assertTrue(any("towns must list shop receipts" in error for error in autoplay_chapter.check_chapter(bad_towns, campaign())))

    def test_budget_exhausted_run_ends_on_a_win_without_stuck_at(self):
        cut = chapter()
        cut["battles"] = [battle(51, ["win"])]
        cut.update({"brain": "lookahead", "stuck_at": {}, "battles_won": 1, "battles_fought": 1, "retries": 0, "budget_exhausted": {"level": 52, "scenario": "battle_052.json", "budget_seconds": 600}})
        self.assertEqual(autoplay_chapter.check_chapter(cut, campaign()), [])
        with_stuck = copy.deepcopy(cut)
        with_stuck["stuck_at"] = {"level": 52, "outcome": "fail"}
        self.assertTrue(any("budget_exhausted leaves no stuck_at" in error for error in autoplay_chapter.check_chapter(with_stuck, campaign())))
        lost = copy.deepcopy(cut)
        lost["battles"] = [battle(51, ["fail"])]
        lost["battles_won"] = 0
        self.assertTrue(any("requires every battle row to be a win" in error for error in autoplay_chapter.check_chapter(lost, campaign())))

    def test_cleared_chapter_needs_every_row_won_and_no_stuck_at(self):
        cleared = chapter()
        cleared["battles"] = [battle(51, ["fail", "win"]), battle(52, ["win"])]
        cleared.update({"game_clear": True, "stuck_at": {}, "battles_won": 2, "retries": 1})
        self.assertEqual(autoplay_chapter.check_chapter(cleared, campaign()), [])
        cleared["stuck_at"] = {"level": 52}
        self.assertTrue(any("leaves no stuck_at" in error for error in autoplay_chapter.check_chapter(cleared, campaign())))

    def test_rows_name_registered_battles_and_seeds_run_upward(self):
        unregistered = chapter()
        unregistered["battles"][0]["level"] = 58
        errors = autoplay_chapter.check_chapter(unregistered, campaign())
        self.assertTrue(any("registered campaign battle key" in error for error in errors), errors)
        skipped = copy.deepcopy(chapter())
        skipped["battles"][1]["attempts"][1]["seed"] = 5
        errors = autoplay_chapter.check_chapter(skipped, campaign())
        self.assertTrue(any("seed must be base_seed+1=2" in error for error in errors), errors)

    def test_a_win_ends_the_attempts_and_a_loss_ends_the_walk(self):
        won_early = chapter()
        won_early["battles"][1]["attempts"][0]["outcome"] = "win"
        errors = autoplay_chapter.check_chapter(won_early, campaign())
        self.assertTrue(any("no later attempt may follow" in error for error in errors), errors)
        lost_early = chapter()
        lost_early["battles"] = [battle(51, ["fail"]), battle(52, ["fail", "fail", "dead_end"])]
        lost_early["battles_won"] = 0
        errors = autoplay_chapter.check_chapter(lost_early, campaign())
        self.assertTrue(any("must be the last row" in error for error in errors), errors)

    def test_stuck_at_and_counts_must_match_the_rows(self):
        wrong_stuck = chapter()
        wrong_stuck["stuck_at"] = {"level": 51, "outcome": "fail"}
        errors = autoplay_chapter.check_chapter(wrong_stuck, campaign())
        self.assertTrue(any("stuck_at must name the last row" in error for error in errors), errors)
        drifted = chapter()
        drifted["retries"] = 1
        errors = autoplay_chapter.check_chapter(drifted, campaign())
        self.assertTrue(any("retries must equal the recount 2" in error for error in errors), errors)
        too_many = chapter()
        too_many["tries_limit"] = 2
        errors = autoplay_chapter.check_chapter(too_many, campaign())
        self.assertTrue(any("1..tries_limit=2" in error for error in errors), errors)


if __name__ == "__main__":
    unittest.main()
