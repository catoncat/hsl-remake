#!/usr/bin/env python3
from __future__ import annotations

import argparse
import collections
import json
from pathlib import Path
from typing import Any


SCHEMA = "hsl_chapter01_script_vm_semantics.v1"
CONDITION_ACTIONS = {
    "actCheckEnemyTotalNumber": "enemy_total_number_check",
    "actCheckEnemyNumber": "enemy_object_number_check",
    "actCheckPlayerArrivePos": "player_arrive_position_check",
    "actCheckPlayer": "player_state_check",
    "actCheckRoundNumber": "round_number_check",
}
STATUS_INSERT_ACTIONS = {
    "actInsertFailStatus": "fail",
    "actInsertEventStatus": "event",
    "actInsertWinStatus": "win",
}
STATUS_DELETE_ACTIONS = {
    "actDeleteEventStatus": "event",
}
ACTION_CATEGORY_BY_NAME = {
    "actMessage": "message",
    "actMessageIfExist": "message",
    "actSetDeadMessage": "message",
    "actWalkDispWait": "movement",
    "actWalkPrevInsertObjectWait": "movement",
    "actWalkAndDeleteWait": "movement",
    "actInsertObject": "object",
    "actChangePrevInsertObjectID": "object",
    "actDeleteShowPosObject": "object",
    "actInsertShowPosObject": "object",
    "actScrollBGToPos": "camera",
    "actShowSectionName": "ui",
    "actShowWinFailStatus": "ui",
    "actKeepPlayerST": "flow",
    "actSetNextPlayLevelEvent": "flow",
    "actDelay": "timing",
    "actPlayLevelMusic": "audio",
}
NUMERIC_OPCODE_FIELD_NAMES = {
    "opcode",
    "op_code",
    "numeric_opcode",
    "action_opcode",
    "raw_opcode",
    "script_opcode",
    "dispatch_opcode",
    "token_id",
    "numeric_token",
    "raw_token",
    "dispatch_slot",
    "slot",
}
CONDITION_PREDICATE_CANDIDATES = {
    "actCheckEnemyTotalNumber": {
        "args_schema_candidate": ["enemy_total_candidate"],
        "candidate_context_binding": "enemy_total",
        "runtime_probe_priority": "defer_until_enemy_count_transition_probe",
        "exe_static_question": "identify the 0x4537f4 handler slot/opcode and confirm whether arg0 is compared to live enemy total",
        "runtime_question": "capture before/after around an enemy-total-changing UI moment once battle kill/removal probes exist",
    },
    "actCheckEnemyNumber": {
        "args_schema_candidate": ["object_or_group_id", "count_candidate"],
        "candidate_context_binding": "enemy_counts[object_or_group_id]",
        "runtime_probe_priority": "defer_until_enemy_group_count_transition_probe",
        "exe_static_question": "identify the 0x4537f4 handler slot/opcode and confirm whether arg0 indexes object/group identity and arg1 is a count compare",
        "runtime_question": "capture player_control snapshots before/after a known enemy group count changes; use an exact UI/state moment label",
    },
    "actCheckPlayerArrivePos": {
        "args_schema_candidate": ["player_id", "unknown_arg1", "x1", "y1", "x2", "y2"],
        "candidate_context_binding": "player_positions[player_id]",
        "runtime_probe_priority": "defer_until_player_position_transition_probe",
        "exe_static_question": "identify the 0x4537f4 handler slot/opcode and confirm coordinate space, rect inclusivity, and meaning of arg1",
        "runtime_question": "capture player position/cursor/map coordinate scalars around the exact arrive-position objective moment",
    },
    "actCheckPlayer": {
        "args_schema_candidate": ["state_or_mode_candidate", "player_id"],
        "candidate_context_binding": "player_states[player_id]",
        "runtime_probe_priority": "defer_until_player_state_transition_probe",
        "exe_static_question": "identify the 0x4537f4 handler slot/opcode and confirm whether arg0 is alive/dead/state mode for player arg1",
        "runtime_question": "capture before/after around a player-state-changing moment once unit/player state scalars are known",
    },
    "actCheckRoundNumber": {
        "args_schema_candidate": ["round_number_candidate"],
        "candidate_context_binding": "round_number",
        "runtime_probe_priority": "defer_until_round_transition_probe",
        "exe_static_question": "identify the 0x4537f4 handler slot/opcode and confirm round counter comparison polarity",
        "runtime_question": "capture before/after around a round increment using explicit round-change UI/state moment, not a generic script execution phase label",
    },
}


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(doc: dict[str, Any], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def script_path_for_entry(index_path: Path, entry: dict[str, Any]) -> Path:
    file_name = entry.get("file")
    if isinstance(file_name, str) and file_name:
        return index_path.parent / file_name
    path_value = str(entry.get("path", ""))
    if path_value.startswith("res://"):
        return Path(path_value.removeprefix("res://"))
    raise ValueError(f"script entry lacks file/path: {entry!r}")


def load_scripts(index_path: Path) -> tuple[dict[str, Any], dict[str, dict[str, Any]]]:
    index = load_json(index_path)
    scripts: dict[str, dict[str, Any]] = {}
    for entry in index.get("scripts", []):
        if not isinstance(entry, dict):
            continue
        script = load_json(script_path_for_entry(index_path, entry))
        scripts[str(script.get("id", entry.get("id", "")))] = script
    return index, scripts


def iter_chain_actions(script: dict[str, Any]) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for section in script.get("sections", []):
        if not isinstance(section, dict):
            continue
        for action in section.get("actions", []):
            if not isinstance(action, dict):
                continue
            for chain_index, item in enumerate(action.get("chain", [])):
                if not isinstance(item, dict):
                    continue
                records.append(
                    {
                        "script_id": script.get("id"),
                        "source_file": script.get("source_file"),
                        "section_index": section.get("index"),
                        "section_name": section.get("name"),
                        "section_type": section.get("type", section.get("name")),
                        "section_codes": section.get("codes", []),
                        "section_messages": section.get("messages", []),
                        "action_index": action.get("index"),
                        "chain_index": chain_index,
                        "primary": action.get("primary"),
                        "name": item.get("name"),
                        "args": item.get("args", []),
                        "evidence_tier": "resource-derived",
                    }
                )
    return records


def status_id_from_args(args: Any) -> str | None:
    if not isinstance(args, list) or not args:
        return None
    return str(args[0])


def section_status_id(section: dict[str, Any]) -> str | None:
    codes = section.get("codes", [])
    if isinstance(codes, list) and codes:
        return str(codes[0])
    return None


def classify_condition(record: dict[str, Any]) -> dict[str, Any]:
    name = str(record.get("name", ""))
    args = [str(arg) for arg in record.get("args", [])]
    result = {
        "name": name,
        "condition_type": CONDITION_ACTIONS.get(name, "unknown_condition"),
        "args": args,
        "source": action_source(record),
        "evidence_tier": "resource-derived",
        "unresolved_semantics": [
            "condition action is resource-derived; exact truth predicate and comparison semantics require static/runtime evidence",
        ],
    }
    if name == "actCheckRoundNumber" and args:
        result["round_number_candidate"] = args[0]
    elif name == "actCheckEnemyNumber" and len(args) >= 2:
        result["object_or_group_id_candidate"] = args[0]
        result["count_candidate"] = args[1]
    elif name == "actCheckEnemyTotalNumber" and args:
        result["enemy_total_candidate"] = args[0]
    elif name == "actCheckPlayerArrivePos" and len(args) >= 6:
        result["player_id_candidate"] = args[0]
        result["position_rect_candidate"] = {
            "x1": args[2],
            "y1": args[3],
            "x2": args[4],
            "y2": args[5],
            "coordinate_semantics": "resource-derived position args; not proven Godot grid or screen coordinates",
        }
    elif name == "actCheckPlayer" and len(args) >= 2:
        result["state_or_mode_candidate"] = args[0]
        result["player_id_candidate"] = args[1]
    return result


def classify_mutation(record: dict[str, Any]) -> dict[str, Any] | None:
    name = str(record.get("name", ""))
    status_kind = STATUS_INSERT_ACTIONS.get(name) or STATUS_DELETE_ACTIONS.get(name)
    if status_kind is None:
        return None
    operation = "insert" if name in STATUS_INSERT_ACTIONS else "delete"
    return {
        "name": name,
        "operation": operation,
        "status_kind": status_kind,
        "status_id": status_id_from_args(record.get("args")),
        "args": [str(arg) for arg in record.get("args", [])],
        "source": action_source(record),
        "evidence_tier": "resource-derived",
        "unresolved_semantics": [
            "status mutation preserves script token order; enabled/disabled lifecycle timing is dry-run only",
        ],
    }


def action_source(record: dict[str, Any]) -> dict[str, Any]:
    return {
        "script_id": record.get("script_id"),
        "source_file": record.get("source_file"),
        "section_index": record.get("section_index"),
        "section_name": record.get("section_name"),
        "section_type": record.get("section_type"),
        "section_codes": record.get("section_codes", []),
        "action_index": record.get("action_index"),
        "chain_index": record.get("chain_index"),
    }


def build_status_registry(records: list[dict[str, Any]], winfail: dict[str, Any]) -> dict[str, Any]:
    registry: dict[str, Any] = {
        "fail": {"initial_enabled_ids": [], "inserted_ids": [], "deleted_ids": [], "entries": []},
        "event": {"initial_enabled_ids": [], "inserted_ids": [], "deleted_ids": [], "entries": []},
        "win": {"initial_enabled_ids": [], "inserted_ids": [], "deleted_ids": [], "entries": []},
    }
    target_sections = {
        str(section_status_id(section)): {
            "script_id": winfail.get("id"),
            "section_index": section.get("index"),
            "section_name": section.get("name"),
            "section_type": section.get("type", section.get("name")),
            "codes": section.get("codes", []),
        }
        for section in winfail.get("sections", [])
        if isinstance(section, dict) and section_status_id(section) is not None
    }

    for record in records:
        mutation = classify_mutation(record)
        if mutation is None:
            continue
        kind = mutation["status_kind"]
        status_id = mutation.get("status_id")
        if status_id is None:
            continue
        entry = dict(mutation)
        entry["target_section"] = target_sections.get(status_id)
        registry[kind]["entries"].append(entry)
        target_list = "inserted_ids" if mutation["operation"] == "insert" else "deleted_ids"
        if status_id not in registry[kind][target_list]:
            registry[kind][target_list].append(status_id)
        if record.get("script_id") == "story051" and mutation["operation"] == "insert":
            if status_id not in registry[kind]["initial_enabled_ids"]:
                registry[kind]["initial_enabled_ids"].append(status_id)
    return registry


def build_section_dispatch(winfail: dict[str, Any]) -> dict[str, list[dict[str, Any]]]:
    result: dict[str, list[dict[str, Any]]] = {"win": [], "fail": [], "event": []}
    for section in winfail.get("sections", []):
        if not isinstance(section, dict):
            continue
        section_type = str(section.get("type", section.get("name", "")))
        if section_type not in result:
            continue
        conditions: list[dict[str, Any]] = []
        mutations: list[dict[str, Any]] = []
        chain_records = iter_chain_actions(
            {
                "id": winfail.get("id"),
                "source_file": winfail.get("source_file"),
                "sections": [section],
            }
        )
        for record in chain_records:
            if record.get("name") in CONDITION_ACTIONS:
                conditions.append(classify_condition(record))
            mutation = classify_mutation(record)
            if mutation is not None:
                mutations.append(mutation)
        result[section_type].append(
            {
                "status_id": section_status_id(section),
                "section_index": section.get("index"),
                "section_name": section.get("name"),
                "section_type": section_type,
                "codes": section.get("codes", []),
                "messages": section.get("messages", []),
                "conditions": conditions,
                "mutations": mutations,
                "dry_run_semantics": "conditions listed in script order; no battle state is read or mutated",
                "evidence_tier": "resource-derived",
                "unresolved_semantics": [
                    "unresolved dispatch timing, condition polarity, status lifetime, and exact event loop binding",
                ],
            }
        )
    return result


def ordered_unique_action_names(records: list[dict[str, Any]]) -> list[str]:
    result: list[str] = []
    seen: set[str] = set()
    for record in records:
        name = str(record.get("name", ""))
        if not name or name in seen:
            continue
        seen.add(name)
        result.append(name)
    return result


def build_dispatch_correlation_hints(records: list[dict[str, Any]]) -> dict[str, Any]:
    return {
        "correlation_status": "unresolved",
        "ordered_unique_action_names": ordered_unique_action_names(records),
        "ordered_action_name_count": len(ordered_unique_action_names(records)),
        "static_targets": {
            "script_primary_dispatch_table": "0x453708",
            "script_action_dispatch_table": "0x4537f4",
            "script_interpreter_bridge_candidate": "0x450840",
        },
        "static_target_facts": {
            "script_primary_dispatch_table_slots": 24,
            "script_action_dispatch_table_slots": 140,
            "script_action_dispatch_table_unique_handlers": 133,
            "script_interpreter_bridge_call_xrefs": 5,
        },
        "next_static_correlation_need": (
            "map resource action names/order to 0x4537f4 slots only after exe-static exports "
            "slot identifiers or opcode-to-name evidence; repeated handlers are expected"
        ),
        "unresolved_semantics": [
            "IR action order is source order, not proven dispatch-table slot order",
            "static table shape is recorded for correlation only; no handler identity is claimed here",
        ],
    }


def action_category(name: str) -> str:
    if name in CONDITION_ACTIONS:
        return "condition"
    if name in STATUS_INSERT_ACTIONS or name in STATUS_DELETE_ACTIONS:
        return "status"
    return ACTION_CATEGORY_BY_NAME.get(name, "unknown")


def classify_action_semantics(record: dict[str, Any]) -> dict[str, Any]:
    name = str(record.get("name", ""))
    args = [str(arg) for arg in record.get("args", [])]
    category = action_category(name)
    result: dict[str, Any] = {
        "name": name,
        "category": category,
        "args": args,
        "source": action_source(record),
        "evidence_tier": "resource-derived",
        "dispatch_correlation_status": "unresolved",
        "unresolved_semantics": [
            "unresolved action category is a resource-derived dry-run classification; handler behavior and side effects are not fully mapped",
        ],
    }
    if category == "message":
        if args:
            result["speaker_or_channel_candidate"] = args[0]
        if len(args) >= 3:
            result["message_id_candidate"] = args[2]
        elif args:
            result["message_id_candidate"] = args[-1]
    elif category == "movement":
        if args:
            result["actor_or_object_candidate"] = args[0]
        result["coordinate_args"] = args[1:]
        result["coordinate_semantics"] = "resource-derived movement/display args; not proven Godot grid or screen coordinates"
    elif category == "object":
        if args:
            result["object_or_handle_candidate"] = args[0]
        if len(args) >= 3:
            result["position_args_candidate"] = args[1:3]
            result["coordinate_semantics"] = "resource-derived object position args; not proven Godot grid or screen coordinates"
    elif category == "camera" and len(args) >= 2:
        result["target_position_candidate"] = args[:2]
        result["coordinate_semantics"] = "resource-derived camera target args; not proven Godot camera coordinates"
    elif category == "timing" and args:
        result["delay_arg_candidate"] = args[0]
    elif category == "ui" and args:
        result["resource_or_status_arg_candidate"] = args[0]
    elif category == "flow":
        result["flow_args"] = args
    elif category == "audio":
        result["audio_args"] = args
    return result


def build_action_semantics_catalog(records: list[dict[str, Any]]) -> dict[str, Any]:
    by_action: dict[str, list[dict[str, Any]]] = {}
    category_summary: collections.Counter[str] = collections.Counter()
    for record in records:
        name = str(record.get("name", ""))
        entry = classify_action_semantics(record)
        by_action.setdefault(name, []).append(entry)
        category_summary[entry["category"]] += 1
    return {
        "source_total_action_chain_count": len(records),
        "category_summary": dict(sorted(category_summary.items())),
        "by_action": dict(sorted(by_action.items())),
        "unresolved_semantics": [
            "catalog groups resource actions for interpreter planning only; it does not execute handlers",
            "condition and status actions also appear here for complete action coverage, while dedicated summaries carry their dry-run semantics",
        ],
    }


def action_effect_request(category: str) -> str:
    requests = {
        "message": "identify message/dialogue handler slot and confirm speaker/message-id argument roles before text playback",
        "movement": "identify movement/walk handler slot and confirm actor id, coordinate space, and wait timing",
        "object": "identify object insertion/deletion/change handler slot and confirm object handle, placement, and lifetime semantics",
        "camera": "identify camera scroll handler slot and confirm coordinate space and blocking behavior",
        "ui": "identify UI/status display handler slot and confirm whether it blocks script dispatch",
        "timing": "identify delay/wait handler slot and confirm tick/frame unit",
        "audio": "identify audio/music handler slot and confirm resource id/default behavior",
        "flow": "identify flow-control handler slot and confirm next-level/state persistence side effects",
        "unknown": "identify action handler slot and side-effect family",
    }
    return requests.get(category, requests["unknown"])


def build_action_effect_facade_catalog(action_catalog: dict[str, Any]) -> dict[str, Any]:
    by_action: dict[str, dict[str, Any]] = {}
    effect_summary: collections.Counter[str] = collections.Counter()
    source_total = 0
    for name, entries in action_catalog.get("by_action", {}).items():
        if not isinstance(entries, list) or not entries:
            continue
        category = str(entries[0].get("category", "unknown"))
        if category in {"condition", "status"}:
            continue
        occurrences = [
            {
                "args": entry.get("args", []),
                "source": entry.get("source", {}),
                "evidence_tier": "resource-derived",
            }
            for entry in entries
            if isinstance(entry, dict)
        ]
        source_total += len(occurrences)
        effect_summary[category] += len(occurrences)
        by_action[str(name)] = {
            "effect_family": category,
            "facade_mode": "diagnostic_trace_only",
            "effect_status": "candidate_unresolved",
            "occurrence_count": len(occurrences),
            "occurrences": occurrences,
            "evidence_tier": "resource-derived",
            "handler_mapping_status": "unresolved",
            "evidence_requests": {
                "exe_static": [
                    {
                        "target": "0x4537f4",
                        "request": action_effect_request(category),
                        "status": "needed",
                    }
                ],
                "runtime_probes": [
                    {
                        "moment": f"{category}_specific_ui_or_state_moment",
                        "request": "capture exact UI/state transition only after static handler candidate exists",
                        "status": "deferred",
                    }
                ],
            },
            "unresolved_semantics": [
                "facade entry is metadata only; handler identity, side effects, blocking behavior, and runtime state writes are unresolved",
            ],
        }
    return {
        "semantic_status": "facade_only",
        "handler_mapping_status": "unresolved",
        "execution_policy": "no_handlers_no_live_mutation",
        "evidence_tier": "resource-derived",
        "source_non_condition_status_action_count": source_total,
        "effect_family_summary": dict(sorted(effect_summary.items())),
        "by_action": dict(sorted(by_action.items())),
        "downstream_contract": {
            "godot": "read_only_action_metadata_no_handlers",
            "battle_engine": "diagnostic_hint_only",
        },
        "unresolved_semantics": [
            "categories group candidate effect families but do not prove handler mapping or executable behavior",
            "condition and status actions are excluded because dedicated predicate/lifecycle models describe their dry-run metadata",
        ],
    }


def default_static_index_path(index_path: Path) -> Path:
    parts = index_path.parts
    if "content" in parts:
        content_index = parts.index("content")
        root = Path(*parts[:content_index]) if content_index > 0 else Path(".")
        return root / "content" / "generated" / "hsl" / "static" / "hsl01" / "index.json"
    return Path("content/generated/hsl/static/hsl01/index.json")


def default_message_text_evidence_path(index_path: Path) -> Path:
    return index_path.parent / "message_text_evidence.json"


def load_message_text_evidence(path: Path | None) -> dict[str, Any] | None:
    if path is None or not path.exists():
        return None
    item = load_json(path)
    if isinstance(item, dict):
        return item
    return None


def load_condition_static_navigation_hints(static_index_path: Path | None) -> dict[str, dict[str, Any]]:
    if static_index_path is None or not static_index_path.exists():
        return {}
    static_index = load_json(static_index_path)
    candidates = static_index.get("condition_predicate_handler_candidates", {})
    if not isinstance(candidates, dict):
        return {}
    result: dict[str, dict[str, Any]] = {}
    for item in candidates.get("actions", []):
        if not isinstance(item, dict):
            continue
        action_name = str(item.get("action_name", ""))
        if not action_name:
            continue
        result[action_name] = {
            "source": static_index_path.as_posix(),
            "schema": candidates.get("schema"),
            "evidence_tier": candidates.get("evidence_tier", "static_candidate_skeleton"),
            "candidate_slot_if_order_matched": item.get("candidate_slot_if_order_matched"),
            "candidate_handler_if_order_matched": item.get("candidate_handler_if_order_matched"),
            "correlation_status": item.get("correlation_status", "unresolved"),
            "ordinal_as_slot_status": item.get("ordinal_as_slot_status", "not_evidence"),
            "slot_opcode_evidence_status": item.get("slot_opcode_evidence_status", "unresolved"),
            "comparison_polarity_evidence_status": item.get("comparison_polarity_evidence_status", "unresolved"),
            "why_unresolved": item.get("why_unresolved"),
        }
    return result


def load_status_lifecycle_static_navigation_hints(static_index_path: Path | None) -> dict[str, dict[str, Any]]:
    if static_index_path is None or not static_index_path.exists():
        return {}
    static_index = load_json(static_index_path)
    candidates = static_index.get("status_lifecycle_handler_candidates", {})
    if not isinstance(candidates, dict):
        return {}
    result: dict[str, dict[str, Any]] = {}
    for item in candidates.get("actions", []):
        if not isinstance(item, dict):
            continue
        action_name = str(item.get("action_name", ""))
        if not action_name:
            continue
        result[action_name] = {
            "source": static_index_path.as_posix(),
            "schema": candidates.get("schema"),
            "evidence_tier": candidates.get("evidence_tier", "static_candidate_skeleton"),
            "candidate_slot_if_order_matched": item.get("candidate_slot_if_order_matched"),
            "candidate_handler_if_order_matched": item.get("candidate_handler_if_order_matched"),
            "correlation_status": item.get("correlation_status", "unresolved"),
            "ordinal_as_slot_status": item.get("ordinal_as_slot_status", "not_evidence"),
            "slot_opcode_evidence_status": item.get("slot_opcode_evidence_status", "unresolved"),
            "commit_timing_evidence_status": item.get("commit_timing_evidence_status", "unresolved"),
            "lifecycle_semantic_status": item.get("lifecycle_semantic_status", "scheduled_only"),
            "bridge_commit_timing_status": item.get("bridge_commit_timing_status", "unresolved"),
            "why_unresolved": item.get("why_unresolved"),
        }
    return result


def load_status_commit_path_static_context(static_index_path: Path | None) -> dict[str, Any] | None:
    if static_index_path is None or not static_index_path.exists():
        return None
    static_index = load_json(static_index_path)
    context = static_index.get("script_status_commit_path_static_context")
    if isinstance(context, dict):
        return context
    return None


def build_interpreter_progress_boundary(static_context: dict[str, Any] | None) -> dict[str, Any]:
    if not isinstance(static_context, dict):
        return {
            "schema": "hsl_script_vm_interpreter_progress_boundary.v1",
            "evidence_status": "missing_static_context",
            "evidence_tier": "missing",
            "progress_boundary_status": "unresolved",
            "status_mutation_commit_timing_status": "unresolved",
            "status_mutation_commit_status": "unresolved",
            "registry_write_status": "unresolved",
            "deferred_queue_candidate_status": "unresolved",
            "execution_policy": "read_only_boundary_diagnostic_no_live_mutation",
            "unresolved_semantics": [
                "static script status commit path context is missing; no interpreter progress or status commit claim is made",
            ],
        }
    cursor_progress = static_context.get("script_cursor_progress", {})
    if not isinstance(cursor_progress, dict):
        cursor_progress = {}
    handler_candidates = []
    for item in static_context.get("status_handler_boundary_candidates", []):
        if not isinstance(item, dict):
            continue
        handler_candidates.append(
            {
                "action_name": item.get("action_name"),
                "candidate_handler_if_order_matched": item.get("candidate_handler_if_order_matched"),
                "correlation_status": item.get("correlation_status", "unresolved"),
                "ordinal_as_slot_status": item.get("ordinal_as_slot_status", "not_evidence"),
                "commit_timing_evidence_status": item.get("commit_timing_evidence_status", "unresolved"),
                "navigation_policy": "navigation_only_not_commit_evidence",
            }
        )
    return {
        "schema": "hsl_script_vm_interpreter_progress_boundary.v1",
        "source_schema": static_context.get("schema"),
        "source_bridge_address": static_context.get("bridge_address"),
        "evidence_status": "static_cursor_progress_loaded",
        "evidence_tier": static_context.get("evidence_tier"),
        "semantic_status": static_context.get("semantic_status", "unresolved"),
        "execution_policy": "read_only_boundary_diagnostic_no_live_mutation",
        "progress_boundary_status": cursor_progress.get("commit_boundary_status", "unresolved"),
        "script_cursor_field_offset": cursor_progress.get("script_cursor_field_offset"),
        "token_advance_count": cursor_progress.get("token_advance_count"),
        "script_cursor_write_count": cursor_progress.get("script_cursor_write_count"),
        "return_count": cursor_progress.get("return_count"),
        "cursor_write_address_sample": cursor_progress.get("script_cursor_write_addresses_sample", [])[:8],
        "token_advance_address_sample": cursor_progress.get("token_advance_addresses_sample", [])[:8],
        "registry_write_status": static_context.get("registry_write_status", "unresolved"),
        "deferred_queue_candidate_status": static_context.get("deferred_queue_candidate_status", "unresolved"),
        "status_mutation_commit_timing_status": static_context.get("status_mutation_commit_timing_status", "unresolved"),
        "status_mutation_commit_status": cursor_progress.get("status_mutation_commit_status", "unresolved"),
        "status_handler_boundary_candidates": handler_candidates,
        "negative_evidence": static_context.get("negative_evidence", []),
        "downstream_contract": {
            "godot": "may display script cursor/progress boundary diagnostics only",
            "script_vm": "must not use cursor progress evidence as status registry/deferred queue commit proof",
        },
        "unresolved_semantics": [
            "script cursor/token progress evidence is separated from unresolved status mutation lifecycle commit timing",
            "handler boundary candidates are navigation-only and do not prove opcode, registry write, or deferred queue commit semantics",
        ],
    }


def build_condition_predicate_catalog(
    records: list[dict[str, Any]],
    static_navigation_hints: dict[str, dict[str, Any]] | None = None,
) -> dict[str, Any]:
    static_navigation_hints = static_navigation_hints or {}
    by_action: dict[str, dict[str, Any]] = {}
    for record in records:
        name = str(record.get("name", ""))
        if name not in CONDITION_ACTIONS:
            continue
        candidate = CONDITION_PREDICATE_CANDIDATES.get(name, {})
        occurrence = {
            "args": [str(arg) for arg in record.get("args", [])],
            "source": action_source(record),
            "evidence_tier": "resource-derived",
        }
        item = by_action.setdefault(
            name,
            {
                "condition_type": CONDITION_ACTIONS.get(name),
                "predicate_status": "unknown",
                "args_schema_candidate": candidate.get("args_schema_candidate", []),
                "candidate_context_binding": candidate.get("candidate_context_binding", "unknown"),
                "runtime_probe_priority": candidate.get("runtime_probe_priority", "defer_until_specific_probe"),
                "occurrence_count": 0,
                "occurrences": [],
                "evidence_tier": "resource-derived",
                "source_numeric_opcode_status": "missing_in_imported_ir",
                "static_navigation_hint": static_navigation_hints.get(
                    name,
                    {
                        "correlation_status": "missing",
                        "slot_opcode_evidence_status": "missing",
                        "comparison_polarity_evidence_status": "missing",
                    },
                ),
                "evidence_requests": {
                    "exe_static": [
                        {
                            "target": "0x4537f4",
                            "request": candidate.get(
                                "exe_static_question",
                                "identify handler slot/opcode and comparison semantics before mapping predicate",
                            ),
                            "status": "needed",
                        }
                    ],
                    "runtime_probes": [
                        {
                            "phase_profile": "player_control",
                            "request": candidate.get(
                                "runtime_question",
                                "capture an exact UI/state moment for this predicate; use an exact UI/state moment label",
                            ),
                            "status": "needed",
                        }
                    ],
                },
                "unresolved_semantics": [
                    "predicate polarity, equality/range relation, and runtime state binding are unresolved",
                    "resource args are preserved as candidate roles only; no handler mapping or runtime proof is claimed",
                ],
            },
        )
        item["occurrences"].append(occurrence)
        item["occurrence_count"] += 1
    return {
        "semantic_status": "unresolved",
        "evidence_tier": "resource-derived",
        "condition_action_count": sum(item["occurrence_count"] for item in by_action.values()),
        "unique_condition_action_count": len(by_action),
        "by_action": dict(sorted(by_action.items())),
        "bounded_request_policy": (
            "requests must name a concrete handler/slot, scalar, action, or UI moment; "
            "generic script execution phase labels are not accepted as semantic proof"
        ),
        "unresolved_semantics": [
            "catalog deliberately preserves unknown predicate semantics until exe-static or runtime evidence proves them",
            "dry-run context bindings are facade inputs, not confirmed engine variable bindings",
        ],
    }


def build_status_mutation_lifecycle_model(
    status_registry: dict[str, Any],
    section_dispatch: dict[str, list[dict[str, Any]]],
    static_navigation_hints: dict[str, dict[str, Any]] | None = None,
) -> dict[str, Any]:
    static_navigation_hints = static_navigation_hints or {}
    initial_enabled = enabled_status_from_registry(status_registry)
    mutation_counts: collections.Counter[str] = collections.Counter()
    for kind in ("win", "fail", "event"):
        item = status_registry.get(kind, {})
        if not isinstance(item, dict):
            continue
        for entry in item.get("entries", []):
            if isinstance(entry, dict):
                mutation_counts[str(entry.get("name", ""))] += 1
    section_lifecycle: dict[str, list[dict[str, Any]]] = {"win": [], "fail": [], "event": []}
    for kind in ("win", "fail", "event"):
        for section in section_dispatch.get(kind, []):
            scheduled_mutations: list[dict[str, Any]] = []
            for mutation in section.get("mutations", []):
                if not isinstance(mutation, dict):
                    continue
                name = str(mutation.get("name", ""))
                scheduled_mutations.append(
                    {
                        "name": name,
                        "operation": mutation.get("operation"),
                        "status_kind": mutation.get("status_kind"),
                        "status_id": mutation.get("status_id"),
                        "args": mutation.get("args", []),
                        "source": mutation.get("source", {}),
                        "evidence_tier": "resource-derived",
                        "application_status": "scheduled_only",
                        "unresolved_semantics": [
                            "mutation order is script order, but application timing relative to dispatch loop is unresolved",
                        ],
                    }
                )
            section_lifecycle[kind].append(
                {
                    "status_id": section.get("status_id"),
                    "section_index": section.get("section_index"),
                    "section_name": section.get("section_name"),
                    "section_type": kind,
                    "initial_enabled_candidate": str(section.get("status_id")) in initial_enabled.get(kind, []),
                    "condition_count": len(section.get("conditions", [])),
                    "scheduled_mutation_count": len(scheduled_mutations),
                    "scheduled_mutations": scheduled_mutations,
                    "dispatch_timing_status": "unknown",
                    "evidence_tier": "resource-derived",
                    "unresolved_semantics": [
                        "section dispatch loop order, one-shot behavior, and mutation commit point require exe/runtime evidence",
                    ],
                }
            )
    return {
        "semantic_status": "unresolved",
        "evidence_tier": "resource-derived",
        "initial_enabled_status": initial_enabled,
        "mutation_counts_by_action": dict(sorted(mutation_counts.items())),
        "section_lifecycle": section_lifecycle,
        "static_navigation_hints": {
            "semantic_status": "unresolved",
            "evidence_tier": "static_candidate_skeleton" if static_navigation_hints else "missing",
            "navigation_policy": "navigation_only_not_opcode_evidence",
            "by_action": dict(sorted(static_navigation_hints.items())),
        },
        "dry_run_state_transition_policy": "scheduled_only_no_live_mutation",
        "evidence_requests": {
            "exe_static": [
                {
                    "target": "0x450840",
                    "request": "identify when status mutations commit relative to section dispatch and script action execution",
                    "status": "needed",
                },
                {
                    "target": "0x4537f4",
                    "request": "identify handler slots/opcodes for actInsertFailStatus/actInsertEventStatus/actDeleteEventStatus/actInsertWinStatus",
                    "status": "needed",
                },
            ],
            "runtime_probes": [
                {
                    "moment": "round_6_objective_switch_candidate",
                    "request": "observe whether event 0/1 disable and win 0/1 enable after the exact round-6 objective switch moment",
                    "status": "needed",
                }
            ],
        },
        "unresolved_semantics": [
            "initial enabled ids are inferred from story051 insert actions, not confirmed runtime registry defaults",
            "scheduled mutations preserve script order but do not claim immediate, deferred, or one-shot commit semantics",
            "win/fail/event dispatch priority and repeated evaluation behavior remain unresolved",
        ],
    }


def int_arg(value: Any) -> int | None:
    try:
        return int(str(value), 0)
    except (TypeError, ValueError):
        return None


def enabled_status_from_registry(status_registry: dict[str, Any]) -> dict[str, list[str]]:
    result: dict[str, list[str]] = {}
    for kind in ("win", "fail", "event"):
        item = status_registry.get(kind, {})
        if isinstance(item, dict):
            result[kind] = [str(value) for value in item.get("initial_enabled_ids", [])]
        else:
            result[kind] = []
    return result


def evaluate_condition_candidate(condition: dict[str, Any], context: dict[str, Any]) -> dict[str, Any]:
    name = str(condition.get("name", ""))
    args = [str(arg) for arg in condition.get("args", [])]
    result: dict[str, Any] = {
        "condition_name": name,
        "args": args,
        "result": "unknown",
        "evidence_tier": "resource-derived",
        "unresolved_semantics": [
            "candidate dry-run predicate only; exact comparison polarity and runtime state binding are unresolved",
        ],
    }
    if name == "actCheckEnemyTotalNumber" and args:
        expected = int_arg(args[0])
        actual = int_arg(context.get("enemy_total"))
        result["context_field"] = "enemy_total"
        result["expected_candidate"] = expected
        result["actual_candidate"] = actual
        if expected is not None and actual is not None:
            result["result"] = "candidate_true" if actual == expected else "candidate_false"
    elif name == "actCheckRoundNumber" and args:
        expected = int_arg(args[0])
        actual = int_arg(context.get("round_number"))
        result["context_field"] = "round_number"
        result["expected_candidate"] = expected
        result["actual_candidate"] = actual
        if expected is not None and actual is not None:
            result["result"] = "candidate_true" if actual == expected else "candidate_false"
    elif name == "actCheckEnemyNumber" and len(args) >= 2:
        expected = int_arg(args[1])
        enemy_counts = context.get("enemy_counts", {})
        actual = None
        if isinstance(enemy_counts, dict):
            actual = int_arg(enemy_counts.get(args[0]))
        result["context_field"] = f"enemy_counts.{args[0]}"
        result["expected_candidate"] = expected
        result["actual_candidate"] = actual
        if expected is not None and actual is not None:
            result["result"] = "candidate_true" if actual == expected else "candidate_false"
    elif name == "actCheckPlayer" and len(args) >= 2:
        player_states = context.get("player_states", {})
        actual = None
        if isinstance(player_states, dict):
            actual = str(player_states.get(args[1])) if args[1] in player_states else None
        result["context_field"] = f"player_states.{args[1]}"
        result["expected_candidate"] = args[0]
        result["actual_candidate"] = actual
        if actual is not None:
            result["result"] = "candidate_true" if actual == args[0] else "candidate_false"
    elif name == "actCheckPlayerArrivePos" and len(args) >= 6:
        positions = context.get("player_positions", {})
        position = positions.get(args[0]) if isinstance(positions, dict) else None
        result["context_field"] = f"player_positions.{args[0]}"
        result["expected_candidate"] = {
            "x1": int_arg(args[2]),
            "y1": int_arg(args[3]),
            "x2": int_arg(args[4]),
            "y2": int_arg(args[5]),
        }
        result["actual_candidate"] = position
        if isinstance(position, dict):
            x = int_arg(position.get("x"))
            y = int_arg(position.get("y"))
            x1 = result["expected_candidate"]["x1"]
            y1 = result["expected_candidate"]["y1"]
            x2 = result["expected_candidate"]["x2"]
            y2 = result["expected_candidate"]["y2"]
            if None not in (x, y, x1, y1, x2, y2):
                result["result"] = "candidate_true" if x1 <= x <= x2 and y1 <= y <= y2 else "candidate_false"
    return result


def section_candidate_result(status_enabled: bool, condition_results: list[dict[str, Any]]) -> str:
    if not status_enabled:
        return "candidate_false"
    results = [str(item.get("result")) for item in condition_results]
    if not results:
        return "candidate_true"
    if "candidate_false" in results:
        return "candidate_false"
    if all(item == "candidate_true" for item in results):
        return "candidate_true"
    return "unknown"


def build_dry_run_trace(section_dispatch: dict[str, list[dict[str, Any]]], context: dict[str, Any]) -> dict[str, Any]:
    enabled_status = context.get("enabled_status", {})
    if not isinstance(enabled_status, dict):
        enabled_status = {}
    dispatch: dict[str, list[dict[str, Any]]] = {"win": [], "fail": [], "event": []}
    for kind in ("win", "fail", "event"):
        enabled_ids = {str(value) for value in enabled_status.get(kind, [])}
        for section in section_dispatch.get(kind, []):
            status_id = str(section.get("status_id"))
            condition_results = [
                evaluate_condition_candidate(condition, context)
                for condition in section.get("conditions", [])
                if isinstance(condition, dict)
            ]
            status_enabled = status_id in enabled_ids
            candidate_result = section_candidate_result(status_enabled, condition_results)
            dispatch[kind].append(
                {
                    "status_id": status_id,
                    "section_index": section.get("section_index"),
                    "section_name": section.get("section_name"),
                    "section_type": kind,
                    "status_enabled_candidate": status_enabled,
                    "condition_results": condition_results,
                    "candidate_result": candidate_result,
                    "scheduled_mutations": section.get("mutations", []) if candidate_result == "candidate_true" else [],
                    "evidence_tier": "resource-derived",
                    "unresolved_semantics": [
                        "dry-run trace does not mutate live battle state",
                        "candidate_result is based on supplied mock context and unresolved predicate semantics",
                    ],
                }
            )
    return {
        "context": context,
        "dispatch": dispatch,
        "evidence_tier": "resource-derived",
        "unresolved_semantics": [
            "trace is deterministic over supplied mock context only; it is not runtime-observed",
        ],
    }


def build_interpreter_dry_run_trace_model(
    section_dispatch: dict[str, list[dict[str, Any]]],
    status_registry: dict[str, Any],
) -> dict[str, Any]:
    initial_enabled = enabled_status_from_registry(status_registry)
    context_examples = {
        "enemy_clear_candidate": {
            "enabled_status": initial_enabled,
            "enemy_total": 0,
            "enemy_counts": {},
            "round_number": 1,
        },
        "round_6_objective_switch_candidate": {
            "enabled_status": initial_enabled,
            "enemy_total": 1,
            "enemy_counts": {},
            "round_number": 6,
        },
    }
    return {
        "schema": "hsl_script_vm_interpreter_dry_run_trace.v1",
        "evidence_tier": "resource-derived",
        "source_policy": (
            "candidate interpreter dry-run over section_dispatch; evaluates only supplied mock context "
            "and never reads or mutates live battle state"
        ),
        "context_contract": {
            "enabled_status": {"win": "list[str]", "fail": "list[str]", "event": "list[str]"},
            "enemy_total": "optional int",
            "enemy_counts": "optional dict[str,int]",
            "round_number": "optional int",
            "player_states": "optional dict[player_id,state]",
            "player_positions": "optional dict[player_id,{x:int,y:int}]",
        },
        "context_examples": context_examples,
        "trace_examples": {
            name: build_dry_run_trace(section_dispatch, context)
            for name, context in context_examples.items()
        },
        "unresolved_semantics": [
            "condition polarity, runtime variable binding, event loop timing, and handler side effects remain unresolved",
            "runtime-probes phase labels are not used as proof in this model",
        ],
    }


def build_interpreter_facade_contract() -> dict[str, Any]:
    return {
        "schema": "hsl_script_vm_interpreter_facade_contract.v1",
        "consumer": "godot_dry_run_diagnostics",
        "evidence_tier": "resource-derived",
        "execution_policy": "read_only_no_handlers_no_live_mutation",
        "stable_inputs": [
            "condition_predicate_catalog",
            "status_mutation_lifecycle_model",
            "action_effect_facade_catalog",
            "interpreter_dry_run_trace_model",
            "script_event_log_model",
        ],
        "allows_handler_execution": False,
        "allows_live_battle_mutation": False,
        "allows_evidence_tier_upgrade": False,
        "guard_summary": {
            "schema": "hsl_script_vm_facade_guard_summary.v1",
            "required_imported_opcode_status": "missing_in_imported_ir",
            "required_opcode_gap_guard_status": "active",
            "read_only_inputs_only": True,
            "no_handler_execution": True,
            "no_live_battle_mutation": True,
            "no_evidence_tier_upgrade": True,
            "no_generic_phase_label_evidence": True,
            "static_navigation_hints_are_opcode_evidence": False,
            "allowed_evidence_tier": "resource-derived",
        },
        "cross_field_invariants": {
            "condition_predicates": {
                "semantic_status": "unresolved",
                "predicate_status": "unknown",
                "source_numeric_opcode_status": "missing_in_imported_ir",
                "static_navigation_hint_correlation_status": ["missing", "unresolved"],
                "static_navigation_hint_slot_opcode_status": ["missing", "unresolved"],
            },
            "status_lifecycle": {
                "semantic_status": "unresolved",
                "dry_run_state_transition_policy": "scheduled_only_no_live_mutation",
                "mutation_application_status": "scheduled_only",
            },
            "action_effects": {
                "semantic_status": "facade_only",
                "handler_mapping_status": "unresolved",
                "execution_policy": "no_handlers_no_live_mutation",
                "facade_mode": "diagnostic_trace_only",
            },
            "dry_run_trace": {
                "schema": "hsl_script_vm_interpreter_dry_run_trace.v1",
                "candidate_results": ["candidate_true", "candidate_false", "unknown"],
            },
        },
        "forbidden_claims": [
            "handler_confirmed",
            "live_battle_mutation",
            "evidence_tier_upgrade",
            "generic_execution_phase_proof",
        ],
        "unresolved_semantics": [
            "facade contract defines stable read-only fields only; it does not implement or authorize handler execution",
            "static navigation hints remain candidates until numeric opcode/slot evidence is available",
        ],
    }


def message_id_candidates_for_action(name: str, args: list[str]) -> list[str]:
    candidates: list[str] = []
    if name == "actMessage":
        if len(args) >= 3:
            candidates.append(args[2])
        elif args:
            candidates.append(args[-1])
    elif name == "actMessageIfExist":
        for arg in args[2:4]:
            if arg.lstrip("-").isdigit() and arg not in candidates:
                candidates.append(arg)
    return candidates


def build_message_visible_fields(name: str, args: list[str]) -> dict[str, Any]:
    message_ids = message_id_candidates_for_action(name, args)
    speaker = args[0] if args else None
    primary_id = message_ids[0] if message_ids else None
    visible_fields: dict[str, Any] = {
        "speaker_or_channel_candidate": speaker,
        "message_id_candidate": primary_id,
        "message_id_candidates": message_ids,
        "message_text_status": "not_resolved_in_imported_assets",
        "message_text_source_status": "missing_structured_text_table",
        "display_label": f"{speaker or 'unknown'}: message#{primary_id or 'unknown'}",
        "text_lookup_note": (
            "Godot may display this label/id as imported-script content; actual localized text is unresolved until a "
            "message text table is decoded"
        ),
    }
    if len(args) >= 2:
        visible_fields["portrait_or_mode_candidate"] = args[1]
    if name == "actMessageIfExist":
        visible_fields["conditional_or_fallback_message_id_candidates"] = message_ids[1:]
        visible_fields["existence_check_args_candidate"] = args[4:]
    return visible_fields


def build_event_log_phase_views(
    event_log_entries: list[dict[str, Any]],
    dispatch_diagnostics: list[dict[str, Any]],
) -> dict[str, Any]:
    phases = {
        "story": {
            "display_name": "opening_story",
            "entry_indexes": [],
            "dispatch_indexes": [],
            "read_policy": "ordered_event_log_only",
        },
        "win": {
            "display_name": "win_conditions",
            "entry_indexes": [],
            "dispatch_indexes": [],
            "read_policy": "ordered_dispatch_diagnostics_only",
        },
        "fail": {
            "display_name": "fail_conditions",
            "entry_indexes": [],
            "dispatch_indexes": [],
            "read_policy": "ordered_dispatch_diagnostics_only",
        },
        "event": {
            "display_name": "event_sections",
            "entry_indexes": [],
            "dispatch_indexes": [],
            "read_policy": "ordered_dispatch_diagnostics_only",
        },
    }
    for index, entry in enumerate(event_log_entries):
        source = entry.get("source", {})
        section_type = source.get("section_type") if isinstance(source, dict) else None
        if section_type in phases:
            phases[section_type]["entry_indexes"].append(index)
    for index, entry in enumerate(dispatch_diagnostics):
        section_type = entry.get("section_type")
        if section_type in phases:
            phases[section_type]["dispatch_indexes"].append(index)
    for phase in phases.values():
        phase["entry_count"] = len(phase["entry_indexes"])
        phase["dispatch_count"] = len(phase["dispatch_indexes"])
        phase["evidence_tier"] = "resource-derived"
        phase["unresolved_semantics"] = [
            "phase grouping follows imported script section type and source order; it is a read-only presentation view",
        ]
    return {
        "schema": "hsl_script_vm_event_log_phase_views.v1",
        "consumer": "godot_read_play_event_log",
        "phase_order": ["story", "win", "fail", "event"],
        "views": phases,
        "presentation_policy": "read_only_grouping_no_execution",
        "unresolved_semantics": [
            "phase order is for diagnostics/presentation only and does not prove original runtime dispatch priority",
        ],
    }


def build_godot_panel_phase_summaries(
    event_log_entries: list[dict[str, Any]],
    dispatch_diagnostics: list[dict[str, Any]],
    phase_views: dict[str, Any],
) -> dict[str, Any]:
    summaries: dict[str, dict[str, Any]] = {}
    views = phase_views.get("views", {}) if isinstance(phase_views, dict) else {}
    for phase in ("story", "win", "fail", "event"):
        view = views.get(phase, {}) if isinstance(views, dict) else {}
        entry_indexes = view.get("entry_indexes", []) if isinstance(view, dict) else []
        dispatch_indexes = view.get("dispatch_indexes", []) if isinstance(view, dict) else []
        display_labels: list[dict[str, Any]] = []
        scheduled_entries: list[dict[str, Any]] = []
        for entry_index in entry_indexes:
            if not isinstance(entry_index, int) or isinstance(entry_index, bool) or entry_index < 0 or entry_index >= len(event_log_entries):
                continue
            entry = event_log_entries[entry_index]
            if not isinstance(entry, dict):
                continue
            if entry.get("entry_type") == "message":
                visible_fields = entry.get("visible_fields", {})
                if isinstance(visible_fields, dict):
                    display_labels.append(
                        {
                            "entry_index": entry_index,
                            "handler_name": entry.get("handler_name"),
                            "display_label": visible_fields.get("display_label"),
                            "message_id_candidate": visible_fields.get("message_id_candidate"),
                            "message_text_status": visible_fields.get("message_text_status"),
                            "source": entry.get("source", {}),
                        }
                    )
            elif entry.get("entry_type") == "resource_action":
                visible_fields = entry.get("visible_fields", {})
                if isinstance(visible_fields, dict):
                    display_labels.append(
                        {
                            "entry_index": entry_index,
                            "handler_name": entry.get("handler_name"),
                            "display_label": visible_fields.get("display_label"),
                            "resource_action_type": entry.get("resource_action_type"),
                            "resource_ref_candidate": visible_fields.get("resource_ref_candidate"),
                            "resource_text_status": visible_fields.get("resource_text_status"),
                            "music_resource_status": visible_fields.get("music_resource_status"),
                            "source": entry.get("source", {}),
                        }
                    )
            elif entry.get("entry_type") == "scheduled_status_mutation":
                scheduled_entries.append(
                    {
                        "entry_index": entry_index,
                        "handler_name": entry.get("handler_name"),
                        "operation": entry.get("operation"),
                        "status_kind": entry.get("status_kind"),
                        "status_id": entry.get("status_id"),
                        "execution_status": entry.get("execution_status"),
                        "source": entry.get("source", {}),
                    }
                )
        dispatch_entries: list[dict[str, Any]] = []
        for dispatch_index in dispatch_indexes:
            if (
                not isinstance(dispatch_index, int)
                or isinstance(dispatch_index, bool)
                or dispatch_index < 0
                or dispatch_index >= len(dispatch_diagnostics)
            ):
                continue
            dispatch = dispatch_diagnostics[dispatch_index]
            if not isinstance(dispatch, dict):
                continue
            dispatch_entries.append(
                {
                    "dispatch_index": dispatch_index,
                    "section_type": dispatch.get("section_type"),
                    "status_id": dispatch.get("status_id"),
                    "section_index": dispatch.get("section_index"),
                    "condition_count": len(dispatch.get("conditions", [])) if isinstance(dispatch.get("conditions"), list) else 0,
                    "scheduled_mutation_count": len(dispatch.get("scheduled_mutations", []))
                    if isinstance(dispatch.get("scheduled_mutations"), list)
                    else 0,
                    "diagnostic_status": dispatch.get("diagnostic_status"),
                }
            )
        summaries[phase] = {
            "display_name": view.get("display_name") if isinstance(view, dict) else phase,
            "display_label_preview": display_labels[:8],
            "display_label_count": len(display_labels),
            "scheduled_status_preview": scheduled_entries[:8],
            "scheduled_status_count": len(scheduled_entries),
            "dispatch_preview": dispatch_entries[:8],
            "dispatch_count": len(dispatch_entries),
            "panel_policy": "read_only_summary_no_execution",
            "evidence_tier": "resource-derived",
        }
    return {
        "schema": "hsl_script_vm_godot_panel_phase_summaries.v1",
        "consumer": "godot_imported_script_panel",
        "summary_policy": "read_only_preview_no_handler_no_live_mutation",
        "preview_limit": 8,
        "phase_order": ["story", "win", "fail", "event"],
        "phases": summaries,
        "unresolved_semantics": [
            "summaries are presentation previews of imported script event log entries and dispatch diagnostics",
            "message text remains unresolved unless a structured text table is decoded",
        ],
    }


def build_godot_panel_read_play_trace(panel_phase_summaries: dict[str, Any]) -> dict[str, Any]:
    steps: list[dict[str, Any]] = []
    phases = panel_phase_summaries.get("phases", {}) if isinstance(panel_phase_summaries, dict) else {}
    phase_order = panel_phase_summaries.get("phase_order", ["story", "win", "fail", "event"])
    if not isinstance(phase_order, list):
        phase_order = ["story", "win", "fail", "event"]
    for phase in phase_order:
        if not isinstance(phase, str):
            continue
        summary = phases.get(phase, {}) if isinstance(phases, dict) else {}
        if not isinstance(summary, dict):
            continue
        for item in summary.get("display_label_preview", []):
            if not isinstance(item, dict):
                continue
            step_type = "resource_action" if item.get("resource_action_type") else "display_label"
            steps.append(
                {
                    "step_index": len(steps),
                    "phase": phase,
                    "step_type": step_type,
                    "display_text": item.get("display_label"),
                    "handler_name": item.get("handler_name"),
                    "message_id_candidate": item.get("message_id_candidate"),
                    "message_text_status": item.get("message_text_status"),
                    "resource_action_type": item.get("resource_action_type"),
                    "resource_ref_candidate": item.get("resource_ref_candidate"),
                    "resource_text_status": item.get("resource_text_status"),
                    "music_resource_status": item.get("music_resource_status"),
                    "source": item.get("source", {}),
                    "execution_status": "read_only_panel_trace",
                }
            )
        for item in summary.get("scheduled_status_preview", []):
            if not isinstance(item, dict):
                continue
            steps.append(
                {
                    "step_index": len(steps),
                    "phase": phase,
                    "step_type": "scheduled_status",
                    "display_text": (
                        f"{item.get('operation')} {item.get('status_kind')} status {item.get('status_id')}"
                    ),
                    "handler_name": item.get("handler_name"),
                    "operation": item.get("operation"),
                    "status_kind": item.get("status_kind"),
                    "status_id": item.get("status_id"),
                    "source": item.get("source", {}),
                    "execution_status": "read_only_panel_trace",
                    "mutation_status": item.get("execution_status"),
                }
            )
        for item in summary.get("dispatch_preview", []):
            if not isinstance(item, dict):
                continue
            steps.append(
                {
                    "step_index": len(steps),
                    "phase": phase,
                    "step_type": "dispatch_diagnostic",
                    "display_text": (
                        f"{item.get('section_type')} status {item.get('status_id')} "
                        f"conditions={item.get('condition_count')} scheduled={item.get('scheduled_mutation_count')}"
                    ),
                    "section_type": item.get("section_type"),
                    "status_id": item.get("status_id"),
                    "section_index": item.get("section_index"),
                    "diagnostic_status": item.get("diagnostic_status"),
                    "execution_status": "read_only_panel_trace",
                }
            )
    return {
        "schema": "hsl_script_vm_godot_panel_read_play_trace.v1",
        "consumer": "godot_imported_script_panel",
        "trace_policy": "read_only_panel_order_no_handler_no_live_mutation",
        "source_summary_schema": panel_phase_summaries.get("schema"),
        "phase_order": phase_order,
        "step_count": len(steps),
        "steps": steps,
        "unresolved_semantics": [
            "trace order is a Godot panel presentation order over imported event-log previews, not original runtime timing",
            "scheduled status steps are display-only diagnostics and do not mutate battle state",
        ],
    }


def build_godot_timeline_anchors(
    panel_phase_summaries: dict[str, Any],
    progress_boundary: dict[str, Any],
) -> dict[str, Any]:
    phase_order = panel_phase_summaries.get("phase_order", ["story", "win", "fail", "event"])
    if not isinstance(phase_order, list):
        phase_order = ["story", "win", "fail", "event"]
    phases = panel_phase_summaries.get("phases", {}) if isinstance(panel_phase_summaries, dict) else {}
    phase_anchors: dict[str, dict[str, Any]] = {}
    for phase in phase_order:
        if not isinstance(phase, str):
            continue
        summary = phases.get(phase, {}) if isinstance(phases, dict) else {}
        if not isinstance(summary, dict):
            summary = {}
        display_preview = [
            {
                "entry_index": item.get("entry_index"),
                "handler_name": item.get("handler_name"),
                "display_label": item.get("display_label"),
                "message_id_candidate": item.get("message_id_candidate"),
                "message_text_status": item.get("message_text_status"),
                "resource_action_type": item.get("resource_action_type"),
                "resource_ref_candidate": item.get("resource_ref_candidate"),
                "resource_text_status": item.get("resource_text_status"),
                "music_resource_status": item.get("music_resource_status"),
                "anchor_status": "read_only_visible_anchor",
            }
            for item in summary.get("display_label_preview", [])[:4]
            if isinstance(item, dict)
        ]
        scheduled_anchors = [
            {
                "entry_index": item.get("entry_index"),
                "handler_name": item.get("handler_name"),
                "operation": item.get("operation"),
                "status_kind": item.get("status_kind"),
                "status_id": item.get("status_id"),
                "mutation_status": item.get("execution_status"),
                "anchor_status": "scheduled_event_log_only",
            }
            for item in summary.get("scheduled_status_preview", [])[:8]
            if isinstance(item, dict)
        ]
        dispatch_anchors = [
            {
                "dispatch_index": item.get("dispatch_index"),
                "section_type": item.get("section_type"),
                "status_id": item.get("status_id"),
                "section_index": item.get("section_index"),
                "condition_count": item.get("condition_count"),
                "scheduled_mutation_count": item.get("scheduled_mutation_count"),
                "diagnostic_status": item.get("diagnostic_status"),
                "anchor_status": "visible_unresolved_dispatch",
            }
            for item in summary.get("dispatch_preview", [])[:8]
            if isinstance(item, dict)
        ]
        phase_anchors[phase] = {
            "display_name": summary.get("display_name", phase),
            "first_display_label": display_preview[0]["display_label"] if display_preview else None,
            "display_label_anchors": display_preview,
            "display_label_count": summary.get("display_label_count", 0),
            "scheduled_status_anchors": scheduled_anchors,
            "scheduled_status_count": summary.get("scheduled_status_count", 0),
            "dispatch_anchors": dispatch_anchors,
            "dispatch_count": summary.get("dispatch_count", 0),
            "anchor_policy": "read_only_phase_anchor_no_execution",
            "evidence_tier": "resource-derived",
        }
    return {
        "schema": "hsl_script_vm_godot_timeline_anchors.v1",
        "consumer": "godot_imported_script_panel",
        "anchor_policy": "read_only_timeline_anchors_no_handler_no_live_mutation",
        "phase_order": phase_order,
        "preview_limit": 4,
        "progress_boundary_anchor": {
            "source_schema": progress_boundary.get("source_schema"),
            "source_bridge_address": progress_boundary.get("source_bridge_address"),
            "evidence_status": progress_boundary.get("evidence_status"),
            "progress_boundary_status": progress_boundary.get("progress_boundary_status"),
            "script_cursor_field_offset": progress_boundary.get("script_cursor_field_offset"),
            "token_advance_count": progress_boundary.get("token_advance_count"),
            "script_cursor_write_count": progress_boundary.get("script_cursor_write_count"),
            "registry_write_status": progress_boundary.get("registry_write_status"),
            "deferred_queue_candidate_status": progress_boundary.get("deferred_queue_candidate_status"),
            "status_mutation_commit_timing_status": progress_boundary.get("status_mutation_commit_timing_status"),
            "status_mutation_commit_status": progress_boundary.get("status_mutation_commit_status"),
            "anchor_status": "diagnostic_only_not_commit_evidence",
        },
        "phases": phase_anchors,
        "unresolved_semantics": [
            "timeline anchors are stable Godot panel presentation metadata, not original runtime timing",
            "progress boundary anchor exposes interpreter cursor evidence only and does not prove status mutation commit semantics",
        ],
    }


def build_script_event_log_model(
    records: list[dict[str, Any]],
    section_dispatch: dict[str, list[dict[str, Any]]],
    progress_boundary: dict[str, Any],
    message_text_evidence: dict[str, Any] | None = None,
    message_text_evidence_path: Path | None = None,
) -> dict[str, Any]:
    event_log_entries: list[dict[str, Any]] = []
    supported_handler_counts: collections.Counter[str] = collections.Counter()
    unsupported_action_counts: collections.Counter[str] = collections.Counter()
    for record in records:
        name = str(record.get("name", ""))
        args = [str(arg) for arg in record.get("args", [])]
        if name in {"actMessage", "actMessageIfExist"}:
            supported_handler_counts[name] += 1
            entry: dict[str, Any] = {
                "entry_type": "message",
                "handler_name": name,
                "execution_status": "event_log_only",
                "args": args,
                "source": action_source(record),
                "evidence_tier": "resource-derived",
                "visible_fields": build_message_visible_fields(name, args),
                "unresolved_semantics": [
                    "message id and speaker/channel roles are imported script args; text lookup and exact playback timing are not claimed",
                ],
            }
            event_log_entries.append(entry)
        elif name == "actShowSectionName":
            supported_handler_counts[name] += 1
            resource_ref = args[0] if args else None
            event_log_entries.append(
                {
                    "entry_type": "resource_action",
                    "resource_action_type": "section_title_resource",
                    "handler_name": name,
                    "execution_status": "resource_event_log_only",
                    "args": args,
                    "source": action_source(record),
                    "evidence_tier": "resource-derived",
                    "visible_fields": {
                        "display_label": f"section title resource: {resource_ref or 'unknown'}",
                        "resource_ref_candidate": resource_ref,
                        "resource_text_status": "resource_ref_only_text_not_decoded",
                    },
                    "unresolved_semantics": [
                        "section title resource is visible as an imported resource reference only; shape/text rendering is not executed",
                    ],
                }
            )
        elif name == "actPlayLevelMusic":
            supported_handler_counts[name] += 1
            event_log_entries.append(
                {
                    "entry_type": "resource_action",
                    "resource_action_type": "music_action",
                    "handler_name": name,
                    "execution_status": "resource_event_log_only",
                    "args": args,
                    "source": action_source(record),
                    "evidence_tier": "resource-derived",
                    "visible_fields": {
                        "display_label": "play level music",
                        "music_resource_status": "implicit_or_unresolved",
                        "music_args": args,
                    },
                    "unresolved_semantics": [
                        "music action has no imported args here; exact resource id and playback behavior are unresolved",
                    ],
                }
            )
        else:
            mutation = classify_mutation(record)
            if mutation is not None:
                supported_handler_counts[name] += 1
                event_log_entries.append(
                    {
                        "entry_type": "scheduled_status_mutation",
                        "handler_name": name,
                        "execution_status": "scheduled_event_log_only",
                        "operation": mutation.get("operation"),
                        "status_kind": mutation.get("status_kind"),
                        "status_id": mutation.get("status_id"),
                        "args": args,
                        "source": action_source(record),
                        "evidence_tier": "resource-derived",
                        "unresolved_semantics": [
                            "status mutation is visible as a log entry only; live battle state is not mutated",
                        ],
                    }
                )
            else:
                unsupported_action_counts[name] += 1
    dispatch_diagnostics: list[dict[str, Any]] = []
    for kind in ("win", "fail", "event"):
        for section in section_dispatch.get(kind, []):
            if not isinstance(section, dict):
                continue
            dispatch_diagnostics.append(
                {
                    "entry_type": "dispatch_section_diagnostic",
                    "section_type": kind,
                    "status_id": section.get("status_id"),
                    "section_index": section.get("section_index"),
                    "section_name": section.get("section_name"),
                    "conditions": [
                        {
                            "name": condition.get("name"),
                            "args": condition.get("args", []),
                            "source": condition.get("source", {}),
                            "predicate_status": "unknown",
                        }
                        for condition in section.get("conditions", [])
                        if isinstance(condition, dict)
                    ],
                    "scheduled_mutations": [
                        {
                            "name": mutation.get("name"),
                            "operation": mutation.get("operation"),
                            "status_kind": mutation.get("status_kind"),
                            "status_id": mutation.get("status_id"),
                            "application_status": "scheduled_event_log_only",
                        }
                        for mutation in section.get("mutations", [])
                        if isinstance(mutation, dict)
                    ],
                    "diagnostic_status": "visible_unresolved_dispatch",
                    "evidence_tier": "resource-derived",
                    "unresolved_semantics": [
                        "dispatch section is visible diagnostics only; condition truth, priority, and commit timing remain unresolved",
                    ],
                }
            )
    phase_views = build_event_log_phase_views(event_log_entries, dispatch_diagnostics)
    panel_phase_summaries = build_godot_panel_phase_summaries(event_log_entries, dispatch_diagnostics, phase_views)
    panel_read_play_trace = build_godot_panel_read_play_trace(panel_phase_summaries)
    timeline_anchors = build_godot_timeline_anchors(panel_phase_summaries, progress_boundary)
    evidence_bridge: dict[str, Any] = {
        "status": "external_evidence_missing",
        "expected_path": message_text_evidence_path.as_posix() if message_text_evidence_path is not None else None,
        "unresolved_semantics": [
            "message text evidence file is optional; absence means text lookup remains unresolved",
        ],
    }
    if isinstance(message_text_evidence, dict):
        evidence_bridge = {
            "status": "loaded",
            "source_path": message_text_evidence_path.as_posix() if message_text_evidence_path is not None else None,
            "schema": message_text_evidence.get("schema"),
            "message_text_status": message_text_evidence.get("message_text_status"),
            "message_text_source_status": message_text_evidence.get("message_text_source_status"),
            "summary": message_text_evidence.get("summary", {}),
            "word_shape_resource_refs": message_text_evidence.get("word_shape_resource_refs", []),
            "structured_text_table_candidates": message_text_evidence.get("structured_text_table_candidates", []),
            "negative_evidence": message_text_evidence.get("negative_evidence", []),
            "unresolved_semantics": message_text_evidence.get("unresolved_semantics", []),
        }
    return {
        "schema": "hsl_script_vm_event_log_model.v1",
        "consumer": "godot_read_play_event_log",
        "evidence_tier": "resource-derived",
        "execution_policy": "read_only_event_log_no_live_battle_mutation",
        "supported_handler_subset": [
            "actMessage",
            "actMessageIfExist",
            "actInsertFailStatus",
            "actInsertEventStatus",
            "actDeleteEventStatus",
            "actInsertWinStatus",
            "actShowSectionName",
            "actPlayLevelMusic",
            "dispatch_section_diagnostic",
        ],
        "unsupported_action_policy": "preserve_as_unexecuted_counts",
        "message_text_resolution": {
            "status": "not_resolved_in_imported_assets",
            "available_readable_fields": [
                "speaker_or_channel_candidate",
                "portrait_or_mode_candidate",
                "message_id_candidate",
                "message_id_candidates",
                "display_label",
            ],
            "missing_evidence": "structured message text table or decoded dialogue resource for message ids",
            "evidence_bridge": evidence_bridge,
        },
        "phase_views": phase_views,
        "godot_panel_phase_summaries": panel_phase_summaries,
        "godot_panel_read_play_trace": panel_read_play_trace,
        "godot_timeline_anchors": timeline_anchors,
        "event_log_entries": event_log_entries,
        "dispatch_diagnostics": dispatch_diagnostics,
        "supported_handler_counts": dict(sorted(supported_handler_counts.items())),
        "unsupported_action_counts": dict(sorted(unsupported_action_counts.items())),
        "downstream_contract": {
            "godot": "may display event_log_entries and dispatch_diagnostics as imported-script read/play diagnostics",
            "battle_engine": "diagnostic_only_no_state_write",
        },
        "unresolved_semantics": [
            "event log is a minimal executable/readable subset, not a full VM or original-equivalent execution",
            "no opcode, dispatch slot, handler mapping, condition predicate, or live mutation evidence is claimed",
        ],
    }


def imported_script_field_audit(scripts: dict[str, dict[str, Any]]) -> dict[str, Any]:
    action_fields: set[str] = set()
    chain_item_fields: set[str] = set()
    flat_action_fields: set[str] = set()
    numeric_opcode_fields_found: set[str] = set()
    script_action_count = 0
    chain_item_count = 0
    flat_action_count = 0
    for script in scripts.values():
        for section in script.get("sections", []):
            if not isinstance(section, dict):
                continue
            for action in section.get("actions", []):
                if not isinstance(action, dict):
                    continue
                script_action_count += 1
                action_fields.update(str(key) for key in action)
                numeric_opcode_fields_found.update(str(key) for key in action if str(key) in NUMERIC_OPCODE_FIELD_NAMES)
                for item in action.get("chain", []):
                    if not isinstance(item, dict):
                        continue
                    chain_item_count += 1
                    chain_item_fields.update(str(key) for key in item)
                    numeric_opcode_fields_found.update(str(key) for key in item if str(key) in NUMERIC_OPCODE_FIELD_NAMES)
        for flat_action in script.get("action_chain", []):
            if not isinstance(flat_action, dict):
                continue
            flat_action_count += 1
            flat_action_fields.update(str(key) for key in flat_action)
            numeric_opcode_fields_found.update(str(key) for key in flat_action if str(key) in NUMERIC_OPCODE_FIELD_NAMES)
    status = "present" if numeric_opcode_fields_found else "missing_in_imported_ir"
    return {
        "schema": "hsl_imported_opcode_token_gap_audit.v1",
        "evidence_tier": "resource-derived",
        "source_numeric_opcode_status": status,
        "source_token_status": "action_name_tokens_only" if status == "missing_in_imported_ir" else "numeric_fields_present_needs_validation",
        "script_action_count_scanned": script_action_count,
        "chain_item_count_scanned": chain_item_count,
        "flat_action_count_scanned": flat_action_count,
        "observed_action_fields": sorted(action_fields),
        "observed_chain_item_fields": sorted(chain_item_fields),
        "observed_flat_action_fields": sorted(flat_action_fields),
        "numeric_opcode_field_candidates_checked": sorted(NUMERIC_OPCODE_FIELD_NAMES),
        "numeric_opcode_field_candidates_found": sorted(numeric_opcode_fields_found),
        "importer_parser_evidence": {
            "parser": "tools/hsl_payload_inspector.py::parse_action_chain",
            "parser_model": "text action names and comma-separated argument tokens",
            "raw_numeric_opcode_preservation": "not observed in current split IR",
        },
        "next_evidence_need": (
            "If raw script payload or EXE bridge exposes numeric action opcodes/tokens, preserve them as additional fields "
            "without removing current action name, args, order, chain, and source metadata."
        ),
        "unresolved_semantics": [
            "absence is based on current imported JSON fields, not proof that original runtime lacks numeric opcodes",
            "static navigation candidates must remain unresolved until numeric opcode/token evidence is imported or otherwise proven",
        ],
    }


def build_opcode_gap_guard_summary(
    gap_audit: dict[str, Any],
    condition_catalog: dict[str, Any],
    effect_catalog: dict[str, Any],
    lifecycle_model: dict[str, Any],
    dry_run_model: dict[str, Any],
) -> dict[str, Any]:
    section_lifecycle = lifecycle_model.get("section_lifecycle", {})
    guarded_status_section_count = 0
    if isinstance(section_lifecycle, dict):
        guarded_status_section_count = sum(
            len(sections)
            for sections in section_lifecycle.values()
            if isinstance(sections, list)
        )
    trace_examples = dry_run_model.get("trace_examples", {})
    status_static_hints = lifecycle_model.get("static_navigation_hints", {})
    status_static_by_action = {}
    if isinstance(status_static_hints, dict) and isinstance(status_static_hints.get("by_action"), dict):
        status_static_by_action = status_static_hints["by_action"]
    return {
        "schema": "hsl_opcode_gap_guard_summary.v1",
        "evidence_tier": "resource-derived",
        "source_numeric_opcode_status": gap_audit.get("source_numeric_opcode_status"),
        "guard_status": "active" if gap_audit.get("source_numeric_opcode_status") == "missing_in_imported_ir" else "pending_review",
        "active_guards": [
            "condition_static_navigation_hints_remain_unresolved",
            "action_effects_remain_facade_only",
            "status_lifecycle_remains_scheduled_only",
            "dry_run_trace_remains_candidate_only",
        ],
        "guarded_condition_action_count": len(condition_catalog.get("by_action", {})),
        "guarded_action_effect_count": len(effect_catalog.get("by_action", {})),
        "guarded_status_section_count": guarded_status_section_count,
        "guarded_status_lifecycle_hint_count": len(status_static_by_action),
        "guarded_dry_run_trace_example_count": len(trace_examples) if isinstance(trace_examples, dict) else 0,
        "consumer_note": "Godot diagnostic summary only; not an interpreter execution contract",
        "unresolved_semantics": [
            "guards stay active until numeric opcode/token evidence is imported or otherwise proven",
            "summary mirrors checker invariants and does not add handler or runtime evidence",
        ],
    }


def build_semantics(index_path: Path | str, static_index_path: Path | str | None = None) -> dict[str, Any]:
    index_path = Path(index_path)
    static_index_path = Path(static_index_path) if static_index_path is not None else default_static_index_path(index_path)
    message_text_evidence_path = default_message_text_evidence_path(index_path)
    index, scripts = load_scripts(index_path)
    story = scripts.get("story051", {})
    winfail = scripts.get("winfail051", {})
    all_records = iter_chain_actions(story) + iter_chain_actions(winfail)
    condition_summary = collections.Counter(str(record.get("name")) for record in all_records if record.get("name") in CONDITION_ACTIONS)
    mutation_summary = collections.Counter(str(record.get("name")) for record in all_records if record.get("name") in STATUS_INSERT_ACTIONS or record.get("name") in STATUS_DELETE_ACTIONS)
    status_registry = build_status_registry(all_records, winfail)
    section_dispatch = build_section_dispatch(winfail)
    action_catalog = build_action_semantics_catalog(all_records)
    condition_static_hints = load_condition_static_navigation_hints(static_index_path)
    status_static_hints = load_status_lifecycle_static_navigation_hints(static_index_path)
    status_commit_context = load_status_commit_path_static_context(static_index_path)
    condition_catalog = build_condition_predicate_catalog(all_records, condition_static_hints)
    effect_catalog = build_action_effect_facade_catalog(action_catalog)
    lifecycle_model = build_status_mutation_lifecycle_model(status_registry, section_dispatch, status_static_hints)
    dry_run_model = build_interpreter_dry_run_trace_model(section_dispatch, status_registry)
    progress_boundary = build_interpreter_progress_boundary(status_commit_context)
    event_log_model = build_script_event_log_model(
        all_records,
        section_dispatch,
        progress_boundary,
        load_message_text_evidence(message_text_evidence_path),
        message_text_evidence_path,
    )
    gap_audit = imported_script_field_audit(scripts)
    return {
        "schema": SCHEMA,
        "source_policy": (
            "resource-derived dry-run script VM semantics; preserves status ids, section dispatch, "
            "condition action args, action order, sources, unresolved semantics, and evidence tier without mutating battle state"
        ),
        "evidence_tier": "resource-derived",
        "source_index": index_path.as_posix(),
        "source_schema": index.get("schema"),
        "source_total_action_chain_count": index.get("total_action_chain_count"),
        "status_registry": status_registry,
        "section_dispatch": section_dispatch,
        "condition_summary": dict(sorted(condition_summary.items())),
        "mutation_summary": dict(sorted(mutation_summary.items())),
        "dispatch_correlation_hints": build_dispatch_correlation_hints(all_records),
        "action_semantics_catalog": action_catalog,
        "action_effect_facade_catalog": effect_catalog,
        "condition_predicate_catalog": condition_catalog,
        "status_mutation_lifecycle_model": lifecycle_model,
        "interpreter_dry_run_trace_model": dry_run_model,
        "script_event_log_model": event_log_model,
        "interpreter_progress_boundary": progress_boundary,
        "interpreter_facade_contract": build_interpreter_facade_contract(),
        "imported_opcode_token_gap_audit": gap_audit,
        "opcode_gap_guard_summary": build_opcode_gap_guard_summary(
            gap_audit,
            condition_catalog,
            effect_catalog,
            lifecycle_model,
            dry_run_model,
        ),
        "unresolved_semantics": [
            "status ids are resource script ids, not confirmed runtime memory ids",
            "condition action predicates preserve args but do not claim exact comparison semantics",
            "section dispatch is dry-run ordering metadata, not a live interpreter implementation",
        ],
    }


def check_semantics(path: Path | str) -> list[str]:
    path = Path(path)
    try:
        doc = load_json(path)
    except FileNotFoundError:
        return [f"missing file: {path}"]
    errors: list[str] = []
    if not isinstance(doc, dict):
        return ["script VM semantics root must be an object"]
    if doc.get("schema") != SCHEMA:
        errors.append(f"schema mismatch: expected {SCHEMA}, got {doc.get('schema')!r}")
    if doc.get("evidence_tier") != "resource-derived":
        errors.append(f"evidence_tier mismatch: {doc.get('evidence_tier')!r}")
    gap_audit = doc.get("imported_opcode_token_gap_audit")
    if not isinstance(gap_audit, dict):
        errors.append("imported_opcode_token_gap_audit must be an object")
    else:
        if gap_audit.get("schema") != "hsl_imported_opcode_token_gap_audit.v1":
            errors.append("imported_opcode_token_gap_audit.schema mismatch")
        found = gap_audit.get("numeric_opcode_field_candidates_found")
        if not isinstance(found, list):
            errors.append("imported_opcode_token_gap_audit.numeric_opcode_field_candidates_found must be a list")
        if gap_audit.get("source_numeric_opcode_status") != "missing_in_imported_ir":
            errors.append("imported_opcode_token_gap_audit.source_numeric_opcode_status must be missing_in_imported_ir")
        if gap_audit.get("source_token_status") != "action_name_tokens_only":
            errors.append("imported_opcode_token_gap_audit.source_token_status must be action_name_tokens_only")
        for key in ("script_action_count_scanned", "chain_item_count_scanned", "flat_action_count_scanned"):
            if not isinstance(gap_audit.get(key), int) or isinstance(gap_audit.get(key), bool) or gap_audit.get(key) <= 0:
                errors.append(f"imported_opcode_token_gap_audit.{key} must be a positive integer")
        parser_evidence = gap_audit.get("importer_parser_evidence")
        if not isinstance(parser_evidence, dict) or parser_evidence.get("parser") != "tools/hsl_payload_inspector.py::parse_action_chain":
            errors.append("imported_opcode_token_gap_audit.importer_parser_evidence.parser mismatch")
    registry = doc.get("status_registry")
    if not isinstance(registry, dict):
        errors.append("status_registry must be an object")
    else:
        for kind in ("fail", "event", "win"):
            item = registry.get(kind)
            if not isinstance(item, dict):
                errors.append(f"status_registry.{kind} must be an object")
                continue
            for key in ("initial_enabled_ids", "inserted_ids", "deleted_ids", "entries"):
                if not isinstance(item.get(key), list):
                    errors.append(f"status_registry.{kind}.{key} must be a list")
            if kind in {"fail", "event"} and not item.get("initial_enabled_ids"):
                errors.append(f"status_registry.{kind}.initial_enabled_ids must not be empty")
            if kind == "win" and not item.get("inserted_ids"):
                errors.append("status_registry.win.inserted_ids must not be empty")
    dispatch = doc.get("section_dispatch")
    if not isinstance(dispatch, dict):
        errors.append("section_dispatch must be an object")
    else:
        for kind in ("win", "fail", "event"):
            sections = dispatch.get(kind)
            if not isinstance(sections, list) or not sections:
                errors.append(f"section_dispatch.{kind} must be a non-empty list")
                continue
            for index, section in enumerate(sections):
                if not isinstance(section, dict):
                    errors.append(f"section_dispatch.{kind}[{index}] must be an object")
                    continue
                if not isinstance(section.get("conditions"), list):
                    errors.append(f"section_dispatch.{kind}[{index}].conditions must be a list")
                if not isinstance(section.get("mutations"), list):
                    errors.append(f"section_dispatch.{kind}[{index}].mutations must be a list")
                if not section.get("unresolved_semantics"):
                    errors.append(f"section_dispatch.{kind}[{index}].unresolved_semantics must not be empty")
    condition_summary = doc.get("condition_summary")
    if not isinstance(condition_summary, dict) or not condition_summary:
        errors.append("condition_summary must be a non-empty object")
    else:
        for name in CONDITION_ACTIONS:
            if name not in condition_summary:
                errors.append(f"condition_summary missing {name}")
    mutation_summary = doc.get("mutation_summary")
    if not isinstance(mutation_summary, dict) or not mutation_summary:
        errors.append("mutation_summary must be a non-empty object")
    else:
        for name in ("actInsertFailStatus", "actInsertEventStatus", "actInsertWinStatus"):
            if name not in mutation_summary:
                errors.append(f"mutation_summary missing {name}")
    hints = doc.get("dispatch_correlation_hints")
    if not isinstance(hints, dict):
        errors.append("dispatch_correlation_hints must be an object")
    else:
        if hints.get("correlation_status") != "unresolved":
            errors.append("dispatch_correlation_hints.correlation_status must be unresolved")
        names = hints.get("ordered_unique_action_names")
        if not isinstance(names, list) or not all(isinstance(name, str) and name for name in names):
            errors.append("dispatch_correlation_hints.ordered_unique_action_names must be a non-empty string list")
        targets = hints.get("static_targets")
        if not isinstance(targets, dict) or targets.get("script_action_dispatch_table") != "0x4537f4":
            errors.append("dispatch_correlation_hints.static_targets must include script_action_dispatch_table 0x4537f4")
    catalog = doc.get("action_semantics_catalog")
    if not isinstance(catalog, dict):
        errors.append("action_semantics_catalog must be an object")
    else:
        summary = catalog.get("category_summary")
        by_action = catalog.get("by_action")
        if not isinstance(summary, dict) or not summary:
            errors.append("action_semantics_catalog.category_summary must be a non-empty object")
        else:
            for category in ("condition", "status", "message"):
                if category not in summary:
                    errors.append(f"action_semantics_catalog.category_summary missing {category}")
        if not isinstance(by_action, dict) or not by_action:
            errors.append("action_semantics_catalog.by_action must be a non-empty object")
        elif "actMessage" not in by_action:
            errors.append("action_semantics_catalog.by_action missing actMessage")
    effect_catalog = doc.get("action_effect_facade_catalog")
    if not isinstance(effect_catalog, dict):
        errors.append("action_effect_facade_catalog must be an object")
    else:
        if effect_catalog.get("semantic_status") != "facade_only":
            errors.append("action_effect_facade_catalog.semantic_status must be facade_only")
        if effect_catalog.get("handler_mapping_status") != "unresolved":
            errors.append("action_effect_facade_catalog.handler_mapping_status must be unresolved")
        if effect_catalog.get("execution_policy") != "no_handlers_no_live_mutation":
            errors.append("action_effect_facade_catalog.execution_policy must be no_handlers_no_live_mutation")
        if effect_catalog.get("evidence_tier") != "resource-derived":
            errors.append("action_effect_facade_catalog.evidence_tier must be resource-derived")
        summary = effect_catalog.get("effect_family_summary")
        if not isinstance(summary, dict) or not summary:
            errors.append("action_effect_facade_catalog.effect_family_summary must be a non-empty object")
        else:
            for family in ("message", "movement", "object"):
                if family not in summary:
                    errors.append(f"action_effect_facade_catalog.effect_family_summary missing {family}")
        by_effect_action = effect_catalog.get("by_action")
        if not isinstance(by_effect_action, dict) or not by_effect_action:
            errors.append("action_effect_facade_catalog.by_action must be a non-empty object")
        elif "actMessage" not in by_effect_action:
            errors.append("action_effect_facade_catalog.by_action missing actMessage")
        else:
            for name, item in by_effect_action.items():
                if not isinstance(item, dict):
                    errors.append(f"action_effect_facade_catalog.by_action.{name} must be an object")
                    continue
                if item.get("facade_mode") != "diagnostic_trace_only":
                    errors.append(f"action_effect_facade_catalog.by_action.{name}.facade_mode must be diagnostic_trace_only")
                if item.get("effect_status") != "candidate_unresolved":
                    errors.append(f"action_effect_facade_catalog.by_action.{name}.effect_status must be candidate_unresolved")
                if item.get("handler_mapping_status") != "unresolved":
                    errors.append(f"action_effect_facade_catalog.by_action.{name}.handler_mapping_status must be unresolved")
                requests = item.get("evidence_requests")
                request_text = json.dumps(requests, ensure_ascii=False)
                if not isinstance(requests, dict):
                    errors.append(f"action_effect_facade_catalog.by_action.{name}.evidence_requests must be an object")
                else:
                    if "0x4537f4" not in request_text:
                        errors.append(f"action_effect_facade_catalog.by_action.{name}.evidence_requests must request 0x4537f4 evidence")
                    if "script_phase" in request_text:
                        errors.append(f"action_effect_facade_catalog.by_action.{name}.evidence_requests must not request generic script_phase")
            if isinstance(gap_audit, dict) and gap_audit.get("source_numeric_opcode_status") == "missing_in_imported_ir":
                for name, item in by_effect_action.items():
                    if not isinstance(item, dict):
                        continue
                    if (
                        item.get("facade_mode") != "diagnostic_trace_only"
                        or item.get("effect_status") != "candidate_unresolved"
                        or item.get("handler_mapping_status") != "unresolved"
                    ):
                        errors.append(
                            f"action_effect_facade_catalog.by_action.{name} must remain facade-only while missing imported opcode evidence"
                        )
    predicate_catalog = doc.get("condition_predicate_catalog")
    if not isinstance(predicate_catalog, dict):
        errors.append("condition_predicate_catalog must be an object")
    else:
        if predicate_catalog.get("semantic_status") != "unresolved":
            errors.append("condition_predicate_catalog.semantic_status must be unresolved")
        if predicate_catalog.get("evidence_tier") != "resource-derived":
            errors.append("condition_predicate_catalog.evidence_tier must be resource-derived")
        by_condition = predicate_catalog.get("by_action")
        if not isinstance(by_condition, dict) or not by_condition:
            errors.append("condition_predicate_catalog.by_action must be a non-empty object")
        else:
            for name in CONDITION_ACTIONS:
                if name not in by_condition:
                    errors.append(f"condition_predicate_catalog.by_action missing {name}")
                    continue
                item = by_condition.get(name)
                if not isinstance(item, dict):
                    errors.append(f"condition_predicate_catalog.by_action.{name} must be an object")
                    continue
                if item.get("predicate_status") != "unknown":
                    errors.append(f"condition_predicate_catalog.by_action.{name}.predicate_status must be unknown")
                if not isinstance(item.get("args_schema_candidate"), list) or not item.get("args_schema_candidate"):
                    errors.append(f"condition_predicate_catalog.by_action.{name}.args_schema_candidate must be a non-empty list")
                if not isinstance(item.get("candidate_context_binding"), str) or not item.get("candidate_context_binding"):
                    errors.append(f"condition_predicate_catalog.by_action.{name}.candidate_context_binding must be a non-empty string")
                if item.get("source_numeric_opcode_status") != "missing_in_imported_ir":
                    errors.append(f"condition_predicate_catalog.by_action.{name}.source_numeric_opcode_status must be missing_in_imported_ir")
                static_hint = item.get("static_navigation_hint")
                if not isinstance(static_hint, dict):
                    errors.append(f"condition_predicate_catalog.by_action.{name}.static_navigation_hint must be an object")
                else:
                    if static_hint.get("correlation_status") not in {"unresolved", "missing"}:
                        errors.append(f"condition_predicate_catalog.by_action.{name}.static_navigation_hint.correlation_status must remain unresolved or missing")
                    if static_hint.get("ordinal_as_slot_status") not in {"not_evidence", None}:
                        errors.append(f"condition_predicate_catalog.by_action.{name}.static_navigation_hint.ordinal_as_slot_status must be not_evidence")
                    if static_hint.get("slot_opcode_evidence_status") not in {"unresolved", "missing"}:
                        errors.append(f"condition_predicate_catalog.by_action.{name}.static_navigation_hint.slot_opcode_evidence_status must remain unresolved or missing")
                    if static_hint.get("comparison_polarity_evidence_status") not in {"unresolved", "missing"}:
                        errors.append(f"condition_predicate_catalog.by_action.{name}.static_navigation_hint.comparison_polarity_evidence_status must remain unresolved or missing")
                if not isinstance(item.get("occurrences"), list) or not item.get("occurrences"):
                    errors.append(f"condition_predicate_catalog.by_action.{name}.occurrences must be a non-empty list")
                requests = item.get("evidence_requests")
                request_text = json.dumps(requests, ensure_ascii=False)
                if not isinstance(requests, dict):
                    errors.append(f"condition_predicate_catalog.by_action.{name}.evidence_requests must be an object")
                else:
                    if "0x4537f4" not in request_text:
                        errors.append(f"condition_predicate_catalog.by_action.{name}.evidence_requests must request 0x4537f4 evidence")
                    if "script_phase" in request_text:
                        errors.append(f"condition_predicate_catalog.by_action.{name}.evidence_requests must not request generic script_phase")
        if isinstance(gap_audit, dict) and gap_audit.get("source_numeric_opcode_status") == "missing_in_imported_ir":
            for name, item in by_condition.items() if isinstance(by_condition, dict) else []:
                if not isinstance(item, dict):
                    continue
                static_hint = item.get("static_navigation_hint")
                if not isinstance(static_hint, dict):
                    continue
                if (
                    static_hint.get("correlation_status") not in {"unresolved", "missing"}
                    or static_hint.get("ordinal_as_slot_status") not in {"not_evidence", None}
                    or static_hint.get("slot_opcode_evidence_status") not in {"unresolved", "missing"}
                ):
                    errors.append(
                        f"condition_predicate_catalog.by_action.{name}.static_navigation_hint must remain navigation-only while missing imported opcode evidence"
                    )
    lifecycle = doc.get("status_mutation_lifecycle_model")
    if not isinstance(lifecycle, dict):
        errors.append("status_mutation_lifecycle_model must be an object")
    else:
        if lifecycle.get("semantic_status") != "unresolved":
            errors.append("status_mutation_lifecycle_model.semantic_status must be unresolved")
        if lifecycle.get("evidence_tier") != "resource-derived":
            errors.append("status_mutation_lifecycle_model.evidence_tier must be resource-derived")
        if lifecycle.get("dry_run_state_transition_policy") != "scheduled_only_no_live_mutation":
            errors.append("status_mutation_lifecycle_model.dry_run_state_transition_policy must be scheduled_only_no_live_mutation")
        initial_enabled = lifecycle.get("initial_enabled_status")
        if not isinstance(initial_enabled, dict):
            errors.append("status_mutation_lifecycle_model.initial_enabled_status must be an object")
        else:
            for kind in ("win", "fail", "event"):
                if not isinstance(initial_enabled.get(kind), list):
                    errors.append(f"status_mutation_lifecycle_model.initial_enabled_status.{kind} must be a list")
        section_lifecycle = lifecycle.get("section_lifecycle")
        if not isinstance(section_lifecycle, dict):
            errors.append("status_mutation_lifecycle_model.section_lifecycle must be an object")
        else:
            for kind in ("win", "fail", "event"):
                sections = section_lifecycle.get(kind)
                if not isinstance(sections, list) or not sections:
                    errors.append(f"status_mutation_lifecycle_model.section_lifecycle.{kind} must be a non-empty list")
                    continue
                for section_index, section in enumerate(sections):
                    if not isinstance(section, dict):
                        errors.append(f"status_mutation_lifecycle_model.section_lifecycle.{kind}[{section_index}] must be an object")
                        continue
                    if section.get("dispatch_timing_status") != "unknown":
                        errors.append(
                            f"status_mutation_lifecycle_model.section_lifecycle.{kind}[{section_index}].dispatch_timing_status must be unknown"
                        )
                    mutations = section.get("scheduled_mutations")
                    if not isinstance(mutations, list):
                        errors.append(
                            f"status_mutation_lifecycle_model.section_lifecycle.{kind}[{section_index}].scheduled_mutations must be a list"
                        )
                        continue
                    for mutation_index, mutation in enumerate(mutations):
                        if not isinstance(mutation, dict):
                            errors.append(
                                f"status_mutation_lifecycle_model.section_lifecycle.{kind}[{section_index}].scheduled_mutations[{mutation_index}] must be an object"
                            )
                            continue
                        if mutation.get("application_status") != "scheduled_only":
                            errors.append(
                                f"status_mutation_lifecycle_model.section_lifecycle.{kind}[{section_index}].scheduled_mutations[{mutation_index}].application_status must be scheduled_only"
                            )
        status_static_hints = lifecycle.get("static_navigation_hints")
        if not isinstance(status_static_hints, dict):
            errors.append("status_mutation_lifecycle_model.static_navigation_hints must be an object")
            status_static_by_action = {}
        else:
            if status_static_hints.get("semantic_status") != "unresolved":
                errors.append("status_mutation_lifecycle_model.static_navigation_hints.semantic_status must be unresolved")
            if status_static_hints.get("navigation_policy") != "navigation_only_not_opcode_evidence":
                errors.append("status_mutation_lifecycle_model.static_navigation_hints.navigation_policy must be navigation_only_not_opcode_evidence")
            status_static_by_action = status_static_hints.get("by_action")
            if not isinstance(status_static_by_action, dict):
                errors.append("status_mutation_lifecycle_model.static_navigation_hints.by_action must be an object")
                status_static_by_action = {}
            else:
                for name, hint in status_static_by_action.items():
                    if not isinstance(hint, dict):
                        errors.append(f"status_mutation_lifecycle_model.static_navigation_hints.by_action.{name} must be an object")
                        continue
                    if hint.get("correlation_status") != "unresolved":
                        errors.append(f"status_mutation_lifecycle_model.static_navigation_hints.by_action.{name}.correlation_status must be unresolved")
                    if hint.get("ordinal_as_slot_status") != "not_evidence":
                        errors.append(f"status_mutation_lifecycle_model.static_navigation_hints.by_action.{name}.ordinal_as_slot_status must be not_evidence")
                    if hint.get("slot_opcode_evidence_status") != "unresolved":
                        errors.append(f"status_mutation_lifecycle_model.static_navigation_hints.by_action.{name}.slot_opcode_evidence_status must be unresolved")
                    if hint.get("commit_timing_evidence_status") != "unresolved":
                        errors.append(f"status_mutation_lifecycle_model.static_navigation_hints.by_action.{name}.commit_timing_evidence_status must be unresolved")
                    if hint.get("lifecycle_semantic_status") != "scheduled_only":
                        errors.append(f"status_mutation_lifecycle_model.static_navigation_hints.by_action.{name}.lifecycle_semantic_status must be scheduled_only")
                    if hint.get("bridge_commit_timing_status") not in {"unresolved", None}:
                        errors.append(f"status_mutation_lifecycle_model.static_navigation_hints.by_action.{name}.bridge_commit_timing_status must be unresolved")
        if isinstance(gap_audit, dict) and gap_audit.get("source_numeric_opcode_status") == "missing_in_imported_ir":
            lifecycle_requires_opcode = (
                lifecycle.get("semantic_status") != "unresolved"
                or lifecycle.get("dry_run_state_transition_policy") != "scheduled_only_no_live_mutation"
            )
            if not lifecycle_requires_opcode and isinstance(section_lifecycle, dict):
                for sections in section_lifecycle.values():
                    if not isinstance(sections, list):
                        continue
                    for section in sections:
                        if not isinstance(section, dict):
                            continue
                        for mutation in section.get("scheduled_mutations", []):
                            if isinstance(mutation, dict) and mutation.get("application_status") != "scheduled_only":
                                lifecycle_requires_opcode = True
            if not lifecycle_requires_opcode and isinstance(status_static_by_action, dict):
                for hint in status_static_by_action.values():
                    if not isinstance(hint, dict):
                        continue
                    if (
                        hint.get("correlation_status") != "unresolved"
                        or hint.get("ordinal_as_slot_status") != "not_evidence"
                        or hint.get("slot_opcode_evidence_status") != "unresolved"
                        or hint.get("commit_timing_evidence_status") != "unresolved"
                        or hint.get("lifecycle_semantic_status") != "scheduled_only"
                        or hint.get("bridge_commit_timing_status") not in {"unresolved", None}
                    ):
                        lifecycle_requires_opcode = True
            if lifecycle_requires_opcode:
                errors.append(
                    "status_mutation_lifecycle_model must remain scheduled-only while missing imported opcode evidence"
                )
    dry_run = doc.get("interpreter_dry_run_trace_model")
    if not isinstance(dry_run, dict):
        errors.append("interpreter_dry_run_trace_model must be an object")
    else:
        if dry_run.get("schema") != "hsl_script_vm_interpreter_dry_run_trace.v1":
            errors.append("interpreter_dry_run_trace_model.schema mismatch")
        if dry_run.get("evidence_tier") != "resource-derived":
            errors.append("interpreter_dry_run_trace_model.evidence_tier must be resource-derived")
        examples = dry_run.get("trace_examples")
        if not isinstance(examples, dict) or not examples:
            errors.append("interpreter_dry_run_trace_model.trace_examples must be a non-empty object")
        else:
            for name, trace in examples.items():
                if not isinstance(trace, dict):
                    errors.append(f"interpreter_dry_run_trace_model.trace_examples.{name} must be an object")
                    continue
                dispatch = trace.get("dispatch")
                if not isinstance(dispatch, dict):
                    errors.append(f"interpreter_dry_run_trace_model.trace_examples.{name}.dispatch must be an object")
                    continue
                for kind in ("win", "fail", "event"):
                    sections = dispatch.get(kind)
                    if not isinstance(sections, list):
                        errors.append(f"interpreter_dry_run_trace_model.trace_examples.{name}.dispatch.{kind} must be a list")
                        continue
                    for section_index, section in enumerate(sections):
                        if not isinstance(section, dict):
                            errors.append(
                                f"interpreter_dry_run_trace_model.trace_examples.{name}.dispatch.{kind}[{section_index}] must be an object"
                            )
                            continue
                        candidate = section.get("candidate_result")
                        if candidate not in {"candidate_true", "candidate_false", "unknown"}:
                            errors.append(
                                f"interpreter_dry_run_trace_model.trace_examples.{name}.dispatch.{kind}[{section_index}].candidate_result invalid"
                            )
                        if isinstance(gap_audit, dict) and gap_audit.get("source_numeric_opcode_status") == "missing_in_imported_ir":
                            trace_requires_opcode = candidate not in {"candidate_true", "candidate_false", "unknown"}
                            scheduled_mutations = section.get("scheduled_mutations", [])
                            if isinstance(scheduled_mutations, list):
                                for mutation in scheduled_mutations:
                                    if isinstance(mutation, dict) and mutation.get("application_status") in {
                                        "applied",
                                        "live_mutation",
                                        "committed",
                                    }:
                                        trace_requires_opcode = True
                            if trace_requires_opcode:
                                errors.append(
                                    f"interpreter_dry_run_trace_model.trace_examples.{name}.dispatch.{kind}[{section_index}] must remain candidate-only while missing imported opcode evidence"
                                )
                        if not section.get("unresolved_semantics"):
                            errors.append(
                                f"interpreter_dry_run_trace_model.trace_examples.{name}.dispatch.{kind}[{section_index}].unresolved_semantics must not be empty"
                            )
    event_log = doc.get("script_event_log_model")
    if not isinstance(event_log, dict):
        errors.append("script_event_log_model must be an object")
    else:
        if event_log.get("schema") != "hsl_script_vm_event_log_model.v1":
            errors.append("script_event_log_model.schema mismatch")
        if event_log.get("consumer") != "godot_read_play_event_log":
            errors.append("script_event_log_model.consumer must be godot_read_play_event_log")
        if event_log.get("evidence_tier") != "resource-derived":
            errors.append("script_event_log_model.evidence_tier must be resource-derived")
        if event_log.get("execution_policy") != "read_only_event_log_no_live_battle_mutation":
            errors.append("script_event_log_model.execution_policy must be read_only_event_log_no_live_battle_mutation")
        supported_subset = event_log.get("supported_handler_subset")
        required_handlers = {
            "actMessage",
            "actInsertFailStatus",
            "actInsertEventStatus",
            "actDeleteEventStatus",
            "actInsertWinStatus",
            "actShowSectionName",
            "actPlayLevelMusic",
            "dispatch_section_diagnostic",
        }
        if not isinstance(supported_subset, list) or not required_handlers.issubset(set(supported_subset)):
            errors.append("script_event_log_model.supported_handler_subset missing required handlers")
        phase_views = event_log.get("phase_views")
        if not isinstance(phase_views, dict):
            errors.append("script_event_log_model.phase_views must be an object")
        else:
            if phase_views.get("schema") != "hsl_script_vm_event_log_phase_views.v1":
                errors.append("script_event_log_model.phase_views.schema mismatch")
            if phase_views.get("consumer") != "godot_read_play_event_log":
                errors.append("script_event_log_model.phase_views.consumer must be godot_read_play_event_log")
            if phase_views.get("presentation_policy") != "read_only_grouping_no_execution":
                errors.append("script_event_log_model.phase_views.presentation_policy must be read_only_grouping_no_execution")
            if phase_views.get("phase_order") != ["story", "win", "fail", "event"]:
                errors.append("script_event_log_model.phase_views.phase_order mismatch")
            views = phase_views.get("views")
            if not isinstance(views, dict):
                errors.append("script_event_log_model.phase_views.views must be an object")
            else:
                for phase in ("story", "win", "fail", "event"):
                    view = views.get(phase)
                    if not isinstance(view, dict):
                        errors.append(f"script_event_log_model.phase_views.views.{phase} must be an object")
                        continue
                    entry_indexes = view.get("entry_indexes")
                    dispatch_indexes = view.get("dispatch_indexes")
                    if not isinstance(entry_indexes, list) or not all(isinstance(item, int) and not isinstance(item, bool) for item in entry_indexes):
                        errors.append(f"script_event_log_model.phase_views.views.{phase}.entry_indexes must be integer list")
                    if not isinstance(dispatch_indexes, list) or not all(isinstance(item, int) and not isinstance(item, bool) for item in dispatch_indexes):
                        errors.append(f"script_event_log_model.phase_views.views.{phase}.dispatch_indexes must be integer list")
                    if isinstance(entry_indexes, list) and view.get("entry_count") != len(entry_indexes):
                        errors.append(f"script_event_log_model.phase_views.views.{phase}.entry_count mismatch")
                    if isinstance(dispatch_indexes, list) and view.get("dispatch_count") != len(dispatch_indexes):
                        errors.append(f"script_event_log_model.phase_views.views.{phase}.dispatch_count mismatch")
                    if view.get("read_policy") not in {"ordered_event_log_only", "ordered_dispatch_diagnostics_only"}:
                        errors.append(f"script_event_log_model.phase_views.views.{phase}.read_policy invalid")
        panel_summaries = event_log.get("godot_panel_phase_summaries")
        if not isinstance(panel_summaries, dict):
            errors.append("script_event_log_model.godot_panel_phase_summaries must be an object")
        else:
            if panel_summaries.get("schema") != "hsl_script_vm_godot_panel_phase_summaries.v1":
                errors.append("script_event_log_model.godot_panel_phase_summaries.schema mismatch")
            if panel_summaries.get("consumer") != "godot_imported_script_panel":
                errors.append("script_event_log_model.godot_panel_phase_summaries.consumer must be godot_imported_script_panel")
            if panel_summaries.get("summary_policy") != "read_only_preview_no_handler_no_live_mutation":
                errors.append("script_event_log_model.godot_panel_phase_summaries.summary_policy must be read_only_preview_no_handler_no_live_mutation")
            if panel_summaries.get("phase_order") != ["story", "win", "fail", "event"]:
                errors.append("script_event_log_model.godot_panel_phase_summaries.phase_order mismatch")
            phases = panel_summaries.get("phases")
            if not isinstance(phases, dict):
                errors.append("script_event_log_model.godot_panel_phase_summaries.phases must be an object")
            else:
                for phase in ("story", "win", "fail", "event"):
                    summary = phases.get(phase)
                    if not isinstance(summary, dict):
                        errors.append(f"script_event_log_model.godot_panel_phase_summaries.phases.{phase} must be an object")
                        continue
                    if summary.get("panel_policy") != "read_only_summary_no_execution":
                        errors.append(f"script_event_log_model.godot_panel_phase_summaries.phases.{phase}.panel_policy must be read_only_summary_no_execution")
                    for key in ("display_label_preview", "scheduled_status_preview", "dispatch_preview"):
                        if not isinstance(summary.get(key), list):
                            errors.append(f"script_event_log_model.godot_panel_phase_summaries.phases.{phase}.{key} must be a list")
                    if isinstance(summary.get("display_label_preview"), list):
                        if not isinstance(summary.get("display_label_count"), int) or summary.get("display_label_count") < len(summary["display_label_preview"]):
                            errors.append(f"script_event_log_model.godot_panel_phase_summaries.phases.{phase}.display_label_count invalid")
                        for item in summary["display_label_preview"]:
                            if not isinstance(item, dict) or not isinstance(item.get("display_label"), str):
                                errors.append(f"script_event_log_model.godot_panel_phase_summaries.phases.{phase}.display_label_preview item invalid")
                                continue
                            if item.get("resource_action_type"):
                                if item.get("resource_action_type") not in {"section_title_resource", "music_action"}:
                                    errors.append(
                                        f"script_event_log_model.godot_panel_phase_summaries.phases.{phase}.display_label_preview resource_action_type invalid"
                                    )
                            elif item.get("message_text_status") != "not_resolved_in_imported_assets":
                                errors.append(
                                    f"script_event_log_model.godot_panel_phase_summaries.phases.{phase}.display_label_preview message_text_status must be unresolved"
                                )
                    if isinstance(summary.get("scheduled_status_preview"), list):
                        if not isinstance(summary.get("scheduled_status_count"), int) or summary.get("scheduled_status_count") < len(
                            summary["scheduled_status_preview"]
                        ):
                            errors.append(f"script_event_log_model.godot_panel_phase_summaries.phases.{phase}.scheduled_status_count invalid")
                        for item in summary["scheduled_status_preview"]:
                            if not isinstance(item, dict) or item.get("execution_status") != "scheduled_event_log_only":
                                errors.append(
                                    f"script_event_log_model.godot_panel_phase_summaries.phases.{phase}.scheduled_status_preview item must be scheduled_event_log_only"
                                )
                    if isinstance(summary.get("dispatch_preview"), list):
                        if not isinstance(summary.get("dispatch_count"), int) or summary.get("dispatch_count") < len(summary["dispatch_preview"]):
                            errors.append(f"script_event_log_model.godot_panel_phase_summaries.phases.{phase}.dispatch_count invalid")
                        for item in summary["dispatch_preview"]:
                            if not isinstance(item, dict) or item.get("diagnostic_status") != "visible_unresolved_dispatch":
                                errors.append(
                                    f"script_event_log_model.godot_panel_phase_summaries.phases.{phase}.dispatch_preview item must be visible_unresolved_dispatch"
                                )
        panel_trace = event_log.get("godot_panel_read_play_trace")
        if not isinstance(panel_trace, dict):
            errors.append("script_event_log_model.godot_panel_read_play_trace must be an object")
        else:
            if panel_trace.get("schema") != "hsl_script_vm_godot_panel_read_play_trace.v1":
                errors.append("script_event_log_model.godot_panel_read_play_trace.schema mismatch")
            if panel_trace.get("consumer") != "godot_imported_script_panel":
                errors.append("script_event_log_model.godot_panel_read_play_trace.consumer must be godot_imported_script_panel")
            if panel_trace.get("trace_policy") != "read_only_panel_order_no_handler_no_live_mutation":
                errors.append(
                    "script_event_log_model.godot_panel_read_play_trace.trace_policy must be read_only_panel_order_no_handler_no_live_mutation"
                )
            if panel_trace.get("phase_order") != ["story", "win", "fail", "event"]:
                errors.append("script_event_log_model.godot_panel_read_play_trace.phase_order mismatch")
            steps = panel_trace.get("steps")
            if not isinstance(steps, list) or not steps:
                errors.append("script_event_log_model.godot_panel_read_play_trace.steps must be a non-empty list")
            else:
                if panel_trace.get("step_count") != len(steps):
                    errors.append("script_event_log_model.godot_panel_read_play_trace.step_count mismatch")
                for index, step in enumerate(steps):
                    if not isinstance(step, dict):
                        errors.append(f"script_event_log_model.godot_panel_read_play_trace.steps[{index}] must be an object")
                        continue
                    if step.get("step_index") != index:
                        errors.append(f"script_event_log_model.godot_panel_read_play_trace.steps[{index}].step_index mismatch")
                    if step.get("phase") not in {"story", "win", "fail", "event"}:
                        errors.append(f"script_event_log_model.godot_panel_read_play_trace.steps[{index}].phase invalid")
                    if step.get("step_type") not in {"display_label", "resource_action", "scheduled_status", "dispatch_diagnostic"}:
                        errors.append(f"script_event_log_model.godot_panel_read_play_trace.steps[{index}].step_type invalid")
                    if step.get("execution_status") != "read_only_panel_trace":
                        errors.append(
                            f"script_event_log_model.godot_panel_read_play_trace.steps[{index}].execution_status must be read_only_panel_trace"
                        )
                    if not isinstance(step.get("display_text"), str) or not step.get("display_text"):
                        errors.append(f"script_event_log_model.godot_panel_read_play_trace.steps[{index}].display_text must be non-empty")
                    if step.get("step_type") == "display_label" and step.get("message_text_status") != "not_resolved_in_imported_assets":
                        errors.append(
                            f"script_event_log_model.godot_panel_read_play_trace.steps[{index}].message_text_status must remain unresolved"
                        )
                    if step.get("step_type") == "resource_action" and step.get("resource_action_type") not in {
                        "section_title_resource",
                        "music_action",
                    }:
                        errors.append(f"script_event_log_model.godot_panel_read_play_trace.steps[{index}].resource_action_type invalid")
                    if step.get("step_type") == "scheduled_status" and step.get("mutation_status") != "scheduled_event_log_only":
                        errors.append(
                            f"script_event_log_model.godot_panel_read_play_trace.steps[{index}].mutation_status must be scheduled_event_log_only"
                        )
                    if step.get("step_type") == "dispatch_diagnostic" and step.get("diagnostic_status") != "visible_unresolved_dispatch":
                        errors.append(
                            f"script_event_log_model.godot_panel_read_play_trace.steps[{index}].diagnostic_status must be visible_unresolved_dispatch"
                        )
        timeline_anchors = event_log.get("godot_timeline_anchors")
        if not isinstance(timeline_anchors, dict):
            errors.append("script_event_log_model.godot_timeline_anchors must be an object")
        else:
            if timeline_anchors.get("schema") != "hsl_script_vm_godot_timeline_anchors.v1":
                errors.append("script_event_log_model.godot_timeline_anchors.schema mismatch")
            if timeline_anchors.get("consumer") != "godot_imported_script_panel":
                errors.append("script_event_log_model.godot_timeline_anchors.consumer must be godot_imported_script_panel")
            if timeline_anchors.get("anchor_policy") != "read_only_timeline_anchors_no_handler_no_live_mutation":
                errors.append("script_event_log_model.godot_timeline_anchors.anchor_policy invalid")
            if timeline_anchors.get("phase_order") != ["story", "win", "fail", "event"]:
                errors.append("script_event_log_model.godot_timeline_anchors.phase_order mismatch")
            progress_anchor = timeline_anchors.get("progress_boundary_anchor")
            if not isinstance(progress_anchor, dict):
                errors.append("script_event_log_model.godot_timeline_anchors.progress_boundary_anchor must be an object")
            else:
                if progress_anchor.get("anchor_status") != "diagnostic_only_not_commit_evidence":
                    errors.append("script_event_log_model.godot_timeline_anchors.progress_boundary_anchor.anchor_status invalid")
                if progress_anchor.get("evidence_status") not in {"missing_static_context", "static_cursor_progress_loaded"}:
                    errors.append("script_event_log_model.godot_timeline_anchors.progress_boundary_anchor.evidence_status invalid")
                if progress_anchor.get("evidence_status") == "static_cursor_progress_loaded":
                    if progress_anchor.get("source_bridge_address") != "0x450840":
                        errors.append("script_event_log_model.godot_timeline_anchors.progress_boundary_anchor.source_bridge_address must be 0x450840")
                    if progress_anchor.get("progress_boundary_status") != "script_cursor_progress_observed":
                        errors.append(
                            "script_event_log_model.godot_timeline_anchors.progress_boundary_anchor.progress_boundary_status invalid"
                        )
                for key in (
                    "registry_write_status",
                    "deferred_queue_candidate_status",
                    "status_mutation_commit_timing_status",
                    "status_mutation_commit_status",
                ):
                    if progress_anchor.get(key) != "unresolved":
                        errors.append(f"script_event_log_model.godot_timeline_anchors.progress_boundary_anchor.{key} must remain unresolved")
            phases = timeline_anchors.get("phases")
            if not isinstance(phases, dict):
                errors.append("script_event_log_model.godot_timeline_anchors.phases must be an object")
            else:
                for phase in ("story", "win", "fail", "event"):
                    anchor_phase = phases.get(phase)
                    if not isinstance(anchor_phase, dict):
                        errors.append(f"script_event_log_model.godot_timeline_anchors.phases.{phase} must be an object")
                        continue
                    if anchor_phase.get("anchor_policy") != "read_only_phase_anchor_no_execution":
                        errors.append(f"script_event_log_model.godot_timeline_anchors.phases.{phase}.anchor_policy invalid")
                    for key in ("display_label_anchors", "scheduled_status_anchors", "dispatch_anchors"):
                        if not isinstance(anchor_phase.get(key), list):
                            errors.append(f"script_event_log_model.godot_timeline_anchors.phases.{phase}.{key} must be a list")
                    for item in anchor_phase.get("display_label_anchors", []) if isinstance(anchor_phase.get("display_label_anchors"), list) else []:
                        if not isinstance(item, dict) or item.get("anchor_status") != "read_only_visible_anchor":
                            errors.append(
                                f"script_event_log_model.godot_timeline_anchors.phases.{phase}.display_label_anchors item invalid"
                            )
                            continue
                        if item.get("resource_action_type"):
                            if item.get("resource_action_type") not in {"section_title_resource", "music_action"}:
                                errors.append(
                                    f"script_event_log_model.godot_timeline_anchors.phases.{phase}.display_label_anchors resource_action_type invalid"
                                )
                        elif item.get("message_text_status") != "not_resolved_in_imported_assets":
                            errors.append(
                                f"script_event_log_model.godot_timeline_anchors.phases.{phase}.display_label_anchors message_text_status must remain unresolved"
                            )
                    for item in anchor_phase.get("scheduled_status_anchors", []) if isinstance(anchor_phase.get("scheduled_status_anchors"), list) else []:
                        if not isinstance(item, dict) or item.get("anchor_status") != "scheduled_event_log_only":
                            errors.append(
                                f"script_event_log_model.godot_timeline_anchors.phases.{phase}.scheduled_status_anchors item invalid"
                            )
                        if isinstance(item, dict) and item.get("mutation_status") != "scheduled_event_log_only":
                            errors.append(
                                f"script_event_log_model.godot_timeline_anchors.phases.{phase}.scheduled_status_anchors mutation_status invalid"
                            )
                    for item in anchor_phase.get("dispatch_anchors", []) if isinstance(anchor_phase.get("dispatch_anchors"), list) else []:
                        if not isinstance(item, dict) or item.get("anchor_status") != "visible_unresolved_dispatch":
                            errors.append(f"script_event_log_model.godot_timeline_anchors.phases.{phase}.dispatch_anchors item invalid")
                        if isinstance(item, dict) and item.get("diagnostic_status") != "visible_unresolved_dispatch":
                            errors.append(
                                f"script_event_log_model.godot_timeline_anchors.phases.{phase}.dispatch_anchors diagnostic_status invalid"
                            )
        text_resolution = event_log.get("message_text_resolution")
        if not isinstance(text_resolution, dict):
            errors.append("script_event_log_model.message_text_resolution must be an object")
        else:
            if text_resolution.get("status") != "not_resolved_in_imported_assets":
                errors.append("script_event_log_model.message_text_resolution.status must be not_resolved_in_imported_assets")
            readable_fields = text_resolution.get("available_readable_fields")
            for required_field in ("message_id_candidate", "message_id_candidates", "display_label"):
                if not isinstance(readable_fields, list) or required_field not in readable_fields:
                    errors.append(f"script_event_log_model.message_text_resolution.available_readable_fields missing {required_field}")
            evidence_bridge = text_resolution.get("evidence_bridge")
            if not isinstance(evidence_bridge, dict):
                errors.append("script_event_log_model.message_text_resolution.evidence_bridge must be an object")
            else:
                if evidence_bridge.get("status") not in {"external_evidence_missing", "loaded"}:
                    errors.append("script_event_log_model.message_text_resolution.evidence_bridge.status invalid")
                if evidence_bridge.get("status") == "loaded":
                    if evidence_bridge.get("schema") != "hsl_chapter01_imported_message_text_evidence.v1":
                        errors.append("script_event_log_model.message_text_resolution.evidence_bridge.schema mismatch")
                    if evidence_bridge.get("message_text_status") != "not_resolved_in_imported_assets":
                        errors.append(
                            "script_event_log_model.message_text_resolution.evidence_bridge.message_text_status must remain not_resolved_in_imported_assets"
                        )
                    if evidence_bridge.get("message_text_source_status") != "missing_structured_text_table":
                        errors.append(
                            "script_event_log_model.message_text_resolution.evidence_bridge.message_text_source_status must be missing_structured_text_table"
                        )
                    if not isinstance(evidence_bridge.get("negative_evidence"), list) or not evidence_bridge.get("negative_evidence"):
                        errors.append("script_event_log_model.message_text_resolution.evidence_bridge.negative_evidence must be a non-empty list")
                    if not isinstance(evidence_bridge.get("word_shape_resource_refs"), list):
                        errors.append("script_event_log_model.message_text_resolution.evidence_bridge.word_shape_resource_refs must be a list")
        entries = event_log.get("event_log_entries")
        if not isinstance(entries, list) or not entries:
            errors.append("script_event_log_model.event_log_entries must be a non-empty list")
        else:
            message_count = 0
            status_count = 0
            for index, entry in enumerate(entries):
                if not isinstance(entry, dict):
                    errors.append(f"script_event_log_model.event_log_entries[{index}] must be an object")
                    continue
                entry_type = entry.get("entry_type")
                if entry_type == "message":
                    message_count += 1
                    if entry.get("execution_status") != "event_log_only":
                        errors.append(f"script_event_log_model.event_log_entries[{index}].execution_status must be event_log_only")
                    visible_fields = entry.get("visible_fields")
                    if not isinstance(visible_fields, dict) or not visible_fields.get("message_id_candidate"):
                        errors.append(f"script_event_log_model.event_log_entries[{index}].visible_fields.message_id_candidate missing")
                    elif visible_fields.get("message_text_status") != "not_resolved_in_imported_assets":
                        errors.append(
                            f"script_event_log_model.event_log_entries[{index}].visible_fields.message_text_status must be not_resolved_in_imported_assets"
                        )
                    if isinstance(visible_fields, dict):
                        if not isinstance(visible_fields.get("message_id_candidates"), list) or not visible_fields.get("message_id_candidates"):
                            errors.append(f"script_event_log_model.event_log_entries[{index}].visible_fields.message_id_candidates missing")
                        if not isinstance(visible_fields.get("display_label"), str) or "message#" not in visible_fields.get("display_label", ""):
                            errors.append(f"script_event_log_model.event_log_entries[{index}].visible_fields.display_label invalid")
                        if entry.get("handler_name") == "actMessageIfExist" and not isinstance(
                            visible_fields.get("conditional_or_fallback_message_id_candidates"), list
                        ):
                            errors.append(
                                f"script_event_log_model.event_log_entries[{index}].visible_fields.conditional_or_fallback_message_id_candidates must be a list"
                            )
                elif entry_type == "resource_action":
                    if entry.get("execution_status") != "resource_event_log_only":
                        errors.append(
                            f"script_event_log_model.event_log_entries[{index}].execution_status must be resource_event_log_only"
                        )
                    if entry.get("resource_action_type") not in {"section_title_resource", "music_action"}:
                        errors.append(f"script_event_log_model.event_log_entries[{index}].resource_action_type invalid")
                    visible_fields = entry.get("visible_fields")
                    if not isinstance(visible_fields, dict) or not isinstance(visible_fields.get("display_label"), str):
                        errors.append(f"script_event_log_model.event_log_entries[{index}].visible_fields.display_label invalid")
                    if (
                        entry.get("resource_action_type") == "section_title_resource"
                        and isinstance(visible_fields, dict)
                        and visible_fields.get("resource_text_status") != "resource_ref_only_text_not_decoded"
                    ):
                        errors.append(f"script_event_log_model.event_log_entries[{index}].visible_fields.resource_text_status invalid")
                    if (
                        entry.get("resource_action_type") == "music_action"
                        and isinstance(visible_fields, dict)
                        and visible_fields.get("music_resource_status") != "implicit_or_unresolved"
                    ):
                        errors.append(f"script_event_log_model.event_log_entries[{index}].visible_fields.music_resource_status invalid")
                elif entry_type == "scheduled_status_mutation":
                    status_count += 1
                    if entry.get("execution_status") != "scheduled_event_log_only":
                        errors.append(
                            f"script_event_log_model.event_log_entries[{index}].execution_status must be scheduled_event_log_only"
                        )
                    if entry.get("status_kind") not in {"win", "fail", "event"}:
                        errors.append(f"script_event_log_model.event_log_entries[{index}].status_kind invalid")
                    if entry.get("operation") not in {"insert", "delete"}:
                        errors.append(f"script_event_log_model.event_log_entries[{index}].operation invalid")
                else:
                    errors.append(f"script_event_log_model.event_log_entries[{index}].entry_type invalid")
                if entry.get("evidence_tier") != "resource-derived":
                    errors.append(f"script_event_log_model.event_log_entries[{index}].evidence_tier must be resource-derived")
            if message_count == 0:
                errors.append("script_event_log_model.event_log_entries must include message entries")
            if status_count == 0:
                errors.append("script_event_log_model.event_log_entries must include scheduled status mutation entries")
        dispatch_entries = event_log.get("dispatch_diagnostics")
        if not isinstance(dispatch_entries, list) or not dispatch_entries:
            errors.append("script_event_log_model.dispatch_diagnostics must be a non-empty list")
        else:
            for index, entry in enumerate(dispatch_entries):
                if not isinstance(entry, dict):
                    errors.append(f"script_event_log_model.dispatch_diagnostics[{index}] must be an object")
                    continue
                if entry.get("entry_type") != "dispatch_section_diagnostic":
                    errors.append(f"script_event_log_model.dispatch_diagnostics[{index}].entry_type must be dispatch_section_diagnostic")
                if entry.get("diagnostic_status") != "visible_unresolved_dispatch":
                    errors.append(f"script_event_log_model.dispatch_diagnostics[{index}].diagnostic_status must be visible_unresolved_dispatch")
                if not isinstance(entry.get("conditions"), list):
                    errors.append(f"script_event_log_model.dispatch_diagnostics[{index}].conditions must be a list")
                if not isinstance(entry.get("scheduled_mutations"), list):
                    errors.append(f"script_event_log_model.dispatch_diagnostics[{index}].scheduled_mutations must be a list")
        if isinstance(phase_views, dict) and isinstance(entries, list) and isinstance(dispatch_entries, list):
            views = phase_views.get("views", {})
            if isinstance(views, dict):
                for phase, view in views.items():
                    if not isinstance(view, dict):
                        continue
                    for entry_index in view.get("entry_indexes", []):
                        if not isinstance(entry_index, int) or isinstance(entry_index, bool) or entry_index < 0 or entry_index >= len(entries):
                            errors.append(f"script_event_log_model.phase_views.views.{phase}.entry_indexes contains out-of-range index")
                            continue
                        source = entries[entry_index].get("source", {}) if isinstance(entries[entry_index], dict) else {}
                        if not isinstance(source, dict) or source.get("section_type") != phase:
                            errors.append(f"script_event_log_model.phase_views.views.{phase}.entry_indexes references wrong phase")
                    for dispatch_index in view.get("dispatch_indexes", []):
                        if (
                            not isinstance(dispatch_index, int)
                            or isinstance(dispatch_index, bool)
                            or dispatch_index < 0
                            or dispatch_index >= len(dispatch_entries)
                        ):
                            errors.append(f"script_event_log_model.phase_views.views.{phase}.dispatch_indexes contains out-of-range index")
                            continue
                        if not isinstance(dispatch_entries[dispatch_index], dict) or dispatch_entries[dispatch_index].get("section_type") != phase:
                            errors.append(f"script_event_log_model.phase_views.views.{phase}.dispatch_indexes references wrong phase")
        event_log_text = json.dumps(event_log, ensure_ascii=False)
        for forbidden in ("handler_confirmed", "original_equivalent"):
            if forbidden in event_log_text:
                errors.append(f"script_event_log_model must not claim {forbidden}")
        if "script_phase" in event_log_text:
            errors.append("script_event_log_model must not request generic script_phase")
    progress_boundary = doc.get("interpreter_progress_boundary")
    if not isinstance(progress_boundary, dict):
        errors.append("interpreter_progress_boundary must be an object")
    else:
        if progress_boundary.get("schema") != "hsl_script_vm_interpreter_progress_boundary.v1":
            errors.append("interpreter_progress_boundary.schema mismatch")
        if progress_boundary.get("execution_policy") != "read_only_boundary_diagnostic_no_live_mutation":
            errors.append("interpreter_progress_boundary.execution_policy must be read_only_boundary_diagnostic_no_live_mutation")
        if progress_boundary.get("evidence_status") not in {"missing_static_context", "static_cursor_progress_loaded"}:
            errors.append("interpreter_progress_boundary.evidence_status invalid")
        if progress_boundary.get("evidence_status") == "static_cursor_progress_loaded":
            if progress_boundary.get("source_schema") != "hsl_static_script_status_commit_path_context.v1":
                errors.append("interpreter_progress_boundary.source_schema mismatch")
            if progress_boundary.get("source_bridge_address") != "0x450840":
                errors.append("interpreter_progress_boundary.source_bridge_address must be 0x450840")
            if progress_boundary.get("progress_boundary_status") != "script_cursor_progress_observed":
                errors.append("interpreter_progress_boundary.progress_boundary_status must be script_cursor_progress_observed")
            for key in ("token_advance_count", "script_cursor_write_count", "return_count"):
                if not isinstance(progress_boundary.get(key), int) or isinstance(progress_boundary.get(key), bool) or progress_boundary.get(key) <= 0:
                    errors.append(f"interpreter_progress_boundary.{key} must be a positive integer")
        if progress_boundary.get("registry_write_status") != "unresolved":
            errors.append("interpreter_progress_boundary.registry_write_status must remain unresolved")
        if progress_boundary.get("deferred_queue_candidate_status") != "unresolved":
            errors.append("interpreter_progress_boundary.deferred_queue_candidate_status must remain unresolved")
        if progress_boundary.get("status_mutation_commit_timing_status") != "unresolved":
            errors.append("interpreter_progress_boundary.status_mutation_commit_timing_status must remain unresolved")
        if progress_boundary.get("status_mutation_commit_status") != "unresolved":
            errors.append("interpreter_progress_boundary.status_mutation_commit_status must remain unresolved")
        candidates = progress_boundary.get("status_handler_boundary_candidates")
        if candidates is not None:
            if not isinstance(candidates, list):
                errors.append("interpreter_progress_boundary.status_handler_boundary_candidates must be a list")
            else:
                for index, item in enumerate(candidates):
                    if not isinstance(item, dict):
                        errors.append(f"interpreter_progress_boundary.status_handler_boundary_candidates[{index}] must be an object")
                        continue
                    if item.get("correlation_status") != "unresolved":
                        errors.append(f"interpreter_progress_boundary.status_handler_boundary_candidates[{index}].correlation_status must be unresolved")
                    if item.get("ordinal_as_slot_status") != "not_evidence":
                        errors.append(f"interpreter_progress_boundary.status_handler_boundary_candidates[{index}].ordinal_as_slot_status must be not_evidence")
                    if item.get("commit_timing_evidence_status") != "unresolved":
                        errors.append(
                            f"interpreter_progress_boundary.status_handler_boundary_candidates[{index}].commit_timing_evidence_status must be unresolved"
                        )
                    if item.get("navigation_policy") != "navigation_only_not_commit_evidence":
                        errors.append(
                            f"interpreter_progress_boundary.status_handler_boundary_candidates[{index}].navigation_policy must be navigation_only_not_commit_evidence"
                        )
    facade_contract = doc.get("interpreter_facade_contract")
    if not isinstance(facade_contract, dict):
        errors.append("interpreter_facade_contract must be an object")
    else:
        if facade_contract.get("schema") != "hsl_script_vm_interpreter_facade_contract.v1":
            errors.append("interpreter_facade_contract.schema mismatch")
        if facade_contract.get("consumer") != "godot_dry_run_diagnostics":
            errors.append("interpreter_facade_contract.consumer must be godot_dry_run_diagnostics")
        if facade_contract.get("execution_policy") != "read_only_no_handlers_no_live_mutation":
            errors.append("interpreter_facade_contract.execution_policy must be read_only_no_handlers_no_live_mutation")
        if facade_contract.get("allows_handler_execution") is not False:
            errors.append("interpreter_facade_contract.allows_handler_execution must be false")
        if facade_contract.get("allows_live_battle_mutation") is not False:
            errors.append("interpreter_facade_contract.allows_live_battle_mutation must be false")
        if facade_contract.get("allows_evidence_tier_upgrade") is not False:
            errors.append("interpreter_facade_contract.allows_evidence_tier_upgrade must be false")
        facade_guard = facade_contract.get("guard_summary")
        if not isinstance(facade_guard, dict):
            errors.append("interpreter_facade_contract.guard_summary must be an object")
        else:
            if facade_guard.get("schema") != "hsl_script_vm_facade_guard_summary.v1":
                errors.append("interpreter_facade_contract.guard_summary.schema mismatch")
            if facade_guard.get("required_imported_opcode_status") != "missing_in_imported_ir":
                errors.append("interpreter_facade_contract.guard_summary.required_imported_opcode_status must be missing_in_imported_ir")
            if facade_guard.get("required_opcode_gap_guard_status") != "active":
                errors.append("interpreter_facade_contract.guard_summary.required_opcode_gap_guard_status must be active")
            for key in (
                "read_only_inputs_only",
                "no_handler_execution",
                "no_live_battle_mutation",
                "no_evidence_tier_upgrade",
                "no_generic_phase_label_evidence",
            ):
                if facade_guard.get(key) is not True:
                    errors.append(f"interpreter_facade_contract.guard_summary.{key} must be true")
            if facade_guard.get("static_navigation_hints_are_opcode_evidence") is not False:
                errors.append("interpreter_facade_contract.guard_summary.static_navigation_hints_are_opcode_evidence must be false")
            if facade_guard.get("allowed_evidence_tier") != "resource-derived":
                errors.append("interpreter_facade_contract.guard_summary.allowed_evidence_tier must be resource-derived")
            if (
                isinstance(gap_audit, dict)
                and facade_guard.get("required_imported_opcode_status") != gap_audit.get("source_numeric_opcode_status")
            ):
                errors.append("interpreter_facade_contract.guard_summary opcode status disagrees with imported_opcode_token_gap_audit")
        stable_inputs = facade_contract.get("stable_inputs")
        required_inputs = {
            "condition_predicate_catalog",
            "status_mutation_lifecycle_model",
            "action_effect_facade_catalog",
            "interpreter_dry_run_trace_model",
            "script_event_log_model",
        }
        if not isinstance(stable_inputs, list) or not required_inputs.issubset(set(stable_inputs)):
            errors.append("interpreter_facade_contract.stable_inputs missing required facade inputs")
        invariants = facade_contract.get("cross_field_invariants")
        if not isinstance(invariants, dict):
            errors.append("interpreter_facade_contract.cross_field_invariants must be an object")
        else:
            condition_invariants = invariants.get("condition_predicates", {})
            if condition_invariants.get("semantic_status") != "unresolved":
                errors.append("interpreter_facade_contract.condition_predicates.semantic_status must be unresolved")
            if condition_invariants.get("source_numeric_opcode_status") != "missing_in_imported_ir":
                errors.append("interpreter_facade_contract.condition_predicates.source_numeric_opcode_status must be missing_in_imported_ir")
            allowed_hint_status = condition_invariants.get("static_navigation_hint_correlation_status")
            if allowed_hint_status != ["missing", "unresolved"]:
                errors.append("interpreter_facade_contract.condition_predicates.static_navigation_hint_correlation_status must be ['missing', 'unresolved']")
            lifecycle_invariants = invariants.get("status_lifecycle", {})
            if lifecycle_invariants.get("dry_run_state_transition_policy") != "scheduled_only_no_live_mutation":
                errors.append("interpreter_facade_contract.status_lifecycle.dry_run_state_transition_policy must be scheduled_only_no_live_mutation")
            effect_invariants = invariants.get("action_effects", {})
            if effect_invariants.get("execution_policy") != "no_handlers_no_live_mutation":
                errors.append("interpreter_facade_contract.action_effects.execution_policy must be no_handlers_no_live_mutation")
            dry_run_invariants = invariants.get("dry_run_trace", {})
            if dry_run_invariants.get("schema") != "hsl_script_vm_interpreter_dry_run_trace.v1":
                errors.append("interpreter_facade_contract.dry_run_trace.schema mismatch")
        contract_text = json.dumps(facade_contract, ensure_ascii=False)
        if "script_phase" in contract_text:
            errors.append("interpreter_facade_contract must not request generic script_phase")
        if (
            isinstance(predicate_catalog, dict)
            and isinstance(facade_contract.get("cross_field_invariants"), dict)
            and predicate_catalog.get("semantic_status")
            != facade_contract["cross_field_invariants"].get("condition_predicates", {}).get("semantic_status")
        ):
            errors.append("interpreter_facade_contract condition semantic_status disagrees with condition_predicate_catalog")
        if (
            isinstance(lifecycle, dict)
            and isinstance(facade_contract.get("cross_field_invariants"), dict)
            and lifecycle.get("dry_run_state_transition_policy")
            != facade_contract["cross_field_invariants"].get("status_lifecycle", {}).get("dry_run_state_transition_policy")
        ):
            errors.append("interpreter_facade_contract lifecycle policy disagrees with status_mutation_lifecycle_model")
        if (
            isinstance(effect_catalog, dict)
            and isinstance(facade_contract.get("cross_field_invariants"), dict)
            and effect_catalog.get("execution_policy")
            != facade_contract["cross_field_invariants"].get("action_effects", {}).get("execution_policy")
        ):
            errors.append("interpreter_facade_contract effect execution policy disagrees with action_effect_facade_catalog")
    guard_summary = doc.get("opcode_gap_guard_summary")
    if not isinstance(guard_summary, dict):
        errors.append("opcode_gap_guard_summary must be an object")
    else:
        if guard_summary.get("schema") != "hsl_opcode_gap_guard_summary.v1":
            errors.append("opcode_gap_guard_summary.schema mismatch")
        if isinstance(gap_audit, dict) and gap_audit.get("source_numeric_opcode_status") == "missing_in_imported_ir":
            if guard_summary.get("guard_status") != "active":
                errors.append("opcode_gap_guard_summary.guard_status must be active while imported opcode evidence is missing")
        if isinstance(gap_audit, dict) and guard_summary.get("source_numeric_opcode_status") != gap_audit.get("source_numeric_opcode_status"):
            errors.append("opcode_gap_guard_summary.source_numeric_opcode_status disagrees with imported_opcode_token_gap_audit")
        expected_guards = [
            "condition_static_navigation_hints_remain_unresolved",
            "action_effects_remain_facade_only",
            "status_lifecycle_remains_scheduled_only",
            "dry_run_trace_remains_candidate_only",
        ]
        if guard_summary.get("active_guards") != expected_guards:
            errors.append("opcode_gap_guard_summary.active_guards mismatch")
        if isinstance(predicate_catalog, dict):
            by_condition = predicate_catalog.get("by_action", {})
            if isinstance(by_condition, dict) and guard_summary.get("guarded_condition_action_count") != len(by_condition):
                errors.append("opcode_gap_guard_summary.guarded_condition_action_count disagrees with condition_predicate_catalog")
        if isinstance(effect_catalog, dict):
            by_effect_action = effect_catalog.get("by_action", {})
            if isinstance(by_effect_action, dict) and guard_summary.get("guarded_action_effect_count") != len(by_effect_action):
                errors.append("opcode_gap_guard_summary.guarded_action_effect_count disagrees with action_effect_facade_catalog")
        if isinstance(lifecycle, dict):
            section_lifecycle = lifecycle.get("section_lifecycle", {})
            expected_section_count = 0
            if isinstance(section_lifecycle, dict):
                expected_section_count = sum(len(sections) for sections in section_lifecycle.values() if isinstance(sections, list))
            if guard_summary.get("guarded_status_section_count") != expected_section_count:
                errors.append("opcode_gap_guard_summary.guarded_status_section_count disagrees with status_mutation_lifecycle_model")
            status_static_hints = lifecycle.get("static_navigation_hints", {})
            status_static_by_action = {}
            if isinstance(status_static_hints, dict) and isinstance(status_static_hints.get("by_action"), dict):
                status_static_by_action = status_static_hints["by_action"]
            if guard_summary.get("guarded_status_lifecycle_hint_count") != len(status_static_by_action):
                errors.append("opcode_gap_guard_summary.guarded_status_lifecycle_hint_count disagrees with status_mutation_lifecycle_model")
        if isinstance(dry_run, dict):
            trace_examples = dry_run.get("trace_examples", {})
            expected_trace_count = len(trace_examples) if isinstance(trace_examples, dict) else 0
            if guard_summary.get("guarded_dry_run_trace_example_count") != expected_trace_count:
                errors.append("opcode_gap_guard_summary.guarded_dry_run_trace_example_count disagrees with interpreter_dry_run_trace_model")
        if "script_phase" in json.dumps(guard_summary, ensure_ascii=False):
            errors.append("opcode_gap_guard_summary must not request generic script_phase")
        if isinstance(facade_contract, dict):
            facade_guard = facade_contract.get("guard_summary", {})
            if (
                isinstance(facade_guard, dict)
                and facade_guard.get("required_opcode_gap_guard_status") != guard_summary.get("guard_status")
            ):
                errors.append("interpreter_facade_contract.guard_summary required guard status disagrees with opcode_gap_guard_summary")
    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Build or validate HSL chapter-one script VM dry-run semantics.")
    parser.add_argument("script_ir_index", type=Path)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--check", action="store_true", help="Validate an existing semantics JSON path instead of generating.")
    args = parser.parse_args(argv)
    if args.check:
        errors = check_semantics(args.script_ir_index)
        if errors:
            print(f"FAIL hsl script VM semantics ({len(errors)} error(s))")
            for error in errors:
                print(f"- {error}")
            return 1
        print("PASS hsl script VM semantics")
        return 0
    doc = build_semantics(args.script_ir_index)
    if args.out is not None:
        write_json(doc, args.out)
        print(f"wrote {args.out}")
    else:
        print(json.dumps(doc, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
