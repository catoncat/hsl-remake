import json
import tempfile
import unittest
from pathlib import Path

from tools import hsl_runtime_phase_plan


class RuntimePhasePlanTests(unittest.TestCase):
    def test_build_plan_contains_required_phase_profiles_and_transitions(self):
        plan = hsl_runtime_phase_plan.build_plan("run-001")

        self.assertEqual(plan["schema"], "hsl_runtime_phase_collection_plan.v1")
        self.assertEqual(plan["run_id"], "run-001")
        self.assertEqual(plan["phase_count"], 11)
        self.assertEqual(plan["transition_count"], 6)
        self.assertIn("player_control", plan["phase_ids"])
        self.assertIn("action_menu", plan["phase_ids"])
        self.assertIn("camera_scroll", plan["phase_ids"])
        self.assertEqual(hsl_runtime_phase_plan.check_plan(plan), [])

    def test_phase_commands_call_probe_and_write_ignored_outputs(self):
        plan = hsl_runtime_phase_plan.build_plan("run-001", no_window=True)
        phase = next(item for item in plan["phases"] if item["phase_id"] == "player_control")

        self.assertTrue(phase["output"].startswith("ignored/runtime-probes/"))
        self.assertIn("tools/hsl_runtime_probe.py", phase["command_argv"])
        self.assertIn("--no-window", phase["command_argv"])
        self.assertIn("--phase-profile", phase["command_argv"])
        self.assertIn("player_control", phase["command_argv"])
        self.assertIn("camera_or_scroll_x", phase["scalar_names"])
        self.assertIn("camera_or_scroll_y", phase["scalar_names"])

    def test_transition_matrix_preserves_battle_engine_priority_order(self):
        plan = hsl_runtime_phase_plan.build_plan("run-001")
        transitions = plan["transitions"]

        self.assertEqual(transitions[0]["transition_id"], "player_control_to_action_menu")
        self.assertEqual(transitions[0]["priority"], 1)
        self.assertEqual(transitions[1]["transition_id"], "action_menu_to_move_select_and_cancel_back")
        self.assertEqual(transitions[2]["transition_id"], "action_menu_to_attack_target_and_cancel_back")
        self.assertEqual(transitions[3]["transition_id"], "action_menu_to_wait_turn_handoff")
        self.assertEqual(transitions[4]["transition_id"], "attack_target_to_action_feedback")
        self.assertEqual(transitions[5]["transition_id"], "turn_handoff_to_script_or_camera_phase")
        self.assertTrue(all(item["evidence_tier_until_observed"] == "manual_hint_only" for item in transitions))

    def test_static_findings_context_is_metadata_only(self):
        plan = hsl_runtime_phase_plan.build_plan("run-001")
        by_name = {item["name"]: item for item in plan["static_findings_context"]}

        self.assertEqual(by_name["script_primary_dispatch_table"]["address"], "0x453708")
        self.assertEqual(by_name["script_action_dispatch_table"]["address"], "0x4537f4")
        self.assertEqual(by_name["script_interpreter_bridge_candidate"]["summary"], "5 CALL xrefs")
        self.assertEqual(by_name["logical_ui_hit_test_candidate"]["summary"], "1 CODE xref")
        self.assertNotIn("raw_bytes", json.dumps(plan))

    def test_main_check_mode_returns_success_without_writing_plan(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "plan.json"
            exit_code = hsl_runtime_phase_plan.main(
                [
                    "--run-id",
                    "run-001",
                    "--output",
                    output.as_posix(),
                    "--check",
                ]
            )

            self.assertEqual(exit_code, 0)
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
