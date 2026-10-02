"""Regression tests for playtest kit generation; Godot is mocked out."""
from __future__ import annotations

import contextlib
import io
import json
import runpy
import tempfile
import types
import unittest
from pathlib import Path
from unittest import mock

SCRIPT = Path(__file__).with_name("hsl_playtest_kit.py")
TOOL = runpy.run_path(str(SCRIPT), run_name="playtest_kit_test")
TOOL_GLOBALS = TOOL["generate"].__globals__


class PlaytestKitGenerateTests(unittest.TestCase):
    def test_failed_walk_returns_exit_code_and_preserves_existing_package(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            campaign = root / "content" / "battles" / "campaign.json"
            campaign.parent.mkdir(parents=True)
            campaign.write_text('{"battles":{}}', encoding="utf-8")
            kit = root / "kit"
            saves = kit / "saves"
            saves.mkdir(parents=True)
            saved_slot = saves / "memoir_00.json"
            saved_bytes = b'{"schema":"previous-good-slot","keep":"byte for byte"}\n'
            saved_slot.write_bytes(saved_bytes)
            manifest = kit / "kit.json"
            manifest_bytes = b'{"schema":"previous-good-kit","generation":17}\n'
            manifest.write_bytes(manifest_bytes)
            process = types.SimpleNamespace(returncode=7, poll=lambda: 7)
            args = types.SimpleNamespace(tries=1, budget=1, force_win=False)

            with (
                mock.patch.dict(TOOL_GLOBALS, {"ROOT": root, "KIT": kit}),
                mock.patch.object(TOOL_GLOBALS["subprocess"], "Popen", return_value=process),
                mock.patch.object(TOOL_GLOBALS["subprocess"], "run") as git_checkout,
                contextlib.redirect_stdout(io.StringIO()),
            ):
                result = TOOL["generate"](args)

            self.assertEqual(result, 7)
            git_checkout.assert_called_once()
            self.assertEqual(saved_slot.read_bytes(), saved_bytes)
            self.assertEqual(manifest.read_bytes(), manifest_bytes)

    def test_successful_walk_still_generates_a_package(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            kit = root / "kit"
            campaign = root / "content" / "battles" / "campaign.json"
            campaign.parent.mkdir(parents=True)
            campaign.write_text('{"battles":{}}', encoding="utf-8")

            record = {
                "schema": "hsl_campaign_progress_save.v1",
                "scenario_path": "res://content/battles/battle_051.json",
                "carry": {},
                "world": {},
            }

            def start_successful_walk(_cmd, *, env, **_kwargs):
                progress = Path(env["HOME"]) / TOOL_GLOBALS["USER_DIR_TAIL"] / "campaign_progress.json"
                progress.parent.mkdir(parents=True)
                progress.write_text(json.dumps(record), encoding="utf-8")
                return types.SimpleNamespace(returncode=0, poll=lambda: 0)

            args = types.SimpleNamespace(tries=1, budget=1, force_win=False)
            with (
                mock.patch.dict(TOOL_GLOBALS, {"ROOT": root, "KIT": kit}),
                mock.patch.object(TOOL_GLOBALS["subprocess"], "Popen", side_effect=start_successful_walk),
                mock.patch.object(TOOL_GLOBALS["subprocess"], "run"),
                contextlib.redirect_stdout(io.StringIO()),
            ):
                result = TOOL["generate"](args)

            self.assertEqual(result, 0)
            self.assertTrue((kit / "saves" / "memoir_00.json").is_file())
            generated = json.loads((kit / "kit.json").read_text(encoding="utf-8"))
            self.assertEqual(generated["snapshots"], 1)
            self.assertEqual(generated["slots"][0]["status"], "ok")


if __name__ == "__main__":
    unittest.main()
