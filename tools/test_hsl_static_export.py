import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from tools import hsl_exe_static_export


class StaticExportTests(unittest.TestCase):
    def test_dry_run_manifest_uses_compact_outputs_and_known_windows(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            exe = root / "hsl01.exe"
            exe.write_bytes(b"fake exe")
            out_dir = root / "out"

            with mock.patch.object(hsl_exe_static_export, "tool_path") as tool_path:
                tool_path.side_effect = lambda name: f"/bin/{name}" if name in {"rabin2", "r2", "radare2"} else None

                manifest = hsl_exe_static_export.export_static_evidence(
                    exe,
                    out_dir,
                    timeout=1,
                    dry_run=True,
                )

            self.assertEqual(manifest["exe"]["size"], len(b"fake exe"))
            self.assertTrue(manifest["commands"])
            self.assertTrue(manifest["known_windows"])
            self.assertTrue((out_dir / "manifest.json").exists())
            saved = json.loads((out_dir / "manifest.json").read_text(encoding="utf-8"))
            self.assertIn("input_aggregator_candidate", [item["label"] for item in saved["known_windows"]])

    def test_tracked_static_index_omits_private_paths_hashes_and_raw_content(self):
        manifest = {
            "schema": "hsl_static_export.v1",
            "exe": {"path": "/private/hsl01.exe", "sha256": "abc", "size": 123},
            "tools": {"rabin2": "/opt/bin/rabin2", "r2": "/opt/bin/r2", "radare2": None},
            "commands": [
                {"command": ["rabin2", "-zzj", "/private/hsl01.exe"], "output": "ignored/static/strings.json", "status": "dry-run"},
                {"command": ["r2", "aaa"], "stderr": "ignored/static/functions.stderr", "status": "ok"},
            ],
            "known_windows": [
                {
                    "label": "input_aggregator_candidate",
                    "address": "0x415910",
                    "bytes": 544,
                    "status": "dry-run",
                    "output": "ignored/static/windows/input.asm",
                }
            ],
            "dispatch_tables": [
                {
                    "id": "script_primary_dispatch_table",
                    "address": "0x453708",
                    "status": "ok",
                    "entry_count": 3,
                    "entry_width": 4,
                    "entries": [0x45087b, 0x4508ff, 0x11223344],
                    "evidence_sources": ["script_interpreter_bridge_candidate"],
                    "why_next": "Resolve primary dispatch.",
                },
                {
                    "id": "script_action_dispatch_table",
                    "address": "0x4537f4",
                    "status": "ok",
                    "entry_count": 3,
                    "entry_width": 4,
                    "entries": [0x4511e9, 0x4511e9, 0x450a3c],
                    "evidence_sources": ["script_interpreter_bridge_candidate"],
                    "why_next": "Resolve action dispatch.",
                },
            ],
            "xref_targets": [
                {
                    "id": "script_interpreter_bridge_candidate",
                    "address": "0x450840",
                    "label": "script interpreter bridge function",
                    "status": "ok",
                    "xrefs": [
                        {"from": 0x44ec28, "type": "CALL", "opcode": "call fcn.00450840", "fcn_addr": 0x44ebf0, "fcn_name": "fcn.0044ebf0"}
                    ],
                    "evidence_sources": ["script_interpreter_bridge_candidate"],
                    "why_next": "Find script VM callers.",
                },
                {
                    "id": "logical_ui_hit_test_candidate",
                    "address": "0x445977",
                    "label": "logical UI/object hit-test branch target",
                    "status": "ok",
                    "xrefs": [
                        {"from": 0x445914, "type": "CODE", "opcode": "jl 0x445977", "name": "case.0x442aca.14+9814"}
                    ],
                    "evidence_sources": ["logical_ui_hit_test_candidate"],
                    "why_next": "Find owner traversal.",
                },
            ],
            "body_windows": [
                {
                    "id": "script_interpreter_bridge_function",
                    "address": "0x450840",
                    "mode": "pdfj",
                    "status": "ok",
                    "observed_size": 128,
                    "ops": [
                        {"addr": 0x45084d, "type": "mov", "opcode": "mov ax, word [ebp + 0x8e]"},
                        {"addr": 0x450860, "type": "cmp", "opcode": "cmp ecx, 0x8b"},
                        {"addr": 0x45086e, "type": "mov", "refs": [{"addr": 0x453768, "type": "DATA"}], "opcode": "mov dl, byte [ecx + 0x453768]"},
                        {"addr": 0x450874, "type": "ujmp", "opcode": "jmp dword [edx*4 + 0x453708]"},
                        {"addr": 0x450885, "type": "mov", "opcode": "mov edi, dword [esi]"},
                        {"addr": 0x450887, "type": "add", "opcode": "add esi, 4"},
                        {"addr": 0x45088a, "type": "cmp", "opcode": "cmp edi, 0x8b"},
                        {"addr": 0x4508a1, "type": "ujmp", "opcode": "jmp dword [edi*4 + 0x4537f4]"},
                        {"addr": 0x4511e9, "type": "mov", "refs": [{"addr": 0x4c1d38, "type": "DATA"}], "opcode": "mov eax, dword [0x4c1d38]"},
                        {"addr": 0x4511ef, "type": "call", "jump": 0x44fcf0, "opcode": "call fcn.0044fcf0"},
                        {"addr": 0x4511f4, "type": "jmp", "jump": 0x451240, "opcode": "jmp 0x451240"},
                        {"addr": 0x451256, "type": "call", "jump": 0x450450, "opcode": "call fcn.00450450"},
                        {"addr": 0x45120f, "type": "mov", "opcode": "mov dword [ebp + 0x90], esi"},
                        {"addr": 0x45123f, "type": "add", "opcode": "add esi, 4"},
                        {"addr": 0x45121c, "type": "ret", "opcode": "ret"},
                    ],
                    "evidence_sources": ["script_interpreter_bridge_candidate"],
                    "why_next": "Fingerprint handlers.",
                },
                {
                    "id": "logical_ui_hit_test_window",
                    "address": "0x445977",
                    "mode": "pdj",
                    "status": "ok",
                    "ops": [
                        {"addr": 0x445977, "type": "mov", "opcode": "mov eax, dword [esi + 0x80]"},
                        {"addr": 0x44597d, "type": "mov", "opcode": "mov edi, dword [esi + 0x60]"},
                        {"addr": 0x4459b8, "type": "acmp", "refs": [{"addr": 0x4c6398, "type": "DATA"}], "opcode": "test byte [0x4c6398], 3"},
                        {"addr": 0x4459ed, "type": "mov", "refs": [{"addr": 0x4c1a90, "type": "DATA"}], "opcode": "mov ebp, dword [0x4c1a90]"},
                        {"addr": 0x445a93, "type": "mov", "refs": [{"addr": 0x4c1a8c, "type": "DATA"}], "opcode": "mov ebp, dword [0x4c1a8c]"},
                        {"addr": 0x445980, "type": "call", "jump": 0x445d70},
                    ],
                    "evidence_sources": ["logical_ui_hit_test_candidate"],
                    "why_next": "Summarize UI refs.",
                },
            ],
            "condition_handler_windows": [
                {
                    "address": "0x4511e9",
                    "instruction_count": 80,
                    "status": "ok",
                    "slots_if_order_matched": [0],
                    "actions_if_order_matched": [
                        {
                            "action_name": "actMessage",
                            "condition_type": "round_number_check",
                            "candidate_context_binding": "round_number",
                            "occurrence_count": 1,
                        }
                    ],
                    "ops": [
                        {"addr": 0x4511e9, "type": "mov", "refs": [{"addr": 0x4c1d38, "type": "DATA"}]},
                        {"addr": 0x4511ef, "type": "call", "jump": 0x44fcf0},
                        {"addr": 0x4511f4, "type": "cmp"},
                        {"addr": 0x4511f6, "type": "cjmp", "jump": 0x451200, "fail": 0x4511f8},
                        {"addr": 0x4511f8, "type": "ret"},
                    ],
                }
            ],
            "status_handler_windows": [
                {
                    "address": "0x4511e9",
                    "instruction_count": 96,
                    "status": "ok",
                    "slots_if_order_matched": [1],
                    "actions_if_order_matched": [{"action_name": "actInsertEventStatus"}],
                    "ops": [
                        {"addr": 0x4511e9, "type": "mov", "refs": [{"addr": 0x4c1d38, "type": "DATA"}]},
                        {"addr": 0x4511ef, "type": "call", "jump": 0x44fcf0},
                        {"addr": 0x4511f4, "type": "cmp"},
                        {"addr": 0x4511f6, "type": "cjmp", "jump": 0x451200, "fail": 0x4511f8},
                        {"addr": 0x4511f8, "type": "ret"},
                    ],
                }
            ],
            "shp_render_windows": [
                {
                    "id": "shp_row_decode_full_candidate",
                    "address": "0x46e1a8",
                    "instruction_count": 140,
                    "status": "ok",
                    "why_next": "Summarize SHP row decode.",
                    "ops": [
                        {"addr": 0x46e1be, "type": "cmp", "opcode": "cmp eax, 0x53484c54"},
                        {"addr": 0x46e1c9, "type": "mov", "opcode": "mov eax, dword [esi + 8]"},
                        {"addr": 0x46e1cc, "type": "cmp", "opcode": "cmp eax, 2"},
                        {"addr": 0x46e1d5, "type": "mov", "opcode": "mov eax, dword [esi + 0x18]"},
                        {"addr": 0x46e1fb, "type": "add", "opcode": "add esi, 0x24"},
                        {"addr": 0x46e200, "type": "ret", "opcode": "ret"},
                    ],
                }
            ],
            "script_vm_semantics": {
                "evidence_tier": "resource-derived",
                "source_total_action_chain_count": 2,
                "condition_summary": {"actCheckRoundNumber": 1},
                "mutation_summary": {"actInsertEventStatus": 1},
                "status_mutation_lifecycle_model": {
                    "semantic_status": "unresolved",
                    "mutation_counts_by_action": {"actInsertEventStatus": 1},
                    "dry_run_state_transition_policy": "scheduled_only_no_live_mutation",
                },
                "dispatch_correlation_hints": {
                    "ordered_unique_action_names": ["actMessage", "actInsertEventStatus"],
                    "ordered_action_name_count": 2,
                    "correlation_status": "unresolved",
                },
                "action_semantics_catalog": {
                    "category_summary": {"message": 1, "status": 1},
                    "by_action": {
                        "actMessage": [{"category": "message"}],
                        "actInsertEventStatus": [{"category": "status"}],
                    },
                },
                "condition_predicate_catalog": {
                    "semantic_status": "unresolved",
                    "evidence_tier": "resource-derived",
                    "condition_action_count": 1,
                    "unique_condition_action_count": 1,
                    "by_action": {
                        "actMessage": {
                            "condition_type": "round_number_check",
                            "args_schema_candidate": ["round_number_candidate"],
                            "candidate_context_binding": "round_number",
                            "occurrence_count": 1,
                        }
                    },
                },
            },
            "resource_refs": {
                "summary": {
                    "object_shape_ref_count": 69,
                    "resolved_shape_payload_count": 60,
                    "unresolved_shape_ref_count": 9,
                    "shape_number_candidate_kind_counts": {
                        "numeric_literal": 74,
                        "symbolic_or_expression": 4,
                    },
                    "color_header_0x10_counts": {"0x07e0": 10},
                },
                "symbolic_shape_number_refs": [
                    {
                        "resource_id": "021-00001.SHP",
                        "resource_category": "actor_sprite",
                        "process": "defProcEnemy",
                        "role": "enemy",
                        "shape_number": "ENEMY021_Total",
                        "object_codes": ["99", "100"],
                        "match_status": "resolved_payload",
                    }
                ],
                "unresolved_shape_refs": [
                    {
                        "resource_id": "002-00001.SHP",
                        "resource_category": "actor_sprite",
                        "signals": ["not_found_in_current_imported_shp_payloads_by_basename"],
                        "context_signals": ["obj_process_code:defProcPlayerInstall"],
                        "searched_payload_roots": [
                            "legal-assets/derived/w12-first-chapter",
                            "legal-assets/derived/w13-first-chapter-context",
                            "legal-assets/derived/w16-ui-resource-import",
                        ],
                        "shape_number_candidates": ["1"],
                        "object_codes": ["7"],
                    }
                ],
            },
            "ui_resources": {
                "summary": {
                    "resource_count": 42,
                    "ui_group_counts": {
                        "battle_command_icon": 15,
                        "window_or_panel": 9,
                    },
                },
                "unresolved_semantics": [
                    "UI owner traversal, hit-test ownership, command identity, and action dispatch mapping remain unresolved"
                ],
            },
            "ui_owner_windows": [
                {
                    "id": "logical_ui_child_chain_copy_candidate",
                    "address": "0x445f60",
                    "instruction_count": 140,
                    "role": "hit_test_callee",
                    "status": "ok",
                    "why_next": "Summarize child-chain traversal.",
                    "ops": [
                        {"addr": 0x445f64, "type": "mov", "opcode": "mov eax, dword [eax + 0x90]"},
                        {"addr": 0x445fad, "type": "mov", "opcode": "mov eax, dword [eax + 0x60]"},
                        {"addr": 0x445fb0, "type": "acmp", "opcode": "test eax, eax"},
                        {"addr": 0x445fb2, "type": "cjmp", "jump": 0x446056, "fail": 0x445fb8, "opcode": "je 0x446056"},
                        {"addr": 0x445fc8, "type": "mov", "opcode": "mov esi, dword [eax + 0x10]"},
                        {"addr": 0x445fcd, "type": "mov", "opcode": "mov dword [eax + 0x10], esi"},
                    ],
                }
            ],
            "script_commit_caller_windows": [
                {
                    "id": "script_bridge_deferred_slot0_caller",
                    "address": "0x44ebf0",
                    "instruction_count": 96,
                    "role": "bridge_caller_deferred_queue_candidate",
                    "status": "ok",
                    "why_next": "Summarize deferred caller.",
                    "ops": [
                        {"addr": 0x44ebf0, "type": "mov", "refs": [{"addr": 0x4c1d04, "type": "DATA"}]},
                        {"addr": 0x44ec28, "type": "call", "jump": 0x450840},
                        {"addr": 0x44ec92, "type": "call", "jump": 0x453ac0},
                        {"addr": 0x44eca0, "type": "call", "jump": 0x453a80},
                        {"addr": 0x44ec39, "type": "cjmp", "jump": 0x44ec5d, "fail": 0x44ec3b},
                    ],
                },
                {
                    "id": "script_bridge_runtime_flag_caller",
                    "address": "0x408220",
                    "instruction_count": 96,
                    "role": "bridge_caller_flag_gated",
                    "status": "ok",
                    "why_next": "Summarize runtime flag caller.",
                    "ops": [
                        {"addr": 0x408257, "type": "acmp", "refs": [{"addr": 0x4c1b00, "type": "DATA"}]},
                        {"addr": 0x408264, "type": "call", "jump": 0x450840},
                        {"addr": 0x408275, "type": "and", "refs": [{"addr": 0x4c1b00, "type": "DATA"}]},
                        {"addr": 0x40829c, "type": "mov", "refs": [{"addr": 0x4c1d44, "type": "DATA"}]},
                    ],
                },
            ],
            "script_commit_callee_windows": [
                {
                    "id": "script_status_boundary_callee_44fcf0",
                    "address": "0x44fcf0",
                    "instruction_count": 120,
                    "role": "status_boundary_callee_candidate",
                    "status": "ok",
                    "why_next": "Summarize status boundary callee.",
                    "ops": [
                        {"addr": 0x44fcfb, "type": "call", "jump": 0x44fad0},
                        {"addr": 0x44fd51, "type": "mov", "opcode": "mov word [esi + 0x4a], ax"},
                        {"addr": 0x44fd62, "type": "mov", "opcode": "mov word [esi + 0x98], ax"},
                        {"addr": 0x44fd6d, "type": "mov", "opcode": "mov dword [esi + 0x8c], 0x320000"},
                        {"addr": 0x44fd77, "type": "mov", "opcode": "mov dword [esi + 0x50], edx"},
                    ],
                },
                {
                    "id": "script_bridge_cleanup_helper_453a80",
                    "address": "0x453a80",
                    "instruction_count": 120,
                    "role": "bridge_cleanup_helper_candidate",
                    "status": "ok",
                    "why_next": "Summarize cleanup helper.",
                    "ops": [
                        {"addr": 0x453aa7, "type": "mov", "refs": [{"addr": 0x4c1ba0, "type": "DATA"}], "opcode": "mov dword [0x4c1ba0], 1"},
                        {"addr": 0x453ab6, "type": "mov", "refs": [{"addr": 0x4c1b00, "type": "DATA"}], "opcode": "mov dword [0x4c1b00], eax"},
                        {"addr": 0x453b47, "type": "call", "jump": 0x450840},
                    ],
                },
            ],
            "map_object_visibility_evidence": {
                "summary": {
                    "target_resource_count": 4,
                    "target_placement_count": 10,
                    "obj_plane_candidates_by_resource": {
                        "tree07.SHP": ["planeObject1"],
                        "FIRE01-01.SHP": ["planeObject20"],
                        "bar004a.SHP": ["planeObject20"],
                        "bar004b.SHP": ["planeObject1"],
                    },
                    "user_confirmed_role_by_resource": {
                        "tree07.SHP": ["blocking_terrain"],
                        "FIRE01-01.SHP": ["animated_foreground"],
                    },
                },
                "objects": [
                    {
                        "resource_id": "tree07.SHP",
                        "usage_summary": {
                            "placed_instance_count": 6,
                            "object_codes": ["150", "151"],
                            "shape_number_candidates": ["1"],
                            "obj_plane_candidates": ["planeObject1"],
                            "processes": {"defProcStandObject": 6},
                        },
                    },
                    {
                        "resource_id": "FIRE01-01.SHP",
                        "usage_summary": {
                            "placed_instance_count": 2,
                            "object_codes": ["188"],
                            "shape_number_candidates": ["10"],
                            "obj_plane_candidates": ["planeObject20"],
                            "processes": {"defProcStandObject": 2},
                        },
                    },
                ],
            },
            "map_object_static_windows": [
                {
                    "id": "object_definition_field_parser_candidate",
                    "address": "0x45dc5c",
                    "instruction_count": 420,
                    "role": "object_field_parser",
                    "status": "ok",
                    "why_next": "Summarize object definition fields.",
                    "ops": [
                        {"addr": 0x45dd8a, "type": "push", "refs": [{"addr": 0x4A34A0, "type": "STRN"}], "opcode": "push str.obj_Plane"},
                        {"addr": 0x45dda9, "type": "push", "refs": [{"addr": 0x4A34AA, "type": "STRN"}], "opcode": "push str.obj_X1"},
                        {"addr": 0x45ddc8, "type": "push", "refs": [{"addr": 0x4A34B1, "type": "STRN"}], "opcode": "push str.obj_Y1"},
                        {"addr": 0x45ddee, "type": "push", "refs": [{"addr": 0x4A34B8, "type": "STRN"}], "opcode": "push str.obj_X2"},
                        {"addr": 0x45de14, "type": "push", "refs": [{"addr": 0x4A34BF, "type": "STRN"}], "opcode": "push str.obj_Y2"},
                        {"addr": 0x45deed, "type": "push", "refs": [{"addr": 0x4A3521, "type": "STRN"}], "opcode": "push str.obj_Collide_X1"},
                        {"addr": 0x45df0c, "type": "push", "refs": [{"addr": 0x4A3530, "type": "STRN"}], "opcode": "push str.obj_Collide_Y1"},
                        {"addr": 0x45df2b, "type": "push", "refs": [{"addr": 0x4A353F, "type": "STRN"}], "opcode": "push str.obj_Collide_X2"},
                        {"addr": 0x45df4a, "type": "push", "refs": [{"addr": 0x4A354E, "type": "STRN"}], "opcode": "push str.obj_Collide_Y2"},
                        {"addr": 0x45e12e, "type": "push", "refs": [{"addr": 0x4A34FF, "type": "STRN"}], "opcode": "push str.obj_Shape_Number"},
                        {"addr": 0x45e153, "type": "push", "refs": [{"addr": 0x4A34F0, "type": "STRN"}], "opcode": "push str.obj_Shape_Name"},
                    ],
                },
                {
                    "id": "scene_object_draw_candidate",
                    "address": "0x456150",
                    "instruction_count": 420,
                    "role": "scene_object_draw_or_update_candidate",
                    "status": "ok",
                    "why_next": "Summarize scene object traversal.",
                    "ops": [
                        {"addr": 0x456180, "type": "mov", "refs": [{"addr": 0x4c091c, "type": "DATA"}], "opcode": "mov eax, dword [0x4c091c]"},
                        {"addr": 0x456188, "type": "mov", "refs": [{"addr": 0x4c0920, "type": "DATA"}], "opcode": "mov edx, dword [0x4c0920]"},
                        {"addr": 0x456190, "type": "mov", "opcode": "mov eax, dword [esi + 0x70]"},
                        {"addr": 0x456198, "type": "mov", "opcode": "mov eax, dword [esi + 0x74]"},
                        {"addr": 0x4561a0, "type": "mov", "opcode": "mov dword [esi + 0x80], eax"},
                        {"addr": 0x4561a8, "type": "mov", "opcode": "mov dword [esi + 0x98], edx"},
                        {"addr": 0x4561b0, "type": "call", "jump": 0x460058, "opcode": "call fcn.00460058"},
                    ],
                },
                {
                    "id": "shp_descriptor_render_caller_a",
                    "address": "0x460058",
                    "instruction_count": 180,
                    "role": "shp_descriptor_render_caller",
                    "status": "ok",
                    "why_next": "Summarize SHP descriptor render caller.",
                    "ops": [
                        {"addr": 0x46013d, "type": "call", "jump": 0x45fa1e, "opcode": "call fcn.0045fa1e"},
                    ],
                },
                {
                    "id": "shp_descriptor_render_caller_b",
                    "address": "0x4601a2",
                    "instruction_count": 180,
                    "role": "shp_descriptor_render_caller",
                    "status": "ok",
                    "why_next": "Summarize second SHP descriptor render caller.",
                    "ops": [
                        {"addr": 0x460296, "type": "call", "jump": 0x45fa1e, "opcode": "call fcn.0045fa1e"},
                    ],
                },
            ],
            "unresolved_negative_evidence": ["runtime globals require dynamic probe confirmation"],
        }

        index = hsl_exe_static_export.build_tracked_static_index(manifest)
        text = json.dumps(index)

        self.assertEqual(index["tool_presence"], {"r2": True, "rabin2": True, "radare2": False})
        self.assertEqual(index["export_status_counts"], {"dry-run": 1, "ok": 1})
        self.assertEqual(index["known_windows"][0]["label"], "input_aggregator_candidate")
        self.assertEqual(index["known_windows"][0]["byte_count"], 544)
        self.assertEqual(index["export_count_summary"]["dispatch_tables"], 2)
        tables = {table["id"]: table for table in index["dispatch_table_summaries"]}
        self.assertEqual(tables["script_primary_dispatch_table"]["probable_handler_slot_count"], 2)
        self.assertEqual(tables["script_action_dispatch_table"]["repeated_handlers"][0]["handler_address"], "0x4511e9")
        xrefs = {target["id"]: target for target in index["xref_target_summaries"]}
        self.assertEqual(xrefs["script_interpreter_bridge_candidate"]["xref_count"], 1)
        bodies = {body["id"]: body for body in index["body_window_summaries"]}
        self.assertEqual(bodies["script_interpreter_bridge_function"]["call_target_addresses"], ["0x44fcf0", "0x450450"])
        condition_windows = {item["handler_address"]: item for item in index["condition_handler_window_summaries"]}
        self.assertEqual(condition_windows["0x4511e9"]["comparison_branch_shape_status"], "observed")
        self.assertEqual(condition_windows["0x4511e9"]["compare_op_count_until_first_ret"], 1)
        self.assertEqual(condition_windows["0x4511e9"]["conditional_jump_count_until_first_ret"], 1)
        shp_header = index["shp_render_header_static_evidence"]
        self.assertEqual(shp_header["header_0x10_semantic_status"], "unresolved")
        self.assertEqual(shp_header["header_0x10_read_status"], "not_observed_in_bounded_windows")
        self.assertIn("0x18", shp_header["combined_observed_header_offsets"])
        self.assertNotIn("0x10", shp_header["combined_observed_header_offsets"])
        fingerprints = {item["handler_address"]: item for item in index["action_handler_fingerprints"]}
        self.assertEqual(fingerprints["0x4511e9"]["slot_numbers"], [0, 1])
        self.assertEqual(fingerprints["0x4511e9"]["data_ref_addresses"], ["0x4c1d38"])
        skeleton = index["script_action_correlation_skeleton"]
        self.assertEqual(skeleton["ordered_action_name_count"], 2)
        self.assertEqual(skeleton["actions"][0]["action_name"], "actMessage")
        self.assertEqual(skeleton["actions"][0]["correlation_status"], "unresolved")
        self.assertEqual(skeleton["actions"][0]["ordinal_as_slot_status"], "not_evidence")
        consumers = {item["consumer"]: item for item in skeleton["downstream_consumers"]}
        self.assertEqual(consumers["godot-integration"]["current_status"], "read_only_action_metadata_no_handlers")
        self.assertIn("No opcode-to-action-name", skeleton["negative_evidence"][0])
        object_candidates = index["object_shape_handler_candidates"]
        self.assertEqual(object_candidates["correlation_status"], "unresolved")
        self.assertEqual(object_candidates["resource_refs_summary"]["symbolic_shape_ref_count"], 1)
        self.assertEqual(object_candidates["resource_refs_summary"]["unresolved_shape_ref_count_from_list"], 1)
        self.assertEqual(len(object_candidates["resource_refs_summary"]["unresolved_shape_refs"][0]["searched_payload_roots"]), 3)
        self.assertEqual(object_candidates["top_candidates"][0]["candidate_handler_if_order_matched"], "0x4511e9")
        condition_candidates = index["condition_predicate_handler_candidates"]
        self.assertEqual(condition_candidates["semantic_status"], "unresolved")
        self.assertEqual(condition_candidates["actions"][0]["slot_opcode_evidence_status"], "unresolved")
        self.assertEqual(condition_candidates["actions"][0]["comparison_polarity_evidence_status"], "unresolved")
        self.assertEqual(condition_candidates["actions"][0]["condition_handler_window_status"], "observed")
        self.assertEqual(condition_candidates["handler_window_summaries"][0]["handler_address"], "0x4511e9")
        status_candidates = index["status_lifecycle_handler_candidates"]
        self.assertEqual(status_candidates["semantic_status"], "unresolved")
        self.assertEqual(status_candidates["bridge_commit_timing_status"], "unresolved")
        self.assertEqual(status_candidates["actions"][0]["commit_timing_evidence_status"], "unresolved")
        self.assertEqual(status_candidates["actions"][0]["lifecycle_semantic_status"], "scheduled_only")
        commit_path = index["script_status_commit_path_static_context"]
        self.assertEqual(commit_path["semantic_status"], "unresolved")
        self.assertEqual(commit_path["bridge_address"], "0x450840")
        self.assertEqual(commit_path["script_cursor_progress"]["commit_boundary_status"], "script_cursor_progress_observed")
        self.assertEqual(commit_path["script_cursor_progress"]["status_mutation_commit_status"], "unresolved")
        self.assertEqual(commit_path["status_mutation_commit_timing_status"], "unresolved")
        self.assertEqual(commit_path["registry_write_status"], "unresolved")
        self.assertEqual(commit_path["direct_deferred_queue_write_status"], "not_observed_in_prioritized_callee_windows")
        self.assertEqual(commit_path["direct_status_registry_write_status"], "not_observed_in_prioritized_callee_windows")
        self.assertIn("0x4c1b00", commit_path["runtime_flag_write_addresses"])
        caller_refs = {
            ref
            for caller in commit_path["caller_window_summaries"]
            for ref in caller["candidate_deferred_queue_global_refs"]
        }
        self.assertIn("0x4c1d04", caller_refs)
        callee_offsets = {
            offset
            for callee in commit_path["callee_window_summaries"]
            for offset in callee["object_write_offsets"]
        }
        self.assertIn("0x8c", callee_offsets)
        self.assertEqual(commit_path["callee_window_summaries"][0]["direct_status_registry_write_status"], "not_observed_in_bounded_window")
        self.assertEqual(commit_path["status_handler_boundary_candidates"][0]["correlation_status"], "unresolved")
        numeric_tokens = index["script_numeric_dispatch_token_context"]
        self.assertEqual(numeric_tokens["source_numeric_token_status"], "observed_in_0x450840_bridge")
        self.assertEqual(numeric_tokens["action_name_mapping_status"], "unresolved")
        self.assertEqual(numeric_tokens["status_lifecycle_upgrade_status"], "not_evidence")
        self.assertEqual(numeric_tokens["primary_dispatch"]["selector_source_field_offset"], "0x8e")
        self.assertEqual(numeric_tokens["primary_dispatch"]["remap_table_address"], "0x453768")
        self.assertEqual(numeric_tokens["primary_dispatch"]["dispatch_table_address"], "0x453708")
        self.assertEqual(numeric_tokens["action_dispatch"]["script_cursor_field_offset"], "0x90")
        self.assertEqual(numeric_tokens["action_dispatch"]["dispatch_table_address"], "0x4537f4")
        self.assertEqual(numeric_tokens["action_dispatch"]["cursor_advance_bytes"], 4)
        ui_owner = index["ui_owner_traversal_static_context"]
        self.assertEqual(ui_owner["semantic_status"], "unresolved")
        self.assertEqual(ui_owner["command_identity_status"], "unresolved")
        self.assertIn("0x80", ui_owner["hit_test_window"]["object_like_offsets"])
        self.assertEqual(ui_owner["ui_resource_navigation_hints"]["resource_count"], 42)
        self.assertEqual(ui_owner["related_window_summaries"][0]["owner_contract_status"], "unresolved")
        self.assertIn("0x60", ui_owner["related_window_summaries"][0]["object_read_offsets"])
        self.assertEqual(ui_owner["contract_navigation_hints"][0]["semantic_status"], "unresolved")
        self.assertIn("Godot UI/target interaction", ui_owner["playable_blocker_helped"])
        self.assertEqual(ui_owner["blocking_placement_navigation_note"]["relationship_to_ui_hit_test"], "not_joined")
        provenance = index["resource_provenance_static_classification"]
        self.assertEqual(provenance["semantic_status"], "unresolved")
        self.assertEqual(provenance["classification_counts"]["missing_in_searched_chapter_roots_player_install_definition"], 1)
        self.assertEqual(provenance["classifications"][0]["missing_archive_root_status"], "candidate")
        self.assertEqual(provenance["classifications"][0]["global_asset_status"], "unresolved")
        self.assertEqual(provenance["color_header_0x10_static_note"]["semantic_status"], "unresolved")
        map_context = index["map_object_visibility_static_context"]
        self.assertEqual(map_context["semantic_status"], "unresolved")
        self.assertEqual(map_context["obj_plane_status"], "parser_field_ingestion_observed_render_sorting_unresolved")
        self.assertEqual(map_context["shape_number_semantics_status"], "unresolved_navigation_candidate_only")
        self.assertEqual(map_context["resource_scope"]["target_resource_count"], 4)
        self.assertEqual(map_context["resource_scope"]["target_resources"][0]["resource_id"], "tree07.SHP")
        self.assertIn("obj_Plane", map_context["parser_field_ingestion"]["target_fields_observed"])
        self.assertIn("obj_Shape_Number", map_context["parser_field_ingestion"]["target_fields_observed"])
        self.assertEqual(map_context["parser_field_ingestion"]["missing_target_fields"], [])
        self.assertIn("0x70", map_context["draw_or_traversal_candidate"]["clip_or_anchor_candidate_offsets"])
        self.assertIn("0x460058", map_context["draw_or_traversal_candidate"]["shp_related_call_targets"])
        self.assertIn("0x45fa1e", map_context["render_path_windows"][0]["shp_related_call_targets"])
        self.assertTrue(map_context["godot_consumable_fields"]["must_keep_layer_sorting_occlusion_anchor_clip_unresolved"])
        self.assertEqual(index["player_control_action_menu_static_context"]["interpretation_status"], "runtime_transition_unproven")
        self.assertEqual(index["resource_object_static_question_context"]["interpretation_status"], "unresolved")
        self.assertNotIn('"opcode":', json.dumps(index))
        self.assertNotIn('"disasm":', json.dumps(index))
        self.assertNotIn('"bytes":', json.dumps(index))
        self.assertGreaterEqual(index["battle_state_target_count"], 10)
        targets = {target["id"]: target for target in index["battle_state_targets"]}
        self.assertEqual(targets["input_current_edge_bits"]["address"], "0x4c6390")
        self.assertEqual(targets["script_action_dispatch_table"]["address"], "0x4537f4")
        self.assertIn("runtime_probe", targets["logical_ui_object_chain"])
        self.assertNotIn("command", index)
        self.assertNotIn("commands", index)
        self.assertNotIn("exe", index)
        self.assertNotIn("output", index["known_windows"][0])
        self.assertNotIn("stderr", index["known_windows"][0])
        for forbidden in [
            "/private",
            "sha256",
            "ignored/static",
            "strings.json",
            "input.asm",
            "stderr",
            "raw_bytes",
            "disassembly",
        ]:
            self.assertNotIn(forbidden, text)

    def test_write_tracked_static_index_creates_json(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "content" / "generated" / "hsl" / "static" / "hsl01" / "index.json"
            index = hsl_exe_static_export.build_tracked_static_index({
                "tools": {},
                "commands": [],
                "known_windows": [],
                "unresolved_negative_evidence": [],
            })

            hsl_exe_static_export.write_tracked_static_index(index, output)

            saved = json.loads(output.read_text(encoding="utf-8"))
        self.assertEqual(saved["schema"], "hsl_static_compact_index.v1")


class RuntimeProbeSchemaTests(unittest.TestCase):
    def test_runtime_probe_schema_is_tracked_schema_not_trace_payload(self):
        schema_path = Path("tools/hsl_runtime_probe_schema.json")
        schema = json.loads(schema_path.read_text(encoding="utf-8"))

        self.assertEqual(schema["schema"], "hsl_runtime_probe_trace.v1")
        self.assertIn("raw memory dumps", " ".join(schema["forbidden_first_stage"]))
        self.assertTrue(schema["trace"]["probe_targets"][0]["read_only"])
        self.assertIn("samples", schema["trace"])


if __name__ == "__main__":
    unittest.main()
