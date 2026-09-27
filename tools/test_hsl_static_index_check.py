import json
import tempfile
import unittest
from pathlib import Path

import hsltools.checks.static_index as static_index


def valid_index() -> dict:
    return {
        "schema": "hsl_static_compact_index.v1",
        "source_policy": "tracked compact static metadata only",
        "evidence_tier": "static_export_candidate",
        "tool_presence": {"r2": True, "rabin2": True, "radare2": False},
        "export_status_counts": {"dry-run": 6},
        "export_count_summary": {"tool_exports": 6, "known_windows": 1},
        "known_windows": [
            {
                "label": "input_aggregator_candidate",
                "address": "0x415910",
                "byte_count": 544,
                "status": "dry-run",
            }
        ],
        "dispatch_table_summaries": [
            {
                "id": "script_primary_dispatch_table",
                "address": "0x453708",
                "evidence_tier": "static_table_observed",
                "status": "ok",
                "entry_count_declared": 2,
                "entry_count_observed": 2,
                "probable_handler_slot_count": 2,
                "unique_handler_count": 2,
                "handler_slots": [
                    {"slot": 0, "handler_address": "0x45087b"},
                    {"slot": 1, "handler_address": "0x4508ff"},
                ],
                "repeated_handlers": [],
                "evidence_sources": ["input_aggregator_candidate"],
                "why_next": "Resolve primary dispatch.",
            },
            {
                "id": "script_action_dispatch_table",
                "address": "0x4537f4",
                "evidence_tier": "static_table_observed",
                "status": "ok",
                "entry_count_declared": 2,
                "entry_count_observed": 2,
                "probable_handler_slot_count": 2,
                "unique_handler_count": 1,
                "handler_slots": [
                    {"slot": 0, "handler_address": "0x4511e9"},
                    {"slot": 1, "handler_address": "0x4511e9"},
                ],
                "repeated_handlers": [{"handler_address": "0x4511e9", "slot_count": 2}],
                "evidence_sources": ["input_aggregator_candidate"],
                "why_next": "Resolve action dispatch.",
            },
        ],
        "body_window_summaries": [
            {
                "id": "script_interpreter_bridge_function",
                "address": "0x450840",
                "evidence_tier": "static_body_observed",
                "status": "ok",
                "mode": "pdfj",
                "observed_size": 128,
                "op_count": 4,
                "op_type_counts": {"call": 1, "mov": 2, "jmp": 1},
                "call_target_addresses": ["0x44fcf0"],
                "jump_target_addresses": ["0x451240"],
                "data_ref_addresses": ["0x4c1d38"],
                "code_ref_addresses": [],
                "evidence_sources": ["input_aggregator_candidate"],
                "why_next": "Fingerprint handlers.",
            },
            {
                "id": "logical_ui_hit_test_window",
                "address": "0x445977",
                "evidence_tier": "static_body_observed",
                "status": "ok",
                "mode": "pdj",
                "observed_size": None,
                "op_count": 2,
                "op_type_counts": {"call": 1, "mov": 1},
                "call_target_addresses": ["0x445d70"],
                "jump_target_addresses": [],
                "data_ref_addresses": ["0x4c1a8c"],
                "code_ref_addresses": [],
                "evidence_sources": ["input_aggregator_candidate"],
                "why_next": "Summarize UI refs.",
            },
        ],
        "action_handler_fingerprints": [
            {
                "handler_address": "0x4511e9",
                "slot_numbers": [0, 1],
                "evidence_tier": "static_handler_fingerprint",
                "bounded_byte_window": 32,
                "op_count": 3,
                "op_type_counts": {"call": 1, "mov": 1, "jmp": 1},
                "call_target_addresses": ["0x44fcf0"],
                "jump_target_addresses": ["0x451240"],
                "data_ref_addresses": ["0x4c1d38"],
                "code_ref_addresses": [],
                "why_next": "Correlate action names.",
            }
        ],
        "script_action_correlation_skeleton": {
            "schema": "hsl_static_script_action_correlation_skeleton.v1",
            "source_file": "content/imported/hsl/chapter01/script_vm_semantics.json",
            "source_evidence_tier": "resource-derived",
            "source_total_action_chain_count": 2,
            "ordered_action_name_count": 2,
            "static_script_action_dispatch_table": "0x4537f4",
            "static_script_primary_dispatch_table": "0x453708",
            "static_script_interpreter_bridge": "0x450840",
            "script_action_dispatch_slot_count": 2,
            "script_action_dispatch_unique_handler_count": 1,
            "condition_summary": {"actCheckRoundNumber": 1},
            "mutation_summary": {"actInsertEventStatus": 1},
            "actions": [
                {
                    "resource_order_index": 0,
                    "action_name": "actMessage",
                    "correlation_status": "unresolved",
                    "ordinal_as_slot_status": "not_evidence",
                    "candidate_slot_if_order_matched": 0,
                    "candidate_handler_if_order_matched": "0x4511e9",
                    "why_unresolved": "Resource order is not proven slot order.",
                },
                {
                    "resource_order_index": 1,
                    "action_name": "actInsertEventStatus",
                    "correlation_status": "unresolved",
                    "ordinal_as_slot_status": "not_evidence",
                    "candidate_slot_if_order_matched": 1,
                    "candidate_handler_if_order_matched": "0x4511e9",
                    "why_unresolved": "Resource order is not proven slot order.",
                },
            ],
            "downstream_consumers": [
                {
                    "consumer": "godot-integration",
                    "current_status": "read_only_action_metadata_no_handlers",
                    "mapping_exit_criteria": "Requires stable handler evidence.",
                }
            ],
            "negative_evidence": ["No opcode-to-action-name mapping is proven by resource order alone."],
        },
        "resource_object_static_question_context": {
            "schema": "hsl_static_resource_object_question_context.v1",
            "evidence_tier": "static_question_context",
            "interpretation_status": "unresolved",
            "questions": [
                {
                    "id": "obj_shape_number_semantics",
                    "question": "What is obj_shape_number?",
                    "static_anchors": ["0x450840"],
                    "current_evidence": "Not proven.",
                    "next_static_need": "Find shape handlers.",
                },
                {
                    "id": "object_owner_traversal_semantics",
                    "question": "What object kind is traversed?",
                    "static_anchors": ["0x445977"],
                    "current_evidence": "Not proven.",
                    "next_static_need": "Expand callers.",
                },
                {
                    "id": "actor_sprite_template_or_global_definition",
                    "question": "Are actor sprites templates?",
                    "static_anchors": ["0x4537f4"],
                    "current_evidence": "Not proven.",
                    "next_static_need": "Correlate object handlers.",
                },
            ],
            "negative_evidence": ["No current static summary proves resource semantics."],
        },
        "battle_state_target_count": 5,
        "battle_state_targets": [
            {
                "id": "input_current_edge_bits",
                "category": "input_globals",
                "address": "0x4c6390",
                "label": "input current and edge bitfield candidate",
                "evidence_tier": "static_window_observed_runtime_scalar_smoke",
                "evidence_sources": ["input_aggregator_candidate"],
                "static_observation": "Input aggregator writes this candidate.",
                "why_next": "Correlate confirm/cancel/menu phases.",
                "runtime_probe": "sample u32 across controlled input phases",
            },
            {
                "id": "menu_start_state",
                "category": "menu_state",
                "address": "0x4c1ac8",
                "label": "menu/start state latch candidate",
                "evidence_tier": "static_window_observed",
                "evidence_sources": ["input_aggregator_candidate"],
                "static_observation": "Menu state window initializes this candidate.",
                "why_next": "Separate title/start menu state.",
                "runtime_probe": "sample across title and transition phases",
            },
            {
                "id": "script_action_dispatch_table",
                "category": "script_interpreter_tables",
                "address": "0x4537f4",
                "label": "script action sub-dispatch table candidate",
                "evidence_tier": "static_window_observed",
                "evidence_sources": ["input_aggregator_candidate"],
                "static_observation": "Script bridge jumps through this candidate.",
                "why_next": "Map imported script actions to handlers.",
                "runtime_probe": "expand static table entries first",
            },
            {
                "id": "script_current_object_anchor",
                "category": "object_unit_anchors",
                "address": "0x4c1d38",
                "label": "current script object or actor anchor candidate",
                "evidence_tier": "static_window_observed",
                "evidence_sources": ["input_aggregator_candidate"],
                "static_observation": "Script bridge copies this global into action fields.",
                "why_next": "Find actor/object connection.",
                "runtime_probe": "sample around scripted setup phases",
            },
            {
                "id": "cursor_x",
                "category": "cursor_camera_globals",
                "address": "0x4c1a8c",
                "label": "logical cursor x candidate",
                "evidence_tier": "static_window_observed",
                "evidence_sources": ["input_aggregator_candidate"],
                "static_observation": "UI hit-test compares this global to bounds.",
                "why_next": "Recover logical coordinate mapping.",
                "runtime_probe": "sample at known client coordinates",
            },
        ],
        "unresolved_negative_evidence": ["runtime globals require dynamic probe confirmation"],
        "semantic_boundary": "static window registration only",
    }


class StaticIndexCheckTests(unittest.TestCase):
    def write_index(self, index: dict) -> Path:
        self.tmp = tempfile.TemporaryDirectory()
        path = Path(self.tmp.name) / "index.json"
        path.write_text(json.dumps(index), encoding="utf-8")
        return path

    def tearDown(self):
        tmp = getattr(self, "tmp", None)
        if tmp is not None:
            tmp.cleanup()

    def test_valid_index_passes(self):
        errors = static_index.check_static_index(self.write_index(valid_index()))

        self.assertEqual(errors, [])

    def test_forbidden_private_path_fails(self):
        index = valid_index()
        index["known_windows"][0]["output"] = "ignored/static/window.asm"

        errors = static_index.check_static_index(self.write_index(index))

        self.assertTrue(any("forbidden" in error for error in errors), errors)

    def test_missing_windows_fails(self):
        index = valid_index()
        index["known_windows"] = []

        errors = static_index.check_static_index(self.write_index(index))

        self.assertTrue(any("known_windows" in error for error in errors), errors)

    def test_missing_target_category_fails(self):
        index = valid_index()
        index["battle_state_targets"] = index["battle_state_targets"][:1]
        index["battle_state_target_count"] = 1

        errors = static_index.check_static_index(self.write_index(index))

        self.assertTrue(any("missing categories" in error for error in errors), errors)

    def test_unknown_target_evidence_source_fails(self):
        index = valid_index()
        index["battle_state_targets"][0]["evidence_sources"] = ["missing_window"]

        errors = static_index.check_static_index(self.write_index(index))

        self.assertTrue(any("unknown window label" in error for error in errors), errors)

    def test_dispatch_table_count_mismatch_fails(self):
        index = valid_index()
        index["dispatch_table_summaries"][0]["probable_handler_slot_count"] = 3

        errors = static_index.check_static_index(self.write_index(index))

        self.assertTrue(any("probable_handler_slot_count" in error for error in errors), errors)

    def test_body_summary_raw_field_fails(self):
        index = valid_index()
        index["body_window_summaries"][0]["opcode"] = "call fcn.0044fcf0"

        errors = static_index.check_static_index(self.write_index(index))

        self.assertTrue(any("decoded instruction" in error for error in errors), errors)

    def test_handler_fingerprint_invalid_address_fails(self):
        index = valid_index()
        index["action_handler_fingerprints"][0]["call_target_addresses"] = ["4511e9"]

        errors = static_index.check_static_index(self.write_index(index))

        self.assertTrue(any("call_target_addresses" in error for error in errors), errors)

    def test_script_action_correlation_confirmed_mapping_fails(self):
        index = valid_index()
        index["script_action_correlation_skeleton"]["actions"][0]["correlation_status"] = "confirmed"

        errors = static_index.check_static_index(self.write_index(index))

        self.assertTrue(any("correlation_status" in error for error in errors), errors)

    def test_resource_object_context_confirmed_semantics_fails(self):
        index = valid_index()
        index["resource_object_static_question_context"]["interpretation_status"] = "confirmed"

        errors = static_index.check_static_index(self.write_index(index))

        self.assertTrue(any("interpretation_status" in error for error in errors), errors)



if __name__ == "__main__":
    unittest.main()
