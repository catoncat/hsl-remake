from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from tools import hsl_script_vm_semantics
from hsltools import original_content


def action(index: int, name: str, args: list[str]) -> dict:
    return {
        "index": index,
        "primary": name,
        "name": name,
        "chain": [{"name": name, "args": args}],
    }


def script_doc(script_id: str, source_file: str, sections: list[dict]) -> dict:
    return {
        "schema": "hsl_chapter01_script_ir.v1",
        "id": script_id,
        "source_file": source_file,
        "source_id": source_file,
        "source_policy": "test fixture preserving action order, args, and message ids",
        "evidence_tier": "resource-derived",
        "encoding": "ascii",
        "includes": [],
        "resource_refs": [],
        "define_values": {},
        "section_counts": {},
        "action_counts": {},
        "action_line_count": sum(len(section["actions"]) for section in sections),
        "action_chain_count": sum(len(item["chain"]) for section in sections for item in section["actions"]),
        "sections": sections,
        "action_chain": [],
    }


def write_fixture(root: Path) -> Path:
    scripts = root / "scripts"
    scripts.mkdir()
    story = script_doc(
        "story051",
        "STORY051.TXT",
        [
            {
                "index": 0,
                "name": "story",
                "type": "story",
                "codes": [],
                "messages": [],
                "message_ids": [],
                "actions": [
                    action(0, "actPlayLevelMusic", []),
                    action(0, "actMessage", ["SID_PLAYER0", "1", "363"]),
                    action(1, "actWalkDispWait", ["SID_PLAYER0", "1", "0", "-96", "2"]),
                    action(2, "actShowSectionName", ["SHAPE01\\WORD051.SHP"]),
                    action(0, "actInsertFailStatus", ["0"]),
                    action(1, "actInsertEventStatus", ["0"]),
                    action(2, "actInsertEventStatus", ["1"]),
                ],
            }
        ],
    )
    winfail = script_doc(
        "winfail051",
        "winfail051.txt",
        [
            {
                "index": 0,
                "name": "win",
                "type": "win",
                "codes": ["0"],
                "messages": ["-1,121"],
                "message_ids": ["-1", "121"],
                "actions": [action(0, "actCheckEnemyTotalNumber", ["0"])],
            },
            {
                "index": 1,
                "name": "fail",
                "type": "fail",
                "codes": ["0"],
                "messages": ["0,122"],
                "message_ids": ["0", "122"],
                "actions": [action(0, "actCheckPlayer", ["1", "SID_PLAYER0"])],
            },
            {
                "index": 2,
                "name": "event",
                "type": "event",
                "codes": ["0"],
                "messages": [],
                "message_ids": [],
                "actions": [
                    action(0, "actCheckEnemyNumber", ["SID_ENEMY021", "3"]),
                    action(1, "actDeleteEventStatus", ["0"]),
                    action(2, "actInsertWinStatus", ["0"]),
                    action(3, "actInsertEventStatus", ["1"]),
                    action(4, "actInsertObject", ["obj_Story_Level51_Enemy21", "267", "209"]),
                    action(5, "actScrollBGToPos", ["267", "209"]),
                ],
            },
            {
                "index": 3,
                "name": "event",
                "type": "event",
                "codes": ["1"],
                "messages": [],
                "message_ids": [],
                "actions": [
                    action(0, "actCheckRoundNumber", ["6"]),
                    action(1, "actMessageIfExist", ["SID_PLAYER0", "1", "397", "0", "2", "SID_ENEMY023"]),
                ],
            },
        ],
    )
    (scripts / "story051.json").write_text(json.dumps(story), encoding="utf-8")
    (scripts / "winfail051.json").write_text(json.dumps(winfail), encoding="utf-8")
    index = {
        "schema": "hsl_chapter01_script_ir_index.v1",
        "source_policy": "test fixture preserving action order and args",
        "evidence_tier": "resource-derived",
        "scripts": [
            {
                "id": "story051",
                "file": "scripts/story051.json",
                "source_file": "STORY051.TXT",
                "source_id": "STORY051.TXT",
                "section_count": 1,
                "action_line_count": 3,
                "action_chain_count": 3,
                "evidence_tier": "resource-derived",
            },
            {
                "id": "winfail051",
                "file": "scripts/winfail051.json",
                "source_file": "winfail051.txt",
                "source_id": "winfail051.txt",
                "section_count": 4,
                "action_line_count": 7,
                "action_chain_count": 7,
                "evidence_tier": "resource-derived",
            },
        ],
        "total_action_line_count": 10,
        "total_action_chain_count": 10,
    }
    path = root / "script_ir_index.json"
    path.write_text(json.dumps(index), encoding="utf-8")
    return path


def write_message_text_evidence_fixture(root: Path) -> Path:
    path = root / "message_text_evidence.json"
    path.write_text(
        json.dumps(
            {
                "schema": "hsl_chapter01_imported_message_text_evidence.v1",
                "message_text_status": "not_resolved_in_imported_assets",
                "message_text_source_status": "missing_structured_text_table",
                "summary": {
                    "script_message_id_candidate_count": 2,
                    "structured_text_table_candidate_count": 0,
                    "word_shape_ref_count": 1,
                },
                "script_message_id_candidates": ["363", "397"],
                "word_shape_resource_refs": ["SHAPE01\\WORD051.SHP"],
                "structured_text_table_candidates": [],
                "negative_evidence": [
                    "no structured message text table payload was identified in searched imported roots",
                ],
                "unresolved_semantics": [
                    "fixture text lookup remains unresolved",
                ],
            }
        ),
        encoding="utf-8",
    )
    return path


def write_static_candidate_fixture(root: Path) -> Path:
    path = root / "static_index.json"
    path.write_text(
        json.dumps(
            {
                "condition_predicate_handler_candidates": {
                    "schema": "hsl_static_condition_predicate_handler_candidates.v1",
                    "evidence_tier": "static_candidate_skeleton",
                    "semantic_status": "unresolved",
                    "actions": [
                        {
                            "action_name": "actCheckEnemyNumber",
                            "candidate_slot_if_order_matched": 14,
                            "candidate_handler_if_order_matched": "0x451aa3",
                            "correlation_status": "unresolved",
                            "ordinal_as_slot_status": "not_evidence",
                            "slot_opcode_evidence_status": "unresolved",
                            "comparison_polarity_evidence_status": "unresolved",
                            "why_unresolved": "fixture candidate only",
                        }
                    ],
                },
                "status_lifecycle_handler_candidates": {
                    "schema": "hsl_static_status_lifecycle_handler_candidates.v1",
                    "evidence_tier": "static_candidate_skeleton",
                    "semantic_status": "unresolved",
                    "execution_policy": "scheduled_only_no_live_mutation",
                    "actions": [
                        {
                            "action_name": "actInsertWinStatus",
                            "candidate_slot_if_order_matched": 24,
                            "candidate_handler_if_order_matched": "0x4510cd",
                            "correlation_status": "unresolved",
                            "ordinal_as_slot_status": "not_evidence",
                            "slot_opcode_evidence_status": "unresolved",
                            "commit_timing_evidence_status": "unresolved",
                            "lifecycle_semantic_status": "scheduled_only",
                            "bridge_commit_timing_status": "unresolved",
                            "why_unresolved": "fixture status candidate only",
                        }
                    ],
                },
                "script_status_commit_path_static_context": {
                    "schema": "hsl_static_script_status_commit_path_context.v1",
                    "evidence_tier": "static_commit_path_candidate",
                    "semantic_status": "unresolved",
                    "execution_policy": "scheduled_only_no_live_mutation",
                    "bridge_address": "0x450840",
                    "script_cursor_progress": {
                        "script_cursor_field_offset": "0x90",
                        "script_cursor_write_count": 84,
                        "script_cursor_write_addresses_sample": ["0x45120f", "0x451242"],
                        "token_advance_count": 125,
                        "token_advance_addresses_sample": ["0x450887", "0x4508ef"],
                        "return_count": 118,
                        "commit_boundary_status": "script_cursor_progress_observed",
                        "status_mutation_commit_status": "unresolved",
                    },
                    "registry_write_status": "unresolved",
                    "deferred_queue_candidate_status": "unresolved",
                    "status_mutation_commit_timing_status": "unresolved",
                    "status_handler_boundary_candidates": [
                        {
                            "action_name": "actInsertWinStatus",
                            "candidate_handler_if_order_matched": "0x4510cd",
                            "correlation_status": "unresolved",
                            "ordinal_as_slot_status": "not_evidence",
                            "commit_timing_evidence_status": "unresolved",
                        }
                    ],
                    "negative_evidence": [
                        "fixture separates cursor progress from status mutation commit timing",
                    ],
                },
            }
        ),
        encoding="utf-8",
    )
    return path


class ScriptVmSemanticsTests(unittest.TestCase):
    @unittest.skipUnless(original_content.present(), 'original-derived content absent (hsltools.original_content)')
    def test_builds_status_registry_and_section_dispatch(self):
        with tempfile.TemporaryDirectory() as tmp:
            index_path = write_fixture(Path(tmp))

            semantics = hsl_script_vm_semantics.build_semantics(index_path)

        self.assertEqual(semantics["evidence_tier"], "resource-derived")
        self.assertEqual(semantics["status_registry"]["fail"]["initial_enabled_ids"], ["0"])
        self.assertEqual(semantics["status_registry"]["event"]["initial_enabled_ids"], ["0", "1"])
        self.assertEqual(semantics["status_registry"]["event"]["deleted_ids"], ["0"])
        self.assertEqual(semantics["status_registry"]["win"]["inserted_ids"], ["0"])
        self.assertEqual(semantics["condition_summary"]["actCheckRoundNumber"], 1)
        event_zero = semantics["section_dispatch"]["event"][0]
        self.assertEqual(event_zero["status_id"], "0")
        self.assertEqual(event_zero["conditions"][0]["name"], "actCheckEnemyNumber")
        self.assertEqual(event_zero["mutations"][0]["name"], "actDeleteEventStatus")
        self.assertIn("unresolved", event_zero["unresolved_semantics"][0])
        hints = semantics["dispatch_correlation_hints"]
        self.assertEqual(hints["static_targets"]["script_action_dispatch_table"], "0x4537f4")
        self.assertEqual(hints["static_targets"]["script_interpreter_bridge_candidate"], "0x450840")
        self.assertIn("actCheckEnemyNumber", hints["ordered_unique_action_names"])
        self.assertEqual(hints["correlation_status"], "unresolved")
        catalog = semantics["action_semantics_catalog"]
        self.assertEqual(catalog["category_summary"]["message"], 2)
        self.assertEqual(catalog["category_summary"]["movement"], 1)
        self.assertEqual(catalog["category_summary"]["object"], 1)
        self.assertEqual(catalog["category_summary"]["camera"], 1)
        self.assertEqual(catalog["category_summary"]["ui"], 1)
        self.assertEqual(catalog["category_summary"]["audio"], 1)
        message_entry = catalog["by_action"]["actMessage"][0]
        self.assertEqual(message_entry["category"], "message")
        self.assertEqual(message_entry["args"], ["SID_PLAYER0", "1", "363"])
        self.assertIn("unresolved", message_entry["unresolved_semantics"][0])
        dry_run = semantics["interpreter_dry_run_trace_model"]
        self.assertEqual(dry_run["evidence_tier"], "resource-derived")
        self.assertEqual(dry_run["context_examples"]["enemy_clear_candidate"]["enemy_total"], 0)
        event_trace = dry_run["trace_examples"]["round_6_objective_switch_candidate"]
        self.assertEqual(event_trace["context"]["round_number"], 6)
        event_one = [
            item
            for item in event_trace["dispatch"]["event"]
            if item["status_id"] == "1"
        ][0]
        self.assertEqual(event_one["candidate_result"], "candidate_true")
        self.assertEqual(event_one["condition_results"][0]["condition_name"], "actCheckRoundNumber")
        self.assertEqual(event_one["condition_results"][0]["result"], "candidate_true")
        self.assertEqual(event_one["scheduled_mutations"], [])
        predicate_catalog = semantics["condition_predicate_catalog"]
        self.assertEqual(predicate_catalog["semantic_status"], "unresolved")
        self.assertEqual(predicate_catalog["condition_action_count"], 4)
        enemy_predicate = predicate_catalog["by_action"]["actCheckEnemyNumber"]
        self.assertEqual(enemy_predicate["occurrence_count"], 1)
        self.assertEqual(enemy_predicate["candidate_context_binding"], "enemy_counts[object_or_group_id]")
        self.assertEqual(enemy_predicate["predicate_status"], "unknown")
        self.assertEqual(enemy_predicate["args_schema_candidate"][0], "object_or_group_id")
        self.assertEqual(enemy_predicate["evidence_requests"]["exe_static"][0]["target"], "0x4537f4")
        self.assertEqual(enemy_predicate["evidence_requests"]["runtime_probes"][0]["phase_profile"], "player_control")
        self.assertNotIn("script_phase", json.dumps(enemy_predicate["evidence_requests"]))
        round_predicate = predicate_catalog["by_action"]["actCheckRoundNumber"]
        self.assertEqual(round_predicate["candidate_context_binding"], "round_number")
        self.assertEqual(round_predicate["runtime_probe_priority"], "defer_until_round_transition_probe")
        lifecycle = semantics["status_mutation_lifecycle_model"]
        self.assertEqual(lifecycle["semantic_status"], "unresolved")
        self.assertEqual(lifecycle["initial_enabled_status"]["fail"], ["0"])
        self.assertEqual(lifecycle["initial_enabled_status"]["event"], ["0", "1"])
        self.assertEqual(lifecycle["initial_enabled_status"]["win"], [])
        self.assertEqual(lifecycle["mutation_counts_by_action"]["actInsertEventStatus"], 3)
        self.assertEqual(lifecycle["mutation_counts_by_action"]["actDeleteEventStatus"], 1)
        event_zero_mutations = lifecycle["section_lifecycle"]["event"][0]["scheduled_mutations"]
        self.assertEqual(
            [(item["operation"], item["status_kind"], item["status_id"]) for item in event_zero_mutations],
            [("delete", "event", "0"), ("insert", "win", "0"), ("insert", "event", "1")],
        )
        self.assertEqual(lifecycle["section_lifecycle"]["event"][0]["dispatch_timing_status"], "unknown")
        effect_catalog = semantics["action_effect_facade_catalog"]
        self.assertEqual(effect_catalog["semantic_status"], "facade_only")
        self.assertEqual(effect_catalog["handler_mapping_status"], "unresolved")
        self.assertEqual(effect_catalog["effect_family_summary"]["message"], 2)
        self.assertEqual(effect_catalog["effect_family_summary"]["movement"], 1)
        message_effect = effect_catalog["by_action"]["actMessage"]
        self.assertEqual(message_effect["effect_family"], "message")
        self.assertEqual(message_effect["facade_mode"], "diagnostic_trace_only")
        self.assertEqual(message_effect["effect_status"], "candidate_unresolved")
        self.assertEqual(message_effect["occurrence_count"], 1)
        self.assertEqual(message_effect["evidence_requests"]["exe_static"][0]["target"], "0x4537f4")
        self.assertNotIn("handler_confirmed", json.dumps(effect_catalog))
        self.assertNotIn("script_phase", json.dumps(effect_catalog["by_action"]["actMessage"]["evidence_requests"]))
        event_log = semantics["script_event_log_model"]
        self.assertEqual(event_log["consumer"], "godot_read_play_event_log")
        self.assertIn("actMessage", event_log["supported_handler_subset"])
        self.assertIn("dispatch_section_diagnostic", event_log["supported_handler_subset"])
        self.assertEqual(event_log["message_text_resolution"]["status"], "not_resolved_in_imported_assets")
        self.assertIn("display_label", event_log["message_text_resolution"]["available_readable_fields"])
        self.assertEqual(event_log["message_text_resolution"]["evidence_bridge"]["status"], "external_evidence_missing")
        self.assertEqual(event_log["supported_handler_counts"]["actMessage"], 1)
        self.assertEqual(event_log["supported_handler_counts"]["actMessageIfExist"], 1)
        self.assertEqual(event_log["supported_handler_counts"]["actPlayLevelMusic"], 1)
        self.assertEqual(event_log["supported_handler_counts"]["actShowSectionName"], 1)
        self.assertEqual(event_log["supported_handler_counts"]["actInsertEventStatus"], 3)
        self.assertEqual(len(event_log["dispatch_diagnostics"]), 4)
        phase_views = event_log["phase_views"]
        self.assertEqual(phase_views["phase_order"], ["story", "win", "fail", "event"])
        self.assertEqual(phase_views["views"]["story"]["entry_count"], 6)
        self.assertEqual(phase_views["views"]["story"]["dispatch_count"], 0)
        self.assertEqual(phase_views["views"]["event"]["entry_count"], 4)
        self.assertEqual(phase_views["views"]["event"]["dispatch_count"], 2)
        self.assertEqual(phase_views["views"]["win"]["dispatch_count"], 1)
        self.assertEqual(phase_views["views"]["fail"]["dispatch_count"], 1)
        panel_summaries = event_log["godot_panel_phase_summaries"]
        self.assertEqual(panel_summaries["consumer"], "godot_imported_script_panel")
        self.assertEqual(panel_summaries["phase_order"], ["story", "win", "fail", "event"])
        story_summary = panel_summaries["phases"]["story"]
        self.assertEqual(story_summary["display_label_count"], 3)
        self.assertEqual(story_summary["scheduled_status_count"], 3)
        message_preview = [
            item
            for item in story_summary["display_label_preview"]
            if item["display_label"] == "SID_PLAYER0: message#363"
        ][0]
        self.assertEqual(message_preview["message_text_status"], "not_resolved_in_imported_assets")
        self.assertIn("play level music", [item["display_label"] for item in story_summary["display_label_preview"]])
        self.assertIn(
            "section title resource: SHAPE01\\WORD051.SHP",
            [item["display_label"] for item in story_summary["display_label_preview"]],
        )
        event_summary = panel_summaries["phases"]["event"]
        self.assertEqual(event_summary["display_label_count"], 1)
        self.assertEqual(event_summary["dispatch_count"], 2)
        self.assertEqual(event_summary["dispatch_preview"][0]["diagnostic_status"], "visible_unresolved_dispatch")
        panel_trace = event_log["godot_panel_read_play_trace"]
        self.assertEqual(panel_trace["phase_order"], ["story", "win", "fail", "event"])
        self.assertEqual(panel_trace["step_count"], len(panel_trace["steps"]))
        self.assertEqual(panel_trace["steps"][0]["phase"], "story")
        self.assertEqual(panel_trace["steps"][0]["step_type"], "resource_action")
        self.assertEqual(panel_trace["steps"][0]["display_text"], "play level music")
        self.assertEqual(panel_trace["steps"][0]["execution_status"], "read_only_panel_trace")
        resource_steps = [item for item in panel_trace["steps"] if item["step_type"] == "resource_action"]
        self.assertEqual(resource_steps[0]["display_text"], "play level music")
        self.assertEqual(resource_steps[0]["resource_action_type"], "music_action")
        self.assertEqual(resource_steps[1]["display_text"], "section title resource: SHAPE01\\WORD051.SHP")
        self.assertEqual(resource_steps[1]["resource_action_type"], "section_title_resource")
        self.assertEqual(resource_steps[1]["resource_text_status"], "resource_ref_only_text_not_decoded")
        message_step = [item for item in panel_trace["steps"] if item["step_type"] == "display_label"][0]
        self.assertEqual(message_step["display_text"], "SID_PLAYER0: message#363")
        scheduled_step = [item for item in panel_trace["steps"] if item["step_type"] == "scheduled_status"][0]
        self.assertEqual(scheduled_step["mutation_status"], "scheduled_event_log_only")
        dispatch_step = [item for item in panel_trace["steps"] if item["step_type"] == "dispatch_diagnostic"][0]
        self.assertEqual(dispatch_step["diagnostic_status"], "visible_unresolved_dispatch")
        timeline_anchors = event_log["godot_timeline_anchors"]
        self.assertEqual(timeline_anchors["consumer"], "godot_imported_script_panel")
        self.assertEqual(timeline_anchors["phase_order"], ["story", "win", "fail", "event"])
        progress_anchor = timeline_anchors["progress_boundary_anchor"]
        self.assertEqual(progress_anchor["anchor_status"], "diagnostic_only_not_commit_evidence")
        self.assertEqual(progress_anchor["evidence_status"], "static_cursor_progress_loaded")
        self.assertEqual(progress_anchor["source_bridge_address"], "0x450840")
        self.assertEqual(progress_anchor["progress_boundary_status"], "script_cursor_progress_observed")
        self.assertEqual(progress_anchor["registry_write_status"], "unresolved")
        self.assertEqual(progress_anchor["deferred_queue_candidate_status"], "unresolved")
        self.assertEqual(progress_anchor["status_mutation_commit_timing_status"], "unresolved")
        self.assertEqual(progress_anchor["status_mutation_commit_status"], "unresolved")
        story_anchors = timeline_anchors["phases"]["story"]
        self.assertEqual(story_anchors["first_display_label"], "play level music")
        self.assertEqual(story_anchors["display_label_anchors"][0]["anchor_status"], "read_only_visible_anchor")
        self.assertEqual(story_anchors["scheduled_status_anchors"][0]["anchor_status"], "scheduled_event_log_only")
        event_anchors = timeline_anchors["phases"]["event"]
        self.assertEqual(event_anchors["dispatch_anchors"][0]["anchor_status"], "visible_unresolved_dispatch")
        message_log = [item for item in event_log["event_log_entries"] if item["entry_type"] == "message"][0]
        self.assertEqual(message_log["handler_name"], "actMessage")
        self.assertEqual(message_log["execution_status"], "event_log_only")
        self.assertEqual(message_log["visible_fields"]["speaker_or_channel_candidate"], "SID_PLAYER0")
        self.assertEqual(message_log["visible_fields"]["message_id_candidate"], "363")
        self.assertEqual(message_log["visible_fields"]["message_id_candidates"], ["363"])
        self.assertEqual(message_log["visible_fields"]["message_text_status"], "not_resolved_in_imported_assets")
        self.assertEqual(message_log["visible_fields"]["display_label"], "SID_PLAYER0: message#363")
        if_exist_log = [
            item
            for item in event_log["event_log_entries"]
            if item["entry_type"] == "message" and item["handler_name"] == "actMessageIfExist"
        ][0]
        self.assertEqual(if_exist_log["visible_fields"]["message_id_candidates"], ["397", "0"])
        self.assertEqual(if_exist_log["visible_fields"]["conditional_or_fallback_message_id_candidates"], ["0"])
        self.assertEqual(if_exist_log["visible_fields"]["existence_check_args_candidate"], ["2", "SID_ENEMY023"])
        status_log = [
            item
            for item in event_log["event_log_entries"]
            if item["entry_type"] == "scheduled_status_mutation" and item["handler_name"] == "actInsertWinStatus"
        ][0]
        self.assertEqual(status_log["execution_status"], "scheduled_event_log_only")
        self.assertEqual(status_log["status_kind"], "win")
        self.assertEqual(status_log["status_id"], "0")
        resource_log = [
            item
            for item in event_log["event_log_entries"]
            if item["entry_type"] == "resource_action" and item["handler_name"] == "actShowSectionName"
        ][0]
        self.assertEqual(resource_log["execution_status"], "resource_event_log_only")
        self.assertEqual(resource_log["visible_fields"]["resource_ref_candidate"], "SHAPE01\\WORD051.SHP")
        self.assertEqual(resource_log["visible_fields"]["resource_text_status"], "resource_ref_only_text_not_decoded")
        self.assertNotIn("handler_confirmed", json.dumps(event_log))
        self.assertNotIn("script_phase", json.dumps(event_log))
        facade_contract = semantics["interpreter_facade_contract"]
        self.assertEqual(facade_contract["consumer"], "godot_dry_run_diagnostics")
        self.assertIn("condition_predicate_catalog", facade_contract["stable_inputs"])
        self.assertIn("status_mutation_lifecycle_model", facade_contract["stable_inputs"])
        self.assertIn("action_effect_facade_catalog", facade_contract["stable_inputs"])
        self.assertIn("interpreter_dry_run_trace_model", facade_contract["stable_inputs"])
        self.assertIn("script_event_log_model", facade_contract["stable_inputs"])
        invariants = facade_contract["cross_field_invariants"]
        self.assertEqual(invariants["condition_predicates"]["semantic_status"], "unresolved")
        self.assertEqual(invariants["condition_predicates"]["static_navigation_hint_correlation_status"], ["missing", "unresolved"])
        self.assertEqual(invariants["condition_predicates"]["source_numeric_opcode_status"], "missing_in_imported_ir")
        self.assertFalse(facade_contract["allows_handler_execution"])
        self.assertFalse(facade_contract["allows_live_battle_mutation"])
        self.assertFalse(facade_contract["allows_evidence_tier_upgrade"])
        facade_guard = facade_contract["guard_summary"]
        self.assertEqual(facade_guard["required_imported_opcode_status"], "missing_in_imported_ir")
        self.assertEqual(facade_guard["required_opcode_gap_guard_status"], "active")
        self.assertTrue(facade_guard["read_only_inputs_only"])
        self.assertTrue(facade_guard["no_handler_execution"])
        self.assertTrue(facade_guard["no_live_battle_mutation"])
        self.assertTrue(facade_guard["no_evidence_tier_upgrade"])
        self.assertTrue(facade_guard["no_generic_phase_label_evidence"])
        self.assertFalse(facade_guard["static_navigation_hints_are_opcode_evidence"])
        self.assertEqual(facade_guard["allowed_evidence_tier"], "resource-derived")
        self.assertNotIn("script_phase", json.dumps(facade_contract))
        gap_audit = semantics["imported_opcode_token_gap_audit"]
        self.assertEqual(gap_audit["source_numeric_opcode_status"], "missing_in_imported_ir")
        self.assertEqual(gap_audit["source_token_status"], "action_name_tokens_only")
        self.assertEqual(gap_audit["numeric_opcode_field_candidates_found"], [])
        self.assertIn("primary", gap_audit["observed_action_fields"])
        self.assertIn("name", gap_audit["observed_chain_item_fields"])
        self.assertIn("args", gap_audit["observed_chain_item_fields"])
        self.assertEqual(gap_audit["importer_parser_evidence"]["parser"], "tools/hsl_payload_inspector.py::parse_action_chain")
        guard_summary = semantics["opcode_gap_guard_summary"]
        self.assertEqual(guard_summary["source_numeric_opcode_status"], "missing_in_imported_ir")
        self.assertEqual(guard_summary["guard_status"], "active")
        self.assertEqual(guard_summary["guarded_condition_action_count"], len(predicate_catalog["by_action"]))
        self.assertEqual(guard_summary["guarded_action_effect_count"], len(effect_catalog["by_action"]))
        self.assertEqual(guard_summary["guarded_status_section_count"], 4)
        self.assertEqual(
            guard_summary["guarded_status_lifecycle_hint_count"],
            len(lifecycle["static_navigation_hints"]["by_action"]),
        )
        self.assertEqual(guard_summary["guarded_dry_run_trace_example_count"], 2)
        self.assertEqual(
            guard_summary["active_guards"],
            [
                "condition_static_navigation_hints_remain_unresolved",
                "action_effects_remain_facade_only",
                "status_lifecycle_remains_scheduled_only",
                "dry_run_trace_remains_candidate_only",
            ],
        )
        self.assertNotIn("script_phase", json.dumps(guard_summary))

    def test_checker_rejects_missing_condition_dispatch(self):
        with tempfile.TemporaryDirectory() as tmp:
            index_path = write_fixture(Path(tmp))
            semantics = hsl_script_vm_semantics.build_semantics(index_path)
            semantics["condition_summary"] = {}
            path = Path(tmp) / "semantics.json"
            path.write_text(json.dumps(semantics), encoding="utf-8")

            errors = hsl_script_vm_semantics.check_semantics(path)

        self.assertTrue(any("condition_summary" in error for error in errors), errors)

    def test_checker_rejects_confirmed_condition_predicate_catalog(self):
        with tempfile.TemporaryDirectory() as tmp:
            index_path = write_fixture(Path(tmp))
            semantics = hsl_script_vm_semantics.build_semantics(index_path)
            semantics["condition_predicate_catalog"]["semantic_status"] = "confirmed"
            semantics["condition_predicate_catalog"]["by_action"]["actCheckEnemyNumber"]["predicate_status"] = "confirmed"
            path = Path(tmp) / "semantics.json"
            path.write_text(json.dumps(semantics), encoding="utf-8")

            errors = hsl_script_vm_semantics.check_semantics(path)

        self.assertTrue(any("condition_predicate_catalog.semantic_status" in error for error in errors), errors)
        self.assertTrue(any("predicate_status" in error for error in errors), errors)

    def test_condition_static_navigation_hints_remain_unresolved(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            index_path = write_fixture(root)
            static_path = write_static_candidate_fixture(root)

            semantics = hsl_script_vm_semantics.build_semantics(index_path, static_path)

        hint = semantics["condition_predicate_catalog"]["by_action"]["actCheckEnemyNumber"]["static_navigation_hint"]
        self.assertEqual(hint["candidate_slot_if_order_matched"], 14)
        self.assertEqual(hint["candidate_handler_if_order_matched"], "0x451aa3")
        self.assertEqual(hint["correlation_status"], "unresolved")
        self.assertEqual(hint["ordinal_as_slot_status"], "not_evidence")
        self.assertEqual(hint["slot_opcode_evidence_status"], "unresolved")
        self.assertEqual(hint["comparison_polarity_evidence_status"], "unresolved")
        self.assertEqual(
            semantics["condition_predicate_catalog"]["by_action"]["actCheckEnemyNumber"]["source_numeric_opcode_status"],
            "missing_in_imported_ir",
        )

    def test_status_lifecycle_static_navigation_hints_remain_unresolved(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            index_path = write_fixture(root)
            static_path = write_static_candidate_fixture(root)

            semantics = hsl_script_vm_semantics.build_semantics(index_path, static_path)

        hint = semantics["status_mutation_lifecycle_model"]["static_navigation_hints"]["by_action"]["actInsertWinStatus"]
        self.assertEqual(hint["candidate_slot_if_order_matched"], 24)
        self.assertEqual(hint["candidate_handler_if_order_matched"], "0x4510cd")
        self.assertEqual(hint["correlation_status"], "unresolved")
        self.assertEqual(hint["ordinal_as_slot_status"], "not_evidence")
        self.assertEqual(hint["slot_opcode_evidence_status"], "unresolved")
        self.assertEqual(hint["commit_timing_evidence_status"], "unresolved")
        self.assertEqual(hint["lifecycle_semantic_status"], "scheduled_only")
        self.assertEqual(hint["bridge_commit_timing_status"], "unresolved")

    def test_interpreter_progress_boundary_loads_cursor_progress_without_status_commit(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            index_path = write_fixture(root)
            static_path = write_static_candidate_fixture(root)

            semantics = hsl_script_vm_semantics.build_semantics(index_path, static_path)

        boundary = semantics["interpreter_progress_boundary"]
        self.assertEqual(boundary["source_bridge_address"], "0x450840")
        self.assertEqual(boundary["evidence_status"], "static_cursor_progress_loaded")
        self.assertEqual(boundary["progress_boundary_status"], "script_cursor_progress_observed")
        self.assertEqual(boundary["script_cursor_field_offset"], "0x90")
        self.assertEqual(boundary["script_cursor_write_count"], 84)
        self.assertEqual(boundary["token_advance_count"], 125)
        self.assertEqual(boundary["return_count"], 118)
        self.assertEqual(boundary["registry_write_status"], "unresolved")
        self.assertEqual(boundary["deferred_queue_candidate_status"], "unresolved")
        self.assertEqual(boundary["status_mutation_commit_timing_status"], "unresolved")
        self.assertEqual(boundary["status_mutation_commit_status"], "unresolved")
        candidate = boundary["status_handler_boundary_candidates"][0]
        self.assertEqual(candidate["action_name"], "actInsertWinStatus")
        self.assertEqual(candidate["candidate_handler_if_order_matched"], "0x4510cd")
        self.assertEqual(candidate["correlation_status"], "unresolved")
        self.assertEqual(candidate["ordinal_as_slot_status"], "not_evidence")
        self.assertEqual(candidate["commit_timing_evidence_status"], "unresolved")

    def test_checker_rejects_confirmed_status_lifecycle(self):
        with tempfile.TemporaryDirectory() as tmp:
            index_path = write_fixture(Path(tmp))
            semantics = hsl_script_vm_semantics.build_semantics(index_path)
            semantics["status_mutation_lifecycle_model"]["semantic_status"] = "confirmed"
            path = Path(tmp) / "semantics.json"
            path.write_text(json.dumps(semantics), encoding="utf-8")

            errors = hsl_script_vm_semantics.check_semantics(path)

        self.assertTrue(any("status_mutation_lifecycle_model.semantic_status" in error for error in errors), errors)

    def test_checker_rejects_executable_action_effect_facade(self):
        with tempfile.TemporaryDirectory() as tmp:
            index_path = write_fixture(Path(tmp))
            semantics = hsl_script_vm_semantics.build_semantics(index_path)
            semantics["action_effect_facade_catalog"]["semantic_status"] = "handler_confirmed"
            semantics["action_effect_facade_catalog"]["execution_policy"] = "execute_handlers"
            semantics["action_effect_facade_catalog"]["by_action"]["actMessage"]["facade_mode"] = "execute_handler"
            path = Path(tmp) / "semantics.json"
            path.write_text(json.dumps(semantics), encoding="utf-8")

            errors = hsl_script_vm_semantics.check_semantics(path)

        self.assertTrue(any("action_effect_facade_catalog.semantic_status" in error for error in errors), errors)
        self.assertTrue(any("execution_policy" in error for error in errors), errors)
        self.assertTrue(any("facade_mode" in error for error in errors), errors)

    def test_checker_rejects_progress_boundary_as_status_commit_proof(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            index_path = write_fixture(root)
            static_path = write_static_candidate_fixture(root)
            semantics = hsl_script_vm_semantics.build_semantics(index_path, static_path)
            boundary = semantics["interpreter_progress_boundary"]
            boundary["registry_write_status"] = "resolved"
            boundary["deferred_queue_candidate_status"] = "resolved"
            boundary["status_mutation_commit_timing_status"] = "resolved"
            boundary["status_mutation_commit_status"] = "committed"
            candidate = boundary["status_handler_boundary_candidates"][0]
            candidate["commit_timing_evidence_status"] = "resolved"
            candidate["navigation_policy"] = "commit_evidence"
            path = root / "semantics.json"
            path.write_text(json.dumps(semantics), encoding="utf-8")

            errors = hsl_script_vm_semantics.check_semantics(path)

        self.assertTrue(any("registry_write_status" in error for error in errors), errors)
        self.assertTrue(any("deferred_queue_candidate_status" in error for error in errors), errors)
        self.assertTrue(any("status_mutation_commit_timing_status" in error for error in errors), errors)
        self.assertTrue(any("status_mutation_commit_status" in error for error in errors), errors)
        self.assertTrue(any("commit_timing_evidence_status" in error for error in errors), errors)
        self.assertTrue(any("navigation_policy" in error for error in errors), errors)

    def test_checker_rejects_invalid_interpreter_facade_contract(self):
        with tempfile.TemporaryDirectory() as tmp:
            index_path = write_fixture(Path(tmp))
            semantics = hsl_script_vm_semantics.build_semantics(index_path)
            semantics["interpreter_facade_contract"]["allows_handler_execution"] = True
            semantics["interpreter_facade_contract"]["allows_evidence_tier_upgrade"] = True
            semantics["interpreter_facade_contract"]["guard_summary"]["no_handler_execution"] = False
            semantics["interpreter_facade_contract"]["guard_summary"]["static_navigation_hints_are_opcode_evidence"] = True
            semantics["interpreter_facade_contract"]["cross_field_invariants"]["condition_predicates"]["semantic_status"] = "confirmed"
            path = Path(tmp) / "semantics.json"
            path.write_text(json.dumps(semantics), encoding="utf-8")

            errors = hsl_script_vm_semantics.check_semantics(path)

        self.assertTrue(any("interpreter_facade_contract.allows_handler_execution" in error for error in errors), errors)
        self.assertTrue(any("allows_evidence_tier_upgrade" in error for error in errors), errors)
        self.assertTrue(any("guard_summary.no_handler_execution" in error for error in errors), errors)
        self.assertTrue(any("static_navigation_hints_are_opcode_evidence" in error for error in errors), errors)
        self.assertTrue(any("condition_predicates.semantic_status" in error for error in errors), errors)

    def test_checker_rejects_executable_script_event_log(self):
        with tempfile.TemporaryDirectory() as tmp:
            index_path = write_fixture(Path(tmp))
            semantics = hsl_script_vm_semantics.build_semantics(index_path)
            event_log = semantics["script_event_log_model"]
            event_log["execution_policy"] = "live_battle_mutation"
            event_log["event_log_entries"][0]["execution_status"] = "handler_confirmed"
            event_log["event_log_entries"][0]["unresolved_semantics"] = ["original_equivalent"]
            resource_entry = [
                item
                for item in event_log["event_log_entries"]
                if item["entry_type"] == "resource_action" and item["handler_name"] == "actShowSectionName"
            ][0]
            resource_entry["execution_status"] = "rendered"
            resource_entry["visible_fields"]["resource_text_status"] = "decoded"
            path = Path(tmp) / "semantics.json"
            path.write_text(json.dumps(semantics), encoding="utf-8")

            errors = hsl_script_vm_semantics.check_semantics(path)

        self.assertTrue(any("script_event_log_model.execution_policy" in error for error in errors), errors)
        self.assertTrue(any("event_log_only" in error for error in errors), errors)
        self.assertTrue(any("handler_confirmed" in error for error in errors), errors)
        self.assertTrue(any("original_equivalent" in error for error in errors), errors)
        self.assertTrue(any("resource_event_log_only" in error for error in errors), errors)
        self.assertTrue(any("resource_text_status" in error for error in errors), errors)

    def test_checker_rejects_invalid_script_event_log_phase_view(self):
        with tempfile.TemporaryDirectory() as tmp:
            index_path = write_fixture(Path(tmp))
            semantics = hsl_script_vm_semantics.build_semantics(index_path)
            views = semantics["script_event_log_model"]["phase_views"]["views"]
            views["story"]["entry_indexes"] = [999]
            views["story"]["entry_count"] = 1
            views["event"]["dispatch_indexes"] = [0]
            views["event"]["dispatch_count"] = 1
            path = Path(tmp) / "semantics.json"
            path.write_text(json.dumps(semantics), encoding="utf-8")

            errors = hsl_script_vm_semantics.check_semantics(path)

        self.assertTrue(any("out-of-range index" in error for error in errors), errors)
        self.assertTrue(any("references wrong phase" in error for error in errors), errors)

    def test_checker_rejects_executable_godot_panel_phase_summary(self):
        with tempfile.TemporaryDirectory() as tmp:
            index_path = write_fixture(Path(tmp))
            semantics = hsl_script_vm_semantics.build_semantics(index_path)
            summary = semantics["script_event_log_model"]["godot_panel_phase_summaries"]
            summary["summary_policy"] = "execute_handlers"
            story = summary["phases"]["story"]
            story["panel_policy"] = "execute"
            message_preview = [item for item in story["display_label_preview"] if item.get("message_text_status")][0]
            message_preview["message_text_status"] = "resolved_without_source"
            story["scheduled_status_preview"][0]["execution_status"] = "applied"
            path = Path(tmp) / "semantics.json"
            path.write_text(json.dumps(semantics), encoding="utf-8")

            errors = hsl_script_vm_semantics.check_semantics(path)

        self.assertTrue(any("summary_policy" in error for error in errors), errors)
        self.assertTrue(any("panel_policy" in error for error in errors), errors)
        self.assertTrue(any("message_text_status" in error for error in errors), errors)
        self.assertTrue(any("scheduled_event_log_only" in error for error in errors), errors)

    def test_checker_rejects_executable_godot_panel_read_play_trace(self):
        with tempfile.TemporaryDirectory() as tmp:
            index_path = write_fixture(Path(tmp))
            semantics = hsl_script_vm_semantics.build_semantics(index_path)
            trace = semantics["script_event_log_model"]["godot_panel_read_play_trace"]
            trace["trace_policy"] = "execute_handlers"
            trace["step_count"] = 999
            trace["steps"][0]["execution_status"] = "executed"
            message_step = [item for item in trace["steps"] if item["step_type"] == "display_label"][0]
            message_step["message_text_status"] = "resolved"
            scheduled_step = [item for item in trace["steps"] if item["step_type"] == "scheduled_status"][0]
            scheduled_step["mutation_status"] = "applied"
            path = Path(tmp) / "semantics.json"
            path.write_text(json.dumps(semantics), encoding="utf-8")

            errors = hsl_script_vm_semantics.check_semantics(path)

        self.assertTrue(any("trace_policy" in error for error in errors), errors)
        self.assertTrue(any("step_count" in error for error in errors), errors)
        self.assertTrue(any("read_only_panel_trace" in error for error in errors), errors)
        self.assertTrue(any("message_text_status" in error for error in errors), errors)
        self.assertTrue(any("scheduled_event_log_only" in error for error in errors), errors)

    def test_checker_rejects_executable_godot_timeline_anchors(self):
        with tempfile.TemporaryDirectory() as tmp:
            index_path = write_fixture(Path(tmp))
            semantics = hsl_script_vm_semantics.build_semantics(index_path)
            anchors = semantics["script_event_log_model"]["godot_timeline_anchors"]
            anchors["anchor_policy"] = "execute_timeline"
            progress_anchor = anchors["progress_boundary_anchor"]
            progress_anchor["anchor_status"] = "commit_evidence"
            progress_anchor["registry_write_status"] = "resolved"
            progress_anchor["deferred_queue_candidate_status"] = "resolved"
            progress_anchor["status_mutation_commit_timing_status"] = "resolved"
            progress_anchor["status_mutation_commit_status"] = "committed"
            story = anchors["phases"]["story"]
            story["anchor_policy"] = "execute_phase"
            message_anchor = [
                item
                for item in story["display_label_anchors"]
                if not item.get("resource_action_type")
            ][0]
            message_anchor["message_text_status"] = "resolved"
            story["scheduled_status_anchors"][0]["mutation_status"] = "applied"
            event = anchors["phases"]["event"]
            event["dispatch_anchors"][0]["diagnostic_status"] = "handler_confirmed"
            path = Path(tmp) / "semantics.json"
            path.write_text(json.dumps(semantics), encoding="utf-8")

            errors = hsl_script_vm_semantics.check_semantics(path)

        self.assertTrue(any("godot_timeline_anchors.anchor_policy" in error for error in errors), errors)
        self.assertTrue(any("progress_boundary_anchor.anchor_status" in error for error in errors), errors)
        self.assertTrue(any("registry_write_status" in error for error in errors), errors)
        self.assertTrue(any("status_mutation_commit_status" in error for error in errors), errors)
        self.assertTrue(any("phases.story.anchor_policy" in error for error in errors), errors)
        self.assertTrue(any("message_text_status" in error for error in errors), errors)
        self.assertTrue(any("mutation_status" in error for error in errors), errors)
        self.assertTrue(any("dispatch_anchors diagnostic_status" in error for error in errors), errors)

    def test_event_log_loads_message_text_evidence_bridge_without_resolving_text(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_message_text_evidence_fixture(root)
            index_path = write_fixture(root)
            semantics = hsl_script_vm_semantics.build_semantics(index_path)

        bridge = semantics["script_event_log_model"]["message_text_resolution"]["evidence_bridge"]
        self.assertEqual(bridge["status"], "loaded")
        self.assertEqual(bridge["message_text_status"], "not_resolved_in_imported_assets")
        self.assertEqual(bridge["message_text_source_status"], "missing_structured_text_table")
        self.assertEqual(bridge["word_shape_resource_refs"], ["SHAPE01\\WORD051.SHP"])
        self.assertIn("no structured message text table", bridge["negative_evidence"][0])

    def test_checker_rejects_resolved_message_text_evidence_bridge(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_message_text_evidence_fixture(root)
            index_path = write_fixture(root)
            semantics = hsl_script_vm_semantics.build_semantics(index_path)
            bridge = semantics["script_event_log_model"]["message_text_resolution"]["evidence_bridge"]
            bridge["message_text_status"] = "resolved"
            bridge["message_text_source_status"] = "decoded_text_table"
            bridge["negative_evidence"] = []
            path = root / "semantics.json"
            path.write_text(json.dumps(semantics), encoding="utf-8")

            errors = hsl_script_vm_semantics.check_semantics(path)

        self.assertTrue(any("message_text_status" in error for error in errors), errors)
        self.assertTrue(any("message_text_source_status" in error for error in errors), errors)
        self.assertTrue(any("negative_evidence" in error for error in errors), errors)

    def test_checker_rejects_claimed_imported_opcode_without_fields(self):
        with tempfile.TemporaryDirectory() as tmp:
            index_path = write_fixture(Path(tmp))
            semantics = hsl_script_vm_semantics.build_semantics(index_path)
            semantics["imported_opcode_token_gap_audit"]["source_numeric_opcode_status"] = "present"
            path = Path(tmp) / "semantics.json"
            path.write_text(json.dumps(semantics), encoding="utf-8")

            errors = hsl_script_vm_semantics.check_semantics(path)

        self.assertTrue(any("imported_opcode_token_gap_audit.source_numeric_opcode_status" in error for error in errors), errors)

    def test_checker_rejects_inconsistent_opcode_gap_guard_summary(self):
        with tempfile.TemporaryDirectory() as tmp:
            index_path = write_fixture(Path(tmp))
            semantics = hsl_script_vm_semantics.build_semantics(index_path)
            semantics["opcode_gap_guard_summary"]["guard_status"] = "inactive"
            semantics["opcode_gap_guard_summary"]["guarded_action_effect_count"] = 999
            path = Path(tmp) / "semantics.json"
            path.write_text(json.dumps(semantics), encoding="utf-8")

            errors = hsl_script_vm_semantics.check_semantics(path)

        self.assertTrue(any("opcode_gap_guard_summary.guard_status" in error for error in errors), errors)
        self.assertTrue(any("guarded_action_effect_count" in error for error in errors), errors)

    def test_checker_cross_links_missing_opcode_to_unresolved_static_hints(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            index_path = write_fixture(root)
            static_path = write_static_candidate_fixture(root)
            semantics = hsl_script_vm_semantics.build_semantics(index_path, static_path)
            hint = semantics["condition_predicate_catalog"]["by_action"]["actCheckEnemyNumber"]["static_navigation_hint"]
            hint["correlation_status"] = "resolved"
            hint["ordinal_as_slot_status"] = "evidence"
            hint["slot_opcode_evidence_status"] = "resolved"
            path = root / "semantics.json"
            path.write_text(json.dumps(semantics), encoding="utf-8")

            errors = hsl_script_vm_semantics.check_semantics(path)

        self.assertTrue(any("missing imported opcode" in error for error in errors), errors)

    def test_checker_cross_links_missing_opcode_to_facade_only_action_effects(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            index_path = write_fixture(root)
            semantics = hsl_script_vm_semantics.build_semantics(index_path)
            effect = semantics["action_effect_facade_catalog"]["by_action"]["actMessage"]
            effect["facade_mode"] = "mapped_handler"
            effect["effect_status"] = "handler_confirmed"
            effect["handler_mapping_status"] = "resolved"
            path = root / "semantics.json"
            path.write_text(json.dumps(semantics), encoding="utf-8")

            errors = hsl_script_vm_semantics.check_semantics(path)

        self.assertTrue(any("missing imported opcode" in error for error in errors), errors)

    def test_checker_cross_links_missing_opcode_to_scheduled_only_lifecycle(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            index_path = write_fixture(root)
            semantics = hsl_script_vm_semantics.build_semantics(index_path)
            lifecycle = semantics["status_mutation_lifecycle_model"]
            lifecycle["semantic_status"] = "confirmed"
            lifecycle["dry_run_state_transition_policy"] = "applies_live_mutation"
            lifecycle["section_lifecycle"]["event"][0]["scheduled_mutations"][0]["application_status"] = "applied"
            path = root / "semantics.json"
            path.write_text(json.dumps(semantics), encoding="utf-8")

            errors = hsl_script_vm_semantics.check_semantics(path)

        self.assertTrue(any("missing imported opcode" in error for error in errors), errors)

    def test_checker_cross_links_missing_opcode_to_navigation_only_status_hints(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            index_path = write_fixture(root)
            static_path = write_static_candidate_fixture(root)
            semantics = hsl_script_vm_semantics.build_semantics(index_path, static_path)
            hint = semantics["status_mutation_lifecycle_model"]["static_navigation_hints"]["by_action"]["actInsertWinStatus"]
            hint["correlation_status"] = "resolved"
            hint["ordinal_as_slot_status"] = "evidence"
            hint["slot_opcode_evidence_status"] = "resolved"
            hint["commit_timing_evidence_status"] = "resolved"
            hint["lifecycle_semantic_status"] = "committed"
            hint["bridge_commit_timing_status"] = "resolved"
            path = root / "semantics.json"
            path.write_text(json.dumps(semantics), encoding="utf-8")

            errors = hsl_script_vm_semantics.check_semantics(path)

        self.assertTrue(any("missing imported opcode" in error for error in errors), errors)

    def test_checker_cross_links_missing_opcode_to_candidate_only_dry_run_trace(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            index_path = write_fixture(root)
            semantics = hsl_script_vm_semantics.build_semantics(index_path)
            trace_section = semantics["interpreter_dry_run_trace_model"]["trace_examples"][
                "round_6_objective_switch_candidate"
            ]["dispatch"]["event"][1]
            trace_section["candidate_result"] = "confirmed_true"
            trace_section["scheduled_mutations"] = [
                {
                    "name": "actInsertWinStatus",
                    "application_status": "applied",
                }
            ]
            path = root / "semantics.json"
            path.write_text(json.dumps(semantics), encoding="utf-8")

            errors = hsl_script_vm_semantics.check_semantics(path)

        self.assertTrue(any("missing imported opcode" in error for error in errors), errors)

    def test_dry_run_trace_marks_unknown_when_context_lacks_values(self):
        with tempfile.TemporaryDirectory() as tmp:
            index_path = write_fixture(Path(tmp))
            semantics = hsl_script_vm_semantics.build_semantics(index_path)

        trace = hsl_script_vm_semantics.build_dry_run_trace(
            semantics["section_dispatch"],
            {
                "enabled_status": {"win": ["0"], "fail": ["0"], "event": ["0", "1"]},
                "enemy_counts": {},
            },
        )

        event_zero = [
            item
            for item in trace["dispatch"]["event"]
            if item["status_id"] == "0"
        ][0]
        self.assertEqual(event_zero["condition_results"][0]["result"], "unknown")
        self.assertEqual(event_zero["candidate_result"], "unknown")
        self.assertEqual(event_zero["scheduled_mutations"], [])


if __name__ == "__main__":
    unittest.main()
