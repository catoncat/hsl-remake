#!/usr/bin/env python3
"""Parallel runner behind tools/verify.sh.

Sub-commands (all run from the repository root, all exit non-zero on any failure):

  python-tests   every tools/test_hsl_*.py file in its own interpreter, in parallel
  checks         the source / evidence / importer checks = the hsltools registry
                 (tools/hsl.py check --all): every task in a process pool
  godot          the rule suites (tests/run_*.gd that extend tests/support/TestSuite.gd)
                 in-process through tests/run_all.gd, packed into --rule-shards Godot
                 processes (`run_all.gd -- suite...`) by longest-processing-time-first on
                 the per-suite seconds in tests/support/suite_timings.json; every other
                 tests/run_*.gd suite in its own Godot process with its own HOME (user://
                 is per suite), the battle sweep sharded through HSL_SWEEP_LEVELS
  deep           the long end-to-end suites (DEEP_SUITES: the story-mode explorer, the
                 autoplay sweep and the chapter autoplay) that only tools/verify.sh --deep runs, each in its
                 own Godot process and HOME with a 40-minute timeout
  affected --since REF [suite...]
                 what tools/lane_verify.sh affected runs while a lane works: the registry
                 checks `hsl affected --since REF --check` selects, the tools/test_hsl_*.py
                 files that import a changed tools/ module, `bash -n` on changed tools/*.sh,
                 and the Godot suites that are changed or reference a changed game/ or
                 tests/support/ script (res:// path or class_name, also through
                 tests/support/), the sweep for a changed battle scenario; one Godot
                 process at a time
  promote-timings
                 copy the last godot run's per-rule-suite seconds
                 (ignored/rule-suite-timings.json, from run_all.gd's RULE_SUITE_TIMING
                 lines) into the tracked tests/support/suite_timings.json;
                 `promote-timings --missing` instead measures only the rule suites the
                 tracked file lacks (one run_all.gd process) and adds them, keeping the rest

Output is deterministic: result lines are printed sorted after all jobs finish; a failing
job prints its full log. Per-job wall times are remembered in ignored/verify-timings.json
so the next run schedules the longest jobs first.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

# Windows: UTF-8 mode for this runner and every test／check subprocess (see tools/hsl.py).
if sys.platform == "win32" and not sys.flags.utf8_mode:
    os.environ["PYTHONUTF8"] = "1"
    sys.exit(subprocess.call([sys.executable, "-X", "utf8", *sys.argv]))

sys.path.insert(0, str(Path(__file__).resolve().parent))

from hsltools import original_content, registry  # noqa: E402
from hsltools.runner import run_parallel as run_jobs  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
PYTHON = sys.executable
TIMINGS = ROOT / "ignored" / "verify-timings.json"
# Per-rule-suite seconds: the tracked file drives the run_all shard packing; the ignored
# file is what the last godot run measured (promote-timings copies it over).
SUITE_TIMINGS = ROOT / "tests" / "support" / "suite_timings.json"
RULE_SUITE_TIMINGS = ROOT / "ignored" / "rule-suite-timings.json"
RULE_SUITE_TIMING_LINE = re.compile(r"^RULE_SUITE_TIMING suite=(\S+) seconds=([\d.]+)", re.MULTILINE)
# A rule suite without a tracked timing (new or renamed) packs as this many seconds.
DEFAULT_RULE_SUITE_SECONDS = 10.0
GATE_HOMES = ROOT / "ignored" / "gate-homes"
BATTLES = ROOT / "content" / "battles"
# End-to-end suites too long for the fast gate: `deep` runs them, `godot` skips them.
# The explorer walks 歐姆村 → GameClear (~25 s on the fixed clock, ~17 min on the real one);
# the autoplay sweep plays every registered battle to a natural outcome (~15 min, CPU-bound
# on either clock; docs/internal/PLAYABILITY.md R1); the chapter autoplay walks the explorer's path
# fighting every battle with the lookahead commander until GameClear, the first battle it
# cannot win or CHAPTER_BUDGET_SECONDS (docs/internal/PLAYABILITY.md R10; ends early when stuck).
DEEP_SUITES = {"run_story_mode_explorer_tests.gd", "run_autoplay_sweep_tests.gd", "run_chapter_autoplay_tests.gd"}
DEEP_TIMEOUT_SECONDS = 2400
# The chapter autoplay grows with every battle the commander wins; the gate bounds it by
# wall clock (tests/run_chapter_autoplay_tests.gd HSL_CHAPTER_BUDGET_SECONDS: past the
# budget no further battle starts, the run reports budget_exhausted and passes). A manual
# run without the variable defaults to the same budget (DEFAULT_BUDGET_SECONDS there; keep
# the two equal); HSL_CHAPTER_BUDGET_SECONDS=0 runs unbounded.
CHAPTER_BUDGET_SECONDS = 600
DEEP_SUITE_ENV = {"run_chapter_autoplay_tests.gd": {"HSL_CHAPTER_BUDGET_SECONDS": str(CHAPTER_BUDGET_SECONDS)}}
# Developer entry points that are not gate suites.
GODOT_SUITE_EXCLUDE = {"run_first_battle_playthrough.gd"} | DEEP_SUITES
# tests/run_all.gd discovers the rule suites by this first line and runs them in-process.
RULE_SUITE_HEADER = 'extends "res://tests/support/TestSuite.gd"'
RULE_SUITE_RUNNER = "run_all.gd"
# One serial run_all over every rule suite is the gate's tail (32 suites: 53 s alone, 176 s
# under the 8-worker load); the shards are disjoint by construction and the summary checks
# their suites= counts add up to every rule suite once. Round-robin by name left one shard
# at 25.5 s serial (50 s in the gate) against 9-12 s for the others; packing by measured
# seconds bounds every shard near the 14 s serial mean.
DEFAULT_RULE_SHARDS = 4
SWEEP_SUITE = "run_battle_sweep_tests.gd"
# Run a second time under HSL_OPTIONS_PRESET=comfort (docs/OPTIONS.md §7: the gate's only non-original-preset run).
COMFORT_SMOKE_SUITE = "run_scene_smoke.gd"
DEFAULT_SWEEP_SHARDS = 4
# Suites whose flows are condition-driven ("await process_frame until the coordinator
# is idle") and whose wall time is otherwise the headless frame sleep (6.9 ms per frame
# whenever the display cannot draw) times real-time waits. `--fixed-fps N` gives them a
# deterministic 1/N process step, skips the sleep, and the suite's own end-of-run settle
# uses TestSuite.settle_wall_clock. A suite may join once none of its assertions sits a
# fixed number of frames after a scene boot expecting timeline progress (on the real clock
# the first frame's delta is the whole load time); such spots wait on the condition itself
# with a frame cap (TestSuite.await_condition). HSL_TEST_FIXED_FPS=0 restores the real
# clock for every suite.
FAST_CLOCK_SUITES = {
    SWEEP_SUITE,
    "run_story_scene_tests.gd",
    "run_battle_scene_runtime_tests.gd",
    "run_title_screen_tests.gd",
    "run_system_menu_tests.gd",
    "run_campaign_tests.gd",
    # Condition-driven frame loops over the first enemy turn and the level-51 opening.
    "run_walk_camera_follow_tests.gd",
    "run_story_mode_explorer_tests.gd",
    # Rule steps run headless on the loop; only cutscenes and result pages take frames.
    "run_autoplay_sweep_tests.gd",
    "run_chapter_autoplay_tests.gd",
}
DEFAULT_FIXED_FPS = 60
# Every Godot suite process gets HSL_RNG_SEED = DEFAULT_RNG_SEED unless the caller exported
# one: a headless scene seeds its damage stream and the process global stream
# (game/sim/GlobalRandomStream.gd) from it instead of the clock, so two gate runs print the
# same result lines. tests/run_all.gd applies the same default to a direct run.
RNG_SEED_ENV = "HSL_RNG_SEED"
DEFAULT_RNG_SEED = "1"


def rng_seed_setting() -> tuple[str, str]:
    value = os.environ.get(RNG_SEED_ENV, "").strip()
    if re.fullmatch(r"-?\d+", value):
        return value, "environment"
    return DEFAULT_RNG_SEED, "harness_default"


UNKNOWN_DURATION = 600.0
# Scheduling priors for a fresh checkout (no ignored/verify-timings.json yet): the
# long-running suites must start first or they become the tail of the run. Fixed-fps jobs
# are CPU-bound and slow down under a full 8-worker load (a sweep shard 27 s alone,
# 66–76 s in the gate), so they start first. A sweep shard is assumed to take its share
# of one full fixed-fps sweep under load.
DURATION_PRIORS = {
    "run_story_scene_tests.gd": 60.0,
    "run_battle_scene_runtime_tests.gd": 40.0,
    "run_title_screen_tests.gd": 30.0,
}
SWEEP_SERIAL_ESTIMATE = 240.0


def default_jobs() -> int:
    # HSL_VERIFY_JOBS caps the parallelism of every stage (Python tests, checks, Godot
    # suites). Set it to 3-4 when several worktrees run gates on the same machine:
    # eight lanes x eight workers took the load average past 100 during the sprint.
    override = os.environ.get("HSL_VERIFY_JOBS", "").strip()
    if override.isdigit() and int(override) > 0:
        return int(override)
    return max(2, (os.cpu_count() or 4) - 2)


def run_one(argv: list[str], env: dict[str, str], timeout: int = 1800) -> tuple[int, str, float]:
    started = time.monotonic()
    try:
        completed = subprocess.run(argv, cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace", timeout=timeout)
        return completed.returncode, completed.stdout, time.monotonic() - started
    except subprocess.TimeoutExpired as error:
        output = (error.stdout or b"").decode("utf-8", "replace") if isinstance(error.stdout, bytes) else (error.stdout or "")
        return 124, output + f"\n[timeout after {timeout}s]", time.monotonic() - started


def run_parallel(label: str, jobs: list[tuple[str, list[str], dict[str, str]]], workers: int, summary_line, timeout_for=None) -> int:
    """argv jobs on the shared deterministic runner (hsltools.runner). timeout_for(name)
    gives a per-job budget in seconds (default 1800); a job past it exits 124 with
    "[timeout after Ns]" in its log instead of holding the gate."""
    def budget(name: str) -> int:
        return int(timeout_for(name)) if timeout_for is not None else 1800
    return run_jobs(label, [(name, (lambda argv=argv, env=env, seconds=budget(name): run_one(argv, env, seconds))) for name, argv, env in jobs], workers, summary_line)


def base_env() -> dict[str, str]:
    env = dict(os.environ)
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    return env


# Windows prints backslash separators, and repr() doubles them inside the quoted OSError path.
MISSING_PATH = re.compile(r"No such file or directory: '([^']+)'|((?:content|docs[\\/]evidence_packets)[\\/][^\s'\":,)\]]+)")
SKIP_ORIGINAL_ABSENT = "PYTHON_UNIT_FILE_SKIP original-absent"


def names_absent_original(output: str) -> bool:
    """The failure log names an original-derived path this checkout lacks (hsltools.original_content)."""
    for quoted, bare in MISSING_PATH.findall(output):
        path = Path(quoted.replace("\\\\", "\\") if quoted else bare.replace("\\", "/"))
        relative = path.relative_to(ROOT) if path.is_absolute() and path.is_relative_to(ROOT) else path
        if not (ROOT / relative).exists() and (original_content.is_original_derived(relative.as_posix())
                                               or original_content.stands_in(relative.as_posix())):
            return True
    return False


def cmd_python_tests(args) -> int:
    files = sorted(path.name for path in (ROOT / "tools").glob("test_hsl_*.py"))
    env = base_env()
    env["PYTHONPATH"] = str(ROOT)
    # Original-derived content absent (a public checkout before the import): a file that fails
    # because it reads such a file is counted as SKIP original-absent, every other failure fails.
    absent = not original_content.present()
    totals = {"tests": 0, "skipped": 0}

    def thunk(name: str):
        def run():
            code, output, seconds = run_one([PYTHON, "-m", "unittest", "discover", "-s", "tools", "-p", name], env)
            if code and absent and names_absent_original(output):
                return 0, output + "\n" + SKIP_ORIGINAL_ABSENT, seconds
            return code, output, seconds
        return run

    def summary(name: str, output: str, seconds: float) -> str:
        if output.endswith(SKIP_ORIGINAL_ABSENT):
            totals["skipped"] += 1
            return f"{SKIP_ORIGINAL_ABSENT} {name}"
        match = re.search(r"^Ran (\d+) tests?", output, re.MULTILINE)
        count = int(match.group(1)) if match else 0
        totals["tests"] += count
        return f"PYTHON_UNIT_FILE_OK {name} tests={count} seconds={seconds:.1f}"

    code = run_jobs("PYTHON_UNIT_TESTS", [(name, thunk(name)) for name in files], args.jobs, summary)
    if code == 0:
        skipped = f" skipped_original_absent={totals['skipped']}" if totals["skipped"] else ""
        print(f"PYTHON_UNIT_TESTS_SUMMARY files={len(files)} tests={totals['tests']}{skipped}", flush=True)
    return code


def cmd_checks(args) -> int:
    # The registry (tools/hsl.py check --all): the sorted "PASS line  <- task" block.
    return registry.run_tasks("SOURCE_CHECKS", registry.all_tasks(), "check", registry.Context(), args.jobs)


def load_timings(path: Path = TIMINGS) -> dict[str, float]:
    try:
        return {str(key): float(value) for key, value in json.loads(path.read_text(encoding="utf-8")).items()}
    except (OSError, ValueError):
        return {}


def write_timings(path: Path, timings: dict[str, float]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(timings, indent=1, sort_keys=True) + "\n", encoding="utf-8")


def shard_rule_suites(rule_suites: list[str], suite_timings: dict[str, float], shards: int) -> list[list[str]]:
    """Longest-processing-time-first packing: suites by descending seconds (name breaks
    ties), each onto the currently lightest shard. Deterministic for the same inputs; every
    suite lands in exactly one shard; each shard keeps its suites in name order."""
    seconds = {name: suite_timings.get(name, DEFAULT_RULE_SUITE_SECONDS) for name in rule_suites}
    loads = [0.0] * shards
    packed: list[list[str]] = [[] for _ in range(shards)]
    for name in sorted(rule_suites, key=lambda suite: (-seconds[suite], suite)):
        index = min(range(shards), key=lambda shard: (loads[shard], shard))
        loads[index] += seconds[name]
        packed[index].append(name)
    return [sorted(shard) for shard in packed]


def campaign_sweep_keys() -> list[str]:
    campaign = json.loads((BATTLES / "campaign.json").read_text(encoding="utf-8"))
    return [key for key, entry in campaign.get("battles", {}).items() if "kind" not in entry]


def is_rule_suite(path: Path) -> bool:
    with path.open(encoding="utf-8") as handle:
        return handle.readline().strip() == RULE_SUITE_HEADER


def fixed_fps_setting() -> int:
    return int(os.environ.get("HSL_TEST_FIXED_FPS", DEFAULT_FIXED_FPS))


def godot_suite_job(name: str, suite: str, extra_env: dict[str, str], user_args: tuple[str, ...], fixed_fps: int) -> tuple[str, list[str], dict[str, str]]:
    """One Godot process for one suite with its own HOME (user:// per job); fast-clock
    suites get --fixed-fps."""
    home = GATE_HOMES / name
    home.mkdir(parents=True, exist_ok=True)
    env = base_env()
    env["HOME"] = str(home)
    env[RNG_SEED_ENV] = rng_seed_setting()[0]
    env.update(extra_env)
    clock = ["--fixed-fps", str(fixed_fps)] if suite in FAST_CLOCK_SUITES and fixed_fps > 0 else []
    script = ["--script", f"res://tests/{suite}"] + (["--", *user_args] if user_args else [])
    return name, ["tools/godot.sh", "--headless", *clock, *script], env


def cmd_godot(args) -> int:
    suite_paths = sorted(path for path in (ROOT / "tests").glob("run_*.gd") if path.name not in GODOT_SUITE_EXCLUDE | {RULE_SUITE_RUNNER})
    rule_suites = [path.name for path in suite_paths if is_rule_suite(path)]
    suites = [path.name for path in suite_paths if path.name not in rule_suites]
    if SWEEP_SUITE not in suites:
        print(f"GODOT_SUITES_FAIL missing {SWEEP_SUITE}", flush=True)
        return 1
    sweep_keys = campaign_sweep_keys()
    shards = max(1, min(args.sweep_shards, len(sweep_keys)))
    rule_shards = max(1, min(args.rule_shards, len(rule_suites))) if rule_suites else 0
    timings = load_timings()
    jobs: list[tuple[str, list[str], dict[str, str]]] = []
    import shutil
    shutil.rmtree(GATE_HOMES, ignore_errors=True)

    fixed_fps = fixed_fps_setting()
    print("GODOT_SUITES_RNG_SEED seed=%s source=%s" % rng_seed_setting(), flush=True)

    def job(name: str, suite: str, extra_env: dict[str, str], user_args: tuple[str, ...] = ()) -> None:
        jobs.append(godot_suite_job(name, suite, extra_env, user_args, fixed_fps))

    suite_timings = load_timings(SUITE_TIMINGS)
    rule_shard_suites: dict[str, list[str]] = {}
    for index, shard_suites in enumerate(shard_rule_suites(rule_suites, suite_timings, rule_shards)):
        name = f"{RULE_SUITE_RUNNER}#{index + 1}/{rule_shards}"
        rule_shard_suites[name] = shard_suites
        job(name, RULE_SUITE_RUNNER, {}, tuple(shard_suites))
    for suite in suites:
        if suite == SWEEP_SUITE:
            for index in range(shards):
                keys = sweep_keys[index::shards]
                job(f"{suite}#{index + 1}/{shards}", suite, {"HSL_SWEEP_LEVELS": ",".join(keys)})
        else:
            job(suite, suite, {})
            if suite == COMFORT_SMOKE_SUITE:
                # The one "comfort preset, every improvement on" run the gate makes (docs/OPTIONS.md
                # §7): same smoke script, HSL_OPTIONS_PRESET=comfort; script errors and hangs only.
                job(f"{suite}#comfort", suite, {"HSL_OPTIONS_PRESET": "comfort"})
    def expected(name: str) -> float:
        if name in timings:
            return timings[name]
        if name.startswith(SWEEP_SUITE):
            return SWEEP_SERIAL_ESTIMATE / shards
        if name in rule_shard_suites:
            # The shard's own packed seconds (serial; the gate load roughly doubles them).
            return sum(suite_timings.get(suite, DEFAULT_RULE_SUITE_SECONDS) for suite in rule_shard_suites[name])
        return DURATION_PRIORS.get(name, UNKNOWN_DURATION)

    jobs.sort(key=lambda item: -expected(item[0]))
    seen_battles = {"count": 0}
    seen_rule_suites = {"count": 0}
    durations: dict[str, float] = {}
    rule_suite_seconds: dict[str, float] = {}

    def summary(name: str, output: str, seconds: float) -> str:
        durations[name] = seconds
        pass_lines = [line for line in output.splitlines() if re.match(r"^[A-Z0-9_]+_PASS\b", line)]
        if name in rule_shard_suites:
            # One result line per in-process suite, then the shard's own total.
            rule_suite_seconds.update((suite, float(value)) for suite, value in RULE_SUITE_TIMING_LINE.findall(output))
            expected_lines = len(rule_shard_suites[name])
            if len(pass_lines) != expected_lines + 1:
                pass_lines.append(f"(expected {expected_lines} suite PASS lines, saw {max(len(pass_lines) - 1, 0)})")
            match = re.search(r"^RULE_SUITES_PASS suites=(\d+)", pass_lines[-1])
            seen_rule_suites["count"] += int(match.group(1)) if match else 0
            return "\n".join(f"{line}  <- {name}" for line in pass_lines[:-1]) + f"\n{pass_lines[-1]}  <- {name} {seconds:.0f}s"
        line = pass_lines[-1] if pass_lines else "(no PASS line)"
        if name.startswith(SWEEP_SUITE):
            match = re.search(r"battles=(\d+)", line)
            seen_battles["count"] += int(match.group(1)) if match else 0
        return f"{line}  <- {name} {seconds:.0f}s"

    def budget(name: str) -> float:
        # A hung Godot process (a script error that never quits) must not hold the gate for
        # the 30-minute default: 8× the remembered wall time, floor 3 min, cap 30 min.
        return min(1800.0, max(180.0, expected(name) * 8))

    code = run_parallel("GODOT_SUITES", jobs, args.jobs, summary, budget)
    if durations:
        timings.update(durations)
        write_timings(TIMINGS, timings)
    if rule_suite_seconds:
        write_timings(RULE_SUITE_TIMINGS, rule_suite_seconds)
    if code == 0 and seen_battles["count"] != len(sweep_keys):
        print(f"GODOT_SUITES_FAIL sweep covered {seen_battles['count']} of {len(sweep_keys)} registered battles", flush=True)
        return 1
    if code == 0 and seen_rule_suites["count"] != len(rule_suites):
        print(f"GODOT_SUITES_FAIL run_all shards covered {seen_rule_suites['count']} of {len(rule_suites)} rule suites", flush=True)
        return 1
    if code == 0:
        print(f"GODOT_SUITES_SUMMARY suites={len(suites) + len(rule_suites)} in_process={len(rule_suites)} rule_shards={rule_shards} sweep_shards={shards} sweep_battles={seen_battles['count']} fixed_fps={fixed_fps}", flush=True)
    return code


def cmd_deep(args) -> int:
    # The deep tier: every DEEP_SUITES file present, each its own process and HOME, run
    # after the fast gate by tools/verify.sh --deep. A missing suite is a failure (the
    # tier must not silently shrink); the 40-minute timeout covers the real clock.
    missing = sorted(suite for suite in DEEP_SUITES if not (ROOT / "tests" / suite).exists())
    if missing:
        print(f"DEEP_SUITES_FAIL missing {', '.join(missing)}", flush=True)
        return 1
    import shutil
    fixed_fps = fixed_fps_setting()
    print("DEEP_SUITES_RNG_SEED seed=%s source=%s" % rng_seed_setting(), flush=True)
    jobs = []
    for suite in sorted(DEEP_SUITES):
        shutil.rmtree(GATE_HOMES / suite, ignore_errors=True)
        jobs.append(godot_suite_job(suite, suite, DEEP_SUITE_ENV.get(suite, {}), (), fixed_fps))

    def summary(name: str, output: str, seconds: float) -> str:
        pass_lines = [line for line in output.splitlines() if re.match(r"^[A-Z0-9_]+_PASS\b", line)]
        return f"{pass_lines[-1] if pass_lines else '(no PASS line)'}  <- {name} {seconds:.0f}s"

    code = run_jobs("DEEP_SUITES", [(name, (lambda argv=argv, env=env: run_one(argv, env, DEEP_TIMEOUT_SECONDS))) for name, argv, env in jobs], args.jobs, summary)
    if code == 0:
        print(f"DEEP_SUITES_SUMMARY suites={len(jobs)} fixed_fps={fixed_fps} timeout={DEEP_TIMEOUT_SECONDS}", flush=True)
    return code


def gd_reference_tokens(relpath: str) -> list[re.Pattern]:
    """What a script that uses `relpath` contains: its res:// path, the res:// path of the
    same-stem scene it is attached to (BattleSceneRuntime.gd -> .tscn), or its class_name."""
    tokens = [re.compile(re.escape(f"res://{relpath}"))]
    path = ROOT / relpath
    if path.suffix == ".gd" and path.with_suffix(".tscn").exists():
        tokens.append(re.compile(re.escape(f"res://{Path(relpath).with_suffix('.tscn').as_posix()}")))
    if path.suffix == ".gd" and path.exists():
        match = re.search(r"^class_name\s+(\w+)", path.read_text(encoding="utf-8", errors="replace"), re.MULTILINE)
        if match:
            tokens.append(re.compile(rf"\b{match.group(1)}\b"))
    return tokens


def affected_godot_suites(changed: list[str], requested: list[str]) -> tuple[dict[str, str], dict[str, str], list[str]]:
    """({suite: reason}, {sweep level key: reason}, [deep suites skipped]) for the changed paths.
    A suite is hit when it is itself changed, or references a changed .gd directly or through
    tests/support/ (res:// path or class_name); a changed battle scenario hits the sweep for its
    levels. Game-to-game references are not followed (that graph reaches every suite)."""
    tests = ROOT / "tests"
    suites = {path.name: path.read_text(encoding="utf-8", errors="replace") for path in sorted(tests.glob("run_*.gd")) if path.name not in GODOT_SUITE_EXCLUDE | {RULE_SUITE_RUNNER}}
    hits: dict[str, str] = {name: "requested" for name in requested}
    deep = sorted(Path(path).name for path in changed if path.startswith("tests/") and Path(path).name in DEEP_SUITES)
    origin: dict[str, str] = {}
    for path in changed:
        if not path.endswith((".gd", ".tscn")):
            continue
        if path.startswith("tests/run_") and Path(path).name in suites:
            hits.setdefault(Path(path).name, path)
        elif path.startswith(("game/", "tests/support/")):
            origin[path] = path
    support = {f"tests/support/{path.name}": path.read_text(encoding="utf-8", errors="replace") for path in sorted((tests / "support").glob("*.gd"))}
    grew = True
    while grew:
        grew = False
        tokens = {target: gd_reference_tokens(target) for target in origin}
        for relpath, text in support.items():
            if relpath in origin:
                continue
            for target, patterns in tokens.items():
                if any(pattern.search(text) for pattern in patterns):
                    origin[relpath] = origin[target]
                    grew = True
                    break
    tokens = {target: gd_reference_tokens(target) for target in origin}
    for name, text in suites.items():
        for target, patterns in sorted(tokens.items()):
            if any(pattern.search(text) for pattern in patterns):
                hits.setdefault(name, origin[target] if target == origin[target] else f"{origin[target]} via {target}")
                break
    campaign = json.loads((BATTLES / "campaign.json").read_text(encoding="utf-8")).get("battles", {})
    levels: dict[str, str] = {}
    for key, entry in campaign.items():
        scenario = str(entry.get("scenario", "")).removeprefix("res://")
        if "kind" not in entry and (scenario in changed or "content/battles/campaign.json" in changed):
            levels[key] = scenario if scenario in changed else "content/battles/campaign.json"
    if SWEEP_SUITE in hits:
        levels = {}  # the whole sweep runs anyway
    return hits, levels, deep


def affected_python_tests(changed: list[str]) -> dict[str, str]:
    """{tools/test_hsl_*.py name: reason}: a changed test file, or a test file that imports (or
    names the path of) a changed tools/ Python module."""
    files = {path.name: path.read_text(encoding="utf-8", errors="replace") for path in sorted((ROOT / "tools").glob("test_hsl_*.py"))}
    hits: dict[str, str] = {}
    for path in changed:
        if not (path.startswith("tools/") and path.endswith(".py")):
            continue
        name = Path(path).name
        if name in files:
            hits.setdefault(name, path)
            continue
        stem = Path(path).parent.name if name == "__init__.py" else Path(path).stem
        pattern = re.compile(rf"^\s*(?:from|import)\b[^\n]*\b{re.escape(stem)}\b|{re.escape(path)}", re.MULTILINE)
        for test, text in files.items():
            if pattern.search(text):
                hits.setdefault(test, path)
    return hits


def cmd_affected(args) -> int:
    # tools/lane_verify.sh affected: what a lane runs while it works (AGENTS.md 效率节拍) —
    # the registry checks `hsl affected --since REF --check` selects, the Python unit files and
    # Godot suites the change hits, `bash -n` on changed shell scripts. Godot suites run one
    # process at a time (one Godot process per lane on a shared machine).
    from hsl import changed_since
    unknown = sorted(name for name in args.suites if not (ROOT / "tests" / name).exists())
    if unknown:
        print(f"LANE_AFFECTED_FAIL unknown suite(s): {' '.join(unknown)}", flush=True)
        return 2
    started = time.monotonic()
    changed = changed_since(args.since)
    failed: list[str] = []
    print(f"LANE_AFFECTED since={args.since} changed_paths={len(changed)}", flush=True)

    tasks = registry.affected(registry.all_tasks(), changed)
    print(f"LANE_AFFECTED_CHECKS tasks={len(tasks)}", flush=True)
    if tasks and registry.run_tasks("SOURCE_CHECKS", tasks, "check", registry.Context(), args.jobs) != 0:
        failed.append("checks")

    tests = affected_python_tests(changed)
    for name, reason in sorted(tests.items()):
        print(f"LANE_AFFECTED_PYTHON {name} <- {reason}", flush=True)
    if tests:
        env = base_env()
        env["PYTHONPATH"] = str(ROOT)
        jobs = [(name, [PYTHON, "-m", "unittest", "discover", "-s", "tools", "-p", name], env) for name in sorted(tests)]
        if run_parallel("PYTHON_UNIT_TESTS", jobs, args.jobs, lambda name, output, seconds: f"PYTHON_UNIT_FILE_OK {name} seconds={seconds:.1f}") != 0:
            failed.append("python-tests")

    scripts = sorted(path for path in changed if path.startswith("tools/") and path.endswith(".sh") and (ROOT / path).exists())
    for script in scripts:
        if subprocess.run(["bash", "-n", script], cwd=ROOT).returncode != 0:
            print(f"SHELL_SYNTAX_FAIL {script}", flush=True)
            failed.append(f"bash -n {script}")
    if scripts:
        print(f"SHELL_SYNTAX_PASS scripts={len(scripts)}", flush=True)

    hits, levels, deep = affected_godot_suites(changed, args.suites)
    for name in deep:
        print(f"LANE_AFFECTED_SKIP {name} is a deep suite (tools/verify_runner.py deep)", flush=True)
    rule = sorted(name for name in hits if is_rule_suite(ROOT / "tests" / name))
    scene = sorted(name for name in hits if name not in rule)
    for name in rule + scene:
        print(f"LANE_AFFECTED_GODOT {name} <- {hits[name]}", flush=True)
    if levels:
        print(f"LANE_AFFECTED_GODOT {SWEEP_SUITE} levels={','.join(levels)} <- {', '.join(sorted(set(levels.values())))}", flush=True)
    fixed_fps = fixed_fps_setting()
    jobs = []
    deferred = 0
    if len(scene) > args.max_scene_suites:
        # A change to a central scene script hits most scene suites; one at a time that is
        # slower than the parallel fast gate.
        deferred = len(rule) + len(scene) + (1 if levels else 0)
        print(f"LANE_AFFECTED_GODOT_DEFERRED suites={deferred} scene_suites={len(scene)} > {args.max_scene_suites}: run tools/lane_verify.sh fast (parallel) instead", flush=True)
        rule, scene, levels = [], [], {}
    if rule:
        jobs.append(godot_suite_job(RULE_SUITE_RUNNER, RULE_SUITE_RUNNER, {}, tuple(rule), fixed_fps))
    jobs.extend(godot_suite_job(name, name, {}, (), fixed_fps) for name in scene)
    if levels:
        jobs.append(godot_suite_job(f"{SWEEP_SUITE}#levels", SWEEP_SUITE, {"HSL_SWEEP_LEVELS": ",".join(levels)}, (), fixed_fps))
    if jobs:
        import shutil
        for name, _argv, _env in jobs:
            shutil.rmtree(GATE_HOMES / name, ignore_errors=True)
            (GATE_HOMES / name).mkdir(parents=True, exist_ok=True)

        def summary(name: str, output: str, seconds: float) -> str:
            pass_lines = [line for line in output.splitlines() if re.match(r"^[A-Z0-9_]+_PASS\b", line)]
            body = [f"{line}  <- {name}" for line in pass_lines[:-1]] if name == RULE_SUITE_RUNNER else []
            return "\n".join(body + [f"{pass_lines[-1] if pass_lines else '(no PASS line)'}  <- {name} {seconds:.0f}s"])

        if run_parallel("GODOT_SUITES", jobs, 1, summary) != 0:
            failed.append("godot")
    godot_count = len(rule) + len(scene) + (1 if levels else 0)
    seconds = time.monotonic() - started
    tail = f"since={args.since} checks={len(tasks)} python_files={len(tests)} shell={len(scripts)} godot_suites={godot_count}{f' godot_deferred={deferred}' if deferred else ''} seconds={seconds:.0f}"
    if failed:
        print(f"LANE_AFFECTED_FAIL failed={','.join(failed)} {tail}", flush=True)
        return 1
    print(f"LANE_AFFECTED_PASS {tail}", flush=True)
    return 0


def current_rule_suites() -> set[str]:
    return {path.name for path in (ROOT / "tests").glob("run_*.gd") if path.name != RULE_SUITE_RUNNER and is_rule_suite(path)}


def measure_rule_suites(suites: list[str]) -> tuple[int, str, dict[str, float]]:
    """Runs `suites` in one run_all.gd process (own HOME, as in the gate); returns the exit
    code, the log and the RULE_SUITE_TIMING seconds it printed."""
    name, argv, env = godot_suite_job("promote-timings", RULE_SUITE_RUNNER, {}, tuple(suites), fixed_fps_setting())
    code, output, _seconds = run_one(argv, env)
    return code, output, {suite: float(value) for suite, value in RULE_SUITE_TIMING_LINE.findall(output)}


def cmd_promote_timings(args) -> int:
    # The last godot run's per-suite seconds become the tracked shard-packing input; a
    # suite that no longer exists is dropped, one that did not run keeps its old seconds.
    # --missing measures only the rule suites the tracked file lacks (a new suite) and adds them.
    current = current_rule_suites()
    if getattr(args, "missing", False):
        missing = sorted(current - set(load_timings(SUITE_TIMINGS)))
        if not missing:
            measured = {}
        else:
            print(f"PROMOTE_TIMINGS measuring {len(missing)} rule suite(s) the tracked file lacks: {' '.join(missing)}", flush=True)
            code, output, measured = measure_rule_suites(missing)
            unmeasured = [suite for suite in missing if suite not in measured]
            if code != 0 or unmeasured:
                print(output, flush=True)
                print(f"PROMOTE_TIMINGS_FAIL run_all.gd exit={code} unmeasured={unmeasured}", flush=True)
                return 1
    else:
        measured = load_timings(RULE_SUITE_TIMINGS)
        if not measured:
            print(f"PROMOTE_TIMINGS_FAIL no measurements in {RULE_SUITE_TIMINGS} (run `verify_runner.py godot` first, or `promote-timings --missing` for new suites only)", flush=True)
            return 1
    promoted = {name: seconds for name, seconds in load_timings(SUITE_TIMINGS).items() if name in current}
    promoted.update((name, round(seconds, 3)) for name, seconds in measured.items() if name in current)
    write_timings(SUITE_TIMINGS, promoted)
    print(f"PROMOTE_TIMINGS_PASS suites={len(promoted)} measured={len(measured)} total_seconds={sum(promoted.values()):.1f} -> {SUITE_TIMINGS}", flush=True)
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    for name, handler in (("python-tests", cmd_python_tests), ("checks", cmd_checks), ("godot", cmd_godot), ("deep", cmd_deep)):
        p = sub.add_parser(name)
        p.add_argument("--jobs", type=int, default=default_jobs())
        if name == "godot":
            p.add_argument("--sweep-shards", type=int, default=DEFAULT_SWEEP_SHARDS)
            p.add_argument("--rule-shards", type=int, default=DEFAULT_RULE_SHARDS)
        p.set_defaults(handler=handler)
    p = sub.add_parser("affected", help="tools/lane_verify.sh affected: the checks, Python unit files and Godot suites the paths changed since REF hit")
    p.add_argument("--since", required=True)
    p.add_argument("--jobs", type=int, default=default_jobs())
    p.add_argument("--max-scene-suites", type=int, default=12, help="above this many hit scene suites, defer the Godot stage to the fast gate")
    p.add_argument("suites", nargs="*", help="extra tests/run_*.gd suites to run")
    p.set_defaults(handler=cmd_affected)
    p = sub.add_parser("promote-timings")
    p.add_argument("--missing", action="store_true", help="measure and add only the rule suites tests/support/suite_timings.json lacks")
    p.set_defaults(handler=cmd_promote_timings)
    args = parser.parse_args(argv)
    return args.handler(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
