"""Structural check of the chapter autoplay run (content/generated/hsl/development/autoplay/chapter.json).

Registry task autoplay_chapter (family autoplay, CheckTask, replaces=()). chapter.json is written by
tests/run_chapter_autoplay_tests.gd: the story explorer's walk with every formal battle fought by the
scored autoplay commander and the party's growth carried, a lost battle replayed with the next loop
seed up to tries_limit. The check proves: the file parses with its schema, every battle row names a
registered campaign battle with 1..tries_limit attempts whose seeds run base_seed, base_seed+1, …,
whose last attempt is the row's outcome, whose earlier attempts were all lost, and where every row
but the last is a win; `knobs` names the harness diagnostics the run used (gold normal / unlimited, stat_scale) and
`towns` its shop receipts; `stuck_at` is empty exactly when `game_clear` is true or the run stopped at its
time budget (`budget_exhausted` names the battle it did not start; every row is then a win), otherwise
it is the last row (a lost battle); `battles_fought` / `battles_won` / `retries` equal the recount. Whether the chapter
clears is recorded, never asserted; nothing here is evidence about original balance. Not part of the
fast gate's checks-by-suite (the run itself is a deep-gate suite).
"""
from __future__ import annotations

import json
from pathlib import Path

from hsltools.checks import CheckTask
from hsltools.checks.autoplay_results import CAMPAIGN, DEAD_END_REASONS, OUTCOMES
from hsltools.registry import CheckFailed, Context

CHAPTER = "content/generated/hsl/development/autoplay/chapter.json"
CHAPTER_SCHEMA = "hsl_autoplay_chapter.v1"
STARTS = ("campaign", "ohm_village")
GOLD_MODES = ("normal", "unlimited")


def _positive_int(value) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value >= 1


def check_chapter(chapter: dict, campaign: dict) -> list[str]:
    errors: list[str] = []
    if chapter.get("schema") != CHAPTER_SCHEMA:
        errors.append(f"schema must be {CHAPTER_SCHEMA}: {chapter.get('schema')!r}")
    tries_limit = chapter.get("tries_limit")
    base_seed = chapter.get("base_seed")
    battles = chapter.get("battles")
    stuck_at = chapter.get("stuck_at")
    game_clear = chapter.get("game_clear")
    if not _positive_int(tries_limit):
        return errors + [f"tries_limit must be a positive integer: {tries_limit!r}"]
    if not isinstance(base_seed, int) or isinstance(base_seed, bool):
        return errors + [f"base_seed must be an integer: {base_seed!r}"]
    if chapter.get("start") not in STARTS:
        errors.append(f"start must be one of {STARTS}: {chapter.get('start')!r}")
    if not isinstance(battles, list) or not isinstance(stuck_at, dict) or not isinstance(game_clear, bool):
        return errors + ["battles must be a list, stuck_at an object and game_clear a boolean"]
    budget_exhausted = chapter.get("budget_exhausted", {})
    if not isinstance(budget_exhausted, dict):
        return errors + ["budget_exhausted must be an object (empty when the run was not cut off)"]
    knobs = chapter.get("knobs", {"gold": "normal", "stat_scale": 1})
    if not isinstance(knobs, dict) or knobs.get("gold") not in GOLD_MODES or not isinstance(knobs.get("stat_scale"), (int, float)) or isinstance(knobs.get("stat_scale"), bool) or knobs["stat_scale"] <= 0:
        errors.append(f"knobs must name gold in {GOLD_MODES} and a positive stat_scale: {knobs!r}")
    towns = chapter.get("towns", [])
    if not isinstance(towns, list) or any(not isinstance(row, dict) or not isinstance(row.get("purchases"), list) for row in towns):
        errors.append("towns must list shop receipts, each with a purchases list")
    registered = {key for key, entry in campaign.get("battles", {}).items() if "kind" not in entry}
    wins = 0
    retries = 0
    for index, row in enumerate(battles):
        label = f"battle row {index}"
        if not isinstance(row, dict):
            errors.append(f"{label}: must be an object")
            continue
        level = row.get("level")
        if not isinstance(level, int) or isinstance(level, bool) or str(level) not in registered:
            errors.append(f"{label}: level must be a registered campaign battle key: {level!r}")
        outcome = row.get("outcome")
        if outcome not in OUTCOMES:
            errors.append(f"{label}: outcome must be one of {OUTCOMES}: {outcome!r}")
            continue
        attempts = row.get("attempts")
        if not isinstance(attempts, list) or not 1 <= len(attempts) <= tries_limit:
            errors.append(f"{label}: attempts must list 1..tries_limit={tries_limit} attempts")
            continue
        if row.get("tries") != len(attempts):
            errors.append(f"{label}: tries must equal the attempt count {len(attempts)}: {row.get('tries')!r}")
        for number, attempt in enumerate(attempts):
            if not isinstance(attempt, dict):
                errors.append(f"{label} attempt {number}: must be an object")
                continue
            if attempt.get("seed") != base_seed + number:
                errors.append(f"{label} attempt {number}: seed must be base_seed+{number}={base_seed + number}: {attempt.get('seed')!r}")
            attempt_outcome = attempt.get("outcome")
            if attempt_outcome not in OUTCOMES:
                errors.append(f"{label} attempt {number}: outcome must be one of {OUTCOMES}: {attempt_outcome!r}")
                continue
            if number < len(attempts) - 1 and attempt_outcome == "win":
                errors.append(f"{label} attempt {number}: a won attempt ends the battle, no later attempt may follow")
            if attempt_outcome == "dead_end" and attempt.get("reason") not in DEAD_END_REASONS:
                errors.append(f"{label} attempt {number}: dead_end reason must be one of {DEAD_END_REASONS}: {attempt.get('reason')!r}")
            if not isinstance(attempt.get("rounds"), int) or attempt["rounds"] < 0:
                errors.append(f"{label} attempt {number}: rounds must be a non-negative integer")
        if isinstance(attempts[-1], dict) and attempts[-1].get("outcome") in OUTCOMES and attempts[-1]["outcome"] != outcome:
            errors.append(f"{label}: outcome must be the last attempt's outcome {attempts[-1]['outcome']}: {outcome!r}")
        if not isinstance(row.get("party"), dict):
            errors.append(f"{label}: party must map unit ids to levels")
        retries += len(attempts) - 1
        if outcome == "win":
            wins += 1
        elif index != len(battles) - 1:
            errors.append(f"{label}: a lost battle stops the walk, so it must be the last row")
    if game_clear:
        if stuck_at:
            errors.append("game_clear=true leaves no stuck_at")
        if budget_exhausted:
            errors.append("game_clear=true leaves no budget_exhausted")
        if wins != len(battles):
            errors.append("game_clear=true requires every battle row to be a win")
    elif budget_exhausted:
        if stuck_at:
            errors.append("budget_exhausted leaves no stuck_at")
        if wins != len(battles):
            errors.append("budget_exhausted requires every battle row to be a win (the walk stopped before the next battle)")
        if not isinstance(budget_exhausted.get("level"), int) or str(budget_exhausted.get("level")) not in registered:
            errors.append(f"budget_exhausted.level must be a registered campaign battle key: {budget_exhausted.get('level')!r}")
    else:
        if not battles or battles[-1].get("outcome") == "win":
            errors.append("game_clear=false requires the last battle row to be a lost battle")
        elif stuck_at.get("level") != battles[-1].get("level") or stuck_at.get("outcome") != battles[-1].get("outcome"):
            errors.append(f"stuck_at must name the last row's level and outcome: {stuck_at!r} vs {battles[-1].get('level')!r}/{battles[-1].get('outcome')!r}")
    for field, value in (("battles_fought", len(battles)), ("battles_won", wins), ("retries", retries)):
        if chapter.get(field) != value:
            errors.append(f"{field} must equal the recount {value}: {chapter.get(field)!r}")
    return errors


def summary_line(chapter: dict) -> str:
    stuck = chapter["stuck_at"].get("level", "none") if chapter["stuck_at"] else "none"
    budget = chapter.get("budget_exhausted") or {}
    knobs = chapter.get("knobs", {"gold": "normal", "stat_scale": 1})
    purchases = sum(len(row.get("purchases", [])) for row in chapter.get("towns", []))
    return (f"PASS hsl_autoplay_chapter start={chapter.get('start')} brain={chapter.get('brain', 'scored')} gold={knobs.get('gold')} stat_scale={knobs.get('stat_scale')} "
            f"game_clear={str(chapter['game_clear']).lower()} stuck_at={stuck} budget_exhausted_at={budget.get('level', 'none')} "
            f"battles={chapter['battles_fought']} won={chapter['battles_won']} retries={chapter['retries']} tries_limit={chapter['tries_limit']} shops={len(chapter.get('towns', []))} purchases={purchases}")


def check_paths(root: Path) -> str:
    chapter = json.loads((root / CHAPTER).read_text())
    campaign = json.loads((root / CAMPAIGN).read_text())
    errors = check_chapter(chapter, campaign)
    if errors:
        raise ValueError("autoplay chapter check failed:\n  " + "\n  ".join(errors))
    return summary_line(chapter)


class AutoplayChapterTask(CheckTask):
    name = 'autoplay_chapter'
    family = 'autoplay'
    inputs = (CHAPTER, CAMPAIGN)
    replaces = ()  # born as a registry task: no historical command to replace
    scripts = ('tools/hsltools/checks/autoplay_chapter.py', 'tools/hsltools/checks/autoplay_results.py')

    def check(self, ctx: Context) -> str:
        try:
            return check_paths(ctx.root)
        except (ValueError, OSError, KeyError) as error:
            raise CheckFailed(f'{self.name}: {error}') from error


def tasks() -> list[AutoplayChapterTask]:
    return [AutoplayChapterTask()]
