from __future__ import annotations

import argparse
import collections
import json
from pathlib import Path
from typing import Any


SCHEMA = "hsl_chapter01_script_runtime_probe_targets.v1"
PHASE_ORDER = ["story", "win", "fail", "event"]
CONDITION_ACTIONS = {
    "actCheckEnemyNumber",
    "actCheckEnemyTotalNumber",
    "actCheckPlayer",
    "actCheckPlayerArrivePos",
    "actCheckRoundNumber",
}
STATUS_INSERT_ACTIONS = {
    "actInsertFailStatus": "fail",
    "actInsertEventStatus": "event",
    "actInsertWinStatus": "win",
}
STATUS_DELETE_ACTIONS = {
    "actDeleteEventStatus": "event",
}
RESOURCE_ACTIONS = {
    "actShowSectionName": "section_title_resource",
    "actPlayLevelMusic": "music_action",
}
MESSAGE_ACTIONS = {"actMessage", "actMessageIfExist"}
MOVEMENT_ACTIONS = {
    "actWalkDispWait": "scripted_unit_walk",
    "actWalkAndDeleteWait": "scripted_unit_walk_delete",
    "actWalkPrevInsertObjectWait": "scripted_unit_walk_prev_insert_object",
    "actScrollBGToPos": "scripted_camera_scroll",
}
OBJECT_ACTIONS = {
    "actInsertObject": "scripted_object_insert",
    "actInsertShowPosObject": "scripted_object_show_pos_insert",
    "actDeleteShowPosObject": "scripted_object_show_pos_delete",
    "actChangePrevInsertObjectID": "scripted_object_id_change",
}


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def load_scripts(index_path: Path) -> tuple[dict[str, Any], dict[str, dict[str, Any]]]:
    index = load_json(index_path)
    root = index_path.parent
    scripts: dict[str, dict[str, Any]] = {}
    for item in index.get("scripts", []):
        if not isinstance(item, dict):
            continue
        script_id = str(item.get("id", ""))
        file_ref = item.get("file")
        if not script_id or not isinstance(file_ref, str):
            continue
        scripts[script_id] = load_json(root / file_ref)
    return index, scripts


def section_phase(section: dict[str, Any]) -> str:
    phase = str(section.get("type") or section.get("name") or "unknown").lower()
    return phase if phase in PHASE_ORDER else "unknown"


def source_for(
    script: dict[str, Any],
    section: dict[str, Any],
    action: dict[str, Any],
    chain_index: int,
) -> dict[str, Any]:
    phase = section_phase(section)
    return {
        "script_id": script.get("id"),
        "source_file": script.get("source_file") or script.get("source_id"),
        "section_type": phase,
        "section_name": section.get("name"),
        "section_index": section.get("index"),
        "section_codes": section.get("codes", []),
        "section_messages": section.get("messages", []),
        "action_index": action.get("index"),
        "chain_index": chain_index,
    }


def occurrence_key(source: dict[str, Any], action_name: str) -> str:
    return (
        f"{source.get('script_id')}:{source.get('section_type')}[{source.get('section_index')}]:"
        f"action[{source.get('action_index')}]:chain[{source.get('chain_index')}]:{action_name}"
    )


def message_ids_for_action(action_name: str, args: list[str]) -> list[str]:
    if action_name == "actMessage":
        if len(args) >= 3:
            return [args[2]]
        return [args[-1]] if args else []
    if action_name == "actMessageIfExist":
        result: list[str] = []
        for arg in args[2:4]:
            if arg.lstrip("-").isdigit() and arg not in result:
                result.append(arg)
        return result
    return []


def target_phase_hint(source: dict[str, Any], action_name: str) -> str:
    phase = source.get("section_type")
    if phase == "story":
        if action_name in MESSAGE_ACTIONS:
            return "dialogue"
        if action_name in {"actWalkDispWait", "actScrollBGToPos"}:
            return "scripted_scene_motion"
        return "scripted_story_setup"
    if phase in {"win", "fail", "event"}:
        if action_name in CONDITION_ACTIONS:
            return f"{phase}_condition_dispatch"
        if action_name in STATUS_INSERT_ACTIONS or action_name in STATUS_DELETE_ACTIONS:
            return f"{phase}_scheduled_status_mutation"
        if action_name in MESSAGE_ACTIONS:
            return f"{phase}_message"
        return f"{phase}_section_action"
    return "unknown"


def iter_chain_targets(scripts: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    targets: list[dict[str, Any]] = []
    for script_id in sorted(scripts):
        script = scripts[script_id]
        for section in script.get("sections", []):
            if not isinstance(section, dict):
                continue
            for action in section.get("actions", []):
                if not isinstance(action, dict):
                    continue
                for chain_index, chain_item in enumerate(action.get("chain", [])):
                    if not isinstance(chain_item, dict):
                        continue
                    action_name = str(chain_item.get("name") or action.get("name") or action.get("primary") or "")
                    if not action_name:
                        continue
                    args = [str(arg) for arg in chain_item.get("args", [])]
                    source = source_for(script, section, action, chain_index)
                    target = {
                        "occurrence_key": occurrence_key(source, action_name),
                        "action_name": action_name,
                        "args": args,
                        "phase_hint": target_phase_hint(source, action_name),
                        "source": source,
                        "evidence_tier": "resource-derived",
                        "probe_use": "runtime target selector only; does not prove handler semantics or opcode mapping",
                    }
                    targets.append(target)
    return targets


def build_message_targets(action_targets: list[dict[str, Any]]) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for target in action_targets:
        action_name = str(target.get("action_name", ""))
        if action_name not in MESSAGE_ACTIONS:
            continue
        args = [str(arg) for arg in target.get("args", [])]
        message_ids = message_ids_for_action(action_name, args)
        result.append(
            {
                "occurrence_key": target.get("occurrence_key"),
                "action_name": action_name,
                "speaker_or_channel_candidate": args[0] if args else None,
                "portrait_or_mode_candidate": args[1] if len(args) >= 2 else None,
                "message_id_candidates": message_ids,
                "primary_message_id_candidate": message_ids[0] if message_ids else None,
                "phase_hint": target.get("phase_hint"),
                "source": target.get("source", {}),
                "message_text_status": "not_resolved_in_imported_assets",
                "probe_use": "target dialogue/message UI moment by imported message id and source order",
                "evidence_tier": "resource-derived",
            }
        )
    return result


def build_resource_targets(action_targets: list[dict[str, Any]]) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for target in action_targets:
        action_name = str(target.get("action_name", ""))
        if action_name not in RESOURCE_ACTIONS:
            continue
        args = [str(arg) for arg in target.get("args", [])]
        result.append(
            {
                "occurrence_key": target.get("occurrence_key"),
                "action_name": action_name,
                "resource_action_type": RESOURCE_ACTIONS[action_name],
                "resource_ref_candidate": args[0] if args else None,
                "args": args,
                "phase_hint": target.get("phase_hint"),
                "source": target.get("source", {}),
                "resource_resolution_status": "resource_ref_only_or_implicit",
                "probe_use": "target visible resource/audio UI moment from imported action order",
                "evidence_tier": "resource-derived",
            }
        )
    return result


def build_status_targets(action_targets: list[dict[str, Any]]) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for target in action_targets:
        action_name = str(target.get("action_name", ""))
        operation: str | None = None
        status_kind: str | None = None
        if action_name in STATUS_INSERT_ACTIONS:
            operation = "insert"
            status_kind = STATUS_INSERT_ACTIONS[action_name]
        elif action_name in STATUS_DELETE_ACTIONS:
            operation = "delete"
            status_kind = STATUS_DELETE_ACTIONS[action_name]
        if operation is None:
            continue
        args = [str(arg) for arg in target.get("args", [])]
        result.append(
            {
                "occurrence_key": target.get("occurrence_key"),
                "action_name": action_name,
                "operation": operation,
                "status_kind": status_kind,
                "status_id": args[0] if args else None,
                "phase_hint": target.get("phase_hint"),
                "source": target.get("source", {}),
                "mutation_status": "scheduled_only_no_live_mutation",
                "commit_evidence_status": "unresolved",
                "probe_use": "target status scheduling moment only; not registry/deferred queue commit evidence",
                "evidence_tier": "resource-derived",
            }
        )
    return result


def build_condition_targets(action_targets: list[dict[str, Any]]) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for target in action_targets:
        action_name = str(target.get("action_name", ""))
        if action_name not in CONDITION_ACTIONS:
            continue
        result.append(
            {
                "occurrence_key": target.get("occurrence_key"),
                "action_name": action_name,
                "args": target.get("args", []),
                "phase_hint": target.get("phase_hint"),
                "source": target.get("source", {}),
                "predicate_status": "unknown",
                "probe_use": "target condition evaluation window by imported source order; predicate polarity unresolved",
                "evidence_tier": "resource-derived",
            }
        )
    return result


def compact_action_target(target: dict[str, Any], family: str, subtype: str) -> dict[str, Any]:
    return {
        "occurrence_key": target.get("occurrence_key"),
        "action_name": target.get("action_name"),
        "action_family": family,
        "action_subtype": subtype,
        "args": target.get("args", []),
        "phase_hint": target.get("phase_hint"),
        "source": target.get("source", {}),
        "target_status": "imported_ir_selector_only",
        "evidence_tier": "resource-derived",
    }


def build_action_family_targets(action_targets: list[dict[str, Any]]) -> dict[str, Any]:
    families: dict[str, list[dict[str, Any]]] = {
        "message": [],
        "status": [],
        "resource": [],
        "condition": [],
        "movement": [],
        "object": [],
        "attack": [],
        "wait": [],
    }
    for target in action_targets:
        action_name = str(target.get("action_name", ""))
        if action_name in MESSAGE_ACTIONS:
            families["message"].append(compact_action_target(target, "message", "dialogue_or_conditional_message"))
        if action_name in STATUS_INSERT_ACTIONS:
            families["status"].append(compact_action_target(target, "status", f"insert_{STATUS_INSERT_ACTIONS[action_name]}"))
        if action_name in STATUS_DELETE_ACTIONS:
            families["status"].append(compact_action_target(target, "status", f"delete_{STATUS_DELETE_ACTIONS[action_name]}"))
        if action_name in RESOURCE_ACTIONS:
            families["resource"].append(compact_action_target(target, "resource", RESOURCE_ACTIONS[action_name]))
        if action_name in CONDITION_ACTIONS:
            families["condition"].append(compact_action_target(target, "condition", "predicate_unknown"))
        if action_name in MOVEMENT_ACTIONS:
            families["movement"].append(compact_action_target(target, "movement", MOVEMENT_ACTIONS[action_name]))
        if action_name in OBJECT_ACTIONS:
            families["object"].append(compact_action_target(target, "object", OBJECT_ACTIONS[action_name]))
    missing_playability = {
        "attack": {
            "target_status": "missing_in_script_ir",
            "probe_use": "attack is a player action-menu command, not present as an imported STORY051/winfail051 script action target",
        },
        "wait": {
            "target_status": "missing_in_script_ir",
            "probe_use": "wait is a player action-menu command, not present as an imported STORY051/winfail051 script action target",
        },
    }
    return {
        "schema": "hsl_script_runtime_action_family_targets.v1",
        "target_policy": "read_only_family_index_for_measurement_no_handler_execution",
        "families": families,
        "family_counts": {family: len(items) for family, items in families.items()},
        "missing_playability_action_targets": missing_playability,
        "unresolved_semantics": [
            "movement/object/resource/message/status/condition families are imported script selectors only",
            "attack and wait are expected playability controls but are not script action targets in current imported IR",
        ],
    }


def occurrence_for_action(action_targets: list[dict[str, Any]], action_name: str) -> str | None:
    for target in action_targets:
        if target.get("action_name") == action_name:
            key = target.get("occurrence_key")
            return key if isinstance(key, str) else None
    return None


def build_playability_control_probe_requests(action_targets: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [
        {
            "request_id": "action_menu_visible_turn_start",
            "control_state": "action_menu",
            "interaction": "observe_visible_menu_at_player_turn_start",
            "target_occurrence_key": None,
            "script_target_status": "not_script_action",
            "expected_ui_moment": "player turn begins with the action menu already visible",
            "probe_priority": "high",
            "probe_policy": "specific_action_menu_state_no_no_menu_control_state",
            "evidence_source": "live_operation_corrected_control_model",
        },
        {
            "request_id": "action_menu_move_command_enters_move_select",
            "control_state": "action_menu",
            "interaction": "select_move_command",
            "target_occurrence_key": occurrence_for_action(action_targets, "actWalkDispWait"),
            "script_target_status": "scripted_movement_reference_only",
            "expected_ui_moment": "move command transitions from visible action_menu to move_select",
            "probe_priority": "high",
            "probe_policy": "specific_action_menu_to_move_select_transition",
            "evidence_source": "live_operation_corrected_control_model",
        },
        {
            "request_id": "move_select_left_click_confirms_grid_target",
            "control_state": "move_select",
            "interaction": "left_click_grid_target",
            "target_occurrence_key": occurrence_for_action(action_targets, "actWalkDispWait"),
            "script_target_status": "scripted_movement_reference_only",
            "expected_ui_moment": "left click in move_select confirms the grid target",
            "probe_priority": "high",
            "probe_policy": "specific_move_select_confirm_transition",
            "evidence_source": "live_operation_corrected_control_model",
        },
        {
            "request_id": "move_select_right_click_returns_action_menu",
            "control_state": "move_select",
            "interaction": "right_click_cancel",
            "target_occurrence_key": None,
            "script_target_status": "not_script_action",
            "expected_ui_moment": "right click in move_select cancels back to visible action_menu",
            "probe_priority": "high",
            "probe_policy": "specific_move_select_cancel_transition",
            "evidence_source": "live_operation_corrected_control_model",
        },
        {
            "request_id": "action_menu_attack_command_selector_missing_in_script_ir",
            "control_state": "action_menu",
            "interaction": "select_attack_command",
            "target_occurrence_key": None,
            "script_target_status": "missing_in_script_ir",
            "expected_ui_moment": "attack command should be measured as a playability control, not as STORY051/winfail051 script action",
            "probe_priority": "medium",
            "probe_policy": "specific_action_menu_command_no_script_selector",
            "evidence_source": "live_operation_corrected_control_model",
        },
        {
            "request_id": "action_menu_wait_command_selector_missing_in_script_ir",
            "control_state": "action_menu",
            "interaction": "select_wait_command",
            "target_occurrence_key": None,
            "script_target_status": "missing_in_script_ir",
            "expected_ui_moment": "wait command should be measured as a playability control, not as STORY051/winfail051 script action",
            "probe_priority": "medium",
            "probe_policy": "specific_action_menu_command_no_script_selector",
            "evidence_source": "live_operation_corrected_control_model",
        },
    ]


def build_phase_targets(action_targets: list[dict[str, Any]]) -> dict[str, Any]:
    phase_targets: dict[str, dict[str, Any]] = {
        phase: {
            "action_occurrence_keys": [],
            "message_occurrence_keys": [],
            "resource_occurrence_keys": [],
            "status_occurrence_keys": [],
            "condition_occurrence_keys": [],
            "probe_policy": "exact_action_targets_only_no_generic_script_phase",
        }
        for phase in PHASE_ORDER
    }
    for target in action_targets:
        source = target.get("source", {})
        phase = source.get("section_type") if isinstance(source, dict) else None
        if phase not in phase_targets:
            continue
        key = target.get("occurrence_key")
        if not isinstance(key, str):
            continue
        action_name = str(target.get("action_name", ""))
        phase_targets[phase]["action_occurrence_keys"].append(key)
        if action_name in MESSAGE_ACTIONS:
            phase_targets[phase]["message_occurrence_keys"].append(key)
        if action_name in RESOURCE_ACTIONS:
            phase_targets[phase]["resource_occurrence_keys"].append(key)
        if action_name in STATUS_INSERT_ACTIONS or action_name in STATUS_DELETE_ACTIONS:
            phase_targets[phase]["status_occurrence_keys"].append(key)
        if action_name in CONDITION_ACTIONS:
            phase_targets[phase]["condition_occurrence_keys"].append(key)
    for phase, data in phase_targets.items():
        data["action_count"] = len(data["action_occurrence_keys"])
        data["message_count"] = len(data["message_occurrence_keys"])
        data["resource_count"] = len(data["resource_occurrence_keys"])
        data["status_count"] = len(data["status_occurrence_keys"])
        data["condition_count"] = len(data["condition_occurrence_keys"])
    return phase_targets


def build_probe_targets(index_path: Path) -> dict[str, Any]:
    index, scripts = load_scripts(index_path)
    action_targets = iter_chain_targets(scripts)
    action_counts = collections.Counter(str(target.get("action_name", "")) for target in action_targets)
    message_targets = build_message_targets(action_targets)
    resource_targets = build_resource_targets(action_targets)
    status_targets = build_status_targets(action_targets)
    condition_targets = build_condition_targets(action_targets)
    action_family_targets = build_action_family_targets(action_targets)
    playability_control_probe_requests = build_playability_control_probe_requests(action_targets)
    return {
        "schema": SCHEMA,
        "source_index": index_path.as_posix(),
        "source_schema": index.get("schema"),
        "source_total_action_chain_count": index.get("total_action_chain_count"),
        "evidence_tier": "resource-derived",
        "consumer": "runtime_probes_and_godot_read_play_diagnostics",
        "target_policy": "exact_imported_ir_order_targets_no_handler_no_opcode_no_live_mutation",
        "phase_order": PHASE_ORDER,
        "summary": {
            "action_target_count": len(action_targets),
            "unique_action_count": len(action_counts),
            "message_target_count": len(message_targets),
            "resource_target_count": len(resource_targets),
            "status_target_count": len(status_targets),
            "condition_target_count": len(condition_targets),
            "movement_target_count": action_family_targets["family_counts"]["movement"],
            "object_target_count": action_family_targets["family_counts"]["object"],
            "attack_target_count": action_family_targets["family_counts"]["attack"],
            "wait_target_count": action_family_targets["family_counts"]["wait"],
            "playability_control_probe_request_count": len(playability_control_probe_requests),
        },
        "action_counts": dict(sorted(action_counts.items())),
        "action_family_targets": action_family_targets,
        "playability_control_probe_requests": playability_control_probe_requests,
        "phase_targets": build_phase_targets(action_targets),
        "message_targets": message_targets,
        "resource_targets": resource_targets,
        "status_targets": status_targets,
        "condition_targets": condition_targets,
        "action_targets": action_targets,
        "runtime_probe_requests": [
            {
                "request_id": "story_first_dialogue_message_363",
                "target_occurrence_key": next(
                    (
                        item["occurrence_key"]
                        for item in message_targets
                        if item.get("primary_message_id_candidate") == "363"
                    ),
                    None,
                ),
                "expected_ui_moment": "opening dialogue displays imported message id 363 label/source order",
                "probe_priority": "high",
                "probe_policy": "specific_message_target_no_generic_script_phase",
            },
            {
                "request_id": "story_section_title_word051_resource",
                "target_occurrence_key": next(
                    (
                        item["occurrence_key"]
                        for item in resource_targets
                        if item.get("resource_ref_candidate") == "SHAPE01\\WORD051.SHP"
                    ),
                    None,
                ),
                "expected_ui_moment": "opening section title resource reference becomes visible or is skipped by original timing",
                "probe_priority": "medium",
                "probe_policy": "specific_resource_target_no_generic_script_phase",
            },
            {
                "request_id": "event_round6_message_if_exist_397",
                "target_occurrence_key": next(
                    (
                        item["occurrence_key"]
                        for item in message_targets
                        if item.get("primary_message_id_candidate") == "397"
                    ),
                    None,
                ),
                "expected_ui_moment": "round/event dialogue candidate for message id 397 if reachable",
                "probe_priority": "defer_until_round_transition_probe",
                "probe_policy": "specific_message_target_no_generic_script_phase",
            },
        ],
        "forbidden_interpretations": [
            "handler mapping",
            "numeric opcode evidence",
            "condition predicate polarity proof",
            "status registry or deferred queue commit proof",
            "live battle mutation",
            "generic script_phase proof",
        ],
        "unresolved_semantics": [
            "targets preserve imported action order and args for measurement only",
            "message text, handler mapping, opcode ids, condition polarity, and mutation commit timing remain unresolved",
        ],
    }


def check_probe_targets(path: Path) -> list[str]:
    doc = load_json(path)
    errors: list[str] = []
    if not isinstance(doc, dict):
        return ["document must be an object"]
    if doc.get("schema") != SCHEMA:
        errors.append("schema mismatch")
    if doc.get("target_policy") != "exact_imported_ir_order_targets_no_handler_no_opcode_no_live_mutation":
        errors.append("target_policy invalid")
    if doc.get("phase_order") != PHASE_ORDER:
        errors.append("phase_order mismatch")
    summary = doc.get("summary")
    if not isinstance(summary, dict):
        errors.append("summary must be an object")
        summary = {}
    action_targets = doc.get("action_targets")
    if not isinstance(action_targets, list) or not action_targets:
        errors.append("action_targets must be a non-empty list")
        action_targets = []
    occurrence_keys: set[str] = set()
    for index, target in enumerate(action_targets):
        if not isinstance(target, dict):
            errors.append(f"action_targets[{index}] must be an object")
            continue
        key = target.get("occurrence_key")
        if not isinstance(key, str) or not key:
            errors.append(f"action_targets[{index}].occurrence_key missing")
        elif key in occurrence_keys:
            errors.append(f"action_targets[{index}].occurrence_key duplicate")
        else:
            occurrence_keys.add(key)
        if not isinstance(target.get("action_name"), str) or not target.get("action_name"):
            errors.append(f"action_targets[{index}].action_name missing")
        if not isinstance(target.get("args"), list):
            errors.append(f"action_targets[{index}].args must be a list")
        source = target.get("source")
        if not isinstance(source, dict):
            errors.append(f"action_targets[{index}].source must be an object")
        elif source.get("section_type") not in set(PHASE_ORDER):
            errors.append(f"action_targets[{index}].source.section_type invalid")
        if target.get("evidence_tier") != "resource-derived":
            errors.append(f"action_targets[{index}].evidence_tier must be resource-derived")
        if "handler semantics" not in str(target.get("probe_use", "")):
            errors.append(f"action_targets[{index}].probe_use must remain measurement-only")
    if summary.get("action_target_count") != len(action_targets):
        errors.append("summary.action_target_count mismatch")
    for list_key in ("message_targets", "resource_targets", "status_targets", "condition_targets"):
        items = doc.get(list_key)
        if not isinstance(items, list):
            errors.append(f"{list_key} must be a list")
            continue
        expected_summary_key = list_key[:-1] + "_count"
        if summary.get(expected_summary_key) != len(items):
            errors.append(f"summary.{expected_summary_key} mismatch")
        for index, item in enumerate(items):
            if not isinstance(item, dict):
                errors.append(f"{list_key}[{index}] must be an object")
                continue
            key = item.get("occurrence_key")
            if key not in occurrence_keys:
                errors.append(f"{list_key}[{index}].occurrence_key does not reference action_targets")
            if item.get("evidence_tier") != "resource-derived":
                errors.append(f"{list_key}[{index}].evidence_tier must be resource-derived")
    for index, item in enumerate(doc.get("message_targets", []) if isinstance(doc.get("message_targets"), list) else []):
        if item.get("message_text_status") != "not_resolved_in_imported_assets":
            errors.append(f"message_targets[{index}].message_text_status must remain unresolved")
        if not isinstance(item.get("message_id_candidates"), list) or not item.get("message_id_candidates"):
            errors.append(f"message_targets[{index}].message_id_candidates missing")
    for index, item in enumerate(doc.get("status_targets", []) if isinstance(doc.get("status_targets"), list) else []):
        if item.get("mutation_status") != "scheduled_only_no_live_mutation":
            errors.append(f"status_targets[{index}].mutation_status invalid")
        if item.get("commit_evidence_status") != "unresolved":
            errors.append(f"status_targets[{index}].commit_evidence_status must remain unresolved")
    for index, item in enumerate(doc.get("condition_targets", []) if isinstance(doc.get("condition_targets"), list) else []):
        if item.get("predicate_status") != "unknown":
            errors.append(f"condition_targets[{index}].predicate_status must remain unknown")
    family_targets = doc.get("action_family_targets")
    if not isinstance(family_targets, dict):
        errors.append("action_family_targets must be an object")
    else:
        if family_targets.get("schema") != "hsl_script_runtime_action_family_targets.v1":
            errors.append("action_family_targets.schema mismatch")
        if family_targets.get("target_policy") != "read_only_family_index_for_measurement_no_handler_execution":
            errors.append("action_family_targets.target_policy invalid")
        families = family_targets.get("families")
        family_counts = family_targets.get("family_counts")
        if not isinstance(families, dict):
            errors.append("action_family_targets.families must be an object")
            families = {}
        if not isinstance(family_counts, dict):
            errors.append("action_family_targets.family_counts must be an object")
            family_counts = {}
        for family in ("message", "status", "resource", "condition", "movement", "object", "attack", "wait"):
            items = families.get(family)
            if not isinstance(items, list):
                errors.append(f"action_family_targets.families.{family} must be a list")
                continue
            if family_counts.get(family) != len(items):
                errors.append(f"action_family_targets.family_counts.{family} mismatch")
            for index, item in enumerate(items):
                if not isinstance(item, dict):
                    errors.append(f"action_family_targets.families.{family}[{index}] must be an object")
                    continue
                if item.get("occurrence_key") not in occurrence_keys:
                    errors.append(f"action_family_targets.families.{family}[{index}].occurrence_key unknown")
                if item.get("target_status") != "imported_ir_selector_only":
                    errors.append(f"action_family_targets.families.{family}[{index}].target_status invalid")
        missing_playability = family_targets.get("missing_playability_action_targets")
        if not isinstance(missing_playability, dict):
            errors.append("action_family_targets.missing_playability_action_targets must be an object")
        else:
            for action_name in ("attack", "wait"):
                item = missing_playability.get(action_name)
                if not isinstance(item, dict):
                    errors.append(f"action_family_targets.missing_playability_action_targets.{action_name} must be an object")
                elif item.get("target_status") != "missing_in_script_ir":
                    errors.append(f"action_family_targets.missing_playability_action_targets.{action_name}.target_status invalid")
        for key, family in (
            ("movement_target_count", "movement"),
            ("object_target_count", "object"),
            ("attack_target_count", "attack"),
            ("wait_target_count", "wait"),
        ):
            if summary.get(key) != family_counts.get(family):
                errors.append(f"summary.{key} mismatch")
    control_requests = doc.get("playability_control_probe_requests")
    if not isinstance(control_requests, list) or not control_requests:
        errors.append("playability_control_probe_requests must be a non-empty list")
    else:
        if summary.get("playability_control_probe_request_count") != len(control_requests):
            errors.append("summary.playability_control_probe_request_count mismatch")
        seen_control_states: set[str] = set()
        for index, item in enumerate(control_requests):
            if not isinstance(item, dict):
                errors.append(f"playability_control_probe_requests[{index}] must be an object")
                continue
            control_state = item.get("control_state")
            if control_state not in {"action_menu", "move_select"}:
                errors.append(f"playability_control_probe_requests[{index}].control_state invalid")
            else:
                seen_control_states.add(control_state)
            target_key = item.get("target_occurrence_key")
            if target_key is not None and target_key not in occurrence_keys:
                errors.append(f"playability_control_probe_requests[{index}].target_occurrence_key invalid")
            if item.get("script_target_status") not in {
                "not_script_action",
                "scripted_movement_reference_only",
                "missing_in_script_ir",
            }:
                errors.append(f"playability_control_probe_requests[{index}].script_target_status invalid")
            if not isinstance(item.get("probe_policy"), str) or "specific_" not in item.get("probe_policy", ""):
                errors.append(f"playability_control_probe_requests[{index}].probe_policy must be specific")
            if item.get("evidence_source") != "live_operation_corrected_control_model":
                errors.append(f"playability_control_probe_requests[{index}].evidence_source invalid")
        if seen_control_states != {"action_menu", "move_select"}:
            errors.append("playability_control_probe_requests must cover action_menu and move_select")
    phase_targets = doc.get("phase_targets")
    if not isinstance(phase_targets, dict):
        errors.append("phase_targets must be an object")
    else:
        for phase in PHASE_ORDER:
            phase_doc = phase_targets.get(phase)
            if not isinstance(phase_doc, dict):
                errors.append(f"phase_targets.{phase} must be an object")
                continue
            if phase_doc.get("probe_policy") != "exact_action_targets_only_no_generic_script_phase":
                errors.append(f"phase_targets.{phase}.probe_policy invalid")
            for key in (
                "action_occurrence_keys",
                "message_occurrence_keys",
                "resource_occurrence_keys",
                "status_occurrence_keys",
                "condition_occurrence_keys",
            ):
                values = phase_doc.get(key)
                if not isinstance(values, list):
                    errors.append(f"phase_targets.{phase}.{key} must be a list")
                    continue
                for value in values:
                    if value not in occurrence_keys:
                        errors.append(f"phase_targets.{phase}.{key} references unknown occurrence")
    requests = doc.get("runtime_probe_requests")
    if not isinstance(requests, list) or not requests:
        errors.append("runtime_probe_requests must be a non-empty list")
    else:
        for index, item in enumerate(requests):
            if not isinstance(item, dict):
                errors.append(f"runtime_probe_requests[{index}] must be an object")
                continue
            if item.get("target_occurrence_key") not in occurrence_keys:
                errors.append(f"runtime_probe_requests[{index}].target_occurrence_key missing or invalid")
            if "generic_script_phase" not in str(item.get("probe_policy", "")):
                errors.append(f"runtime_probe_requests[{index}].probe_policy must forbid generic script_phase")
    text = json.dumps(doc, ensure_ascii=False)
    for forbidden in ("handler_confirmed", "opcode_confirmed", "live_battle_mutation"):
        if forbidden in text:
            errors.append(f"document must not claim {forbidden}")
    if "player_control" in text:
        errors.append("document must not frame probes around player_control")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description="Build or check chapter01 script runtime probe targets.")
    parser.add_argument("path", type=Path)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.check:
        errors = check_probe_targets(args.path)
        if errors:
            for error in errors:
                print(f"ERROR: {error}")
            return 1
        print("PASS hsl script runtime probe targets")
        return 0
    if args.out is None:
        parser.error("--out is required unless --check is used")
    write_json(args.out, build_probe_targets(args.path))
    print(f"wrote {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
