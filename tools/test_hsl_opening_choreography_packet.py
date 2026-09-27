import argparse
import json
import tempfile
import unittest
from pathlib import Path

from tools import hsl_opening_choreography_packet as packet_builder
import hsltools.evidence.opening_choreography_packet as packet_check


class OpeningChoreographyPacketTest(unittest.TestCase):
    def test_build_packet_preserves_direct_actor_motion_boundary(self) -> None:
        args = argparse.Namespace(
            visual_index=packet_builder.DEFAULT_VISUAL_INDEX,
            timeline=packet_builder.DEFAULT_TIMELINE,
            map_objects=packet_builder.DEFAULT_MAP_OBJECTS,
            map_object_visibility=packet_builder.DEFAULT_MAP_OBJECT_VISIBILITY,
            actor_walk=packet_builder.DEFAULT_ACTOR_WALK,
            runtime_capture=packet_builder.DEFAULT_RUNTIME_CAPTURE,
            opening_capture=packet_builder.DEFAULT_OPENING_CAPTURE,
            autoplay_capture=packet_builder.DEFAULT_AUTOPLAY_CAPTURE,
        )
        packet = packet_builder.build_packet(args)
        self.assertEqual(packet["schema"], packet_builder.SCHEMA)
        self.assertEqual(packet["script_timeline"]["direct_actor_motion_count"], 1)
        self.assertEqual(
            packet["script_timeline"]["direct_actor_motion_tokens"][0]["source_token"],
            "actWalkDispWait(SID_PLAYER0,1,0,-96,2)",
        )
        actors = {item["actor_token"]: item for item in packet["actor_choreography"]}
        self.assertEqual(actors["SID_PLAYER0"]["motion_status"], "direct_story051_walk_token")
        self.assertEqual(actors["SID_ENEMY023"]["motion_status"], "dialogue_actor_only_no_direct_walk_token")
        self.assertEqual(actors["SID_ENEMY024"]["motion_status"], "dialogue_actor_only_no_direct_walk_token")
        self.assertEqual(actors["SID_ENEMY021"]["motion_status"], "dialogue_actor_only_no_direct_walk_token")
        self.assertEqual(actors["SID_ENEMY026"]["motion_status"], "known_first_scene_actor_no_story051_motion_token")
        self.assertIn("first_control_idle_no_menu", packet["missing_original_truth"])
        self.assertIn("complete_enemy_gate_entry_paths", packet["missing_original_truth"])
        current = packet["current_godot_consumption"]
        status = current["generated_capture_status"]
        if status["runtime_capture"] == packet_builder.MISSING_CAPTURE_STATUS:
            self.assertEqual(current["runtime_capture_count"], 0)
        else:
            self.assertEqual(
                current["runtime_contract_opening_choreography_packet_schema"],
                packet_builder.SCHEMA,
            )
        if status["opening_capture"] == packet_builder.MISSING_CAPTURE_STATUS:
            self.assertEqual(current["opening_capture_count"], 0)
            self.assertEqual(current["opening_capture_segment_record_stages"], [])
            self.assertEqual(current["opening_capture_camera_contract_stages"], [])
        else:
            self.assertEqual(current["opening_capture_choreography_packet_schema"], packet_builder.SCHEMA)
            self.assertEqual(current["opening_capture_motion_driver_segments"], ["leonard_story_walk"])
            opening_records = {
                item["stage"]: item
                for item in current["opening_capture_segment_record_stages"]
            }
            self.assertEqual(opening_records["opening_music"]["segment_ids"], ["transition_context", "upper_gate_bridge_context"])
            self.assertEqual(opening_records["opening_music"]["segment_record_count"], 2)
            self.assertIn("complete enemy entry path", opening_records["opening_music"]["segment_not_proven"])
            self.assertEqual(opening_records["actor_walk_token"]["segment_ids"], ["leonard_story_walk"])
            self.assertEqual(opening_records["actor_walk_token"]["segment_record_count"], 1)
            self.assertIn("foot anchor", opening_records["actor_walk_token"]["segment_not_proven"])
            self.assertEqual(opening_records["dialogue_message_363"]["segment_ids"], ["dialogue_lower_context"])
            self.assertIn("original message box layout", opening_records["dialogue_message_363"]["segment_not_proven"])
            self.assertEqual(opening_records["winfail_board_refresh"]["segment_ids"], ["status_and_first_control_handoff"])
            self.assertIn("first_control_idle_no_menu", opening_records["winfail_board_refresh"]["segment_not_proven"])
            opening_camera_records = {
                item["stage"]: item
                for item in current["opening_capture_camera_contract_stages"]
            }
            self.assertEqual(
                opening_camera_records["opening_music"]["candidate_camera_evidence_ids"],
                ["p1_route_upper_formation_11", "p1_route_upper_formation_12"],
            )
            self.assertEqual(
                opening_camera_records["opening_music"]["context_only_evidence_ids"],
                ["opening_transition_rain_frame", "opening_transition_castle_wall_frame"],
            )
            self.assertTrue(opening_camera_records["opening_music"]["transition_frames_are_context_only"])
            self.assertEqual(opening_camera_records["opening_music"]["continuous_curve_status"], "missing_original_truth")
            self.assertEqual(
                opening_camera_records["dialogue_message_363"]["candidate_camera_evidence_ids"],
                ["opening_dialogue_leonard", "opening_dialogue_soldier", "opening_lower_formation_before_dialogue"],
            )
            self.assertIn(
                "dialogue_text_source",
                opening_camera_records["dialogue_message_363"]["current_stage_not_proven"],
            )
        if status["opening_autoplay_capture"] == packet_builder.MISSING_CAPTURE_STATUS:
            self.assertEqual(current["autoplay_capture_count"], 0)
            self.assertEqual(current["autoplay_capture_segment_record_stages"], [])
            self.assertEqual(current["autoplay_capture_camera_contract_stages"], [])
        else:
            self.assertEqual(current["autoplay_capture_choreography_packet_schema"], packet_builder.SCHEMA)
            self.assertEqual(current["autoplay_capture_motion_driver_segments"], ["leonard_story_walk"])
            autoplay_records = {
                item["stage"]: item
                for item in current["autoplay_capture_segment_record_stages"]
            }
            self.assertEqual(autoplay_records["autoplay_start"]["segment_ids"], ["transition_context", "upper_gate_bridge_context"])
            self.assertEqual(autoplay_records["autoplay_start"]["segment_record_count"], 2)
            autoplay_camera_records = {
                item["stage"]: item
                for item in current["autoplay_capture_camera_contract_stages"]
            }
            self.assertTrue(autoplay_camera_records["autoplay_start"]["transition_frames_are_context_only"])
            self.assertEqual(
                autoplay_camera_records["autoplay_first_control"]["candidate_camera_evidence_ids"],
                ["first_control_action_menu", "p1_route_action_menu_13"],
            )
            self.assertIn(
                "original_action_menu_handler_semantics",
                autoplay_camera_records["autoplay_first_control"]["current_stage_not_proven"],
            )

    def test_generated_packet_passes_checker(self) -> None:
        args = argparse.Namespace(
            visual_index=packet_builder.DEFAULT_VISUAL_INDEX,
            timeline=packet_builder.DEFAULT_TIMELINE,
            map_objects=packet_builder.DEFAULT_MAP_OBJECTS,
            map_object_visibility=packet_builder.DEFAULT_MAP_OBJECT_VISIBILITY,
            actor_walk=packet_builder.DEFAULT_ACTOR_WALK,
            runtime_capture=packet_builder.DEFAULT_RUNTIME_CAPTURE,
            opening_capture=packet_builder.DEFAULT_OPENING_CAPTURE,
            autoplay_capture=packet_builder.DEFAULT_AUTOPLAY_CAPTURE,
        )
        packet = packet_builder.build_packet(args)
        with tempfile.TemporaryDirectory() as tmpdir:
            packet_path = Path(tmpdir) / "packet.json"
            packet_path.write_text(json.dumps(packet, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            summary = packet_check.check_packet(packet_path, Path.cwd())
        self.assertEqual(summary["segments"], 5)
        self.assertEqual(summary["direct_actor_motion_count"], 1)


if __name__ == "__main__":
    unittest.main()
