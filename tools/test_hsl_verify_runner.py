"""The gate tiers of tools/verify_runner.py stay disjoint: a deep suite is a real file the
fast gate skips, and the sweep the fast gate needs is never a deep suite. The run_all
shards pack every rule suite exactly once by the tracked per-suite seconds."""
import argparse
import json
import sys
import tempfile
import unittest
import unittest.mock
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

import verify_runner  # noqa: E402


class VerifyRunnerTiers(unittest.TestCase):
    def test_deep_suites_exist_and_are_excluded_from_the_fast_gate(self):
        for suite in verify_runner.DEEP_SUITES:
            self.assertTrue((ROOT / "tests" / suite).exists(), suite)
            self.assertIn(suite, verify_runner.GODOT_SUITE_EXCLUDE)
        self.assertNotIn(verify_runner.SWEEP_SUITE, verify_runner.DEEP_SUITES)
        self.assertNotIn(verify_runner.RULE_SUITE_RUNNER, verify_runner.DEEP_SUITES)

    def test_deep_job_runs_the_suite_in_its_own_home(self):
        name, argv, env = verify_runner.godot_suite_job("run_story_mode_explorer_tests.gd", "run_story_mode_explorer_tests.gd", {}, (), 60)
        self.assertEqual(argv, ["tools/godot.sh", "--headless", "--fixed-fps", "60", "--script", "res://tests/run_story_mode_explorer_tests.gd"])
        self.assertEqual(Path(env["HOME"]).name, name)
        _, real_clock, _ = verify_runner.godot_suite_job(name, "run_story_mode_explorer_tests.gd", {}, (), 0)
        self.assertNotIn("--fixed-fps", real_clock)

    def test_every_godot_job_has_a_seed_unless_the_caller_named_one(self):
        with unittest.mock.patch.dict(verify_runner.os.environ, {}, clear=False):
            verify_runner.os.environ.pop(verify_runner.RNG_SEED_ENV, None)
            _, _, env = verify_runner.godot_suite_job("run_a.gd", "run_a.gd", {}, (), 60)
            self.assertEqual(env[verify_runner.RNG_SEED_ENV], verify_runner.DEFAULT_RNG_SEED)
            self.assertEqual(verify_runner.rng_seed_setting(), (verify_runner.DEFAULT_RNG_SEED, "harness_default"))
            verify_runner.os.environ[verify_runner.RNG_SEED_ENV] = "42"
            _, _, env = verify_runner.godot_suite_job("run_a.gd", "run_a.gd", {}, (), 60)
            self.assertEqual(env[verify_runner.RNG_SEED_ENV], "42")
            self.assertEqual(verify_runner.rng_seed_setting(), ("42", "environment"))


class RuleSuiteSharding(unittest.TestCase):
    def rule_suites(self) -> list[str]:
        return sorted(path.name for path in (ROOT / "tests").glob("run_*.gd") if path.name != verify_runner.RULE_SUITE_RUNNER and verify_runner.is_rule_suite(path))

    def test_shard_rule_suites_packs_longest_first_onto_the_lightest_shard(self):
        timings = {"a.gd": 9.0, "b.gd": 6.0, "c.gd": 4.0, "d.gd": 3.0, "e.gd": 2.0}
        shards = verify_runner.shard_rule_suites(sorted(timings), timings, 2)
        # 9 | 6+4 → 9 vs 10; then 3 → 12 goes to the 9 side, 2 → 14 to the 10 side.
        self.assertEqual(shards, [["a.gd", "d.gd"], ["b.gd", "c.gd", "e.gd"]])
        self.assertEqual(verify_runner.shard_rule_suites(["a.gd", "b.gd"], timings, 4), [["a.gd"], ["b.gd"], [], []])

    def test_shard_rule_suites_is_deterministic_and_defaults_an_unknown_suite(self):
        suites = ["run_new_tests.gd", "run_old_tests.gd"]
        timings = {"run_old_tests.gd": 1.0}
        first = verify_runner.shard_rule_suites(suites, timings, 2)
        self.assertEqual(first, verify_runner.shard_rule_suites(list(reversed(suites)), timings, 2))
        # 10 s default outranks the 1 s measured suite, so the unknown suite opens shard 1.
        self.assertEqual(first, [["run_new_tests.gd"], ["run_old_tests.gd"]])
        self.assertEqual(verify_runner.DEFAULT_RULE_SUITE_SECONDS, 10.0)

    def test_tracked_suite_timings_cover_every_rule_suite_and_balance_the_shards(self):
        suites = self.rule_suites()
        timings = verify_runner.load_timings(verify_runner.SUITE_TIMINGS)
        missing = sorted(set(suites) - set(timings))
        deleted = sorted(set(timings) - set(suites))
        if missing or deleted:
            self.fail(f"tests/support/suite_timings.json is out of date (missing rule suites {missing}, deleted suites {deleted}). "
                      "FIX: python3 tools/verify_runner.py promote-timings --missing   "
                      "(measures only the missing suites and drops deleted ones; commit the file). "
                      "A full remeasure: python3 tools/verify_runner.py godot && python3 tools/verify_runner.py promote-timings")
        shards = verify_runner.shard_rule_suites(suites, timings, verify_runner.DEFAULT_RULE_SHARDS)
        self.assertEqual(sorted(name for shard in shards for name in shard), suites)
        loads = [sum(timings[name] for name in shard) for shard in shards]
        # LPT is within 4/3 of optimal; the tracked file must not regress to a lopsided pack.
        self.assertLessEqual(max(loads), sum(loads) / len(loads) * 4 / 3, loads)

    def test_promote_timings_keeps_only_current_rule_suites(self):
        suites = self.rule_suites()
        with tempfile.TemporaryDirectory() as tmp:
            measured = Path(tmp) / "measured.json"
            tracked = Path(tmp) / "tracked.json"
            measured.write_text(json.dumps({suites[0]: 2.3456, "run_deleted_tests.gd": 5.0}), encoding="utf-8")
            tracked.write_text(json.dumps({suites[1]: 1.0, "run_renamed_tests.gd": 7.0}), encoding="utf-8")
            with unittest.mock.patch.object(verify_runner, "RULE_SUITE_TIMINGS", measured), unittest.mock.patch.object(verify_runner, "SUITE_TIMINGS", tracked):
                self.assertEqual(verify_runner.cmd_promote_timings(None), 0)
            self.assertEqual(json.loads(tracked.read_text(encoding="utf-8")), {suites[0]: 2.346, suites[1]: 1.0})
            measured.write_text("{}", encoding="utf-8")
            with unittest.mock.patch.object(verify_runner, "RULE_SUITE_TIMINGS", measured), unittest.mock.patch.object(verify_runner, "SUITE_TIMINGS", tracked):
                self.assertEqual(verify_runner.cmd_promote_timings(None), 1)

    def test_promote_timings_missing_measures_only_the_suites_the_tracked_file_lacks(self):
        suites = self.rule_suites()
        with tempfile.TemporaryDirectory() as tmp:
            tracked = Path(tmp) / "tracked.json"
            tracked.write_text(json.dumps({suite: 1.0 for suite in suites[1:]} | {"run_deleted_tests.gd": 5.0}), encoding="utf-8")
            measure = unittest.mock.Mock(return_value=(0, "", {suites[0]: 2.3456}))
            with unittest.mock.patch.object(verify_runner, "SUITE_TIMINGS", tracked), unittest.mock.patch.object(verify_runner, "measure_rule_suites", measure):
                self.assertEqual(verify_runner.cmd_promote_timings(argparse.Namespace(missing=True)), 0)
            measure.assert_called_once_with([suites[0]])
            self.assertEqual(json.loads(tracked.read_text(encoding="utf-8")), {suite: 1.0 for suite in suites[1:]} | {suites[0]: 2.346})


if __name__ == "__main__":
    unittest.main()
