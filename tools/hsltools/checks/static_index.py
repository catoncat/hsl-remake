"""Structural check of the tracked static compact index (content/generated/hsl/static/hsl01/index.json).

Registry task static_index_check (family checks, CheckTask). Bodies moved verbatim from the former hsl_static_index_check.py.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from hsltools.checks import CheckTask
from hsltools.data import printed_last_line
from hsltools.registry import Context


EXPECTED_SCHEMA = "hsl_static_compact_index.v1"
FORBIDDEN_FIELD_NAMES = {
    "command",
    "commands",
    "exe",
    "output",
    "path",
    "sha256",
    "stderr",
}
FORBIDDEN_STRING_TOKENS = {
    "/Users",
    "ignored/",
    "raw_bytes",
    "strings.json",
}


def load_json(path: Path) -> tuple[Any | None, str | None]:
    try:
        return json.loads(path.read_text(encoding="utf-8")), None
    except FileNotFoundError:
        return None, f"missing file: {path}"
    except json.JSONDecodeError as exc:
        return None, f"invalid JSON: {exc.msg}"


def collect_forbidden(value: Any, prefix: str = "") -> list[str]:
    errors: list[str] = []
    if isinstance(value, dict):
        for key, child in value.items():
            child_path = f"{prefix}.{key}" if prefix else str(key)
            if key in FORBIDDEN_FIELD_NAMES:
                errors.append(f"forbidden field {child_path}")
            errors.extend(collect_forbidden(child, child_path))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            errors.extend(collect_forbidden(child, f"{prefix}[{index}]"))
    elif isinstance(value, str):
        for token in sorted(FORBIDDEN_STRING_TOKENS):
            if token in value:
                errors.append(f"forbidden string token {token!r} at {prefix or '<root>'}")
    return errors


def check_static_index(path: Path | str) -> list[str]:
    index, error = load_json(Path(path))
    if error:
        return [error]
    if not isinstance(index, dict):
        return ["index root must be an object"]
    errors: list[str] = []
    if index.get("schema") != EXPECTED_SCHEMA:
        errors.append(f"schema mismatch: expected {EXPECTED_SCHEMA!r}, got {index.get('schema')!r}")
    errors.extend(collect_forbidden(index))
    if index.get("evidence_tier") != "static_export_candidate":
        errors.append("evidence_tier must be static_export_candidate")
    windows = index.get("known_windows")
    if not isinstance(windows, list) or not windows:
        errors.append("known_windows must be a non-empty list")
    else:
        for idx, window in enumerate(windows):
            if not isinstance(window, dict):
                errors.append(f"known_windows[{idx}] must be an object")
                continue
            if not str(window.get("address", "")).startswith("0x"):
                errors.append(f"known_windows[{idx}].address must be hex")
            if int(window.get("byte_count", 0)) <= 0:
                errors.append(f"known_windows[{idx}].byte_count must be positive")
    targets = index.get("battle_state_targets")
    if targets is not None:
        errors.extend(check_battle_state_targets(index, targets))
    table_summaries = index.get("dispatch_table_summaries")
    if table_summaries is not None:
        errors.extend(check_dispatch_table_summaries(table_summaries))
    xref_summaries = index.get("xref_target_summaries")
    if xref_summaries is not None:
        errors.extend(check_xref_target_summaries(xref_summaries))
    body_summaries = index.get("body_window_summaries")
    if body_summaries is not None:
        errors.extend(check_body_window_summaries(body_summaries))
    condition_window_summaries = index.get("condition_handler_window_summaries")
    if condition_window_summaries is not None:
        errors.extend(check_condition_handler_window_summaries(condition_window_summaries))
    shp_render = index.get("shp_render_header_static_evidence")
    if shp_render is not None:
        errors.extend(check_shp_render_header_static_evidence(shp_render))
    fingerprints = index.get("action_handler_fingerprints")
    if fingerprints is not None:
        errors.extend(check_action_handler_fingerprints(fingerprints))
    skeleton = index.get("script_action_correlation_skeleton")
    if skeleton is not None:
        errors.extend(check_script_action_correlation_skeleton(skeleton))
    object_shape_candidates = index.get("object_shape_handler_candidates")
    if object_shape_candidates is not None:
        errors.extend(check_object_shape_handler_candidates(object_shape_candidates))
    condition_candidates = index.get("condition_predicate_handler_candidates")
    if condition_candidates is not None:
        errors.extend(check_condition_predicate_handler_candidates(condition_candidates))
    status_candidates = index.get("status_lifecycle_handler_candidates")
    if status_candidates is not None:
        errors.extend(check_status_lifecycle_handler_candidates(status_candidates))
    commit_path = index.get("script_status_commit_path_static_context")
    if commit_path is not None:
        errors.extend(check_script_status_commit_path_static_context(commit_path))
    numeric_tokens = index.get("script_numeric_dispatch_token_context")
    if numeric_tokens is not None:
        errors.extend(check_script_numeric_dispatch_token_context(numeric_tokens))
    ui_owner = index.get("ui_owner_traversal_static_context")
    if ui_owner is not None:
        errors.extend(check_ui_owner_traversal_static_context(ui_owner))
    player_context = index.get("player_control_action_menu_static_context")
    if player_context is not None:
        errors.extend(check_player_control_action_menu_context(player_context))
    resource_context = index.get("resource_object_static_question_context")
    if resource_context is not None:
        errors.extend(check_resource_object_static_question_context(resource_context))
    resource_classification = index.get("resource_provenance_static_classification")
    if resource_classification is not None:
        errors.extend(check_resource_provenance_static_classification(resource_classification))
    map_object_context = index.get("map_object_visibility_static_context")
    if map_object_context is not None:
        errors.extend(check_map_object_visibility_static_context(map_object_context))
    return errors


def check_battle_state_targets(index: dict[str, Any], targets: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(targets, list) or not targets:
        return ["battle_state_targets must be a non-empty list when present"]
    known_window_labels = {
        str(window.get("label"))
        for window in index.get("known_windows", [])
        if isinstance(window, dict) and window.get("label")
    }
    target_ids: set[str] = set()
    categories: set[str] = set()
    for idx, target in enumerate(targets):
        prefix = f"battle_state_targets[{idx}]"
        if not isinstance(target, dict):
            errors.append(f"{prefix} must be an object")
            continue
        target_id = target.get("id")
        if not isinstance(target_id, str) or not target_id:
            errors.append(f"{prefix}.id must be a non-empty string")
        elif target_id in target_ids:
            errors.append(f"{prefix}.id duplicate: {target_id}")
        else:
            target_ids.add(target_id)
        category = target.get("category")
        if not isinstance(category, str) or not category:
            errors.append(f"{prefix}.category must be a non-empty string")
        else:
            categories.add(category)
        address = target.get("address")
        if not isinstance(address, str) or not address.startswith("0x"):
            errors.append(f"{prefix}.address must be hex")
        tier = target.get("evidence_tier")
        if not isinstance(tier, str) or not tier:
            errors.append(f"{prefix}.evidence_tier must be a non-empty string")
        sources = target.get("evidence_sources")
        if not isinstance(sources, list) or not sources:
            errors.append(f"{prefix}.evidence_sources must be a non-empty list")
        else:
            for source in sources:
                if source not in known_window_labels:
                    errors.append(f"{prefix}.evidence_sources unknown window label: {source!r}")
        for key in ("label", "static_observation", "why_next", "runtime_probe"):
            if not isinstance(target.get(key), str) or not target.get(key):
                errors.append(f"{prefix}.{key} must be a non-empty string")
    expected_categories = {
        "input_globals",
        "menu_state",
        "script_interpreter_tables",
        "object_unit_anchors",
        "cursor_camera_globals",
    }
    missing_categories = expected_categories - categories
    if missing_categories:
        errors.append(f"battle_state_targets missing categories: {sorted(missing_categories)}")
    if index.get("battle_state_target_count") != len(targets):
        errors.append("battle_state_target_count must match battle_state_targets length")
    return errors


def check_dispatch_table_summaries(summaries: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(summaries, list) or not summaries:
        return ["dispatch_table_summaries must be a non-empty list when present"]
    ids: set[str] = set()
    for idx, summary in enumerate(summaries):
        prefix = f"dispatch_table_summaries[{idx}]"
        if not isinstance(summary, dict):
            errors.append(f"{prefix} must be an object")
            continue
        table_id = summary.get("id")
        if not isinstance(table_id, str) or not table_id:
            errors.append(f"{prefix}.id must be a non-empty string")
        elif table_id in ids:
            errors.append(f"{prefix}.id duplicate: {table_id}")
        else:
            ids.add(table_id)
        if not str(summary.get("address", "")).startswith("0x"):
            errors.append(f"{prefix}.address must be hex")
        declared = summary.get("entry_count_declared")
        observed = summary.get("entry_count_observed")
        if not isinstance(declared, int) or declared <= 0:
            errors.append(f"{prefix}.entry_count_declared must be positive")
        if not isinstance(observed, int) or observed < 0:
            errors.append(f"{prefix}.entry_count_observed must be non-negative")
        slots = summary.get("handler_slots")
        if not isinstance(slots, list):
            errors.append(f"{prefix}.handler_slots must be a list")
        else:
            for slot_index, slot in enumerate(slots):
                slot_prefix = f"{prefix}.handler_slots[{slot_index}]"
                if not isinstance(slot, dict):
                    errors.append(f"{slot_prefix} must be an object")
                    continue
                if not isinstance(slot.get("slot"), int) or slot.get("slot") < 0:
                    errors.append(f"{slot_prefix}.slot must be non-negative int")
                if not str(slot.get("handler_address", "")).startswith("0x"):
                    errors.append(f"{slot_prefix}.handler_address must be hex")
        if summary.get("probable_handler_slot_count") != len(slots or []):
            errors.append(f"{prefix}.probable_handler_slot_count must match handler_slots length")
        if not isinstance(summary.get("unique_handler_count"), int) or summary.get("unique_handler_count") < 0:
            errors.append(f"{prefix}.unique_handler_count must be non-negative int")
    required = {"script_primary_dispatch_table", "script_action_dispatch_table"}
    missing = required - ids
    if missing:
        errors.append(f"dispatch_table_summaries missing ids: {sorted(missing)}")
    return errors


def check_xref_target_summaries(summaries: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(summaries, list) or not summaries:
        return ["xref_target_summaries must be a non-empty list when present"]
    ids: set[str] = set()
    for idx, summary in enumerate(summaries):
        prefix = f"xref_target_summaries[{idx}]"
        if not isinstance(summary, dict):
            errors.append(f"{prefix} must be an object")
            continue
        target_id = summary.get("id")
        if not isinstance(target_id, str) or not target_id:
            errors.append(f"{prefix}.id must be a non-empty string")
        elif target_id in ids:
            errors.append(f"{prefix}.id duplicate: {target_id}")
        else:
            ids.add(target_id)
        if not str(summary.get("address", "")).startswith("0x"):
            errors.append(f"{prefix}.address must be hex")
        if not isinstance(summary.get("xref_count"), int) or summary.get("xref_count") < 0:
            errors.append(f"{prefix}.xref_count must be non-negative int")
        xrefs = summary.get("xrefs")
        if not isinstance(xrefs, list):
            errors.append(f"{prefix}.xrefs must be a list")
        else:
            if summary.get("xref_count") != len(xrefs):
                errors.append(f"{prefix}.xref_count must match xrefs length")
            for xref_index, xref in enumerate(xrefs):
                xref_prefix = f"{prefix}.xrefs[{xref_index}]"
                if not isinstance(xref, dict):
                    errors.append(f"{xref_prefix} must be an object")
                    continue
                if not str(xref.get("from_address", "")).startswith("0x"):
                    errors.append(f"{xref_prefix}.from_address must be hex")
                if not isinstance(xref.get("type"), str) or not xref.get("type"):
                    errors.append(f"{xref_prefix}.type must be a non-empty string")
    required = {"logical_ui_hit_test_candidate", "script_interpreter_bridge_candidate"}
    missing = required - ids
    if missing:
        errors.append(f"xref_target_summaries missing ids: {sorted(missing)}")
    return errors


def _check_hex_list(value: Any, path: str) -> list[str]:
    if not isinstance(value, list):
        return [f"{path} must be a list"]
    errors: list[str] = []
    for index, item in enumerate(value):
        if not isinstance(item, str) or not item.startswith("0x"):
            errors.append(f"{path}[{index}] must be hex string")
    return errors


def check_body_window_summaries(summaries: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(summaries, list) or not summaries:
        return ["body_window_summaries must be a non-empty list when present"]
    ids: set[str] = set()
    for idx, summary in enumerate(summaries):
        prefix = f"body_window_summaries[{idx}]"
        if not isinstance(summary, dict):
            errors.append(f"{prefix} must be an object")
            continue
        body_id = summary.get("id")
        if not isinstance(body_id, str) or not body_id:
            errors.append(f"{prefix}.id must be a non-empty string")
        else:
            ids.add(body_id)
        if not str(summary.get("address", "")).startswith("0x"):
            errors.append(f"{prefix}.address must be hex")
        if not isinstance(summary.get("op_count"), int) or summary.get("op_count") < 0:
            errors.append(f"{prefix}.op_count must be non-negative int")
        for key in ("call_target_addresses", "jump_target_addresses", "data_ref_addresses", "code_ref_addresses"):
            errors.extend(_check_hex_list(summary.get(key), f"{prefix}.{key}"))
        if "disasm" in summary or "opcode" in summary or "bytes" in summary:
            errors.append(f"{prefix} must not include decoded instruction text or raw bytes")
    required = {"script_interpreter_bridge_function", "logical_ui_hit_test_window"}
    missing = required - ids
    if missing:
        errors.append(f"body_window_summaries missing ids: {sorted(missing)}")
    return errors


def check_condition_handler_window_summaries(summaries: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(summaries, list):
        return ["condition_handler_window_summaries must be a list when present"]
    for idx, summary in enumerate(summaries):
        prefix = f"condition_handler_window_summaries[{idx}]"
        if not isinstance(summary, dict):
            errors.append(f"{prefix} must be an object")
            continue
        if not str(summary.get("handler_address", "")).startswith("0x"):
            errors.append(f"{prefix}.handler_address must be hex")
        if summary.get("correlation_status") != "unresolved":
            errors.append(f"{prefix}.correlation_status must remain unresolved")
        if summary.get("ordinal_as_slot_status") != "not_evidence":
            errors.append(f"{prefix}.ordinal_as_slot_status must be not_evidence")
        if not isinstance(summary.get("bounded_instruction_count"), int) or summary.get("bounded_instruction_count") <= 0:
            errors.append(f"{prefix}.bounded_instruction_count must be positive int")
        if not isinstance(summary.get("op_count_until_first_ret"), int) or summary.get("op_count_until_first_ret") < 0:
            errors.append(f"{prefix}.op_count_until_first_ret must be non-negative int")
        for key in (
            "call_target_addresses_until_first_ret",
            "data_ref_addresses_until_first_ret",
            "compare_op_addresses",
            "code_or_data_pointer_values",
        ):
            errors.extend(_check_hex_list(summary.get(key), f"{prefix}.{key}"))
        branches = summary.get("conditional_branch_edges")
        if not isinstance(branches, list):
            errors.append(f"{prefix}.conditional_branch_edges must be a list")
        else:
            for branch_index, branch in enumerate(branches):
                branch_prefix = f"{prefix}.conditional_branch_edges[{branch_index}]"
                if not isinstance(branch, dict):
                    errors.append(f"{branch_prefix} must be an object")
                    continue
                if not str(branch.get("from_address", "")).startswith("0x"):
                    errors.append(f"{branch_prefix}.from_address must be hex")
                for key in ("jump_target", "fallthrough_target"):
                    value = branch.get(key)
                    if value is not None and (not isinstance(value, str) or not value.startswith("0x")):
                        errors.append(f"{branch_prefix}.{key} must be hex when present")
        if summary.get("comparison_branch_shape_status") not in {"observed", "not_observed_in_bounded_window"}:
            errors.append(f"{prefix}.comparison_branch_shape_status invalid")
        negative = summary.get("negative_evidence")
        if not isinstance(negative, list) or not negative:
            errors.append(f"{prefix}.negative_evidence must be non-empty list")
        if "opcode" in summary or "disasm" in summary or "bytes" in summary:
            errors.append(f"{prefix} must not include decoded instruction text or raw bytes")
    return errors


def check_shp_render_header_static_evidence(evidence: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(evidence, dict):
        return ["shp_render_header_static_evidence must be an object when present"]
    if evidence.get("schema") != "hsl_static_shp_render_header_evidence.v1":
        errors.append("shp_render_header_static_evidence.schema mismatch")
    if evidence.get("semantic_status") != "unresolved":
        errors.append("shp_render_header_static_evidence.semantic_status must remain unresolved")
    if evidence.get("header_0x10_semantic_status") != "unresolved":
        errors.append("shp_render_header_static_evidence.header_0x10_semantic_status must remain unresolved")
    if evidence.get("header_0x10_read_status") not in {"observed", "not_observed_in_bounded_windows"}:
        errors.append("shp_render_header_static_evidence.header_0x10_read_status invalid")
    errors.extend(_check_hex_list(evidence.get("combined_observed_header_offsets"), "shp_render_header_static_evidence.combined_observed_header_offsets"))
    windows = evidence.get("window_summaries")
    if not isinstance(windows, list):
        errors.append("shp_render_header_static_evidence.window_summaries must be a list")
    else:
        for index, window in enumerate(windows):
            prefix = f"shp_render_header_static_evidence.window_summaries[{index}]"
            if not isinstance(window, dict):
                errors.append(f"{prefix} must be an object")
                continue
            if not isinstance(window.get("id"), str) or not window.get("id"):
                errors.append(f"{prefix}.id must be non-empty string")
            if not str(window.get("address", "")).startswith("0x"):
                errors.append(f"{prefix}.address must be hex")
            if window.get("header_0x10_read_status") not in {"observed", "not_observed_in_bounded_windows"}:
                errors.append(f"{prefix}.header_0x10_read_status invalid")
            if not isinstance(window.get("bounded_instruction_count"), int) or window.get("bounded_instruction_count") <= 0:
                errors.append(f"{prefix}.bounded_instruction_count must be positive int")
            for key in (
                "observed_header_offsets",
                "tlhs_magic_compare_addresses",
                "format_version_compare_addresses",
                "row_table_header_skip_addresses",
                "call_target_addresses",
            ):
                errors.extend(_check_hex_list(window.get(key), f"{prefix}.{key}"))
    negative = evidence.get("negative_evidence")
    if not isinstance(negative, list) or not negative:
        errors.append("shp_render_header_static_evidence.negative_evidence must be non-empty list")
    return errors


def check_action_handler_fingerprints(fingerprints: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(fingerprints, list) or not fingerprints:
        return ["action_handler_fingerprints must be a non-empty list when present"]
    seen: set[str] = set()
    for idx, item in enumerate(fingerprints):
        prefix = f"action_handler_fingerprints[{idx}]"
        if not isinstance(item, dict):
            errors.append(f"{prefix} must be an object")
            continue
        address = item.get("handler_address")
        if not isinstance(address, str) or not address.startswith("0x"):
            errors.append(f"{prefix}.handler_address must be hex")
        elif address in seen:
            errors.append(f"{prefix}.handler_address duplicate: {address}")
        else:
            seen.add(address)
        slots = item.get("slot_numbers")
        if not isinstance(slots, list) or not slots:
            errors.append(f"{prefix}.slot_numbers must be a non-empty list")
        else:
            for slot_index, slot in enumerate(slots):
                if not isinstance(slot, int) or slot < 0:
                    errors.append(f"{prefix}.slot_numbers[{slot_index}] must be non-negative int")
        if not isinstance(item.get("bounded_byte_window"), int) or item.get("bounded_byte_window") <= 0:
            errors.append(f"{prefix}.bounded_byte_window must be positive int")
        if not isinstance(item.get("op_count"), int) or item.get("op_count") < 0:
            errors.append(f"{prefix}.op_count must be non-negative int")
        for key in ("call_target_addresses", "jump_target_addresses", "data_ref_addresses", "code_ref_addresses"):
            errors.extend(_check_hex_list(item.get(key), f"{prefix}.{key}"))
        if "disasm" in item or "opcode" in item or "bytes" in item:
            errors.append(f"{prefix} must not include decoded instruction text or raw bytes")
    return errors


def check_script_action_correlation_skeleton(skeleton: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(skeleton, dict):
        return ["script_action_correlation_skeleton must be an object when present"]
    if skeleton.get("schema") != "hsl_static_script_action_correlation_skeleton.v1":
        errors.append("script_action_correlation_skeleton.schema mismatch")
    for key in (
        "static_script_action_dispatch_table",
        "static_script_primary_dispatch_table",
        "static_script_interpreter_bridge",
    ):
        if not str(skeleton.get(key, "")).startswith("0x"):
            errors.append(f"script_action_correlation_skeleton.{key} must be hex")
    actions = skeleton.get("actions")
    if not isinstance(actions, list) or not actions:
        errors.append("script_action_correlation_skeleton.actions must be non-empty list")
    else:
        if skeleton.get("ordered_action_name_count") != len(actions):
            errors.append("script_action_correlation_skeleton ordered_action_name_count must match actions length")
        for index, action in enumerate(actions):
            prefix = f"script_action_correlation_skeleton.actions[{index}]"
            if not isinstance(action, dict):
                errors.append(f"{prefix} must be an object")
                continue
            if action.get("resource_order_index") != index:
                errors.append(f"{prefix}.resource_order_index must match list order")
            if not isinstance(action.get("action_name"), str) or not action.get("action_name"):
                errors.append(f"{prefix}.action_name must be a non-empty string")
            if action.get("correlation_status") != "unresolved":
                errors.append(f"{prefix}.correlation_status must remain unresolved")
            if action.get("ordinal_as_slot_status") != "not_evidence":
                errors.append(f"{prefix}.ordinal_as_slot_status must be not_evidence")
            handler = action.get("candidate_handler_if_order_matched")
            if handler is not None and (not isinstance(handler, str) or not handler.startswith("0x")):
                errors.append(f"{prefix}.candidate_handler_if_order_matched must be hex or null")
    negative = skeleton.get("negative_evidence")
    if not isinstance(negative, list) or not negative:
        errors.append("script_action_correlation_skeleton.negative_evidence must be non-empty list")
    consumers = skeleton.get("downstream_consumers")
    if consumers is not None:
        if not isinstance(consumers, list) or not consumers:
            errors.append("script_action_correlation_skeleton.downstream_consumers must be non-empty list when present")
        else:
            for index, consumer in enumerate(consumers):
                prefix = f"script_action_correlation_skeleton.downstream_consumers[{index}]"
                if not isinstance(consumer, dict):
                    errors.append(f"{prefix} must be an object")
                    continue
                for key in ("consumer", "current_status", "mapping_exit_criteria"):
                    if not isinstance(consumer.get(key), str) or not consumer.get(key):
                        errors.append(f"{prefix}.{key} must be non-empty string")
    if isinstance(consumers, list):
        godot = [
            item
            for item in consumers
            if isinstance(item, dict) and item.get("consumer") == "godot-integration"
        ]
        if godot and godot[0].get("current_status") != "read_only_action_metadata_no_handlers":
            errors.append("godot-integration downstream consumer must remain read_only_action_metadata_no_handlers")
    return errors


def _check_candidate_handler_common(item: dict[str, Any], prefix: str) -> list[str]:
    errors: list[str] = []
    if item.get("correlation_status") != "unresolved":
        errors.append(f"{prefix}.correlation_status must remain unresolved")
    if item.get("ordinal_as_slot_status") != "not_evidence":
        errors.append(f"{prefix}.ordinal_as_slot_status must be not_evidence")
    slot = item.get("candidate_slot_if_order_matched")
    if slot is not None and (not isinstance(slot, int) or slot < 0):
        errors.append(f"{prefix}.candidate_slot_if_order_matched must be non-negative int or null")
    handler = item.get("candidate_handler_if_order_matched")
    if handler is not None and (not isinstance(handler, str) or not handler.startswith("0x")):
        errors.append(f"{prefix}.candidate_handler_if_order_matched must be hex or null")
    return errors


def check_object_shape_handler_candidates(candidates: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(candidates, dict):
        return ["object_shape_handler_candidates must be an object when present"]
    if candidates.get("schema") != "hsl_static_object_shape_handler_candidates.v1":
        errors.append("object_shape_handler_candidates.schema mismatch")
    if candidates.get("correlation_status") != "unresolved":
        errors.append("object_shape_handler_candidates.correlation_status must remain unresolved")
    top = candidates.get("top_candidates")
    if not isinstance(top, list):
        errors.append("object_shape_handler_candidates.top_candidates must be a list")
    else:
        if candidates.get("candidate_count", 0) < len(top):
            errors.append("object_shape_handler_candidates.candidate_count must be >= top_candidates length")
        for index, item in enumerate(top):
            prefix = f"object_shape_handler_candidates.top_candidates[{index}]"
            if not isinstance(item, dict):
                errors.append(f"{prefix} must be an object")
                continue
            if not isinstance(item.get("action_name"), str) or not item.get("action_name"):
                errors.append(f"{prefix}.action_name must be a non-empty string")
            errors.extend(_check_candidate_handler_common(item, prefix))
            if not isinstance(item.get("score"), int) or item.get("score") <= 0:
                errors.append(f"{prefix}.score must be positive int")
            for key in (
                "matched_object_helper_calls",
                "matched_object_context_globals",
                "handler_call_targets",
                "handler_data_refs",
            ):
                errors.extend(_check_hex_list(item.get(key), f"{prefix}.{key}"))
    summary = candidates.get("resource_refs_summary")
    if summary is not None and not isinstance(summary, dict):
        errors.append("object_shape_handler_candidates.resource_refs_summary must be an object")
    negative = candidates.get("negative_evidence")
    if not isinstance(negative, list) or not negative:
        errors.append("object_shape_handler_candidates.negative_evidence must be non-empty list")
    return errors


def check_condition_predicate_handler_candidates(candidates: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(candidates, dict):
        return ["condition_predicate_handler_candidates must be an object when present"]
    if candidates.get("schema") != "hsl_static_condition_predicate_handler_candidates.v1":
        errors.append("condition_predicate_handler_candidates.schema mismatch")
    if candidates.get("semantic_status") != "unresolved":
        errors.append("condition_predicate_handler_candidates.semantic_status must remain unresolved")
    if not str(candidates.get("static_script_action_dispatch_table", "")).startswith("0x"):
        errors.append("condition_predicate_handler_candidates.static_script_action_dispatch_table must be hex")
    actions = candidates.get("actions")
    if not isinstance(actions, list) or not actions:
        errors.append("condition_predicate_handler_candidates.actions must be non-empty list")
    else:
        if candidates.get("unique_condition_action_count") != len(actions):
            errors.append("condition_predicate_handler_candidates.unique_condition_action_count must match actions length")
        for index, action in enumerate(actions):
            prefix = f"condition_predicate_handler_candidates.actions[{index}]"
            if not isinstance(action, dict):
                errors.append(f"{prefix} must be an object")
                continue
            for key in ("action_name", "condition_type", "candidate_context_binding"):
                if not isinstance(action.get(key), str) or not action.get(key):
                    errors.append(f"{prefix}.{key} must be a non-empty string")
            errors.extend(_check_candidate_handler_common(action, prefix))
            if action.get("slot_opcode_evidence_status") != "unresolved":
                errors.append(f"{prefix}.slot_opcode_evidence_status must remain unresolved")
            if action.get("comparison_polarity_evidence_status") != "unresolved":
                errors.append(f"{prefix}.comparison_polarity_evidence_status must remain unresolved")
            if action.get("condition_handler_window_status") not in {
                "observed",
                "not_observed_in_bounded_window",
                "not_exported",
            }:
                errors.append(f"{prefix}.condition_handler_window_status invalid")
            if not isinstance(action.get("occurrence_count"), int) or action.get("occurrence_count") <= 0:
                errors.append(f"{prefix}.occurrence_count must be positive int")
            for key in ("handler_call_targets_if_order_matched", "handler_data_refs_if_order_matched"):
                errors.extend(_check_hex_list(action.get(key), f"{prefix}.{key}"))
    handler_windows = candidates.get("handler_window_summaries")
    if handler_windows is not None:
        errors.extend(check_condition_handler_window_summaries(handler_windows))
    negative = candidates.get("negative_evidence")
    if not isinstance(negative, list) or not negative:
        errors.append("condition_predicate_handler_candidates.negative_evidence must be non-empty list")
    return errors


def check_status_lifecycle_handler_candidates(candidates: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(candidates, dict):
        return ["status_lifecycle_handler_candidates must be an object when present"]
    if candidates.get("schema") != "hsl_static_status_lifecycle_handler_candidates.v1":
        errors.append("status_lifecycle_handler_candidates.schema mismatch")
    if candidates.get("semantic_status") != "unresolved":
        errors.append("status_lifecycle_handler_candidates.semantic_status must remain unresolved")
    if candidates.get("execution_policy") != "scheduled_only_no_live_mutation":
        errors.append("status_lifecycle_handler_candidates.execution_policy must remain scheduled_only_no_live_mutation")
    if candidates.get("bridge_commit_timing_status") != "unresolved":
        errors.append("status_lifecycle_handler_candidates.bridge_commit_timing_status must remain unresolved")
    actions = candidates.get("actions")
    if not isinstance(actions, list) or not actions:
        errors.append("status_lifecycle_handler_candidates.actions must be non-empty list")
    else:
        if candidates.get("action_count") != len(actions):
            errors.append("status_lifecycle_handler_candidates.action_count must match actions length")
        for index, action in enumerate(actions):
            prefix = f"status_lifecycle_handler_candidates.actions[{index}]"
            if not isinstance(action, dict):
                errors.append(f"{prefix} must be an object")
                continue
            if not isinstance(action.get("action_name"), str) or not action.get("action_name"):
                errors.append(f"{prefix}.action_name must be non-empty string")
            errors.extend(_check_candidate_handler_common(action, prefix))
            if action.get("slot_opcode_evidence_status") != "unresolved":
                errors.append(f"{prefix}.slot_opcode_evidence_status must remain unresolved")
            if action.get("commit_timing_evidence_status") != "unresolved":
                errors.append(f"{prefix}.commit_timing_evidence_status must remain unresolved")
            if action.get("lifecycle_semantic_status") != "scheduled_only":
                errors.append(f"{prefix}.lifecycle_semantic_status must remain scheduled_only")
            for key in (
                "handler_call_targets_if_order_matched",
                "handler_data_refs_if_order_matched",
                "status_handler_call_targets_until_first_ret",
                "status_handler_data_refs_until_first_ret",
            ):
                errors.extend(_check_hex_list(action.get(key), f"{prefix}.{key}"))
    handler_windows = candidates.get("handler_window_summaries")
    if handler_windows is not None:
        errors.extend(check_condition_handler_window_summaries(handler_windows))
    negative = candidates.get("negative_evidence")
    if not isinstance(negative, list) or not negative:
        errors.append("status_lifecycle_handler_candidates.negative_evidence must be non-empty list")
    return errors


def check_script_status_commit_path_static_context(context: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(context, dict):
        return ["script_status_commit_path_static_context must be an object when present"]
    if context.get("schema") != "hsl_static_script_status_commit_path_context.v1":
        errors.append("script_status_commit_path_static_context.schema mismatch")
    if context.get("semantic_status") != "unresolved":
        errors.append("script_status_commit_path_static_context.semantic_status must remain unresolved")
    if context.get("execution_policy") != "scheduled_only_no_live_mutation":
        errors.append("script_status_commit_path_static_context.execution_policy must remain scheduled_only_no_live_mutation")
    if context.get("bridge_address") != "0x450840":
        errors.append("script_status_commit_path_static_context.bridge_address must be 0x450840")
    if context.get("script_primary_dispatch_table") != "0x453708":
        errors.append("script_status_commit_path_static_context.script_primary_dispatch_table must be 0x453708")
    if context.get("script_action_dispatch_table") != "0x4537f4":
        errors.append("script_status_commit_path_static_context.script_action_dispatch_table must be 0x4537f4")
    for key in ("deferred_queue_candidate_status", "registry_write_status", "status_mutation_commit_timing_status"):
        if context.get(key) != "unresolved":
            errors.append(f"script_status_commit_path_static_context.{key} must remain unresolved")
    if context.get("direct_deferred_queue_write_status") not in {
        "observed_in_prioritized_callee_windows",
        "not_observed_in_prioritized_callee_windows",
    }:
        errors.append("script_status_commit_path_static_context.direct_deferred_queue_write_status invalid")
    if context.get("direct_status_registry_write_status") != "not_observed_in_prioritized_callee_windows":
        errors.append("script_status_commit_path_static_context.direct_status_registry_write_status must remain bounded negative")
    errors.extend(_check_hex_list(context.get("direct_deferred_queue_write_addresses"), "script_status_commit_path_static_context.direct_deferred_queue_write_addresses"))
    errors.extend(_check_hex_list(context.get("runtime_flag_write_addresses"), "script_status_commit_path_static_context.runtime_flag_write_addresses"))
    xrefs = context.get("bridge_xrefs")
    if not isinstance(xrefs, list) or not xrefs:
        errors.append("script_status_commit_path_static_context.bridge_xrefs must be non-empty list")
    else:
        for index, xref in enumerate(xrefs):
            prefix = f"script_status_commit_path_static_context.bridge_xrefs[{index}]"
            if not isinstance(xref, dict):
                errors.append(f"{prefix} must be an object")
                continue
            if not str(xref.get("from_address", "")).startswith("0x"):
                errors.append(f"{prefix}.from_address must be hex")
            if xref.get("type") != "CALL":
                errors.append(f"{prefix}.type must be CALL")
    body = context.get("bridge_body_summary")
    if not isinstance(body, dict):
        errors.append("script_status_commit_path_static_context.bridge_body_summary must be an object")
    else:
        if not isinstance(body.get("op_count"), int) or body.get("op_count") <= 0:
            errors.append("script_status_commit_path_static_context.bridge_body_summary.op_count must be positive int")
        if not isinstance(body.get("call_target_count"), int) or body.get("call_target_count") <= 0:
            errors.append("script_status_commit_path_static_context.bridge_body_summary.call_target_count must be positive int")
        errors.extend(_check_hex_list(body.get("data_ref_addresses"), "script_status_commit_path_static_context.bridge_body_summary.data_ref_addresses"))
        top_calls = body.get("top_call_targets")
        if not isinstance(top_calls, list):
            errors.append("script_status_commit_path_static_context.bridge_body_summary.top_call_targets must be a list")
        else:
            for index, call in enumerate(top_calls):
                prefix = f"script_status_commit_path_static_context.bridge_body_summary.top_call_targets[{index}]"
                if not isinstance(call, dict):
                    errors.append(f"{prefix} must be an object")
                    continue
                if not str(call.get("callee_address", "")).startswith("0x"):
                    errors.append(f"{prefix}.callee_address must be hex")
                if not isinstance(call.get("call_count"), int) or call.get("call_count") <= 0:
                    errors.append(f"{prefix}.call_count must be positive int")
    cursor = context.get("script_cursor_progress")
    if not isinstance(cursor, dict):
        errors.append("script_status_commit_path_static_context.script_cursor_progress must be an object")
    else:
        if cursor.get("script_cursor_field_offset") != "0x90":
            errors.append("script_status_commit_path_static_context.script_cursor_progress.script_cursor_field_offset must be 0x90")
        if cursor.get("commit_boundary_status") != "script_cursor_progress_observed":
            errors.append("script_status_commit_path_static_context.script_cursor_progress.commit_boundary_status invalid")
        if cursor.get("status_mutation_commit_status") != "unresolved":
            errors.append("script_status_commit_path_static_context.script_cursor_progress.status_mutation_commit_status must remain unresolved")
        for key in ("script_cursor_write_addresses_sample", "token_advance_addresses_sample", "argument_scratch_field_offsets"):
            errors.extend(_check_hex_list(cursor.get(key), f"script_status_commit_path_static_context.script_cursor_progress.{key}"))
        if not isinstance(cursor.get("script_cursor_write_count"), int) or cursor.get("script_cursor_write_count") <= 0:
            errors.append("script_status_commit_path_static_context.script_cursor_progress.script_cursor_write_count must be positive int")
    callers = context.get("caller_window_summaries")
    if not isinstance(callers, list) or not callers:
        errors.append("script_status_commit_path_static_context.caller_window_summaries must be non-empty list")
    else:
        for index, caller in enumerate(callers):
            prefix = f"script_status_commit_path_static_context.caller_window_summaries[{index}]"
            if not isinstance(caller, dict):
                errors.append(f"{prefix} must be an object")
                continue
            if caller.get("semantic_status") != "unresolved":
                errors.append(f"{prefix}.semantic_status must remain unresolved")
            if not str(caller.get("address", "")).startswith("0x"):
                errors.append(f"{prefix}.address must be hex")
            for key in (
                "bridge_call_addresses",
                "call_target_addresses",
                "data_ref_addresses",
                "candidate_deferred_queue_global_refs",
                "candidate_runtime_flag_global_refs",
                "cleanup_or_followup_call_addresses",
            ):
                errors.extend(_check_hex_list(caller.get(key), f"{prefix}.{key}"))
    callees = context.get("callee_window_summaries")
    if not isinstance(callees, list):
        errors.append("script_status_commit_path_static_context.callee_window_summaries must be a list")
    else:
        for index, callee in enumerate(callees):
            prefix = f"script_status_commit_path_static_context.callee_window_summaries[{index}]"
            if not isinstance(callee, dict):
                errors.append(f"{prefix} must be an object")
                continue
            if callee.get("semantic_status") != "unresolved":
                errors.append(f"{prefix}.semantic_status must remain unresolved")
            if callee.get("direct_status_registry_write_status") != "not_observed_in_bounded_window":
                errors.append(f"{prefix}.direct_status_registry_write_status must remain bounded negative")
            if not str(callee.get("address", "")).startswith("0x"):
                errors.append(f"{prefix}.address must be hex")
            for key in (
                "call_target_addresses",
                "data_ref_addresses",
                "global_write_addresses",
                "object_write_offsets",
                "candidate_deferred_queue_global_refs",
                "candidate_deferred_queue_global_writes",
                "candidate_runtime_flag_global_refs",
                "candidate_runtime_flag_global_writes",
            ):
                errors.extend(_check_hex_list(callee.get(key), f"{prefix}.{key}"))
    boundaries = context.get("status_handler_boundary_candidates")
    if not isinstance(boundaries, list):
        errors.append("script_status_commit_path_static_context.status_handler_boundary_candidates must be a list")
    else:
        for index, item in enumerate(boundaries):
            prefix = f"script_status_commit_path_static_context.status_handler_boundary_candidates[{index}]"
            if not isinstance(item, dict):
                errors.append(f"{prefix} must be an object")
                continue
            if item.get("correlation_status") != "unresolved":
                errors.append(f"{prefix}.correlation_status must remain unresolved")
            if item.get("ordinal_as_slot_status") != "not_evidence":
                errors.append(f"{prefix}.ordinal_as_slot_status must be not_evidence")
            if item.get("commit_timing_evidence_status") != "unresolved":
                errors.append(f"{prefix}.commit_timing_evidence_status must remain unresolved")
            handler = item.get("candidate_handler_if_order_matched")
            if handler is not None and (not isinstance(handler, str) or not handler.startswith("0x")):
                errors.append(f"{prefix}.candidate_handler_if_order_matched must be hex or null")
            for key in ("handler_call_targets_if_order_matched", "handler_data_refs_if_order_matched"):
                errors.extend(_check_hex_list(item.get(key), f"{prefix}.{key}"))
    negative = context.get("negative_evidence")
    if not isinstance(negative, list) or not negative:
        errors.append("script_status_commit_path_static_context.negative_evidence must be non-empty list")
    if not isinstance(context.get("playable_blocker_helped"), str) or not context.get("playable_blocker_helped"):
        errors.append("script_status_commit_path_static_context.playable_blocker_helped must be non-empty string")
    return errors


def check_script_numeric_dispatch_token_context(context: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(context, dict):
        return ["script_numeric_dispatch_token_context must be an object when present"]
    if context.get("schema") != "hsl_static_script_numeric_dispatch_token_context.v1":
        errors.append("script_numeric_dispatch_token_context.schema mismatch")
    if context.get("semantic_status") != "numeric_token_source_observed_handler_name_mapping_unresolved":
        errors.append("script_numeric_dispatch_token_context.semantic_status invalid")
    if context.get("source_numeric_token_status") != "observed_in_0x450840_bridge":
        errors.append("script_numeric_dispatch_token_context.source_numeric_token_status invalid")
    if context.get("action_name_mapping_status") != "unresolved":
        errors.append("script_numeric_dispatch_token_context.action_name_mapping_status must remain unresolved")
    if context.get("handler_identity_status") != "unresolved":
        errors.append("script_numeric_dispatch_token_context.handler_identity_status must remain unresolved")
    if context.get("status_lifecycle_upgrade_status") != "not_evidence":
        errors.append("script_numeric_dispatch_token_context.status_lifecycle_upgrade_status must remain not_evidence")
    if context.get("bridge_address") != "0x450840":
        errors.append("script_numeric_dispatch_token_context.bridge_address must be 0x450840")
    primary = context.get("primary_dispatch")
    if not isinstance(primary, dict):
        errors.append("script_numeric_dispatch_token_context.primary_dispatch must be an object")
    else:
        expected = {
            "selector_source_field_offset": "0x8e",
            "selector_source_width": "word",
            "max_selector_value": "0x8b",
            "remap_table_address": "0x453768",
            "dispatch_table_address": "0x453708",
            "dispatch_slot_source": "remapped_selector_byte",
        }
        for key, value in expected.items():
            if primary.get(key) != value:
                errors.append(f"script_numeric_dispatch_token_context.primary_dispatch.{key} must be {value}")
        if primary.get("remap_table_read_status") != "observed":
            errors.append("script_numeric_dispatch_token_context.primary_dispatch.remap_table_read_status must be observed")
        for key in ("dispatch_table_observed_slots", "dispatch_table_unique_handlers"):
            if not isinstance(primary.get(key), int) or primary.get(key) <= 0:
                errors.append(f"script_numeric_dispatch_token_context.primary_dispatch.{key} must be positive int")
    action = context.get("action_dispatch")
    if not isinstance(action, dict):
        errors.append("script_numeric_dispatch_token_context.action_dispatch must be an object")
    else:
        expected = {
            "script_cursor_field_offset": "0x90",
            "token_read_offset_from_cursor": "0x0",
            "token_source_width": "dword",
            "max_token_value": "0x8b",
            "dispatch_table_address": "0x4537f4",
            "dispatch_slot_source": "script_token_value_direct",
        }
        for key, value in expected.items():
            if action.get(key) != value:
                errors.append(f"script_numeric_dispatch_token_context.action_dispatch.{key} must be {value}")
        if action.get("cursor_advance_bytes") != 4:
            errors.append("script_numeric_dispatch_token_context.action_dispatch.cursor_advance_bytes must be 4")
        for key in ("dispatch_table_observed_slots", "dispatch_table_unique_handlers"):
            if not isinstance(action.get(key), int) or action.get(key) <= 0:
                errors.append(f"script_numeric_dispatch_token_context.action_dispatch.{key} must be positive int")
    loop = context.get("loop_reentry")
    if not isinstance(loop, dict):
        errors.append("script_numeric_dispatch_token_context.loop_reentry must be an object")
    else:
        if loop.get("script_cursor_field_offset") != "0x90":
            errors.append("script_numeric_dispatch_token_context.loop_reentry.script_cursor_field_offset must be 0x90")
        for key in (
            "loop_token_read_address",
            "loop_cursor_advance_address",
            "loop_bounds_check_address",
            "loop_dispatch_reentry_target",
            "script_cursor_commit_address",
        ):
            if not str(loop.get(key, "")).startswith("0x"):
                errors.append(f"script_numeric_dispatch_token_context.loop_reentry.{key} must be hex")
    negative = context.get("negative_evidence")
    if not isinstance(negative, list) or not negative:
        errors.append("script_numeric_dispatch_token_context.negative_evidence must be non-empty list")
    return errors


def check_ui_owner_traversal_static_context(context: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(context, dict):
        return ["ui_owner_traversal_static_context must be an object when present"]
    if context.get("schema") != "hsl_static_ui_owner_traversal_context.v1":
        errors.append("ui_owner_traversal_static_context.schema mismatch")
    for key in ("semantic_status", "owner_traversal_status", "command_identity_status"):
        if context.get(key) != "unresolved":
            errors.append(f"ui_owner_traversal_static_context.{key} must remain unresolved")
    hit = context.get("hit_test_window")
    if not isinstance(hit, dict):
        errors.append("ui_owner_traversal_static_context.hit_test_window must be an object")
    else:
        if hit.get("address") != "0x445977":
            errors.append("ui_owner_traversal_static_context.hit_test_window.address must be 0x445977")
        if not isinstance(hit.get("op_count"), int) or hit.get("op_count") < 0:
            errors.append("ui_owner_traversal_static_context.hit_test_window.op_count must be non-negative int")
        for key in ("call_target_addresses", "data_ref_addresses", "cursor_global_refs", "input_global_refs", "object_like_offsets"):
            errors.extend(_check_hex_list(hit.get(key), f"ui_owner_traversal_static_context.hit_test_window.{key}"))
        branches = hit.get("conditional_branch_edges")
        if not isinstance(branches, list):
            errors.append("ui_owner_traversal_static_context.hit_test_window.conditional_branch_edges must be a list")
    hints = context.get("ui_resource_navigation_hints")
    if not isinstance(hints, dict):
        errors.append("ui_owner_traversal_static_context.ui_resource_navigation_hints must be an object")
    else:
        if hints.get("owner_semantics_status") != "unresolved":
            errors.append("ui_owner_traversal_static_context.ui_resource_navigation_hints.owner_semantics_status must remain unresolved")
        if hints.get("command_identity_status") != "unresolved":
            errors.append("ui_owner_traversal_static_context.ui_resource_navigation_hints.command_identity_status must remain unresolved")
    related = context.get("related_window_summaries")
    if not isinstance(related, list):
        errors.append("ui_owner_traversal_static_context.related_window_summaries must be a list")
    else:
        for index, window in enumerate(related):
            prefix = f"ui_owner_traversal_static_context.related_window_summaries[{index}]"
            if not isinstance(window, dict):
                errors.append(f"{prefix} must be an object")
                continue
            if not isinstance(window.get("id"), str) or not window.get("id"):
                errors.append(f"{prefix}.id must be non-empty string")
            if not str(window.get("address", "")).startswith("0x"):
                errors.append(f"{prefix}.address must be hex")
            if window.get("semantic_status") != "unresolved":
                errors.append(f"{prefix}.semantic_status must remain unresolved")
            if window.get("owner_contract_status") != "unresolved":
                errors.append(f"{prefix}.owner_contract_status must remain unresolved")
            for key in ("call_target_addresses", "data_ref_addresses", "object_read_offsets", "object_write_offsets"):
                errors.extend(_check_hex_list(window.get(key), f"{prefix}.{key}"))
    contract_hints = context.get("contract_navigation_hints")
    if not isinstance(contract_hints, list):
        errors.append("ui_owner_traversal_static_context.contract_navigation_hints must be a list")
    else:
        for index, hint in enumerate(contract_hints):
            prefix = f"ui_owner_traversal_static_context.contract_navigation_hints[{index}]"
            if not isinstance(hint, dict):
                errors.append(f"{prefix} must be an object")
                continue
            for key in ("candidate", "source_window", "static_signal", "why_playable"):
                if not isinstance(hint.get(key), str) or not hint.get(key):
                    errors.append(f"{prefix}.{key} must be non-empty string")
            if hint.get("semantic_status") != "unresolved":
                errors.append(f"{prefix}.semantic_status must remain unresolved")
    if not isinstance(context.get("playable_blocker_helped"), str) or not context.get("playable_blocker_helped"):
        errors.append("ui_owner_traversal_static_context.playable_blocker_helped must be non-empty string")
    blocking = context.get("blocking_placement_navigation_note")
    if not isinstance(blocking, dict):
        errors.append("ui_owner_traversal_static_context.blocking_placement_navigation_note must be an object")
    else:
        if blocking.get("semantic_status") != "unresolved":
            errors.append("ui_owner_traversal_static_context.blocking_placement_navigation_note.semantic_status must remain unresolved")
        if blocking.get("relationship_to_ui_hit_test") != "not_joined":
            errors.append("ui_owner_traversal_static_context.blocking_placement_navigation_note.relationship_to_ui_hit_test must remain not_joined")
    negative = context.get("negative_evidence")
    if not isinstance(negative, list) or not negative:
        errors.append("ui_owner_traversal_static_context.negative_evidence must be non-empty list")
    return errors


def check_player_control_action_menu_context(context: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(context, dict):
        return ["player_control_action_menu_static_context must be an object when present"]
    if context.get("schema") != "hsl_static_player_control_action_menu_context.v1":
        errors.append("player_control_action_menu_static_context.schema mismatch")
    if context.get("evidence_tier") != "static_context_only":
        errors.append("player_control_action_menu_static_context.evidence_tier must be static_context_only")
    if context.get("interpretation_status") != "runtime_transition_unproven":
        errors.append("player_control_action_menu_static_context.interpretation_status must remain runtime_transition_unproven")
    flow = context.get("static_flow")
    if not isinstance(flow, list) or len(flow) < 4:
        errors.append("player_control_action_menu_static_context.static_flow must include the input/menu/ui/script bridge steps")
    else:
        step_ids = {step.get("step") for step in flow if isinstance(step, dict)}
        required = {"input_aggregate", "menu_state_loop", "logical_ui_hit_test", "script_bridge_entry"}
        missing = required - step_ids
        if missing:
            errors.append(f"player_control_action_menu_static_context missing steps: {sorted(missing)}")
        for index, step in enumerate(flow):
            prefix = f"player_control_action_menu_static_context.static_flow[{index}]"
            if not isinstance(step, dict):
                errors.append(f"{prefix} must be an object")
                continue
            if not str(step.get("address", "")).startswith("0x"):
                errors.append(f"{prefix}.address must be hex")
    negative = context.get("negative_evidence")
    if not isinstance(negative, list) or not negative:
        errors.append("player_control_action_menu_static_context.negative_evidence must be non-empty list")
    return errors


def check_resource_object_static_question_context(context: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(context, dict):
        return ["resource_object_static_question_context must be an object when present"]
    if context.get("schema") != "hsl_static_resource_object_question_context.v1":
        errors.append("resource_object_static_question_context.schema mismatch")
    if context.get("interpretation_status") != "unresolved":
        errors.append("resource_object_static_question_context.interpretation_status must remain unresolved")
    questions = context.get("questions")
    if not isinstance(questions, list) or not questions:
        errors.append("resource_object_static_question_context.questions must be non-empty list")
    else:
        ids = {item.get("id") for item in questions if isinstance(item, dict)}
        required = {
            "obj_shape_number_semantics",
            "object_owner_traversal_semantics",
            "actor_sprite_template_or_global_definition",
        }
        missing = required - ids
        if missing:
            errors.append(f"resource_object_static_question_context missing questions: {sorted(missing)}")
        for index, item in enumerate(questions):
            prefix = f"resource_object_static_question_context.questions[{index}]"
            if not isinstance(item, dict):
                errors.append(f"{prefix} must be an object")
                continue
            anchors = item.get("static_anchors")
            errors.extend(_check_hex_list(anchors, f"{prefix}.static_anchors"))
            for key in ("question", "current_evidence", "next_static_need"):
                if not isinstance(item.get(key), str) or not item.get(key):
                    errors.append(f"{prefix}.{key} must be a non-empty string")
    negative = context.get("negative_evidence")
    if not isinstance(negative, list) or not negative:
        errors.append("resource_object_static_question_context.negative_evidence must be non-empty list")
    return errors


def check_resource_provenance_static_classification(classification: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(classification, dict):
        return ["resource_provenance_static_classification must be an object when present"]
    if classification.get("schema") != "hsl_static_resource_provenance_classification.v1":
        errors.append("resource_provenance_static_classification.schema mismatch")
    if classification.get("semantic_status") != "unresolved":
        errors.append("resource_provenance_static_classification.semantic_status must remain unresolved")
    entries = classification.get("classifications")
    if not isinstance(entries, list):
        errors.append("resource_provenance_static_classification.classifications must be a list")
    else:
        if classification.get("unresolved_shape_ref_count") != len(entries):
            errors.append("resource_provenance_static_classification.unresolved_shape_ref_count must match classifications length")
        for index, item in enumerate(entries):
            prefix = f"resource_provenance_static_classification.classifications[{index}]"
            if not isinstance(item, dict):
                errors.append(f"{prefix} must be an object")
                continue
            if not isinstance(item.get("resource_id"), str) or not item.get("resource_id"):
                errors.append(f"{prefix}.resource_id must be non-empty string")
            if not isinstance(item.get("static_provenance_class"), str) or not item.get("static_provenance_class"):
                errors.append(f"{prefix}.static_provenance_class must be non-empty string")
            if item.get("runtime_usage_status") != "unresolved":
                errors.append(f"{prefix}.runtime_usage_status must remain unresolved")
            if item.get("global_asset_status") != "unresolved":
                errors.append(f"{prefix}.global_asset_status must remain unresolved")
            if item.get("unused_definition_status") != "unresolved":
                errors.append(f"{prefix}.unused_definition_status must remain unresolved")
            if item.get("missing_archive_root_status") != "candidate":
                errors.append(f"{prefix}.missing_archive_root_status must remain candidate")
            roots = item.get("searched_payload_roots")
            if not isinstance(roots, list) or not roots:
                errors.append(f"{prefix}.searched_payload_roots must be non-empty list")
    color_note = classification.get("color_header_0x10_static_note")
    if not isinstance(color_note, dict):
        errors.append("resource_provenance_static_classification.color_header_0x10_static_note must be an object")
    elif color_note.get("semantic_status") != "unresolved":
        errors.append("resource_provenance_static_classification.color_header_0x10_static_note.semantic_status must remain unresolved")
    negative = classification.get("negative_evidence")
    if not isinstance(negative, list) or not negative:
        errors.append("resource_provenance_static_classification.negative_evidence must be non-empty list")
    return errors


def check_map_object_visibility_static_context(context: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(context, dict):
        return ["map_object_visibility_static_context must be an object when present"]
    if context.get("schema") != "hsl_static_map_object_visibility_context.v1":
        errors.append("map_object_visibility_static_context.schema mismatch")
    if context.get("semantic_status") != "unresolved":
        errors.append("map_object_visibility_static_context.semantic_status must remain unresolved")
    expected_statuses = {
        "obj_plane_status": "parser_field_ingestion_observed_render_sorting_unresolved",
        "stand_object_traversal_status": "candidate_scene_draw_window_observed_owner_semantics_unresolved",
        "shape_number_semantics_status": "unresolved_navigation_candidate_only",
        "occlusion_sorting_status": "unresolved_no_direct_tree_fire_bar_unit_occlusion_proof",
    }
    for key, expected in expected_statuses.items():
        if context.get(key) != expected:
            errors.append(f"map_object_visibility_static_context.{key} must be {expected}")

    scope = context.get("resource_scope")
    if not isinstance(scope, dict):
        errors.append("map_object_visibility_static_context.resource_scope must be an object")
    else:
        if scope.get("status") not in {"loaded", "missing"}:
            errors.append("map_object_visibility_static_context.resource_scope.status must be loaded or missing")
        if not isinstance(scope.get("target_resources"), list):
            errors.append("map_object_visibility_static_context.resource_scope.target_resources must be a list")
        for index, resource in enumerate(scope.get("target_resources", []) if isinstance(scope.get("target_resources"), list) else []):
            prefix = f"map_object_visibility_static_context.resource_scope.target_resources[{index}]"
            if not isinstance(resource, dict):
                errors.append(f"{prefix} must be an object")
                continue
            if not isinstance(resource.get("resource_id"), str) or not resource.get("resource_id"):
                errors.append(f"{prefix}.resource_id must be non-empty string")
            if not isinstance(resource.get("placed_instance_count"), int) or resource.get("placed_instance_count") < 0:
                errors.append(f"{prefix}.placed_instance_count must be non-negative int")
            for key in ("object_codes", "shape_number_candidates", "obj_plane_candidates", "user_confirmed_roles"):
                if not isinstance(resource.get(key), list):
                    errors.append(f"{prefix}.{key} must be a list")

    parser = context.get("parser_field_ingestion")
    if not isinstance(parser, dict):
        errors.append("map_object_visibility_static_context.parser_field_ingestion must be an object")
    else:
        if parser.get("window_address") != "0x45dc5c":
            errors.append("map_object_visibility_static_context.parser_field_ingestion.window_address must be 0x45dc5c")
        if not isinstance(parser.get("observed_field_count"), int) or parser.get("observed_field_count") < 0:
            errors.append("map_object_visibility_static_context.parser_field_ingestion.observed_field_count must be non-negative int")
        for key in ("target_fields_observed", "missing_target_fields", "field_reference_order"):
            if not isinstance(parser.get(key), list):
                errors.append(f"map_object_visibility_static_context.parser_field_ingestion.{key} must be a list")
        for index, ref in enumerate(parser.get("field_reference_order", []) if isinstance(parser.get("field_reference_order"), list) else []):
            prefix = f"map_object_visibility_static_context.parser_field_ingestion.field_reference_order[{index}]"
            if not isinstance(ref, dict):
                errors.append(f"{prefix} must be an object")
                continue
            if not isinstance(ref.get("field_name"), str) or not ref.get("field_name"):
                errors.append(f"{prefix}.field_name must be non-empty string")
            for key in ("string_address", "reference_address"):
                if not str(ref.get(key, "")).startswith("0x"):
                    errors.append(f"{prefix}.{key} must be hex")

    draw = context.get("draw_or_traversal_candidate")
    if not isinstance(draw, dict):
        errors.append("map_object_visibility_static_context.draw_or_traversal_candidate must be an object")
    else:
        if draw.get("window_address") != "0x456150":
            errors.append("map_object_visibility_static_context.draw_or_traversal_candidate.window_address must be 0x456150")
        if draw.get("semantic_status") != "unresolved":
            errors.append("map_object_visibility_static_context.draw_or_traversal_candidate.semantic_status must remain unresolved")
        for key in (
            "object_like_offsets",
            "object_write_offsets",
            "shp_related_call_targets",
            "camera_or_view_global_refs",
            "clip_or_anchor_candidate_offsets",
        ):
            errors.extend(_check_hex_list(draw.get(key), f"map_object_visibility_static_context.draw_or_traversal_candidate.{key}"))

    for list_key in ("render_path_windows", "window_summaries"):
        windows = context.get(list_key)
        if not isinstance(windows, list):
            errors.append(f"map_object_visibility_static_context.{list_key} must be a list")
            continue
        for index, window in enumerate(windows):
            prefix = f"map_object_visibility_static_context.{list_key}[{index}]"
            if not isinstance(window, dict):
                errors.append(f"{prefix} must be an object")
                continue
            if not isinstance(window.get("id"), str) or not window.get("id"):
                errors.append(f"{prefix}.id must be non-empty string")
            if not str(window.get("address", "")).startswith("0x"):
                errors.append(f"{prefix}.address must be hex")
            if window.get("semantic_status") != "unresolved":
                errors.append(f"{prefix}.semantic_status must remain unresolved")
            if not isinstance(window.get("op_count"), int) or window.get("op_count") < 0:
                errors.append(f"{prefix}.op_count must be non-negative int")
            for key in (
                "call_target_addresses",
                "data_ref_addresses",
                "object_like_offsets",
                "object_write_offsets",
                "global_write_addresses",
                "shp_related_call_targets",
            ):
                errors.extend(_check_hex_list(window.get(key), f"{prefix}.{key}"))

    godot = context.get("godot_consumable_fields")
    if not isinstance(godot, dict):
        errors.append("map_object_visibility_static_context.godot_consumable_fields must be an object")
    else:
        for key in (
            "can_keep_resource_preview_and_role_labels",
            "can_surface_obj_plane_as_parser_ingested_candidate",
            "can_surface_shape_number_as_parser_ingested_candidate",
            "must_keep_layer_sorting_occlusion_anchor_clip_unresolved",
        ):
            if godot.get(key) is not True:
                errors.append(f"map_object_visibility_static_context.godot_consumable_fields.{key} must be true")
    negative = context.get("negative_evidence")
    if not isinstance(negative, list) or len(negative) < 3:
        errors.append("map_object_visibility_static_context.negative_evidence must contain bounded negative evidence")
    if not isinstance(context.get("next_static_need"), str) or not context.get("next_static_need"):
        errors.append("map_object_visibility_static_context.next_static_need must be non-empty string")
    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Check tracked HSL static compact index.")
    parser.add_argument("index_json", type=Path)
    args = parser.parse_args(argv)
    errors = check_static_index(args.index_json)
    if errors:
        print(f"FAIL hsl static index ({len(errors)} error(s))")
        for error in errors[:8]:
            print(f"- {error}")
        if len(errors) > 8:
            print(f"- ... {len(errors) - 8} more")
        return 1
    print("PASS hsl static index")
    return 0


class StaticIndexCheckTask(CheckTask):
    name = 'static_index_check'
    family = 'checks'
    inputs = ('content/generated/hsl/static/hsl01/index.json',)
    replaces = ('tools/hsl_static_index_check.py content/generated/hsl/static/hsl01/index.json',)
    scripts = ('tools/hsltools/checks/static_index.py',)

    def check(self, ctx: Context) -> str:
        return printed_last_line(main, ['content/generated/hsl/static/hsl01/index.json'])


def tasks() -> list[StaticIndexCheckTask]:
    return [StaticIndexCheckTask()]


if __name__ == '__main__':
    raise SystemExit(main())
