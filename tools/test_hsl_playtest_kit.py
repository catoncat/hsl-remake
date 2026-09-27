"""Offline unit tests for tools/hsl_playtest_kit.py: select turns kept campaign positions into
回憶錄 slots (first entry into each kit battle; the last big-map position before a battle for a
"before" slot; a fresh start for level 51; unreached slots reported), and install copies them
into a playtest profile with the title's 戰場記錄 pointed at the chosen slot and no battle
checkpoint left to win over it."""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load_kit(home: Path):
    os.environ["HSL_PLAYTEST_HOME"] = str(home)
    spec = importlib.util.spec_from_file_location("hsl_playtest_kit_under_test", ROOT / "tools" / "hsl_playtest_kit.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PlaytestKitTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name)
        self.kit = load_kit(self.home)
        snaps = self.kit.KIT / "snapshots"
        snaps.mkdir(parents=True)
        world = "res://content/world/world_map_scene.json"
        positions = [
            ("res://content/battles/battle_052.json", {"units": {"leonard": {"level": 1}}}),
            ("res://content/battles/story_058.json", {"units": {"leonard": {"level": 2}}}),
            ("res://content/battles/battle_053.json", {"units": {"tina": {"level": 1}}}),
            ("res://content/battles/battle_053.json", {"units": {"tina": {"level": 9}}}),
            (world, {"units": {"leonard": {"level": 7}}, "loop": {"gold": 300}}),
            (world, {"units": {"leonard": {"level": 8}}, "loop": {"gold": 270}}),
            ("res://content/battles/battle_006.json", {"units": {"leonard": {"level": 8}}, "loop": {"gold": 70}}),
        ]
        for index, (scenario, carry) in enumerate(positions, start=1):
            record = {"schema": self.kit.PROGRESS_SCHEMA, "scenario_path": scenario, "carry": carry, "world": {}}
            (snaps / f"{index:04d}.json").write_text(json.dumps(record), encoding="utf-8")
        (self.kit.KIT / "generate.log").write_text("CHAPTER_AUTOPLAY level=52 outcome=win\n", encoding="utf-8")

    def tearDown(self) -> None:
        os.environ.pop("HSL_PLAYTEST_HOME", None)
        self.tmp.cleanup()

    def test_select_takes_the_first_entry_and_reports_unreached_slots(self) -> None:
        self.assertEqual(self.kit.select(argparse.Namespace()), 0)
        slots = json.loads((self.kit.KIT / "kit.json").read_text(encoding="utf-8"))["slots"]
        by_scenario = {slot["scenario_path"]: slot for slot in slots}
        self.assertEqual(by_scenario["res://content/battles/battle_051.json"]["status"], "ok")
        self.assertEqual(by_scenario["res://content/battles/battle_005.json"]["status"], "not_reached")
        memoir = json.loads((self.kit.KIT / "saves" / "memoir_02.json").read_text(encoding="utf-8"))
        self.assertEqual(memoir["scenario_path"], "res://content/battles/battle_053.json")
        self.assertEqual(memoir["carry"]["units"]["tina"]["level"], 1, "first entry into the battle, not a later retry")
        self.assertTrue(memoir["memoir_label"].startswith("驗收3"))
        fresh = json.loads((self.kit.KIT / "saves" / "memoir_00.json").read_text(encoding="utf-8"))
        self.assertEqual(fresh["carry"], {}, "level 51 opens the campaign with no carry")
        before = json.loads((self.kit.KIT / "saves" / "memoir_06.json").read_text(encoding="utf-8"))
        self.assertEqual(before["scenario_path"], "res://content/world/world_map_scene.json")
        self.assertEqual(before["carry"]["loop"]["gold"], 270, "the last big-map position before the battle, not an earlier one")
        self.assertEqual(by_scenario["res://content/battles/battle_006.json"]["party"], {"leonard": 8})

    def test_install_points_the_title_resume_at_the_slot_and_clears_checkpoints(self) -> None:
        self.kit.select(argparse.Namespace())
        profile = self.home / "profile"
        user_dir = self.kit.user_dir(profile)
        user_dir.mkdir(parents=True)
        (user_dir / "battle_053_escape.save").write_text("{}", encoding="utf-8")
        self.assertEqual(self.kit.install(argparse.Namespace(profile=str(profile), slot=3)), 0)
        progress = json.loads((user_dir / "campaign_progress.json").read_text(encoding="utf-8"))
        self.assertEqual(progress["scenario_path"], "res://content/battles/battle_053.json")
        self.assertNotIn("memoir_label", progress)
        self.assertEqual(progress["schema"], self.kit.PROGRESS_SCHEMA)
        self.assertFalse(list(user_dir.glob("*.save")), "a battle checkpoint would win over the campaign position")
        self.assertTrue((user_dir / "memoir_02.json").exists())
        self.assertEqual(self.kit.install(argparse.Namespace(profile=str(profile), slot=5)), 1, "an unreached slot refuses")
        self.assertEqual(self.kit.install(argparse.Namespace(profile=str(profile), slot=7)), 0)
        progress = json.loads((user_dir / "campaign_progress.json").read_text(encoding="utf-8"))
        self.assertEqual(progress["scenario_path"], "res://content/world/world_map_scene.json")


if __name__ == "__main__":
    unittest.main()
