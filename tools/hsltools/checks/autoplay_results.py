"""Structural check of the autoplay sweep results (content/generated/hsl/development/autoplay).

Registry task autoplay_results (family autoplay, CheckTask: born as a registry task, so its
ledger entry is its own CLI form rather than a replaced tools/hsl_*.py command). results.json is written by
tests/run_autoplay_sweep_tests.gd (every registered formal battle played to a natural outcome
by tests/support/Autoplay.gd, not a gate suite); known_dead_ends.json lists the battles whose
dead_end is recorded but not yet fixed. The check proves: both files parse with their schema,
every registered battle has exactly one result row, win/fail rows carry no reason, every
`battle_outcome` is a BattleOutcome structure ({} or {result, reason}) whose result and reason are
spelled in game/sim/BattleOutcome.gd (plus the autoplayer's own `event_handoff` victory reason,
tests/support/Autoplay.gd EVENT_HANDOFF_OUTCOME) and whose result agrees with the row's win/fail, every
dead_end row is listed as known with the same reason category, and the file carries no wall
clock (the sweep seeds the loop RNG through BattleSceneRuntime.LOOP_SEED_ENV and records
`loop_seed`, so a rerun reproduces it: the sweep suite itself is the regen-and-compare
step — a changed outcome or dead_end reason fails it, rounds and action counts only print as
drift for the merger to commit — this check is the offline structural half). A known entry the latest run did not hit
stays valid; the PASS line counts known_hit / known_not_hit so a fixed category can be
removed. Outcomes themselves are recorded, never asserted.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

from hsltools.checks import CheckTask
from hsltools.registry import CheckFailed, Context

RESULTS = "content/generated/hsl/development/autoplay/results.json"
KNOWN_DEAD_ENDS = "content/generated/hsl/development/autoplay/known_dead_ends.json"
CAMPAIGN = "content/battles/campaign.json"

BATTLE_OUTCOME_MODULE = "game/sim/BattleOutcome.gd"

RESULTS_SCHEMA = "hsl_autoplay_results.v1"
KNOWN_DEAD_ENDS_SCHEMA = "hsl_autoplay_known_dead_ends.v1"
OUTCOMES = ("win", "fail", "dead_end")
DEAD_END_REASONS = ("no_legal_action", "party_wiped_no_defeat", "outcome_never_armed", "stalemate_no_contact", "round_limit", "stalled", "exception")
# The autoplayer's own victory reason for a battle the campaign hand-off ended before the loop
# decided (tests/support/Autoplay.gd EVENT_HANDOFF_OUTCOME); not a loop reason.
EVENT_HANDOFF_REASON = "event_handoff"
RESULT_OF_OUTCOME = {"win": "victory", "fail": "defeat"}

GD_CONST = re.compile(r'^const (?P<name>[A-Z_]+) := "(?P<value>[a-z_]+)"', re.M)


def battle_outcome_vocabulary(root: Path) -> dict[str, list[str]]:
    """{result: [reasons]} spelled by game/sim/BattleOutcome.gd (the single spelling of the structure)."""
    constants = {match["name"]: match["value"] for match in GD_CONST.finditer((root / BATTLE_OUTCOME_MODULE).read_text())}
    reasons = [value for name, value in constants.items() if name.startswith("REASON_")]
    victory, defeat = constants["VICTORY"], constants["DEFEAT"]
    fallen = constants["REASON_FALLEN"]
    return {victory: [reason for reason in reasons if reason != fallen] + [EVENT_HANDOFF_REASON], defeat: [fallen]}


def battle_outcome_error(value, vocabulary: dict[str, list[str]]) -> str:
    """"" for a well-formed battle_outcome ({} or a listed {result, reason}), else the defect."""
    if not isinstance(value, dict):
        return "must be an object"
    if not value:
        return ""
    if sorted(value) != ["reason", "result"]:
        return "must carry exactly result and reason"
    if value["result"] not in vocabulary:
        return f"result must be one of {sorted(vocabulary)}: {value['result']!r}"
    if value["reason"] not in vocabulary[value["result"]]:
        return f"reason must be one of {vocabulary[value['result']]}: {value['reason']!r}"
    return ""


def registered_battles(campaign: dict) -> list[str]:
    """campaign.json battle keys that are battle scenarios (no story / world_map / game_clear kind)."""
    return [key for key, entry in campaign.get("battles", {}).items() if "kind" not in entry]


def check_autoplay_results(results: dict, known: dict, campaign: dict, vocabulary: dict[str, list[str]]) -> list[str]:
    errors: list[str] = []
    if results.get("schema") != RESULTS_SCHEMA:
        errors.append(f"results schema must be {RESULTS_SCHEMA}: {results.get('schema')!r}")
    if known.get("schema") != KNOWN_DEAD_ENDS_SCHEMA:
        errors.append(f"known_dead_ends schema must be {KNOWN_DEAD_ENDS_SCHEMA}: {known.get('schema')!r}")
    levels = results.get("levels")
    known_levels = known.get("levels")
    if not isinstance(levels, dict):
        return errors + ["results.levels must be an object"]
    if not isinstance(known_levels, dict):
        return errors + ["known_dead_ends.levels must be an object"]
    expected = registered_battles(campaign)
    missing = [key for key in expected if key not in levels]
    extra = [key for key in levels if key not in expected]
    if missing:
        errors.append(f"registered battles without a result row: {missing}")
    if extra:
        errors.append(f"result rows for unregistered battles: {extra}")
    if results.get("battles") != len(levels):
        errors.append(f"results.battles must equal the row count: {results.get('battles')!r} vs {len(levels)}")
    if not isinstance(results.get("loop_seed"), int) or isinstance(results.get("loop_seed"), bool):
        errors.append(f"results.loop_seed must be the integer HSL_RNG_SEED the sweep played: {results.get('loop_seed')!r}")
    if "seconds" in results:
        errors.append("results must not carry a wall clock (seconds): the file is seed-determined")
    for key, row in levels.items():
        if not isinstance(row, dict):
            errors.append(f"level {key}: row must be an object")
            continue
        outcome = row.get("outcome")
        if outcome not in OUTCOMES:
            errors.append(f"level {key}: outcome must be one of {OUTCOMES}: {outcome!r}")
        if not isinstance(row.get("rounds"), int) or row["rounds"] < 0:
            errors.append(f"level {key}: rounds must be a non-negative integer")
        if "seconds" in row:
            errors.append(f"level {key}: rows must not carry a wall clock (seconds)")
        outcome_error = battle_outcome_error(row.get("battle_outcome"), vocabulary)
        if outcome_error:
            errors.append(f"level {key}: battle_outcome {outcome_error}")
        reason = row.get("reason")
        if outcome == "dead_end":
            if reason not in DEAD_END_REASONS:
                errors.append(f"level {key}: dead_end reason must be one of {DEAD_END_REASONS}: {reason!r}")
            if key not in known_levels:
                errors.append(f"level {key}: dead_end ({reason}, unit={row.get('unit')!r}, round={row.get('round')!r}) is not listed in known_dead_ends.json")
            elif isinstance(known_levels[key], dict) and known_levels[key].get("reason") != reason:
                errors.append(f"level {key}: known dead_end reason {known_levels[key].get('reason')!r} differs from the result {reason!r}")
        elif outcome in OUTCOMES:
            if reason not in ("", None):
                errors.append(f"level {key}: a {outcome} row must not carry a reason: {reason!r}")
            if not outcome_error and (not row.get("battle_outcome") or row["battle_outcome"]["result"] != RESULT_OF_OUTCOME[outcome]):
                errors.append(f"level {key}: a {outcome} row names a {RESULT_OF_OUTCOME[outcome]} battle_outcome: {row.get('battle_outcome')!r}")
    for key, entry in known_levels.items():
        if not isinstance(entry, dict):
            errors.append(f"known dead_end {key}: entry must be an object")
            continue
        for field in ("reason", "first_observed_commit"):
            if not isinstance(entry.get(field), str) or not entry[field]:
                errors.append(f"known dead_end {key}: {field} must be a non-empty string")
        if not isinstance(entry.get("unit"), str):
            errors.append(f"known dead_end {key}: unit must be a string (empty when the category, not this battle's run, was observed)")
        if entry.get("reason") not in DEAD_END_REASONS:
            errors.append(f"known dead_end {key}: reason must be one of {DEAD_END_REASONS}: {entry.get('reason')!r}")
        if not isinstance(entry.get("round"), int):
            errors.append(f"known dead_end {key}: round must be an integer")
        if key not in expected:
            errors.append(f"known dead_end {key}: not a registered battle")
    return errors


def summary_line(results: dict, known: dict) -> str:
    rows = [row for row in results["levels"].values() if isinstance(row, dict)]
    counts = {outcome: sum(1 for row in rows if row.get("outcome") == outcome) for outcome in OUTCOMES}
    hit = sum(1 for key in known["levels"] if results["levels"].get(key, {}).get("outcome") == "dead_end")
    return (f"PASS hsl_autoplay_results battles={len(rows)} win={counts['win']} fail={counts['fail']} "
            f"dead_end={counts['dead_end']} known_hit={hit} known_not_hit={len(known['levels']) - hit}")


def check_paths(root: Path) -> str:
    """Load the three tracked files under `root`, validate, return the PASS line (ValueError on errors)."""
    results = json.loads((root / RESULTS).read_text())
    known = json.loads((root / KNOWN_DEAD_ENDS).read_text())
    campaign = json.loads((root / CAMPAIGN).read_text())
    errors = check_autoplay_results(results, known, campaign, battle_outcome_vocabulary(root))
    if errors:
        raise ValueError("autoplay results check failed:\n  " + "\n  ".join(errors))
    return summary_line(results, known)


class AutoplayResultsTask(CheckTask):
    name = 'autoplay_results'
    family = 'autoplay'
    inputs = (RESULTS, KNOWN_DEAD_ENDS, CAMPAIGN, BATTLE_OUTCOME_MODULE)
    replaces = ()  # born after the migration: no historical command to replace
    scripts = ('tools/hsltools/checks/autoplay_results.py',)

    def check(self, ctx: Context) -> str:
        try:
            return check_paths(ctx.root)
        except (ValueError, OSError, KeyError) as error:
            raise CheckFailed(f'{self.name}: {error}') from error


def tasks() -> list[AutoplayResultsTask]:
    return [AutoplayResultsTask()]
