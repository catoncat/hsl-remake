"""Structural check of the autoplay brain comparison (content/generated/hsl/development/autoplay).

Registry task autoplay_brain (family autoplay, CheckTask, replaces=()). brain_comparison.json is
written by tests/run_autoplay_sweep_tests.gd under HSL_AUTOPLAY_COMPARE=1: the first N main-line
battles the tracked greedy run (results.json) lost, each played `repeats` times per autoplay
policy (greedy = tests/support/Autoplay.gd, scored / lookahead = tests/support/AutoplayBrain.gd). The check
proves: the file parses with its schema, `levels` is exactly the selection rule applied to
results.json and campaign.json, every level has one row per mode in `modes` (and no other), every
row has `repeats` runs whose per-outcome counts add up, and `summary` equals the recount over the
rows. Which policy wins more is recorded, never asserted; nothing here is evidence about original
balance. Not part of the fast or deep gate's suites (the comparison is a developer run).
"""
from __future__ import annotations

import json
from pathlib import Path

from hsltools.checks import CheckTask
from hsltools.checks.autoplay_results import RESULTS, RESULTS_SCHEMA, CAMPAIGN, DEAD_END_REASONS, OUTCOMES
from hsltools.registry import CheckFailed, Context

COMPARISON = "content/generated/hsl/development/autoplay/brain_comparison.json"
COMPARISON_SCHEMA = "hsl_autoplay_brain_comparison.v1"
MODES = ("greedy", "scored", "lookahead")
MAIN_LINE_LIMIT = 500


def greedy_lost_main_line(results: dict, campaign: dict, count: int) -> list[str]:
    """The first `count` main-line battles (numeric key < 500, no kind) whose greedy outcome is fail, in campaign order."""
    levels = results.get("levels", {})
    selected: list[str] = []
    for key, entry in campaign.get("battles", {}).items():
        if len(selected) >= count:
            break
        if "kind" in entry or not str(key).isdigit() or int(key) >= MAIN_LINE_LIMIT:
            continue
        if isinstance(levels.get(key), dict) and levels[key].get("outcome") == "fail":
            selected.append(key)
    return selected


def check_brain_comparison(comparison: dict, results: dict, campaign: dict) -> list[str]:
    errors: list[str] = []
    if comparison.get("schema") != COMPARISON_SCHEMA:
        errors.append(f"schema must be {COMPARISON_SCHEMA}: {comparison.get('schema')!r}")
    if results.get("schema") != RESULTS_SCHEMA:
        errors.append(f"results schema must be {RESULTS_SCHEMA}: {results.get('schema')!r}")
    modes = comparison.get("modes")
    levels = comparison.get("levels")
    repeats = comparison.get("repeats")
    battles = comparison.get("battles")
    summary = comparison.get("summary")
    if not isinstance(modes, list) or not modes or any(mode not in MODES for mode in modes) or len(set(modes)) != len(modes):
        return errors + [f"modes must be a non-empty list of distinct entries from {MODES}: {modes!r}"]
    if not isinstance(levels, list) or not all(isinstance(level, str) for level in levels):
        return errors + ["levels must be a list of battle keys"]
    if not isinstance(repeats, int) or isinstance(repeats, bool) or repeats < 1:
        return errors + [f"repeats must be a positive integer: {repeats!r}"]
    if not isinstance(battles, dict) or not isinstance(summary, dict):
        return errors + ["battles and summary must be objects"]
    expected = greedy_lost_main_line(results, campaign, len(levels))
    if levels != expected:
        errors.append(f"levels must be the first {len(levels)} greedy-lost main-line battles of results.json in campaign order: {levels} vs {expected}")
    if sorted(battles) != sorted(levels):
        errors.append(f"battles must have exactly one entry per level: {sorted(battles)} vs {sorted(levels)}")
    recount = {mode: {"runs": 0, **{outcome: 0 for outcome in OUTCOMES}} for mode in modes}
    for level in levels:
        rows = battles.get(level)
        if not isinstance(rows, dict):
            errors.append(f"level {level}: battles entry must be an object")
            continue
        if sorted(rows) != sorted(modes):
            errors.append(f"level {level}: one row per mode {sorted(modes)} required: {sorted(rows)}")
            continue
        for mode in modes:
            row = rows[mode]
            runs = row.get("runs") if isinstance(row, dict) else None
            if not isinstance(runs, list) or len(runs) != repeats:
                errors.append(f"level {level} {mode}: runs must list exactly repeats={repeats} runs")
                continue
            counts = {outcome: 0 for outcome in OUTCOMES}
            for index, run in enumerate(runs):
                outcome = run.get("outcome") if isinstance(run, dict) else None
                if outcome not in OUTCOMES:
                    errors.append(f"level {level} {mode} run {index}: outcome must be one of {OUTCOMES}: {outcome!r}")
                    continue
                counts[outcome] += 1
                if not isinstance(run.get("rounds"), int) or run["rounds"] < 0:
                    errors.append(f"level {level} {mode} run {index}: rounds must be a non-negative integer")
                if not isinstance(run.get("seconds"), (int, float)) or isinstance(run.get("seconds"), bool) or run["seconds"] < 0:
                    errors.append(f"level {level} {mode} run {index}: seconds must be a non-negative number")
                if outcome == "dead_end" and run.get("reason") not in DEAD_END_REASONS:
                    errors.append(f"level {level} {mode} run {index}: dead_end reason must be one of {DEAD_END_REASONS}: {run.get('reason')!r}")
                if mode != "greedy" and (not isinstance(run.get("plans"), int) or run["plans"] < 0):
                    errors.append(f"level {level} {mode} run {index}: a brain run records its plans count")
            for outcome in OUTCOMES:
                if row.get(outcome) != counts[outcome]:
                    errors.append(f"level {level} {mode}: {outcome} must equal the run count {counts[outcome]}: {row.get(outcome)!r}")
                recount[mode][outcome] += counts[outcome]
            recount[mode]["runs"] += len(runs)
    if sorted(summary) != sorted(modes):
        errors.append(f"summary must have one entry per mode: {sorted(summary)} vs {sorted(modes)}")
    for mode in modes:
        entry = summary.get(mode)
        if not isinstance(entry, dict):
            errors.append(f"summary {mode}: must be an object")
            continue
        for field, value in recount[mode].items():
            if entry.get(field) != value:
                errors.append(f"summary {mode}: {field} must equal the recount {value}: {entry.get(field)!r}")
    return errors


def summary_line(comparison: dict) -> str:
    parts = [f"PASS hsl_autoplay_brain_comparison battles={len(comparison['levels'])} repeats={comparison['repeats']}"]
    for mode in comparison["modes"]:
        entry = comparison["summary"][mode]
        parts.append(f"{mode}=win:{entry['win']}/fail:{entry['fail']}/dead_end:{entry['dead_end']}")
    return " ".join(parts)


def check_paths(root: Path) -> str:
    comparison = json.loads((root / COMPARISON).read_text())
    results = json.loads((root / RESULTS).read_text())
    campaign = json.loads((root / CAMPAIGN).read_text())
    errors = check_brain_comparison(comparison, results, campaign)
    if errors:
        raise ValueError("autoplay brain comparison check failed:\n  " + "\n  ".join(errors))
    return summary_line(comparison)


class AutoplayBrainTask(CheckTask):
    name = 'autoplay_brain'
    family = 'autoplay'
    inputs = (COMPARISON, RESULTS, CAMPAIGN)
    replaces = ()  # born as a registry task: no historical command to replace
    scripts = ('tools/hsltools/checks/autoplay_brain.py', 'tools/hsltools/checks/autoplay_results.py')

    def check(self, ctx: Context) -> str:
        try:
            return check_paths(ctx.root)
        except (ValueError, OSError, KeyError) as error:
            raise CheckFailed(f'{self.name}: {error}') from error


def tasks() -> list[AutoplayBrainTask]:
    return [AutoplayBrainTask()]
