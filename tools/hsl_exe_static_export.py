#!/usr/bin/env python3
"""Export compact static-analysis evidence for the local-private HSL executable."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))  # hsltools
from hsltools.paths import ORIGINAL_EXE

DEFAULT_EXE = ORIGINAL_EXE
DEFAULT_OUT_DIR = Path("ignored/static/hsl01")
DEFAULT_TRACKED_INDEX_OUT = Path("content/generated/hsl/static/hsl01/index.json")
DEFAULT_SCRIPT_VM_SEMANTICS = Path("content/imported/hsl/chapter01/script_vm_semantics.json")
DEFAULT_RESOURCE_REFS = Path("content/imported/hsl/chapter01/resource_refs.json")
DEFAULT_UI_RESOURCES = Path("content/imported/hsl/chapter01/ui_resources.json")
DEFAULT_MAP_OBJECT_VISIBILITY_EVIDENCE = Path("content/imported/hsl/chapter01/map_object_visibility_evidence.json")
DEFAULT_WINDOWS = [
    ("input_aggregator_candidate", "0x415910", 0x220),
    ("menu_start_state_candidate", "0x42d7c0", 0x260),
    ("logical_ui_hit_test_candidate", "0x445977", 0x420),
    ("script_interpreter_bridge_candidate", "0x450840", 0x360),
]
DEFAULT_DISPATCH_TABLES = [
    {
        "id": "script_primary_dispatch_table",
        "address": "0x453708",
        "entry_count": 24,
        "entry_width": 4,
        "evidence_sources": ["script_interpreter_bridge_candidate"],
        "why_next": "Resolve the first script opcode dispatch layer used before action sub-dispatch.",
    },
    {
        "id": "script_action_dispatch_table",
        "address": "0x4537f4",
        "entry_count": 140,
        "entry_width": 4,
        "evidence_sources": ["script_interpreter_bridge_candidate"],
        "why_next": "Correlate imported script action order and action names with engine handler addresses.",
    },
]
DEFAULT_XREF_TARGETS = [
    {
        "id": "logical_ui_hit_test_candidate",
        "address": "0x445977",
        "label": "logical UI/object hit-test branch target",
        "evidence_sources": ["logical_ui_hit_test_candidate"],
        "why_next": "Find owning object-list traversal and callers before naming unit or menu object semantics.",
    },
    {
        "id": "script_interpreter_bridge_candidate",
        "address": "0x450840",
        "label": "script interpreter bridge function",
        "evidence_sources": ["script_interpreter_bridge_candidate"],
        "why_next": "Find callers that enter the script VM bridge and prioritize adjacent windows for naming.",
    },
]
DEFAULT_BODY_WINDOWS = [
    {
        "id": "script_interpreter_bridge_function",
        "address": "0x450840",
        "mode": "pdfj",
        "evidence_sources": ["script_interpreter_bridge_candidate"],
        "why_next": "Fingerprint script action handlers and bridge callers without tracking decoded instruction text.",
    },
    {
        "id": "logical_ui_hit_test_window",
        "address": "0x445977",
        "mode": "pdj",
        "instruction_count": 320,
        "evidence_sources": ["logical_ui_hit_test_candidate"],
        "why_next": "Summarize local call/data/jump references for UI/object traversal without tracking decoded instruction text.",
    },
]
DEFAULT_UI_OWNER_WINDOWS = [
    {
        "id": "logical_ui_hit_test_caller_window",
        "address": "0x4458e0",
        "instruction_count": 160,
        "role": "caller_context",
        "why_next": "Summarize the single CODE xref region that reaches 0x445977 and walks candidate child/object links.",
    },
    {
        "id": "logical_ui_bounds_update_candidate",
        "address": "0x445d70",
        "instruction_count": 120,
        "role": "hit_test_callee",
        "why_next": "Summarize bounds/selection offset updates called from 0x445977.",
    },
    {
        "id": "logical_ui_child_chain_copy_candidate",
        "address": "0x445f60",
        "instruction_count": 140,
        "role": "hit_test_callee",
        "why_next": "Summarize repeated child-chain traversal through object offset 0x60.",
    },
    {
        "id": "logical_ui_list_entry_alloc_candidate",
        "address": "0x45e307",
        "instruction_count": 140,
        "role": "hit_test_callee_allocator",
        "why_next": "Summarize list-entry allocation/linking helper called by child-chain propagation.",
    },
    {
        "id": "logical_ui_allocator_pool_candidate",
        "address": "0x46ee70",
        "instruction_count": 140,
        "role": "hit_test_allocator_callee",
        "why_next": "Summarize allocator/pool helper reached from list-entry allocation without naming owner semantics.",
    },
    {
        "id": "logical_ui_rect_link_candidate",
        "address": "0x46ce20",
        "instruction_count": 180,
        "role": "hit_test_callee",
        "why_next": "Summarize rectangle pool/link construction used by 0x445977 without naming owner semantics.",
    },
]
DEFAULT_SCRIPT_COMMIT_CALLER_WINDOWS = [
    {
        "id": "script_bridge_runtime_flag_caller",
        "address": "0x408220",
        "instruction_count": 96,
        "role": "bridge_caller_flag_gated",
        "why_next": "Summarize the caller that gates 0x450840 with 0x4c1b00/0x4c1d44 state before naming script lifecycle semantics.",
    },
    {
        "id": "script_bridge_deferred_slot0_caller",
        "address": "0x44ebf0",
        "instruction_count": 96,
        "role": "bridge_caller_deferred_queue_candidate",
        "why_next": "Summarize bridge caller around 0x4c1d04 and post-bridge cleanup calls without naming queue semantics.",
    },
    {
        "id": "script_bridge_deferred_slot1_caller",
        "address": "0x44ecb0",
        "instruction_count": 96,
        "role": "bridge_caller_deferred_queue_candidate",
        "why_next": "Summarize bridge caller around 0x4c1d08 and post-bridge cleanup calls without naming queue semantics.",
    },
    {
        "id": "script_bridge_deferred_slot2_caller",
        "address": "0x44ed70",
        "instruction_count": 96,
        "role": "bridge_caller_deferred_queue_candidate",
        "why_next": "Summarize bridge caller around 0x4c1d0c and post-bridge cleanup calls without naming queue semantics.",
    },
    {
        "id": "script_bridge_list_node_caller",
        "address": "0x453ac0",
        "instruction_count": 96,
        "role": "bridge_caller_list_node_candidate",
        "why_next": "Summarize 0x453ac0 caller path that can invoke 0x450840 and adjacent cleanup/list helpers.",
    },
]
DEFAULT_SCRIPT_COMMIT_CALLEE_WINDOWS = [
    {
        "id": "script_bridge_top_callee_44fad0",
        "address": "0x44fad0",
        "instruction_count": 120,
        "role": "bridge_top_callee",
        "why_next": "Summarize the most frequent 0x450840 callee for direct queue or registry write evidence.",
    },
    {
        "id": "script_status_boundary_callee_44fcf0",
        "address": "0x44fcf0",
        "instruction_count": 120,
        "role": "status_boundary_callee_candidate",
        "why_next": "Summarize status-navigation callee boundary without naming mutation semantics.",
    },
    {
        "id": "script_status_boundary_callee_44fd90",
        "address": "0x44fd90",
        "instruction_count": 120,
        "role": "status_boundary_callee_candidate",
        "why_next": "Summarize status-navigation callee boundary without naming mutation semantics.",
    },
    {
        "id": "script_status_boundary_callee_44fe40",
        "address": "0x44fe40",
        "instruction_count": 120,
        "role": "status_boundary_callee_candidate",
        "why_next": "Summarize status-navigation callee boundary without naming mutation semantics.",
    },
    {
        "id": "script_status_boundary_callee_44fed0",
        "address": "0x44fed0",
        "instruction_count": 120,
        "role": "status_boundary_callee_candidate",
        "why_next": "Summarize status-navigation callee boundary without naming mutation semantics.",
    },
    {
        "id": "script_status_boundary_callee_44ff50",
        "address": "0x44ff50",
        "instruction_count": 120,
        "role": "status_boundary_callee_candidate",
        "why_next": "Summarize status-navigation callee boundary without naming mutation semantics.",
    },
    {
        "id": "script_bridge_cleanup_helper_453ac0",
        "address": "0x453ac0",
        "instruction_count": 120,
        "role": "bridge_cleanup_helper_candidate",
        "why_next": "Summarize cleanup/list helper that can re-enter 0x450840 and update bridge runtime flags.",
    },
    {
        "id": "script_bridge_cleanup_helper_453a80",
        "address": "0x453a80",
        "instruction_count": 120,
        "role": "bridge_cleanup_helper_candidate",
        "why_next": "Summarize cleanup/list helper that updates bridge runtime flags before adjacent bridge flow.",
    },
]
CONDITION_HANDLER_WINDOW_INSTRUCTION_COUNT = 80
STATUS_HANDLER_WINDOW_INSTRUCTION_COUNT = 96
DEFAULT_SHP_RENDER_WINDOWS = [
    {
        "id": "shp_header_validate_and_descriptor_copy_candidate",
        "address": "0x45fa1e",
        "instruction_count": 160,
        "why_next": "Validate TLHS header fields and descriptor-copy offsets before naming SHP header 0x10 semantics.",
    },
    {
        "id": "shp_row_decode_full_candidate",
        "address": "0x46e1a8",
        "instruction_count": 140,
        "why_next": "Summarize full-row decode header offsets and determine whether header 0x10 is read in render path.",
    },
    {
        "id": "shp_row_decode_clipped_candidate",
        "address": "0x46e270",
        "instruction_count": 200,
        "why_next": "Summarize clipped-row decode header offsets and determine whether header 0x10 is read in render path.",
    },
]
DEFAULT_MAP_OBJECT_STATIC_WINDOWS = [
    {
        "id": "object_definition_field_parser_candidate",
        "address": "0x45dc5c",
        "instruction_count": 420,
        "role": "object_field_parser",
        "why_next": "Summarize object field-name ingestion for obj_plane, x/y, shape name/number, and collision fields.",
    },
    {
        "id": "scene_object_draw_candidate",
        "address": "0x456150",
        "instruction_count": 420,
        "role": "scene_object_draw_or_update_candidate",
        "why_next": "Summarize object-like offsets and SHP draw calls that may consume placement, anchor, or clip state.",
    },
    {
        "id": "shp_descriptor_render_caller_a",
        "address": "0x460058",
        "instruction_count": 180,
        "role": "shp_descriptor_render_caller",
        "why_next": "Summarize SHP descriptor caller that reaches 0x45fa1e and related clipping/render helpers.",
    },
    {
        "id": "shp_descriptor_render_caller_b",
        "address": "0x4601a2",
        "instruction_count": 180,
        "role": "shp_descriptor_render_caller",
        "why_next": "Summarize adjacent SHP descriptor caller that reaches 0x45fa1e and object/clip-like offsets.",
    },
]
DEFAULT_BATTLE_STATE_TARGETS = [
    {
        "id": "input_current_edge_bits",
        "category": "input_globals",
        "address": "0x4c6390",
        "label": "input current and edge bitfield candidate",
        "evidence_tier": "static_window_observed_runtime_scalar_smoke",
        "evidence_sources": ["input_aggregator_candidate", "logical_ui_hit_test_candidate", "menu_start_state_candidate"],
        "static_observation": "Input aggregator clears then ORs keyboard-style bits, later folds previous-state delta into the same dword; menu and UI hit-test windows read it.",
        "why_next": "Primary scalar for correlating confirm, cancel, arrows, and mouse/action-menu phases.",
        "runtime_probe": "sample u32 during title idle, dialogue advance, player control, action menu open, confirm, cancel, and arrow-key/menu navigation phases",
    },
    {
        "id": "input_previous_bits",
        "category": "input_globals",
        "address": "0x4c1a88",
        "label": "previous raw input bitfield candidate",
        "evidence_tier": "static_window_observed",
        "evidence_sources": ["input_aggregator_candidate"],
        "static_observation": "Input aggregator reads the prior value, XORs it with the new value, then stores the current value back before producing edge bits.",
        "why_next": "Distinguishes held input from just-pressed transitions when matching original command consumption.",
        "runtime_probe": "sample alongside input_current_edge_bits while holding and releasing one key/button across several frames",
    },
    {
        "id": "input_pointer_or_button_bits",
        "category": "input_globals",
        "address": "0x4c6398",
        "label": "mouse/button state candidate",
        "evidence_tier": "static_window_observed",
        "evidence_sources": ["input_aggregator_candidate", "logical_ui_hit_test_candidate", "menu_start_state_candidate"],
        "static_observation": "Input aggregator passes this address to the cursor/button helper; menu and UI hit-test windows test low bits from it.",
        "why_next": "Needed to prove whether action-menu open/selection is click-edge, held-button, or mixed keyboard/mouse logic.",
        "runtime_probe": "sample u32 around HID click down/up and around menu hover without click",
    },
    {
        "id": "cursor_x",
        "category": "cursor_camera_globals",
        "address": "0x4c1a8c",
        "label": "logical cursor x candidate",
        "evidence_tier": "static_window_observed",
        "evidence_sources": ["input_aggregator_candidate", "logical_ui_hit_test_candidate"],
        "static_observation": "Input aggregator passes this address to the cursor helper; UI hit-test compares it against object bounds and stores relative offsets.",
        "why_next": "Correlates original logical-coordinate UI/menu hit testing with Godot tactical viewport mapping.",
        "runtime_probe": "sample while moving the physical cursor to known client x coordinates in title/menu/player-control phases",
    },
    {
        "id": "cursor_y",
        "category": "cursor_camera_globals",
        "address": "0x4c1a90",
        "label": "logical cursor y candidate",
        "evidence_tier": "static_window_observed",
        "evidence_sources": ["input_aggregator_candidate", "logical_ui_hit_test_candidate"],
        "static_observation": "Input aggregator passes this address to the cursor helper; UI hit-test compares it against object bounds and stores relative offsets.",
        "why_next": "Pairs with cursor_x to recover the original logical-coordinate hit-test surface.",
        "runtime_probe": "sample while moving the physical cursor to known client y coordinates in title/menu/player-control phases",
    },
    {
        "id": "menu_start_state",
        "category": "menu_state",
        "address": "0x4c1ac8",
        "label": "menu/start state latch candidate",
        "evidence_tier": "static_window_observed",
        "evidence_sources": ["menu_start_state_candidate"],
        "static_observation": "Menu/start-like state machine reads the dword at entry and writes 1 during initialization.",
        "why_next": "Separates title/start-menu state from battle action-menu state before naming higher-level phases.",
        "runtime_probe": "sample across launch, title idle, new-story click, transition, and first battle map phases",
    },
    {
        "id": "menu_local_x_or_selection",
        "category": "menu_state",
        "address": "0x4c1b98",
        "label": "menu-local x/selection candidate",
        "evidence_tier": "static_window_observed",
        "evidence_sources": ["menu_start_state_candidate"],
        "static_observation": "Menu/start-like loop clears this dword and later passes it as an argument to a menu/UI routine.",
        "why_next": "May reveal title-menu cursor/selection mechanics that map to action-menu selection handling.",
        "runtime_probe": "sample while navigating menu choices with arrow keys and mouse hover",
    },
    {
        "id": "menu_local_y_or_selection",
        "category": "menu_state",
        "address": "0x4c1b9c",
        "label": "menu-local y/selection candidate",
        "evidence_tier": "static_window_observed",
        "evidence_sources": ["menu_start_state_candidate"],
        "static_observation": "Menu/start-like loop clears this dword and later passes it as an argument to a menu/UI routine.",
        "why_next": "Pairs with menu_local_x_or_selection for menu navigation and highlight correlation.",
        "runtime_probe": "sample while navigating menu choices with arrow keys and mouse hover",
    },
    {
        "id": "camera_or_view_x",
        "category": "cursor_camera_globals",
        "address": "0x4c091c",
        "label": "camera/view x candidate",
        "evidence_tier": "static_window_candidate",
        "evidence_sources": ["menu_start_state_candidate"],
        "static_observation": "Menu/start-like window copies this global into a stack structure before a render/update call.",
        "why_next": "Candidate for correlating original camera scroll and map crop with Godot viewport behavior.",
        "runtime_probe": "sample during first battle map idle and supervised camera scroll/event-scroll phases",
    },
    {
        "id": "camera_or_view_y",
        "category": "cursor_camera_globals",
        "address": "0x4c0920",
        "label": "camera/view y candidate",
        "evidence_tier": "static_window_candidate",
        "evidence_sources": ["menu_start_state_candidate"],
        "static_observation": "Menu/start-like window copies this global next to camera_or_view_x before a render/update call.",
        "why_next": "Pairs with camera_or_view_x for event camera scroll and logical-to-screen mapping.",
        "runtime_probe": "sample during first battle map idle and supervised camera scroll/event-scroll phases",
    },
    {
        "id": "script_primary_dispatch_table",
        "category": "script_interpreter_tables",
        "address": "0x453708",
        "label": "primary script opcode dispatch table candidate",
        "evidence_tier": "static_window_observed",
        "evidence_sources": ["script_interpreter_bridge_candidate"],
        "static_observation": "Script bridge bounds an opcode value, indexes a byte remap table, then jumps through this table.",
        "why_next": "Maps resource action opcodes to engine handlers before naming battle/menu/script commands.",
        "runtime_probe": "breakpoint or scalar-call correlation later; for now expand static xrefs and table entries with r2 only",
    },
    {
        "id": "script_opcode_remap_table",
        "category": "script_interpreter_tables",
        "address": "0x453768",
        "label": "script opcode remap table candidate",
        "evidence_tier": "static_window_observed",
        "evidence_sources": ["script_interpreter_bridge_candidate"],
        "static_observation": "Script bridge reads a byte from this table before the primary dispatch jump.",
        "why_next": "Needed to translate raw script/action ids into dispatch slots without guessing from resource names.",
        "runtime_probe": "static-only next step: export compact table shape and referenced handler address list",
    },
    {
        "id": "script_action_dispatch_table",
        "category": "script_interpreter_tables",
        "address": "0x4537f4",
        "label": "script action sub-dispatch table candidate",
        "evidence_tier": "static_window_observed",
        "evidence_sources": ["script_interpreter_bridge_candidate"],
        "static_observation": "After reading action data, the bridge jumps through this table using the action value.",
        "why_next": "Likely bridge from resource actions to object/UI/battle command handlers.",
        "runtime_probe": "static-only next step: export compact table shape and handler addresses, then correlate with imported script IR action order",
    },
    {
        "id": "script_current_object_anchor",
        "category": "object_unit_anchors",
        "address": "0x4c1d38",
        "label": "current script object or actor anchor candidate",
        "evidence_tier": "static_window_observed",
        "evidence_sources": ["script_interpreter_bridge_candidate"],
        "static_observation": "Script bridge copies this global into object/action fields when script args request the current context.",
        "why_next": "Candidate bridge between script execution, spawned objects, actors, or unit-facing state.",
        "runtime_probe": "sample around STORY051 setup, player-display actions, first player-control phase, and status/event dispatch",
    },
    {
        "id": "logical_ui_object_chain",
        "category": "object_unit_anchors",
        "address": "0x445977",
        "label": "logical UI/object chain handler candidate",
        "evidence_tier": "static_window_observed",
        "evidence_sources": ["logical_ui_hit_test_candidate"],
        "static_observation": "Function walks object-like structures through link offsets, compares cursor globals to bounds, and tests per-object input masks.",
        "why_next": "Likely reusable hit-test surface for menus, cursor objects, and selectable tactical objects; needs object base discovery before unit-array naming.",
        "runtime_probe": "static-expand caller/callee windows, then correlate cursor/button scalars while action menu and target selection are visible",
    },
]
TRACKED_SOURCE_POLICY = (
    "tracked compact static metadata only; local executable identity, tool invocation details, "
    "diagnostic paths, text payloads, decoded instruction text, and raw bytes are not exported"
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def tool_path(name: str) -> str | None:
    return shutil.which(name)


def run_capture(command: list[str], output_path: Path, timeout: int, dry_run: bool) -> dict[str, Any]:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    if dry_run:
        return {
            "command": command,
            "output": output_path.as_posix(),
            "status": "dry-run",
        }
    completed = subprocess.run(
        command,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )
    output_path.write_text(completed.stdout, encoding="utf-8")
    stderr_path = output_path.with_suffix(output_path.suffix + ".stderr")
    stderr_path.write_text(completed.stderr, encoding="utf-8")
    return {
        "command": command,
        "output": output_path.as_posix(),
        "stderr": stderr_path.as_posix(),
        "returncode": completed.returncode,
        "status": "ok" if completed.returncode == 0 else "failed",
    }


def parse_json_file(path: Path) -> Any | None:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        return None


def hex_address(value: Any) -> str:
    if isinstance(value, str):
        text = value.strip()
        if text.startswith("0x"):
            return text.lower()
        try:
            return f"0x{int(text, 0):x}"
        except ValueError:
            return text
    if isinstance(value, int):
        return f"0x{value:x}"
    return str(value)


def is_probable_code_address(value: int) -> bool:
    return 0x400000 <= value < 0x480000


def export_dispatch_tables(exe: Path, r2: str, out_dir: Path, timeout: int, dry_run: bool) -> list[dict[str, Any]]:
    exports: list[dict[str, Any]] = []
    for table in DEFAULT_DISPATCH_TABLES:
        output_path = out_dir / "tables" / f"{table['id']}.json"
        byte_count = int(table["entry_count"]) * int(table["entry_width"])
        command = [
            r2,
            "-2",
            "-q",
            "-e",
            "scr.color=false",
            "-c",
            f"pxwj {byte_count} @ {table['address']};q",
            exe.as_posix(),
        ]
        result = run_capture(command, output_path, timeout, dry_run)
        values = parse_json_file(output_path) if not dry_run and result.get("status") == "ok" else None
        entries = values if isinstance(values, list) else []
        result.update({
            "id": table["id"],
            "address": table["address"],
            "entry_count": table["entry_count"],
            "entry_width": table["entry_width"],
            "evidence_sources": table["evidence_sources"],
            "why_next": table["why_next"],
            "entries": entries,
        })
        exports.append(result)
    return exports


def export_xref_summaries(exe: Path, r2: str, out_dir: Path, timeout: int, dry_run: bool) -> list[dict[str, Any]]:
    exports: list[dict[str, Any]] = []
    for target in DEFAULT_XREF_TARGETS:
        output_path = out_dir / "xrefs" / f"{target['id']}.json"
        command = [
            r2,
            "-2",
            "-q",
            "-e",
            "scr.color=false",
            "-c",
            f"aaa;axtj {target['address']};q",
            exe.as_posix(),
        ]
        result = run_capture(command, output_path, timeout, dry_run)
        values = parse_json_file(output_path) if not dry_run and result.get("status") == "ok" else None
        xrefs = values if isinstance(values, list) else []
        result.update({
            "id": target["id"],
            "address": target["address"],
            "label": target["label"],
            "evidence_sources": target["evidence_sources"],
            "why_next": target["why_next"],
            "xrefs": xrefs,
        })
        exports.append(result)
    return exports


def export_body_windows(exe: Path, r2: str, out_dir: Path, timeout: int, dry_run: bool) -> list[dict[str, Any]]:
    exports: list[dict[str, Any]] = []
    for body in DEFAULT_BODY_WINDOWS:
        output_path = out_dir / "bodies" / f"{body['id']}.json"
        if body["mode"] == "pdfj":
            r2_command = f"aaa;pdfj @ {body['address']};q"
        else:
            r2_command = f"aaa;pdj {int(body.get('instruction_count', 128))} @ {body['address']};q"
        command = [
            r2,
            "-2",
            "-q",
            "-e",
            "scr.color=false",
            "-c",
            r2_command,
            exe.as_posix(),
        ]
        result = run_capture(command, output_path, timeout, dry_run)
        values = parse_json_file(output_path) if not dry_run and result.get("status") == "ok" else None
        if body["mode"] == "pdfj" and isinstance(values, dict):
            ops = values.get("ops", [])
            observed_size = values.get("size")
        elif isinstance(values, list):
            ops = values
            observed_size = None
        else:
            ops = []
            observed_size = None
        result.update({
            "id": body["id"],
            "address": body["address"],
            "mode": body["mode"],
            "instruction_count": body.get("instruction_count"),
            "observed_size": observed_size,
            "evidence_sources": body["evidence_sources"],
            "why_next": body["why_next"],
            "ops": ops if isinstance(ops, list) else [],
        })
        exports.append(result)
    return exports


def _condition_handler_targets_from_semantics(
    script_vm_semantics: Any,
    dispatch_table_exports: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    if not isinstance(script_vm_semantics, dict):
        return []
    catalog = script_vm_semantics.get("condition_predicate_catalog")
    hints = script_vm_semantics.get("dispatch_correlation_hints")
    if not isinstance(catalog, dict) or not isinstance(hints, dict):
        return []
    by_action = catalog.get("by_action")
    action_names = hints.get("ordered_unique_action_names")
    if not isinstance(by_action, dict) or not isinstance(action_names, list):
        return []
    action_entries = [str(name) for name in action_names]
    table_entries: list[Any] = []
    for table in dispatch_table_exports:
        if table.get("id") == "script_action_dispatch_table":
            entries = table.get("entries", [])
            table_entries = entries if isinstance(entries, list) else []
            break
    targets: dict[str, dict[str, Any]] = {}
    for action_name, predicate in by_action.items():
        if not isinstance(action_name, str) or not isinstance(predicate, dict):
            continue
        if action_name not in action_entries:
            continue
        slot = action_entries.index(action_name)
        if slot >= len(table_entries):
            continue
        handler = table_entries[slot]
        if not isinstance(handler, int) or not is_probable_code_address(handler):
            continue
        address = hex_address(handler)
        item = targets.setdefault(address, {
            "address": address,
            "slots_if_order_matched": [],
            "actions_if_order_matched": [],
        })
        item["slots_if_order_matched"].append(slot)
        item["actions_if_order_matched"].append({
            "action_name": action_name,
            "condition_type": str(predicate.get("condition_type", "")),
            "candidate_context_binding": str(predicate.get("candidate_context_binding", "")),
            "occurrence_count": int(predicate.get("occurrence_count", 0)),
        })
    return sorted(targets.values(), key=lambda item: int(str(item["address"]), 16))


def _ordered_action_handler_targets(
    script_vm_semantics: Any,
    dispatch_table_exports: list[dict[str, Any]],
    action_names_to_include: set[str],
) -> list[dict[str, Any]]:
    if not isinstance(script_vm_semantics, dict) or not action_names_to_include:
        return []
    hints = script_vm_semantics.get("dispatch_correlation_hints")
    if not isinstance(hints, dict):
        return []
    ordered_names = hints.get("ordered_unique_action_names")
    if not isinstance(ordered_names, list):
        return []
    ordered_action_names = [str(name) for name in ordered_names]
    table_entries: list[Any] = []
    for table in dispatch_table_exports:
        if table.get("id") == "script_action_dispatch_table":
            entries = table.get("entries", [])
            table_entries = entries if isinstance(entries, list) else []
            break
    targets: dict[str, dict[str, Any]] = {}
    for action_name in sorted(action_names_to_include):
        if action_name not in ordered_action_names:
            continue
        slot = ordered_action_names.index(action_name)
        if slot >= len(table_entries):
            continue
        handler = table_entries[slot]
        if not isinstance(handler, int) or not is_probable_code_address(handler):
            continue
        address = hex_address(handler)
        item = targets.setdefault(address, {
            "address": address,
            "slots_if_order_matched": [],
            "actions_if_order_matched": [],
        })
        item["slots_if_order_matched"].append(slot)
        item["actions_if_order_matched"].append({"action_name": action_name})
    return sorted(targets.values(), key=lambda item: int(str(item["address"]), 16))


def export_condition_handler_windows(
    exe: Path,
    r2: str,
    out_dir: Path,
    timeout: int,
    dry_run: bool,
    script_vm_semantics: Any,
    dispatch_table_exports: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    exports: list[dict[str, Any]] = []
    for target in _condition_handler_targets_from_semantics(script_vm_semantics, dispatch_table_exports):
        address = str(target["address"])
        output_path = out_dir / "condition_handlers" / f"{address}.json"
        command = [
            r2,
            "-2",
            "-q",
            "-e",
            "scr.color=false",
            "-c",
            f"aaa;pdj {CONDITION_HANDLER_WINDOW_INSTRUCTION_COUNT} @ {address};q",
            exe.as_posix(),
        ]
        result = run_capture(command, output_path, timeout, dry_run)
        values = parse_json_file(output_path) if not dry_run and result.get("status") == "ok" else None
        result.update({
            "address": address,
            "instruction_count": CONDITION_HANDLER_WINDOW_INSTRUCTION_COUNT,
            "ops": values if isinstance(values, list) else [],
            "slots_if_order_matched": target["slots_if_order_matched"],
            "actions_if_order_matched": target["actions_if_order_matched"],
            "evidence_sources": ["condition_predicate_catalog", "script_action_dispatch_table"],
            "why_next": "Recover compact argument-load and comparison-branch shape for condition predicates without tracking decoded instruction text.",
        })
        exports.append(result)
    return exports


def _status_lifecycle_action_names(script_vm_semantics: Any) -> set[str]:
    if not isinstance(script_vm_semantics, dict):
        return set()
    names: set[str] = set()
    lifecycle = script_vm_semantics.get("status_mutation_lifecycle_model")
    mutation_counts = lifecycle.get("mutation_counts_by_action", {}) if isinstance(lifecycle, dict) else {}
    if isinstance(mutation_counts, dict):
        names.update(str(name) for name in mutation_counts)
    catalog = script_vm_semantics.get("action_semantics_catalog")
    by_action = catalog.get("by_action", {}) if isinstance(catalog, dict) else {}
    if isinstance(by_action, dict):
        for action_name, entries in by_action.items():
            if not isinstance(action_name, str) or not isinstance(entries, list):
                continue
            if any(isinstance(entry, dict) and entry.get("category") == "status" for entry in entries):
                names.add(action_name)
    return names


def export_status_handler_windows(
    exe: Path,
    r2: str,
    out_dir: Path,
    timeout: int,
    dry_run: bool,
    script_vm_semantics: Any,
    dispatch_table_exports: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    exports: list[dict[str, Any]] = []
    targets = _ordered_action_handler_targets(
        script_vm_semantics,
        dispatch_table_exports,
        _status_lifecycle_action_names(script_vm_semantics),
    )
    for target in targets:
        address = str(target["address"])
        output_path = out_dir / "status_handlers" / f"{address}.json"
        command = [
            r2,
            "-2",
            "-q",
            "-e",
            "scr.color=false",
            "-c",
            f"aaa;pdj {STATUS_HANDLER_WINDOW_INSTRUCTION_COUNT} @ {address};q",
            exe.as_posix(),
        ]
        result = run_capture(command, output_path, timeout, dry_run)
        values = parse_json_file(output_path) if not dry_run and result.get("status") == "ok" else None
        result.update({
            "address": address,
            "instruction_count": STATUS_HANDLER_WINDOW_INSTRUCTION_COUNT,
            "ops": values if isinstance(values, list) else [],
            "slots_if_order_matched": target["slots_if_order_matched"],
            "actions_if_order_matched": target["actions_if_order_matched"],
            "evidence_sources": ["status_mutation_lifecycle_model", "script_action_dispatch_table"],
            "why_next": "Fingerprint candidate status mutation handlers without claiming opcode, commit timing, or lifecycle semantics.",
        })
        exports.append(result)
    return exports


def export_shp_render_windows(exe: Path, r2: str, out_dir: Path, timeout: int, dry_run: bool) -> list[dict[str, Any]]:
    exports: list[dict[str, Any]] = []
    for window in DEFAULT_SHP_RENDER_WINDOWS:
        output_path = out_dir / "shp_render" / f"{window['id']}.json"
        command = [
            r2,
            "-2",
            "-q",
            "-e",
            "scr.color=false",
            "-c",
            f"aaa;pdj {int(window['instruction_count'])} @ {window['address']};q",
            exe.as_posix(),
        ]
        result = run_capture(command, output_path, timeout, dry_run)
        values = parse_json_file(output_path) if not dry_run and result.get("status") == "ok" else None
        result.update({
            "id": window["id"],
            "address": window["address"],
            "instruction_count": window["instruction_count"],
            "ops": values if isinstance(values, list) else [],
            "evidence_sources": ["tlhs_magic_static_search", "resource_refs_color_header_0x10"],
            "why_next": window["why_next"],
        })
        exports.append(result)
    return exports


def export_map_object_static_windows(exe: Path, r2: str, out_dir: Path, timeout: int, dry_run: bool) -> list[dict[str, Any]]:
    exports: list[dict[str, Any]] = []
    for window in DEFAULT_MAP_OBJECT_STATIC_WINDOWS:
        output_path = out_dir / "map_object_static" / f"{window['id']}.json"
        command = [
            r2,
            "-2",
            "-q",
            "-e",
            "scr.color=false",
            "-c",
            f"aaa;pdj {int(window['instruction_count'])} @ {window['address']};q",
            exe.as_posix(),
        ]
        result = run_capture(command, output_path, timeout, dry_run)
        values = parse_json_file(output_path) if not dry_run and result.get("status") == "ok" else None
        result.update({
            "id": window["id"],
            "address": window["address"],
            "instruction_count": window["instruction_count"],
            "role": window["role"],
            "ops": values if isinstance(values, list) else [],
            "evidence_sources": ["map_object_visibility_evidence", "object_field_strings", "shp_render_windows"],
            "why_next": window["why_next"],
        })
        exports.append(result)
    return exports


def export_ui_owner_windows(exe: Path, r2: str, out_dir: Path, timeout: int, dry_run: bool) -> list[dict[str, Any]]:
    exports: list[dict[str, Any]] = []
    for window in DEFAULT_UI_OWNER_WINDOWS:
        output_path = out_dir / "ui_owner" / f"{window['id']}.json"
        command = [
            r2,
            "-2",
            "-q",
            "-e",
            "scr.color=false",
            "-c",
            f"aaa;pdj {int(window['instruction_count'])} @ {window['address']};q",
            exe.as_posix(),
        ]
        result = run_capture(command, output_path, timeout, dry_run)
        values = parse_json_file(output_path) if not dry_run and result.get("status") == "ok" else None
        result.update({
            "id": window["id"],
            "address": window["address"],
            "instruction_count": window["instruction_count"],
            "role": window["role"],
            "ops": values if isinstance(values, list) else [],
            "evidence_sources": ["logical_ui_hit_test_candidate", "ui_resources"],
            "why_next": window["why_next"],
        })
        exports.append(result)
    return exports


def export_script_commit_caller_windows(
    exe: Path,
    r2: str,
    out_dir: Path,
    timeout: int,
    dry_run: bool,
) -> list[dict[str, Any]]:
    exports: list[dict[str, Any]] = []
    for window in DEFAULT_SCRIPT_COMMIT_CALLER_WINDOWS:
        output_path = out_dir / "script_commit_callers" / f"{window['id']}.json"
        command = [
            r2,
            "-2",
            "-q",
            "-e",
            "scr.color=false",
            "-c",
            f"aaa;pdj {int(window['instruction_count'])} @ {window['address']};q",
            exe.as_posix(),
        ]
        result = run_capture(command, output_path, timeout, dry_run)
        values = parse_json_file(output_path) if not dry_run and result.get("status") == "ok" else None
        result.update({
            "id": window["id"],
            "address": window["address"],
            "instruction_count": window["instruction_count"],
            "role": window["role"],
            "ops": values if isinstance(values, list) else [],
            "evidence_sources": ["script_interpreter_bridge_candidate", "status_mutation_lifecycle_model"],
            "why_next": window["why_next"],
        })
        exports.append(result)
    return exports


def export_script_commit_callee_windows(
    exe: Path,
    r2: str,
    out_dir: Path,
    timeout: int,
    dry_run: bool,
) -> list[dict[str, Any]]:
    exports: list[dict[str, Any]] = []
    for window in DEFAULT_SCRIPT_COMMIT_CALLEE_WINDOWS:
        output_path = out_dir / "script_commit_callees" / f"{window['id']}.json"
        command = [
            r2,
            "-2",
            "-q",
            "-e",
            "scr.color=false",
            "-c",
            f"aaa;pdj {int(window['instruction_count'])} @ {window['address']};q",
            exe.as_posix(),
        ]
        result = run_capture(command, output_path, timeout, dry_run)
        values = parse_json_file(output_path) if not dry_run and result.get("status") == "ok" else None
        result.update({
            "id": window["id"],
            "address": window["address"],
            "instruction_count": window["instruction_count"],
            "role": window["role"],
            "ops": values if isinstance(values, list) else [],
            "evidence_sources": ["script_interpreter_bridge_candidate", "status_mutation_lifecycle_model"],
            "why_next": window["why_next"],
        })
        exports.append(result)
    return exports


def export_static_evidence(exe: Path, out_dir: Path, timeout: int, dry_run: bool) -> dict[str, Any]:
    rabin2 = tool_path("rabin2")
    r2 = tool_path("r2")
    radare2 = tool_path("radare2")
    if rabin2 is None:
        raise SystemExit("rabin2 not found in PATH")
    if r2 is None:
        raise SystemExit("r2 not found in PATH")
    if not exe.exists():
        raise SystemExit(f"executable not found: {exe}")

    out_dir.mkdir(parents=True, exist_ok=True)
    commands: list[dict[str, Any]] = []
    commands.append(run_capture([rabin2, "-Ij", exe.as_posix()], out_dir / "pe_info.json", timeout, dry_run))
    commands.append(run_capture([rabin2, "-Sj", exe.as_posix()], out_dir / "sections.json", timeout, dry_run))
    commands.append(run_capture([rabin2, "-ij", exe.as_posix()], out_dir / "imports.json", timeout, dry_run))
    commands.append(run_capture([rabin2, "-zzj", exe.as_posix()], out_dir / "strings.json", timeout, dry_run))
    commands.append(
        run_capture(
            [r2, "-2", "-q", "-e", "scr.color=false", "-c", "aaa;aflt;q", exe.as_posix()],
            out_dir / "functions.tsv",
            timeout,
            dry_run,
        )
    )
    commands.append(
        run_capture(
            [r2, "-2", "-q", "-e", "scr.color=false", "-c", "aaa;aflj;q", exe.as_posix()],
            out_dir / "functions.json",
            timeout,
            dry_run,
        )
    )

    window_exports = []
    for label, address, size in DEFAULT_WINDOWS:
        output_path = out_dir / "windows" / f"{label}.asm"
        command = [
            r2,
            "-2",
            "-q",
            "-e",
            "scr.color=false",
            "-c",
            f"s {address};pD {size};q",
            exe.as_posix(),
        ]
        result = run_capture(command, output_path, timeout, dry_run)
        result["label"] = label
        result["address"] = address
        result["bytes"] = size
        window_exports.append(result)

    dispatch_table_exports = export_dispatch_tables(exe, r2, out_dir, timeout, dry_run)
    xref_exports = export_xref_summaries(exe, r2, out_dir, timeout, dry_run)
    body_window_exports = export_body_windows(exe, r2, out_dir, timeout, dry_run)
    script_vm_semantics = parse_json_file(DEFAULT_SCRIPT_VM_SEMANTICS)
    resource_refs = parse_json_file(DEFAULT_RESOURCE_REFS)
    ui_resources = parse_json_file(DEFAULT_UI_RESOURCES)
    map_object_visibility = parse_json_file(DEFAULT_MAP_OBJECT_VISIBILITY_EVIDENCE)
    condition_handler_exports = export_condition_handler_windows(
        exe,
        r2,
        out_dir,
        timeout,
        dry_run,
        script_vm_semantics,
        dispatch_table_exports,
    )
    shp_render_exports = export_shp_render_windows(exe, r2, out_dir, timeout, dry_run)
    map_object_exports = export_map_object_static_windows(exe, r2, out_dir, timeout, dry_run)
    ui_owner_exports = export_ui_owner_windows(exe, r2, out_dir, timeout, dry_run)
    script_commit_caller_exports = export_script_commit_caller_windows(exe, r2, out_dir, timeout, dry_run)
    script_commit_callee_exports = export_script_commit_callee_windows(exe, r2, out_dir, timeout, dry_run)
    status_handler_exports = export_status_handler_windows(
        exe,
        r2,
        out_dir,
        timeout,
        dry_run,
        script_vm_semantics,
        dispatch_table_exports,
    )

    manifest = {
        "schema": "hsl_static_export.v1",
        "created_at": datetime.now(timezone.utc).isoformat(),
        "source_policy": "local-private executable stays outside tracked outputs; this export stores compact text evidence only",
        "exe": {
            "path": exe.as_posix(),
            "size": exe.stat().st_size,
            "sha256": sha256_file(exe),
        },
        "tools": {
            "rabin2": rabin2,
            "r2": r2,
            "radare2": radare2,
        },
        "commands": commands,
        "known_windows": window_exports,
        "dispatch_tables": dispatch_table_exports,
        "xref_targets": xref_exports,
        "body_windows": body_window_exports,
        "condition_handler_windows": condition_handler_exports,
        "shp_render_windows": shp_render_exports,
        "map_object_static_windows": map_object_exports,
        "ui_owner_windows": ui_owner_exports,
        "script_commit_caller_windows": script_commit_caller_exports,
        "script_commit_callee_windows": script_commit_callee_exports,
        "status_handler_windows": status_handler_exports,
        "script_vm_semantics": script_vm_semantics if isinstance(script_vm_semantics, dict) else None,
        "resource_refs": resource_refs if isinstance(resource_refs, dict) else None,
        "ui_resources": ui_resources if isinstance(ui_resources, dict) else None,
        "map_object_visibility_evidence": map_object_visibility if isinstance(map_object_visibility, dict) else None,
        "unresolved_negative_evidence": [
            "battle command handler identities are not resolved by this export alone",
            "runtime globals require dynamic probe confirmation before Godot behavior changes",
            "Ghidra/RetDec absence must not block first-stage r2/rabin2 evidence export",
        ],
    }
    manifest_path = out_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return manifest


def _command_status_counts(commands: list[dict[str, Any]]) -> dict[str, int]:
    counts: dict[str, int] = {}
    for command in commands:
        status = str(command.get("status", "unknown"))
        counts[status] = counts.get(status, 0) + 1
    return dict(sorted(counts.items()))


def _handler_slots(entries: list[Any]) -> list[dict[str, Any]]:
    slots: list[dict[str, Any]] = []
    for index, value in enumerate(entries):
        if isinstance(value, int) and is_probable_code_address(value):
            slots.append({
                "slot": index,
                "handler_address": hex_address(value),
            })
    return slots


def _repeated_handlers(slots: list[dict[str, Any]]) -> list[dict[str, Any]]:
    counts: dict[str, int] = {}
    for slot in slots:
        address = str(slot["handler_address"])
        counts[address] = counts.get(address, 0) + 1
    repeated = [
        {"handler_address": address, "slot_count": count}
        for address, count in sorted(counts.items())
        if count > 1
    ]
    return sorted(repeated, key=lambda item: (-int(item["slot_count"]), str(item["handler_address"])))[:12]


def build_dispatch_table_summaries(tables: list[dict[str, Any]]) -> list[dict[str, Any]]:
    summaries: list[dict[str, Any]] = []
    for table in tables:
        entries = table.get("entries", [])
        entry_list = entries if isinstance(entries, list) else []
        slots = _handler_slots(entry_list)
        unique_handlers = sorted({str(slot["handler_address"]) for slot in slots})
        summaries.append({
            "id": str(table.get("id", "")),
            "address": str(table.get("address", "")),
            "evidence_tier": "static_table_observed" if slots else "static_table_shape_candidate",
            "status": str(table.get("status", "unknown")),
            "entry_count_declared": int(table.get("entry_count", 0)),
            "entry_count_observed": len(entry_list),
            "probable_handler_slot_count": len(slots),
            "unique_handler_count": len(unique_handlers),
            "handler_slots": slots,
            "repeated_handlers": _repeated_handlers(slots),
            "evidence_sources": [
                str(item)
                for item in table.get("evidence_sources", [])
            ],
            "why_next": str(table.get("why_next", "")),
        })
    return summaries


def _sanitize_xrefs(xrefs: list[Any]) -> list[dict[str, Any]]:
    sanitized: list[dict[str, Any]] = []
    for item in xrefs:
        if not isinstance(item, dict):
            continue
        entry: dict[str, Any] = {
            "from_address": hex_address(item.get("from")),
            "type": str(item.get("type", "")),
        }
        if item.get("fcn_addr") is not None:
            entry["caller_function_address"] = hex_address(item.get("fcn_addr"))
        if item.get("fcn_name"):
            entry["caller_function_name"] = str(item.get("fcn_name"))
        elif item.get("name"):
            entry["caller_context"] = str(item.get("name"))
        sanitized.append(entry)
    return sanitized


def _op_address(op: dict[str, Any]) -> int | None:
    value = op.get("addr")
    return value if isinstance(value, int) else None


def _op_refs(op: dict[str, Any], ref_type: str | None = None) -> list[int]:
    refs: list[int] = []
    for key in ("refs", "xrefs"):
        values = op.get(key, [])
        if not isinstance(values, list):
            continue
        for item in values:
            if not isinstance(item, dict):
                continue
            if ref_type is not None and item.get("type") != ref_type:
                continue
            addr = item.get("addr")
            if isinstance(addr, int):
                refs.append(addr)
    return refs


def _unique_hex(values: list[int]) -> list[str]:
    return [hex_address(value) for value in sorted(set(values))]


def summarize_ops(ops: list[Any], start: int | None = None, end: int | None = None) -> dict[str, Any]:
    typed_ops = [
        op
        for op in ops
        if isinstance(op, dict)
        and (start is None or (_op_address(op) is not None and _op_address(op) >= start))
        and (end is None or (_op_address(op) is not None and _op_address(op) < end))
    ]
    call_targets: list[int] = []
    jump_targets: list[int] = []
    data_refs: list[int] = []
    code_refs: list[int] = []
    type_counts: dict[str, int] = {}
    for op in typed_ops:
        op_type = str(op.get("type", "unknown"))
        type_counts[op_type] = type_counts.get(op_type, 0) + 1
        jump = op.get("jump")
        if isinstance(jump, int) and is_probable_code_address(jump):
            if op_type == "call":
                call_targets.append(jump)
            else:
                jump_targets.append(jump)
        data_refs.extend(_op_refs(op, "DATA"))
        code_refs.extend(_op_refs(op, "CODE"))
    return {
        "op_count": len(typed_ops),
        "op_type_counts": dict(sorted(type_counts.items())),
        "call_target_addresses": _unique_hex(call_targets),
        "jump_target_addresses": _unique_hex(jump_targets),
        "data_ref_addresses": _unique_hex(data_refs),
        "code_ref_addresses": _unique_hex(code_refs),
    }


def summarize_condition_handler_ops(ops: list[Any]) -> dict[str, Any]:
    typed_ops = [op for op in ops if isinstance(op, dict)]
    bounded_ops: list[dict[str, Any]] = []
    for op in typed_ops:
        bounded_ops.append(op)
        if op.get("type") == "ret":
            break
    op_summary = summarize_ops(bounded_ops)
    compare_addresses: list[str] = []
    conditional_branches: list[dict[str, Any]] = []
    immediate_values: set[int] = set()
    pointer_values: set[int] = set()
    for op in bounded_ops:
        address = _op_address(op)
        if op.get("type") in {"cmp", "acmp"} and address is not None:
            compare_addresses.append(hex_address(address))
        if op.get("type") == "cjmp" and address is not None:
            branch: dict[str, Any] = {"from_address": hex_address(address)}
            if isinstance(op.get("jump"), int):
                branch["jump_target"] = hex_address(op.get("jump"))
            if isinstance(op.get("fail"), int):
                branch["fallthrough_target"] = hex_address(op.get("fail"))
            conditional_branches.append(branch)
        for key in ("val", "ptr"):
            value = op.get(key)
            if isinstance(value, int) and abs(value) < 0x10000:
                immediate_values.add(value)
        ptr = op.get("ptr")
        if isinstance(ptr, int) and ptr >= 0x400000:
            pointer_values.add(ptr)
    has_compare_branch = bool(compare_addresses and conditional_branches)
    return {
        "op_count_until_first_ret": len(bounded_ops),
        "op_type_counts_until_first_ret": op_summary["op_type_counts"],
        "call_target_addresses_until_first_ret": op_summary["call_target_addresses"],
        "data_ref_addresses_until_first_ret": op_summary["data_ref_addresses"],
        "compare_op_count_until_first_ret": len(compare_addresses),
        "conditional_jump_count_until_first_ret": len(conditional_branches),
        "compare_op_addresses": compare_addresses[:12],
        "conditional_branch_edges": conditional_branches[:12],
        "small_immediate_values": [value for value in sorted(immediate_values)[:24]],
        "code_or_data_pointer_values": _unique_hex(list(pointer_values))[:12],
        "comparison_branch_shape_status": "observed" if has_compare_branch else "not_observed_in_bounded_window",
    }


def _opcode_header_offsets(opcode: str) -> set[int]:
    import re

    offsets: set[int] = set()
    opcode_lower = opcode.lower()
    destination_operand = opcode_lower.split(",", 1)[0] if "," in opcode_lower else ""
    for match in re.finditer(r"\[([a-z]{2,3})(?: \+ (0x[0-9a-f]+|\d+))?\]", opcode.lower()):
        base_register = match.group(1)
        if base_register in {"ebp", "esp"}:
            continue
        if opcode_lower.startswith("mov ") and match.start() < len(destination_operand):
            continue
        raw = match.group(2)
        offsets.add(int(raw, 0) if raw is not None else 0)
    return offsets


def summarize_shp_render_ops(ops: list[Any]) -> dict[str, Any]:
    typed_ops = [op for op in ops if isinstance(op, dict)]
    header_offsets: set[int] = set()
    magic_compare_addresses: list[str] = []
    version_or_format_compare_addresses: list[str] = []
    row_table_skip_addresses: list[str] = []
    call_targets: list[int] = []
    type_counts: dict[str, int] = {}
    for op in typed_ops:
        op_type = str(op.get("type", "unknown"))
        type_counts[op_type] = type_counts.get(op_type, 0) + 1
        address = _op_address(op)
        opcode = str(op.get("opcode", ""))
        header_offsets.update(offset for offset in _opcode_header_offsets(opcode) if 0 <= offset <= 0x24)
        if "0x53484c54" in opcode and address is not None:
            magic_compare_addresses.append(hex_address(address))
        if "cmp" in opcode and ", 2" in opcode and address is not None:
            version_or_format_compare_addresses.append(hex_address(address))
        if "0x24" in opcode and address is not None:
            row_table_skip_addresses.append(hex_address(address))
        jump = op.get("jump")
        if op_type == "call" and isinstance(jump, int) and is_probable_code_address(jump):
            call_targets.append(jump)
    offsets_hex = [hex_address(offset) for offset in sorted(header_offsets)]
    return {
        "op_count": len(typed_ops),
        "op_type_counts": dict(sorted(type_counts.items())),
        "observed_header_offsets": offsets_hex,
        "header_0x10_read_status": "observed" if "0x10" in offsets_hex else "not_observed_in_bounded_windows",
        "tlhs_magic_compare_addresses": magic_compare_addresses[:8],
        "format_version_compare_addresses": version_or_format_compare_addresses[:8],
        "row_table_header_skip_addresses": row_table_skip_addresses[:8],
        "call_target_addresses": _unique_hex(call_targets),
    }


def build_body_window_summaries(body_windows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    summaries: list[dict[str, Any]] = []
    for body in body_windows:
        ops = body.get("ops", [])
        op_list = ops if isinstance(ops, list) else []
        op_summary = summarize_ops(op_list)
        summaries.append({
            "id": str(body.get("id", "")),
            "address": str(body.get("address", "")),
            "evidence_tier": "static_body_observed" if op_summary["op_count"] else "static_body_shape_candidate",
            "status": str(body.get("status", "unknown")),
            "mode": str(body.get("mode", "")),
            "observed_size": body.get("observed_size"),
            "op_count": op_summary["op_count"],
            "op_type_counts": op_summary["op_type_counts"],
            "call_target_addresses": op_summary["call_target_addresses"],
            "jump_target_addresses": op_summary["jump_target_addresses"],
            "data_ref_addresses": op_summary["data_ref_addresses"],
            "code_ref_addresses": op_summary["code_ref_addresses"],
            "evidence_sources": [
                str(item)
                for item in body.get("evidence_sources", [])
            ],
            "why_next": str(body.get("why_next", "")),
        })
    return summaries


def build_shp_render_header_static_evidence(manifest: dict[str, Any]) -> dict[str, Any]:
    windows = manifest.get("shp_render_windows", [])
    window_list = windows if isinstance(windows, list) else []
    resource_refs = manifest.get("resource_refs")
    summary = resource_refs.get("summary", {}) if isinstance(resource_refs, dict) else {}
    window_summaries: list[dict[str, Any]] = []
    combined_offsets: set[str] = set()
    for window in window_list:
        if not isinstance(window, dict):
            continue
        ops = window.get("ops", [])
        op_list = ops if isinstance(ops, list) else []
        op_summary = summarize_shp_render_ops(op_list)
        combined_offsets.update(op_summary["observed_header_offsets"])
        window_summaries.append({
            "id": str(window.get("id", "")),
            "address": str(window.get("address", "")),
            "evidence_tier": "static_shp_render_window",
            "status": str(window.get("status", "unknown")),
            "bounded_instruction_count": int(window.get("instruction_count", 0)),
            **op_summary,
            "why_next": str(window.get("why_next", "")),
        })
    return {
        "schema": "hsl_static_shp_render_header_evidence.v1",
        "evidence_tier": "static_render_path_candidate",
        "semantic_status": "unresolved",
        "header_0x10_semantic_status": "unresolved",
        "header_0x10_read_status": "observed" if "0x10" in combined_offsets else "not_observed_in_bounded_windows",
        "combined_observed_header_offsets": sorted(combined_offsets, key=lambda value: int(value, 16)),
        "window_summaries": window_summaries,
        "resource_color_header_0x10_counts": summary.get("color_header_0x10_counts", {}),
        "resource_only_negative_evidence": "Resource-formats reports resolved referenced SHP refs do not show header 0x10 values in pixels; this static EXE slice only checks bounded TLHS render/load candidates.",
        "negative_evidence": [
            "No bounded TLHS render/load window in this slice reads header offset 0x10.",
            "Absence in these bounded windows does not prove header 0x10 is unused globally.",
            "Do not name header 0x10 as color key, flags, palette index, checksum-like, or unused metadata until wider render/load xrefs are mapped.",
        ],
        "next_static_need": "Find callers of TLHS row decode candidates and broader SHP loader allocation path to determine whether header 0x10 is read outside these bounded windows.",
    }


def build_condition_handler_window_summaries(handler_windows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    summaries: list[dict[str, Any]] = []
    for window in handler_windows:
        ops = window.get("ops", [])
        op_list = ops if isinstance(ops, list) else []
        op_summary = summarize_condition_handler_ops(op_list)
        summaries.append({
            "handler_address": str(window.get("address", "")),
            "evidence_tier": "static_condition_handler_window",
            "status": str(window.get("status", "unknown")),
            "bounded_instruction_count": int(window.get("instruction_count", 0)),
            "slots_if_order_matched": [
                int(slot)
                for slot in window.get("slots_if_order_matched", [])
                if isinstance(slot, int)
            ],
            "actions_if_order_matched": window.get("actions_if_order_matched", []),
            "correlation_status": "unresolved",
            "ordinal_as_slot_status": "not_evidence",
            **op_summary,
            "negative_evidence": [
                "Window is selected through unresolved resource-order-to-slot navigation.",
                "Branch shape does not identify comparison polarity or live predicate binding by itself.",
            ],
        })
    return summaries


def build_status_handler_window_summaries(handler_windows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    summaries: list[dict[str, Any]] = []
    for window in handler_windows:
        if not isinstance(window, dict):
            continue
        ops = window.get("ops", [])
        op_list = ops if isinstance(ops, list) else []
        op_summary = summarize_condition_handler_ops(op_list)
        summaries.append({
            "handler_address": str(window.get("address", "")),
            "evidence_tier": "static_status_handler_window",
            "status": str(window.get("status", "unknown")),
            "bounded_instruction_count": int(window.get("instruction_count", 0)),
            "slots_if_order_matched": [
                int(slot)
                for slot in window.get("slots_if_order_matched", [])
                if isinstance(slot, int)
            ],
            "actions_if_order_matched": window.get("actions_if_order_matched", []),
            "correlation_status": "unresolved",
            "ordinal_as_slot_status": "not_evidence",
            **op_summary,
            "negative_evidence": [
                "Window is selected through unresolved resource-order-to-slot navigation.",
                "Handler shape does not prove opcode identity, status registry target, or mutation commit timing.",
            ],
        })
    return summaries


def _script_bridge_body_ops(manifest: dict[str, Any]) -> list[dict[str, Any]]:
    for body in manifest.get("body_windows", []):
        if isinstance(body, dict) and body.get("id") == "script_interpreter_bridge_function":
            ops = body.get("ops", [])
            return [op for op in ops if isinstance(op, dict)] if isinstance(ops, list) else []
    return []


def _script_bridge_xrefs(manifest: dict[str, Any]) -> list[dict[str, Any]]:
    for target in manifest.get("xref_targets", []):
        if isinstance(target, dict) and target.get("id") == "script_interpreter_bridge_candidate":
            return _sanitize_xrefs(target.get("xrefs", []) if isinstance(target.get("xrefs"), list) else [])
    return []


def _script_cursor_commit_summary(ops: list[dict[str, Any]]) -> dict[str, Any]:
    import re

    cursor_write_addresses: list[str] = []
    token_advance_addresses: list[str] = []
    return_write_addresses: list[str] = []
    field_access_offsets: dict[str, int] = {}
    for op in ops:
        address = _op_address(op)
        opcode = str(op.get("opcode", "")).lower()
        if address is None:
            continue
        for match in re.finditer(r"\[ebp \+ (0x[0-9a-f]+|\d+)\]", opcode):
            offset = hex_address(int(match.group(1), 0))
            field_access_offsets[offset] = field_access_offsets.get(offset, 0) + 1
        if "mov dword [ebp + 0x90], esi" in opcode:
            cursor_write_addresses.append(hex_address(address))
        if opcode.startswith("add esi,"):
            token_advance_addresses.append(hex_address(address))
        if op.get("type") == "ret":
            return_write_addresses.append(hex_address(address))
    return {
        "script_cursor_field_offset": "0x90",
        "primary_control_field_offset": "0x8e",
        "interpreter_result_or_state_field_offset": "0x8c",
        "argument_scratch_field_offsets": ["0x94", "0x98", "0x9c", "0xa0", "0xa4"],
        "script_cursor_write_count": len(cursor_write_addresses),
        "script_cursor_write_addresses_sample": cursor_write_addresses[:24],
        "token_advance_count": len(token_advance_addresses),
        "token_advance_addresses_sample": token_advance_addresses[:24],
        "return_count": len(return_write_addresses),
        "field_access_offsets": dict(sorted(field_access_offsets.items(), key=lambda item: int(item[0], 16))),
        "commit_boundary_status": "script_cursor_progress_observed",
        "status_mutation_commit_status": "unresolved",
    }


def _call_count_summary(ops: list[dict[str, Any]], limit: int = 24) -> list[dict[str, Any]]:
    counts: dict[int, int] = {}
    for op in ops:
        if op.get("type") == "call" and isinstance(op.get("jump"), int) and is_probable_code_address(op.get("jump")):
            jump = int(op["jump"])
            counts[jump] = counts.get(jump, 0) + 1
    ranked = sorted(counts.items(), key=lambda item: (-item[1], item[0]))[:limit]
    return [{"callee_address": hex_address(address), "call_count": count} for address, count in ranked]


def _script_commit_caller_window_summaries(windows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    summaries: list[dict[str, Any]] = []
    bridge_callers: list[str] = []
    cleanup_calls = {"0x453ac0", "0x453a80", "0x44ee20"}
    for window in windows:
        if not isinstance(window, dict):
            continue
        ops = window.get("ops", [])
        op_list = [op for op in ops if isinstance(op, dict)] if isinstance(ops, list) else []
        op_summary = summarize_ops(op_list)
        bridge_call_addresses: list[str] = []
        cleanup_call_addresses: list[str] = []
        branch_edges: list[dict[str, Any]] = []
        for op in op_list:
            address = _op_address(op)
            if address is not None and op.get("type") == "call" and op.get("jump") == 0x450840:
                bridge_call_addresses.append(hex_address(address))
                bridge_callers.append(hex_address(address))
            if address is not None and op.get("type") == "call" and hex_address(op.get("jump")) in cleanup_calls:
                cleanup_call_addresses.append(hex_address(address))
            if address is not None and op.get("type") == "cjmp":
                edge: dict[str, Any] = {"from_address": hex_address(address)}
                if isinstance(op.get("jump"), int):
                    edge["jump_target"] = hex_address(op.get("jump"))
                if isinstance(op.get("fail"), int):
                    edge["fallthrough_target"] = hex_address(op.get("fail"))
                branch_edges.append(edge)
        data_ref_set = set(op_summary["data_ref_addresses"])
        candidate_queue_refs = sorted(
            data_ref_set & {"0x4c1d04", "0x4c1d08", "0x4c1d0c", "0x4c1d10", "0x4c1d14", "0x4c1d18"},
            key=lambda value: int(value, 16),
        )
        candidate_flag_refs = sorted(
            data_ref_set & {"0x4c1b00", "0x4c1ba0", "0x4c1d44", "0x4c1b50"},
            key=lambda value: int(value, 16),
        )
        summaries.append({
            "id": str(window.get("id", "")),
            "address": str(window.get("address", "")),
            "role": str(window.get("role", "")),
            "evidence_tier": "static_script_commit_caller_window",
            "status": str(window.get("status", "unknown")),
            "bounded_instruction_count": int(window.get("instruction_count", 0)),
            "op_count": op_summary["op_count"],
            "op_type_counts": op_summary["op_type_counts"],
            "bridge_call_addresses": bridge_call_addresses,
            "call_target_addresses": op_summary["call_target_addresses"],
            "data_ref_addresses": op_summary["data_ref_addresses"],
            "candidate_deferred_queue_global_refs": candidate_queue_refs,
            "candidate_runtime_flag_global_refs": candidate_flag_refs,
            "cleanup_or_followup_call_addresses": cleanup_call_addresses,
            "conditional_branch_edges_sample": branch_edges[:12],
            "semantic_status": "unresolved",
            "why_next": str(window.get("why_next", "")),
        })
    return summaries


def _memory_write_summary(ops: list[dict[str, Any]]) -> dict[str, Any]:
    import re

    global_writes: set[int] = set()
    object_write_offsets: set[int] = set()
    stack_write_count = 0
    for op in ops:
        opcode = str(op.get("opcode", "")).lower()
        if not (
            opcode.startswith("mov ")
            or opcode.startswith("and ")
            or opcode.startswith("or ")
            or opcode.startswith("add ")
            or opcode.startswith("sub ")
        ):
            continue
        destination = opcode.split(",", 1)[0] if "," in opcode else opcode
        if "[" not in destination:
            continue
        absolute = re.search(r"\[(0x[0-9a-f]+)\]", destination)
        if absolute:
            global_writes.add(int(absolute.group(1), 16))
            continue
        relative = re.search(r"\[([a-z]{2,3}) \+ (0x[0-9a-f]+|\d+)\]", destination)
        if not relative:
            continue
        base = relative.group(1)
        offset = int(relative.group(2), 0)
        if base in {"esp", "ebp"}:
            stack_write_count += 1
        elif 0 <= offset <= 0x140:
            object_write_offsets.add(offset)
    return {
        "global_write_addresses": _unique_hex(list(global_writes)),
        "object_write_offsets": [hex_address(value) for value in sorted(object_write_offsets)],
        "stack_write_count": stack_write_count,
    }


def _script_commit_callee_window_summaries(windows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    summaries: list[dict[str, Any]] = []
    queue_globals = {"0x4c1d04", "0x4c1d08", "0x4c1d0c", "0x4c1d10", "0x4c1d14", "0x4c1d18"}
    runtime_flags = {"0x4c1b00", "0x4c1ba0", "0x4c1d44", "0x4c1b50"}
    for window in windows:
        if not isinstance(window, dict):
            continue
        ops = window.get("ops", [])
        op_list = [op for op in ops if isinstance(op, dict)] if isinstance(ops, list) else []
        op_summary = summarize_ops(op_list)
        write_summary = _memory_write_summary(op_list)
        data_ref_set = set(op_summary["data_ref_addresses"])
        global_write_set = set(write_summary["global_write_addresses"])
        summaries.append({
            "id": str(window.get("id", "")),
            "address": str(window.get("address", "")),
            "role": str(window.get("role", "")),
            "evidence_tier": "static_script_commit_callee_window",
            "status": str(window.get("status", "unknown")),
            "bounded_instruction_count": int(window.get("instruction_count", 0)),
            "op_count": op_summary["op_count"],
            "op_type_counts": op_summary["op_type_counts"],
            "call_target_addresses": op_summary["call_target_addresses"],
            "data_ref_addresses": op_summary["data_ref_addresses"],
            "global_write_addresses": write_summary["global_write_addresses"],
            "object_write_offsets": write_summary["object_write_offsets"],
            "stack_write_count": write_summary["stack_write_count"],
            "candidate_deferred_queue_global_refs": sorted(data_ref_set & queue_globals, key=lambda value: int(value, 16)),
            "candidate_deferred_queue_global_writes": sorted(global_write_set & queue_globals, key=lambda value: int(value, 16)),
            "candidate_runtime_flag_global_refs": sorted(data_ref_set & runtime_flags, key=lambda value: int(value, 16)),
            "candidate_runtime_flag_global_writes": sorted(global_write_set & runtime_flags, key=lambda value: int(value, 16)),
            "direct_status_registry_write_status": "not_observed_in_bounded_window",
            "semantic_status": "unresolved",
            "why_next": str(window.get("why_next", "")),
        })
    return summaries


def build_script_status_commit_path_context(manifest: dict[str, Any]) -> dict[str, Any]:
    bridge_ops = _script_bridge_body_ops(manifest)
    bridge_summary = summarize_ops(bridge_ops)
    cursor_summary = _script_cursor_commit_summary(bridge_ops)
    caller_summaries = _script_commit_caller_window_summaries(manifest.get("script_commit_caller_windows", []))
    callee_summaries = _script_commit_callee_window_summaries(manifest.get("script_commit_callee_windows", []))
    lifecycle_candidates = build_status_lifecycle_handler_candidates(manifest)
    status_actions = lifecycle_candidates.get("actions", []) if isinstance(lifecycle_candidates, dict) else []
    direct_queue_writes = sorted(
        {
            address
            for summary in callee_summaries
            for address in summary.get("candidate_deferred_queue_global_writes", [])
        },
        key=lambda value: int(value, 16),
    )
    direct_flag_writes = sorted(
        {
            address
            for summary in callee_summaries
            for address in summary.get("candidate_runtime_flag_global_writes", [])
        },
        key=lambda value: int(value, 16),
    )
    return {
        "schema": "hsl_static_script_status_commit_path_context.v1",
        "evidence_tier": "static_commit_path_candidate",
        "semantic_status": "unresolved",
        "execution_policy": "scheduled_only_no_live_mutation",
        "playable_blocker_helped": (
            "script-vm/Godot status lifecycle currently stays event-log-only; this context separates script cursor progress "
            "commit evidence from unresolved status registry mutation timing."
        ),
        "bridge_address": "0x450840",
        "script_primary_dispatch_table": "0x453708",
        "script_action_dispatch_table": "0x4537f4",
        "bridge_xrefs": _script_bridge_xrefs(manifest),
        "bridge_body_summary": {
            "op_count": bridge_summary["op_count"],
            "op_type_counts": bridge_summary["op_type_counts"],
            "call_target_count": len(bridge_summary["call_target_addresses"]),
            "data_ref_addresses": bridge_summary["data_ref_addresses"],
            "top_call_targets": _call_count_summary(bridge_ops),
        },
        "script_cursor_progress": cursor_summary,
        "caller_window_summaries": caller_summaries,
        "callee_window_summaries": callee_summaries,
        "deferred_queue_candidate_status": "unresolved",
        "registry_write_status": "unresolved",
        "direct_deferred_queue_write_status": "observed_in_prioritized_callee_windows" if direct_queue_writes else "not_observed_in_prioritized_callee_windows",
        "direct_deferred_queue_write_addresses": direct_queue_writes,
        "runtime_flag_write_addresses": direct_flag_writes,
        "direct_status_registry_write_status": "not_observed_in_prioritized_callee_windows",
        "status_mutation_commit_timing_status": "unresolved",
        "status_handler_boundary_candidates": [
            {
                "action_name": str(action.get("action_name", "")),
                "candidate_handler_if_order_matched": action.get("candidate_handler_if_order_matched"),
                "handler_call_targets_if_order_matched": action.get("handler_call_targets_if_order_matched", []),
                "handler_data_refs_if_order_matched": action.get("handler_data_refs_if_order_matched", []),
                "correlation_status": "unresolved",
                "ordinal_as_slot_status": "not_evidence",
                "commit_timing_evidence_status": "unresolved",
            }
            for action in status_actions
            if isinstance(action, dict)
        ],
        "negative_evidence": [
            "Bridge body shows many writes to script cursor field 0x90, but that only proves interpreter progress state, not status registry mutation commit.",
            "Caller windows expose candidate deferred queue globals around 0x4c1d04/0x4c1d08/0x4c1d0c and runtime flag globals around 0x4c1b00/0x4c1d44, but the queue/flag semantics remain unresolved.",
            "Prioritized status-related callees write object-like fields but do not show direct writes to candidate deferred queue globals in this bounded slice.",
            "Status handler boundary candidates still come from unresolved resource-order navigation; they do not prove numeric opcode, action name, or commit timing.",
        ],
        "next_static_need": "Inspect compact callees 0x44fad0/0x44fcf0/0x44fd90/0x44fe40/0x44fed0/0x44ff50 and cleanup helpers 0x453ac0/0x453a80 for direct registry writes or deferred queue consumption.",
    }


def _has_op_at(ops: list[dict[str, Any]], address: int, contains: str) -> bool:
    needle = contains.lower()
    for op in ops:
        if _op_address(op) == address and needle in str(op.get("opcode", "")).lower():
            return True
    return False


def build_script_numeric_dispatch_token_context(manifest: dict[str, Any]) -> dict[str, Any]:
    bridge_ops = _script_bridge_body_ops(manifest)
    table_summaries = {
        str(summary.get("id")): summary
        for summary in build_dispatch_table_summaries(manifest.get("dispatch_tables", []))
        if isinstance(summary, dict)
    }
    primary = table_summaries.get("script_primary_dispatch_table", {})
    action = table_summaries.get("script_action_dispatch_table", {})
    primary_evidence = {
        "selector_source_field_offset": "0x8e",
        "selector_source_width": "word",
        "selector_zero_extend_status": "observed",
        "max_selector_value": "0x8b",
        "bounds_check_address": "0x450860",
        "out_of_range_target": "0x4536f1",
        "remap_table_address": "0x453768",
        "remap_table_entry_width": 1,
        "remap_table_read_status": "observed" if _has_op_at(bridge_ops, 0x45086e, "0x453768") else "not_observed",
        "dispatch_table_address": "0x453708",
        "dispatch_slot_source": "remapped_selector_byte",
        "dispatch_jump_address": "0x450874",
        "dispatch_table_observed_slots": int(primary.get("entry_count_observed", 0)) if isinstance(primary, dict) else 0,
        "dispatch_table_unique_handlers": int(primary.get("unique_handler_count", 0)) if isinstance(primary, dict) else 0,
    }
    action_evidence = {
        "script_cursor_field_offset": "0x90",
        "token_read_offset_from_cursor": "0x0",
        "token_source_width": "dword",
        "token_read_address": "0x450885",
        "cursor_advance_bytes": 4,
        "cursor_advance_address": "0x450887",
        "max_token_value": "0x8b",
        "bounds_check_address": "0x45088a",
        "out_of_range_target": "0x4511fe",
        "dispatch_table_address": "0x4537f4",
        "dispatch_slot_source": "script_token_value_direct",
        "dispatch_jump_address": "0x4508a1",
        "dispatch_table_observed_slots": int(action.get("entry_count_observed", 0)) if isinstance(action, dict) else 0,
        "dispatch_table_unique_handlers": int(action.get("unique_handler_count", 0)) if isinstance(action, dict) else 0,
    }
    loop_evidence = {
        "loop_token_read_address": "0x4511e9",
        "loop_cursor_advance_address": "0x4511ef",
        "loop_bounds_check_address": "0x4511f2",
        "loop_dispatch_reentry_target": "0x45089b",
        "script_cursor_commit_address": "0x45120f",
        "script_cursor_field_offset": "0x90",
    }
    return {
        "schema": "hsl_static_script_numeric_dispatch_token_context.v1",
        "evidence_tier": "static_numeric_token_source_observed",
        "semantic_status": "numeric_token_source_observed_handler_name_mapping_unresolved",
        "source_numeric_token_status": "observed_in_0x450840_bridge",
        "action_name_mapping_status": "unresolved",
        "handler_identity_status": "unresolved",
        "status_lifecycle_upgrade_status": "not_evidence",
        "bridge_address": "0x450840",
        "primary_dispatch": primary_evidence,
        "action_dispatch": action_evidence,
        "loop_reentry": loop_evidence,
        "downstream_guard_note": (
            "This proves that the bridge consumes numeric selector/token values before dispatch; it does not map imported action names "
            "to token values because current imported IR still lacks numeric token fields."
        ),
        "negative_evidence": [
            "No imported split script numeric token field is available in script_vm_semantics.json.",
            "Dispatch slot source is observed, but action-name-to-token mapping remains unresolved.",
            "Numeric token source evidence does not prove status lifecycle commit timing or executable handler semantics.",
        ],
        "next_static_need": "Find raw script/importer numeric token source or runtime trace of script cursor token values to join imported action names to 0x4537f4 slots.",
    }


OBJECT_FIELD_STRING_NAMES = {
    0x4A34A0: "obj_Plane",
    0x4A34AA: "obj_X1",
    0x4A34B1: "obj_Y1",
    0x4A34B8: "obj_X2",
    0x4A34BF: "obj_Y2",
    0x4A34F0: "obj_Shape_Name",
    0x4A34FF: "obj_Shape_Number",
    0x4A3510: "obj_Process_Code",
    0x4A3521: "obj_Collide_X1",
    0x4A3530: "obj_Collide_Y1",
    0x4A353F: "obj_Collide_X2",
    0x4A354E: "obj_Collide_Y2",
}


def _map_object_field_ref_summary(ops: list[dict[str, Any]]) -> list[dict[str, Any]]:
    refs: list[dict[str, Any]] = []
    for op in ops:
        address = _op_address(op)
        if address is None:
            continue
        for ref in op.get("refs", []) if isinstance(op.get("refs"), list) else []:
            if not isinstance(ref, dict) or ref.get("type") != "STRN":
                continue
            ref_addr = ref.get("addr")
            if not isinstance(ref_addr, int) or ref_addr not in OBJECT_FIELD_STRING_NAMES:
                continue
            refs.append({
                "field_name": OBJECT_FIELD_STRING_NAMES[ref_addr],
                "string_address": hex_address(ref_addr),
                "reference_address": hex_address(address),
            })
    return refs


def _object_offset_summary(ops: list[dict[str, Any]]) -> dict[str, Any]:
    import re

    offset_counts: dict[str, int] = {}
    for op in ops:
        opcode = str(op.get("opcode", "")).lower()
        for match in re.finditer(r"\[([a-z]{2,3})(?: \+ (0x[0-9a-f]+|\d+))?\]", opcode):
            base = match.group(1)
            if base in {"esp", "ebp"}:
                continue
            raw = match.group(2)
            offset = int(raw, 0) if raw is not None else 0
            if not 0 <= offset <= 0x180:
                continue
            key = hex_address(offset)
            offset_counts[key] = offset_counts.get(key, 0) + 1
    return {
        "object_like_offsets": sorted(offset_counts, key=lambda value: int(value, 16)),
        "hot_object_like_offsets": [
            {"offset": offset, "reference_count": count}
            for offset, count in sorted(offset_counts.items(), key=lambda item: (-item[1], int(item[0], 16)))[:16]
        ],
    }


def _map_object_window_summaries(windows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    summaries: list[dict[str, Any]] = []
    shp_related_calls = {
        "0x45fa1e",
        "0x45fc01",
        "0x45fca5",
        "0x45fd4b",
        "0x460058",
        "0x4601a2",
        "0x4602d4",
        "0x46e100",
        "0x46e1a8",
        "0x46cab0",
        "0x46cb70",
        "0x46c970",
    }
    for window in windows:
        if not isinstance(window, dict):
            continue
        ops = window.get("ops", [])
        op_list = [op for op in ops if isinstance(op, dict)] if isinstance(ops, list) else []
        op_summary = summarize_ops(op_list)
        offset_summary = _object_offset_summary(op_list)
        write_summary = _memory_write_summary(op_list)
        field_refs = _map_object_field_ref_summary(op_list)
        call_targets = set(op_summary["call_target_addresses"])
        summaries.append({
            "id": str(window.get("id", "")),
            "address": str(window.get("address", "")),
            "role": str(window.get("role", "")),
            "evidence_tier": "static_map_object_window",
            "status": str(window.get("status", "unknown")),
            "bounded_instruction_count": int(window.get("instruction_count", 0)),
            "op_count": op_summary["op_count"],
            "op_type_counts": op_summary["op_type_counts"],
            "call_target_addresses": op_summary["call_target_addresses"],
            "data_ref_addresses": op_summary["data_ref_addresses"],
            "object_field_string_refs": field_refs,
            "object_field_names_observed": sorted({ref["field_name"] for ref in field_refs}),
            "object_like_offsets": offset_summary["object_like_offsets"],
            "hot_object_like_offsets": offset_summary["hot_object_like_offsets"],
            "object_write_offsets": write_summary["object_write_offsets"],
            "global_write_addresses": write_summary["global_write_addresses"],
            "shp_related_call_targets": sorted(call_targets & shp_related_calls, key=lambda value: int(value, 16)),
            "semantic_status": "unresolved",
            "why_next": str(window.get("why_next", "")),
        })
    return summaries


def _map_object_resource_summary(manifest: dict[str, Any]) -> dict[str, Any]:
    evidence = manifest.get("map_object_visibility_evidence")
    if not isinstance(evidence, dict):
        return {
            "source_file": "content/imported/hsl/chapter01/map_object_visibility_evidence.json",
            "status": "missing",
            "target_resource_count": 0,
            "target_resources": [],
        }
    summary = evidence.get("summary", {}) if isinstance(evidence.get("summary"), dict) else {}
    objects = evidence.get("objects", []) if isinstance(evidence.get("objects"), list) else []
    target_resources: list[dict[str, Any]] = []
    for item in objects:
        if not isinstance(item, dict):
            continue
        usage = item.get("usage_summary", {}) if isinstance(item.get("usage_summary"), dict) else {}
        target_resources.append({
            "resource_id": str(item.get("resource_id", "")),
            "placed_instance_count": int(usage.get("placed_instance_count", 0)) if isinstance(usage.get("placed_instance_count"), int) else 0,
            "object_codes": [str(value) for value in usage.get("object_codes", [])] if isinstance(usage.get("object_codes"), list) else [],
            "shape_number_candidates": [str(value) for value in usage.get("shape_number_candidates", [])] if isinstance(usage.get("shape_number_candidates"), list) else [],
            "obj_plane_candidates": [str(value) for value in usage.get("obj_plane_candidates", [])] if isinstance(usage.get("obj_plane_candidates"), list) else [],
            "processes": dict(usage.get("processes", {})) if isinstance(usage.get("processes"), dict) else {},
            "user_confirmed_roles": sorted(
                (summary.get("user_confirmed_role_by_resource", {}) or {}).get(str(item.get("resource_id", "")), [])
            ) if isinstance(summary.get("user_confirmed_role_by_resource"), dict) else [],
        })
    return {
        "source_file": "content/imported/hsl/chapter01/map_object_visibility_evidence.json",
        "status": "loaded",
        "target_resource_count": int(summary.get("target_resource_count", len(target_resources))),
        "target_placement_count": int(summary.get("target_placement_count", 0)) if isinstance(summary.get("target_placement_count"), int) else 0,
        "obj_plane_candidates_by_resource": dict(summary.get("obj_plane_candidates_by_resource", {})) if isinstance(summary.get("obj_plane_candidates_by_resource"), dict) else {},
        "target_resources": target_resources,
    }


def build_map_object_visibility_static_context(manifest: dict[str, Any]) -> dict[str, Any]:
    windows = _map_object_window_summaries(manifest.get("map_object_static_windows", []))
    parser = next((window for window in windows if window.get("id") == "object_definition_field_parser_candidate"), None)
    draw = next((window for window in windows if window.get("id") == "scene_object_draw_candidate"), None)
    parser_fields = set(parser.get("object_field_names_observed", [])) if isinstance(parser, dict) else set()
    required_fields = {
        "obj_Plane",
        "obj_X1",
        "obj_Y1",
        "obj_X2",
        "obj_Y2",
        "obj_Shape_Name",
        "obj_Shape_Number",
        "obj_Collide_X1",
        "obj_Collide_Y1",
        "obj_Collide_X2",
        "obj_Collide_Y2",
    }
    draw_offsets = set(draw.get("object_like_offsets", [])) if isinstance(draw, dict) else set()
    return {
        "schema": "hsl_static_map_object_visibility_context.v1",
        "evidence_tier": "static_window_resource_join",
        "semantic_status": "unresolved",
        "resource_scope": _map_object_resource_summary(manifest),
        "obj_plane_status": "parser_field_ingestion_observed_render_sorting_unresolved",
        "stand_object_traversal_status": "candidate_scene_draw_window_observed_owner_semantics_unresolved",
        "shape_number_semantics_status": "unresolved_navigation_candidate_only",
        "occlusion_sorting_status": "unresolved_no_direct_tree_fire_bar_unit_occlusion_proof",
        "parser_field_ingestion": {
            "window_address": "0x45dc5c",
            "observed_field_count": len(parser_fields),
            "target_fields_observed": sorted(parser_fields & required_fields),
            "missing_target_fields": sorted(required_fields - parser_fields),
            "field_reference_order": parser.get("object_field_string_refs", []) if isinstance(parser, dict) else [],
        },
        "draw_or_traversal_candidate": {
            "window_address": "0x456150",
            "object_like_offsets": sorted(draw_offsets, key=lambda value: int(value, 16)) if draw_offsets else [],
            "object_write_offsets": draw.get("object_write_offsets", []) if isinstance(draw, dict) else [],
            "shp_related_call_targets": draw.get("shp_related_call_targets", []) if isinstance(draw, dict) else [],
            "camera_or_view_global_refs": sorted(set(draw.get("data_ref_addresses", [])) & {"0x4c091c", "0x4c0920"}, key=lambda value: int(value, 16)) if isinstance(draw, dict) else [],
            "clip_or_anchor_candidate_offsets": sorted(draw_offsets & {"0x70", "0x74", "0x80", "0x88", "0x8c", "0x90", "0x94", "0x98", "0x9a", "0x9c", "0xa0", "0xa4", "0xa8", "0xaa", "0xac"}, key=lambda value: int(value, 16)) if draw_offsets else [],
            "semantic_status": "unresolved",
        },
        "render_path_windows": [
            window
            for window in windows
            if window.get("id") in {"shp_descriptor_render_caller_a", "shp_descriptor_render_caller_b"}
        ],
        "window_summaries": windows,
        "godot_consumable_fields": {
            "can_keep_resource_preview_and_role_labels": True,
            "can_surface_obj_plane_as_parser_ingested_candidate": True,
            "can_surface_shape_number_as_parser_ingested_candidate": True,
            "must_keep_layer_sorting_occlusion_anchor_clip_unresolved": True,
        },
        "negative_evidence": [
            "Resource object plane values planeObject1/planeObject20 are not observed as EXE string constants in this slice.",
            "No bounded window proves obj_plane enters render sorting or unit/backdrop occlusion ordering.",
            "Parser field ingestion proves obj_Shape_Number is read as object data, but does not prove frame index, variant id, or animation semantics.",
            "Scene/draw candidate and SHP render caller windows expose object-like offsets and SHP calls, but do not bind tree/fire/bar instances to exact unit occlusion behavior.",
        ],
        "next_static_need": "Find xrefs from parsed object records into draw-order traversal or runtime list sorting, or use runtime sampling to correlate planeObject1/20 with visible unit/backdrop occlusion.",
    }


def build_status_lifecycle_handler_candidates(manifest: dict[str, Any]) -> dict[str, Any] | None:
    semantics = manifest.get("script_vm_semantics")
    action_names = _status_lifecycle_action_names(semantics)
    if not action_names:
        return None
    ordered_names = _ordered_action_names(manifest)
    fingerprints_by_slot = _fingerprint_by_slot(manifest)
    status_windows_by_handler = {
        str(item.get("handler_address")): item
        for item in build_status_handler_window_summaries(manifest.get("status_handler_windows", []))
        if isinstance(item, dict)
    }
    lifecycle = semantics.get("status_mutation_lifecycle_model") if isinstance(semantics, dict) else {}
    mutation_counts = lifecycle.get("mutation_counts_by_action", {}) if isinstance(lifecycle, dict) else {}
    actions: list[dict[str, Any]] = []
    for action_name in sorted(action_names):
        ordinal = ordered_names.index(action_name) if action_name in ordered_names else None
        fingerprint = fingerprints_by_slot.get(ordinal) if ordinal is not None else None
        handler_address = fingerprint.get("handler_address") if fingerprint else None
        window = status_windows_by_handler.get(str(handler_address)) if handler_address else None
        actions.append({
            "action_name": action_name,
            "scheduled_mutation_count": int(mutation_counts.get(action_name, 0)) if isinstance(mutation_counts, dict) else 0,
            "candidate_slot_if_order_matched": ordinal if fingerprint is not None else None,
            "candidate_handler_if_order_matched": handler_address,
            "handler_call_targets_if_order_matched": fingerprint.get("call_target_addresses", []) if fingerprint else [],
            "handler_data_refs_if_order_matched": fingerprint.get("data_ref_addresses", []) if fingerprint else [],
            "handler_op_type_counts_if_order_matched": fingerprint.get("op_type_counts", {}) if fingerprint else {},
            "status_handler_window_status": window.get("comparison_branch_shape_status") if window else "not_exported",
            "status_handler_call_targets_until_first_ret": window.get("call_target_addresses_until_first_ret", []) if window else [],
            "status_handler_data_refs_until_first_ret": window.get("data_ref_addresses_until_first_ret", []) if window else [],
            "correlation_status": "unresolved",
            "ordinal_as_slot_status": "not_evidence",
            "slot_opcode_evidence_status": "unresolved",
            "commit_timing_evidence_status": "unresolved",
            "lifecycle_semantic_status": "scheduled_only",
            "why_unresolved": "Imported IR has no numeric opcode/token fields; resource order is navigation only and does not prove handler identity or mutation commit timing.",
        })
    return {
        "schema": "hsl_static_status_lifecycle_handler_candidates.v1",
        "evidence_tier": "static_candidate_skeleton",
        "semantic_status": "unresolved",
        "execution_policy": "scheduled_only_no_live_mutation",
        "static_script_action_dispatch_table": "0x4537f4",
        "static_script_interpreter_bridge": "0x450840",
        "action_count": len(actions),
        "actions": actions,
        "handler_window_summaries": build_status_handler_window_summaries(manifest.get("status_handler_windows", [])),
        "bridge_commit_timing_status": "unresolved",
        "negative_evidence": [
            "No status action has proven numeric opcode-to-slot evidence.",
            "No bounded status handler window proves immediate, deferred, or one-shot mutation commit timing.",
            "0x450840 bridge timing still requires caller/commit-path evidence before lifecycle semantics can move beyond diagnostics.",
        ],
        "next_static_need": "Inspect 0x450840 commit path and status handler callees/data refs for registry write targets or deferred queue boundaries without using action order as evidence.",
    }


def _opcode_object_offsets(opcode: str) -> list[str]:
    import re

    offsets: set[int] = set()
    for match in re.finditer(r"\[([a-z]{2,3})(?: \+ (0x[0-9a-f]+|\d+))?\]", opcode.lower()):
        base = match.group(1)
        if base in {"ebp", "esp"}:
            continue
        raw = match.group(2)
        offset = int(raw, 0) if raw is not None else 0
        if 0 <= offset <= 0x120:
            offsets.add(offset)
    return [hex_address(offset) for offset in sorted(offsets)]


def summarize_ui_owner_window_ops(ops: list[Any]) -> dict[str, Any]:
    import re

    op_list = [op for op in ops if isinstance(op, dict)]
    op_summary = summarize_ops(op_list)
    read_offsets: set[int] = set()
    write_offsets: set[int] = set()
    chain_offset_counts: dict[str, int] = {}
    global_refs: set[str] = set()
    branch_edges: list[dict[str, Any]] = []
    indirect_call_count = 0
    for op in op_list:
        opcode = str(op.get("opcode", "")).lower()
        destination = opcode.split(",", 1)[0] if "," in opcode else ""
        for match in re.finditer(r"\[([a-z]{2,3})(?: \+ (0x[0-9a-f]+|\d+))?\]", opcode):
            base = match.group(1)
            if base in {"ebp", "esp"}:
                continue
            raw = match.group(2)
            offset = int(raw, 0) if raw is not None else 0
            if not 0 <= offset <= 0x140:
                continue
            if opcode.startswith("mov ") and match.start() < len(destination):
                write_offsets.add(offset)
            else:
                read_offsets.add(offset)
            key = hex_address(offset)
            chain_offset_counts[key] = chain_offset_counts.get(key, 0) + 1
        for ref in _op_refs(op, "DATA"):
            global_refs.add(hex_address(ref))
        if op.get("type") in {"ircall", "rcall"}:
            indirect_call_count += 1
        if op.get("type") == "cjmp" and _op_address(op) is not None:
            edge: dict[str, Any] = {"from_address": hex_address(_op_address(op))}
            if isinstance(op.get("jump"), int):
                edge["jump_target"] = hex_address(op.get("jump"))
            if isinstance(op.get("fail"), int):
                edge["fallthrough_target"] = hex_address(op.get("fail"))
            branch_edges.append(edge)
    hot_offsets = [
        {"offset": offset, "reference_count": count}
        for offset, count in sorted(chain_offset_counts.items(), key=lambda item: (-item[1], int(item[0], 16)))[:16]
    ]
    return {
        "op_count": op_summary["op_count"],
        "op_type_counts": op_summary["op_type_counts"],
        "call_target_addresses": op_summary["call_target_addresses"],
        "data_ref_addresses": sorted(global_refs, key=lambda value: int(value, 16)),
        "object_read_offsets": [hex_address(offset) for offset in sorted(read_offsets)],
        "object_write_offsets": [hex_address(offset) for offset in sorted(write_offsets)],
        "hot_object_offsets": hot_offsets,
        "indirect_call_count": indirect_call_count,
        "conditional_branch_edges": branch_edges[:24],
    }


def build_ui_owner_related_window_summaries(windows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    summaries: list[dict[str, Any]] = []
    for window in windows:
        if not isinstance(window, dict):
            continue
        ops = window.get("ops", [])
        op_list = ops if isinstance(ops, list) else []
        op_summary = summarize_ui_owner_window_ops(op_list)
        summaries.append({
            "id": str(window.get("id", "")),
            "address": str(window.get("address", "")),
            "role": str(window.get("role", "")),
            "evidence_tier": "static_ui_owner_related_window",
            "status": str(window.get("status", "unknown")),
            "bounded_instruction_count": int(window.get("instruction_count", 0)),
            "semantic_status": "unresolved",
            "owner_contract_status": "unresolved",
            **op_summary,
            "why_next": str(window.get("why_next", "")),
        })
    return summaries


def _ui_owner_contract_navigation_hints(related_windows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    hints: list[dict[str, Any]] = []
    for window in related_windows:
        window_id = str(window.get("id", ""))
        if window_id == "logical_ui_hit_test_caller_window":
            hints.append({
                "candidate": "object_list_traversal_fields",
                "source_window": window_id,
                "evidence_tier": "static_window_shape",
                "static_signal": "caller and hit-test window repeatedly reference object offsets 0x60, 0x80, and 0x98",
                "semantic_status": "unresolved",
                "why_playable": "Prioritizes object-list fields for Godot UI/target hit-test probes.",
            })
        elif window_id == "logical_ui_child_chain_copy_candidate":
            hints.append({
                "candidate": "child_chain_copy_contract",
                "source_window": window_id,
                "evidence_tier": "static_window_shape",
                "static_signal": "callee traverses 0x60 and copies child-node fields 0x4..0x1c",
                "semantic_status": "unresolved",
                "why_playable": "Suggests where nested UI/target objects propagate bounds or state.",
            })
        elif window_id == "logical_ui_list_entry_alloc_candidate":
            hints.append({
                "candidate": "list_entry_allocation_or_linking_contract",
                "source_window": window_id,
                "evidence_tier": "static_window_shape",
                "static_signal": "callee writes flag-like high-bit constants and links through first dwords of a list entry",
                "semantic_status": "unresolved",
                "why_playable": "Potential allocator/linker for UI hit-test child entries; needs caller proof before naming owner.",
            })
        elif window_id == "logical_ui_allocator_pool_candidate":
            hints.append({
                "candidate": "allocator_pool_contract",
                "source_window": window_id,
                "evidence_tier": "static_window_shape",
                "static_signal": "callee is reached from list-entry allocation and should be inspected with globals 0x4a19c4/0x4a35ec/0x4a35f0/0x4a35f4 as pool navigation hints",
                "semantic_status": "unresolved",
                "why_playable": "Potentially identifies where UI hit-test list entries are allocated before Godot mirrors target/UI object lifetimes.",
            })
        elif window_id == "logical_ui_rect_link_candidate":
            hints.append({
                "candidate": "rectangle_pool_link_contract",
                "source_window": window_id,
                "evidence_tier": "static_window_shape",
                "static_signal": "callee uses globals 0x4c09dc..0x4c09f0, increments pool cursors, and links rect nodes through 0xc/0x10",
                "semantic_status": "unresolved",
                "why_playable": "Candidate bridge from object offsets 0x68..0x74 to screen-space hit rectangles.",
            })
    return hints


def build_ui_owner_traversal_static_context(manifest: dict[str, Any]) -> dict[str, Any]:
    hit_test_ops: list[Any] = []
    for body in manifest.get("body_windows", []):
        if isinstance(body, dict) and body.get("id") == "logical_ui_hit_test_window":
            ops = body.get("ops", [])
            hit_test_ops = ops if isinstance(ops, list) else []
            break
    op_summary = summarize_ops(hit_test_ops)
    object_offsets: set[str] = set()
    cursor_global_refs: set[str] = set()
    input_global_refs: set[str] = set()
    branch_edges: list[dict[str, Any]] = []
    for op in hit_test_ops:
        if not isinstance(op, dict):
            continue
        opcode = str(op.get("opcode", ""))
        object_offsets.update(_opcode_object_offsets(opcode))
        for ref in _op_refs(op, "DATA"):
            ref_hex = hex_address(ref)
            if ref_hex in {"0x4c1a8c", "0x4c1a90"}:
                cursor_global_refs.add(ref_hex)
            if ref_hex in {"0x4c6390", "0x4c6398"}:
                input_global_refs.add(ref_hex)
        if op.get("type") == "cjmp" and _op_address(op) is not None:
            edge: dict[str, Any] = {"from_address": hex_address(_op_address(op))}
            if isinstance(op.get("jump"), int):
                edge["jump_target"] = hex_address(op.get("jump"))
            if isinstance(op.get("fail"), int):
                edge["fallthrough_target"] = hex_address(op.get("fail"))
            branch_edges.append(edge)
    ui_resources = manifest.get("ui_resources")
    ui_summary = ui_resources.get("summary", {}) if isinstance(ui_resources, dict) else {}
    resource_refs = manifest.get("resource_refs")
    resource_summary = resource_refs.get("summary", {}) if isinstance(resource_refs, dict) else {}
    related_window_summaries = build_ui_owner_related_window_summaries(manifest.get("ui_owner_windows", []))
    return {
        "schema": "hsl_static_ui_owner_traversal_context.v1",
        "evidence_tier": "static_hit_test_window_resource_navigation",
        "semantic_status": "unresolved",
        "owner_traversal_status": "unresolved",
        "command_identity_status": "unresolved",
        "hit_test_window": {
            "address": "0x445977",
            "op_count": op_summary["op_count"],
            "op_type_counts": op_summary["op_type_counts"],
            "call_target_addresses": op_summary["call_target_addresses"],
            "data_ref_addresses": op_summary["data_ref_addresses"],
            "cursor_global_refs": sorted(cursor_global_refs),
            "input_global_refs": sorted(input_global_refs),
            "object_like_offsets": sorted(object_offsets, key=lambda value: int(value, 16)),
            "conditional_branch_edges": branch_edges[:24],
        },
        "xref_context": {
            "known_xref_target": "0x445977",
            "current_xref_status": "single_CODE_xref_observed",
            "caller_resolution_status": "unresolved",
        },
            "ui_resource_navigation_hints": {
            "source_file": DEFAULT_UI_RESOURCES.as_posix(),
            "resource_count": ui_summary.get("resource_count"),
            "ui_group_counts": ui_summary.get("ui_group_counts", resource_summary.get("battle_ui_group_counts", {})),
            "owner_semantics_status": "unresolved",
            "command_identity_status": "unresolved",
        },
        "related_window_summaries": related_window_summaries,
        "contract_navigation_hints": _ui_owner_contract_navigation_hints(related_window_summaries),
        "playable_blocker_helped": "Godot UI/target interaction needs object-list base, hit-test owner flags, and callback contract evidence before battle command identity or target selection behavior can be implemented from original semantics.",
        "blocking_placement_navigation_note": {
            "source_file": "content/generated/hsl/static/hsl01/level051_terrain.json",
            "semantic_status": "unresolved",
            "relationship_to_ui_hit_test": "not_joined",
            "next_static_need": "Use the compact WRD terrain packet only when terrain/collision owner analysis starts; do not merge it with UI hit-test semantics without EXE evidence.",
        },
        "negative_evidence": [
            "UI resource group names are navigation hints and do not prove command identity.",
            "0x445977 proves cursor/button-driven object-like hit testing but not battle command ownership, unit selection, or terrain blocking semantics.",
            "compact WRD terrain evidence is not joined to this UI hit-test window in the current static slice.",
        ],
        "next_static_need": "Expand caller/owner around the single CODE xref and inspect call targets 0x445d70/0x445f60 to identify object list base, owner flags, or callback contract.",
    }


def _action_table_slots(tables: list[dict[str, Any]]) -> dict[str, list[int]]:
    slots_by_handler: dict[str, list[int]] = {}
    for table in tables:
        if table.get("id") != "script_action_dispatch_table":
            continue
        for slot in _handler_slots(table.get("entries", [])):
            address = str(slot["handler_address"])
            slots_by_handler.setdefault(address, []).append(int(slot["slot"]))
    return {address: sorted(slots) for address, slots in sorted(slots_by_handler.items())}


def build_action_handler_fingerprints(
    dispatch_tables: list[dict[str, Any]],
    body_windows: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    slots_by_handler = _action_table_slots(dispatch_tables)
    bridge_ops: list[Any] = []
    for body in body_windows:
        if body.get("id") == "script_interpreter_bridge_function":
            ops = body.get("ops", [])
            bridge_ops = ops if isinstance(ops, list) else []
            break
    handler_addresses = sorted(int(address, 16) for address in slots_by_handler)
    fingerprints: list[dict[str, Any]] = []
    for index, address in enumerate(handler_addresses):
        next_address = handler_addresses[index + 1] if index + 1 < len(handler_addresses) else address + 0x80
        # Keep each tracked fingerprint bounded to avoid turning handler summaries into disassembly dumps.
        end_address = min(next_address, address + 0x80)
        summary = summarize_ops(bridge_ops, start=address, end=end_address)
        fingerprints.append({
            "handler_address": hex_address(address),
            "slot_numbers": slots_by_handler[hex_address(address)],
            "evidence_tier": "static_handler_fingerprint",
            "bounded_byte_window": end_address - address,
            "op_count": summary["op_count"],
            "op_type_counts": summary["op_type_counts"],
            "call_target_addresses": summary["call_target_addresses"],
            "jump_target_addresses": summary["jump_target_addresses"],
            "data_ref_addresses": summary["data_ref_addresses"],
            "code_ref_addresses": summary["code_ref_addresses"],
            "why_next": "Use slot_numbers plus compact call/data refs to correlate imported action names and resource/object semantics without tracking raw instructions.",
        })
    return fingerprints


def build_script_action_correlation_skeleton(manifest: dict[str, Any]) -> dict[str, Any] | None:
    semantics = manifest.get("script_vm_semantics")
    if not isinstance(semantics, dict):
        return None
    hints = semantics.get("dispatch_correlation_hints")
    if not isinstance(hints, dict):
        return None
    action_names = hints.get("ordered_unique_action_names")
    if not isinstance(action_names, list):
        return None
    catalog = semantics.get("action_semantics_catalog")
    by_action = catalog.get("by_action", {}) if isinstance(catalog, dict) else {}
    category_summary = catalog.get("category_summary", {}) if isinstance(catalog, dict) else {}
    fingerprints = build_action_handler_fingerprints(
        manifest.get("dispatch_tables", []),
        manifest.get("body_windows", []),
    )
    handler_by_slot: dict[int, str] = {}
    for item in fingerprints:
        for slot in item.get("slot_numbers", []):
            if isinstance(slot, int):
                handler_by_slot[slot] = str(item.get("handler_address", ""))
    actions = []
    for ordinal, name in enumerate(action_names):
        occurrences = by_action.get(name, []) if isinstance(by_action, dict) else []
        occurrence_list = occurrences if isinstance(occurrences, list) else []
        categories = sorted({
            str(item.get("category"))
            for item in occurrence_list
            if isinstance(item, dict) and item.get("category")
        })
        actions.append({
            "resource_order_index": ordinal,
            "action_name": str(name),
            "catalog_categories": categories,
            "catalog_occurrence_count": len(occurrence_list),
            "correlation_status": "unresolved",
            "ordinal_as_slot_status": "not_evidence",
            "candidate_slot_if_order_matched": ordinal if ordinal in handler_by_slot else None,
            "candidate_handler_if_order_matched": handler_by_slot.get(ordinal),
            "why_unresolved": "Resource first-seen action order is not proven to equal script action opcode or 0x4537f4 slot number.",
        })
    return {
        "schema": "hsl_static_script_action_correlation_skeleton.v1",
        "source_file": DEFAULT_SCRIPT_VM_SEMANTICS.as_posix(),
        "source_evidence_tier": str(semantics.get("evidence_tier", "")),
        "source_total_action_chain_count": semantics.get("source_total_action_chain_count"),
        "ordered_action_name_count": int(hints.get("ordered_action_name_count", len(action_names))),
        "static_script_action_dispatch_table": "0x4537f4",
        "static_script_primary_dispatch_table": "0x453708",
        "static_script_interpreter_bridge": "0x450840",
        "script_action_dispatch_slot_count": len(handler_by_slot),
        "script_action_dispatch_unique_handler_count": len({address for address in handler_by_slot.values() if address}),
        "action_catalog_category_summary": category_summary,
        "condition_summary": semantics.get("condition_summary", {}),
        "mutation_summary": semantics.get("mutation_summary", {}),
        "actions": actions,
        "downstream_consumers": [
            {
                "consumer": "godot-integration",
                "current_status": "read_only_action_metadata_no_handlers",
                "mapping_exit_criteria": "Requires stable action name to 0x4537f4 slot and handler evidence before mapped dry-run semantics.",
            },
            {
                "consumer": "script-vm",
                "current_status": "ordered action names and categories only",
                "mapping_exit_criteria": "Requires opcode-to-action-name evidence or runtime/static proof that a resource action token selects a specific 0x4537f4 slot.",
            },
        ],
        "negative_evidence": [
            "No opcode-to-action-name mapping is proven by resource order alone.",
            "candidate_slot_if_order_matched is a navigation aid, not semantic evidence.",
            "Use handler fingerprints, runtime phase probes, or recovered numeric opcode fields before naming handlers.",
        ],
    }


def _script_catalog_by_action(manifest: dict[str, Any]) -> dict[str, list[dict[str, Any]]]:
    semantics = manifest.get("script_vm_semantics")
    if not isinstance(semantics, dict):
        return {}
    catalog = semantics.get("action_semantics_catalog")
    if not isinstance(catalog, dict):
        return {}
    by_action = catalog.get("by_action")
    if not isinstance(by_action, dict):
        return {}
    result: dict[str, list[dict[str, Any]]] = {}
    for name, entries in by_action.items():
        if isinstance(name, str) and isinstance(entries, list):
            result[name] = [entry for entry in entries if isinstance(entry, dict)]
    return result


def _ordered_action_names(manifest: dict[str, Any]) -> list[str]:
    semantics = manifest.get("script_vm_semantics")
    if not isinstance(semantics, dict):
        return []
    hints = semantics.get("dispatch_correlation_hints")
    if not isinstance(hints, dict):
        return []
    names = hints.get("ordered_unique_action_names")
    return [str(name) for name in names] if isinstance(names, list) else []


def _fingerprint_by_slot(manifest: dict[str, Any]) -> dict[int, dict[str, Any]]:
    fingerprints = build_action_handler_fingerprints(
        manifest.get("dispatch_tables", []),
        manifest.get("body_windows", []),
    )
    by_slot: dict[int, dict[str, Any]] = {}
    for fingerprint in fingerprints:
        for slot in fingerprint.get("slot_numbers", []):
            if isinstance(slot, int):
                by_slot[slot] = fingerprint
    return by_slot


def _resource_ref_compact_summary(resource_refs: Any) -> dict[str, Any]:
    if not isinstance(resource_refs, dict):
        return {}
    summary = resource_refs.get("summary", {})
    summary = summary if isinstance(summary, dict) else {}
    symbolic_refs = resource_refs.get("symbolic_shape_number_refs", [])
    symbolic_refs = symbolic_refs if isinstance(symbolic_refs, list) else []
    unresolved_refs = resource_refs.get("unresolved_shape_refs", [])
    unresolved_refs = unresolved_refs if isinstance(unresolved_refs, list) else []
    return {
        "object_shape_ref_count": summary.get("object_shape_ref_count"),
        "resolved_shape_payload_count": summary.get("resolved_shape_payload_count"),
        "unresolved_shape_ref_count": summary.get("unresolved_shape_ref_count"),
        "shape_number_candidate_kind_counts": summary.get("shape_number_candidate_kind_counts", {}),
        "symbolic_shape_ref_count": len(symbolic_refs),
        "symbolic_shape_refs": [
            {
                "resource_id": str(item.get("resource_id", "")),
                "resource_category": str(item.get("resource_category", "")),
                "process": str(item.get("process", "")),
                "role": str(item.get("role", "")),
                "shape_number": str(item.get("shape_number", "")),
                "object_codes": [str(code) for code in item.get("object_codes", []) if code is not None],
                "match_status": str(item.get("match_status", "")),
            }
            for item in symbolic_refs
            if isinstance(item, dict)
        ],
        "unresolved_shape_ref_count_from_list": len(unresolved_refs),
        "unresolved_shape_refs": [
            {
                "resource_id": str(item.get("resource_id", "")),
                "resource_category": str(item.get("resource_category", "")),
                "signals": [str(signal) for signal in item.get("signals", [])],
                "context_signals": [str(signal) for signal in item.get("context_signals", [])],
                "searched_payload_roots": [str(root) for root in item.get("searched_payload_roots", [])],
                "shape_number_candidates": [str(value) for value in item.get("shape_number_candidates", [])],
                "object_codes": [str(code) for code in item.get("object_codes", []) if code is not None],
            }
            for item in unresolved_refs
            if isinstance(item, dict)
        ],
    }


def build_resource_provenance_static_classification(manifest: dict[str, Any]) -> dict[str, Any]:
    resource_refs = manifest.get("resource_refs")
    summary = resource_refs.get("summary", {}) if isinstance(resource_refs, dict) else {}
    unresolved_refs = resource_refs.get("unresolved_shape_refs", []) if isinstance(resource_refs, dict) else []
    unresolved_list = [item for item in unresolved_refs if isinstance(item, dict)]
    classifications: list[dict[str, Any]] = []
    for item in unresolved_list:
        context = [str(signal) for signal in item.get("context_signals", [])]
        if "obj_process_code:defProcPlayerInstall" in context:
            provenance_class = "missing_in_searched_chapter_roots_player_install_definition"
            next_static_need = "Find EXE player-install traversal/load path for object codes 7..14 before calling these global assets or unused definitions."
        elif "obj_process_code:defProcReturn" in context:
            provenance_class = "missing_in_searched_chapter_roots_return_background_definition"
            next_static_need = "Find defProcReturn or ANIMAL/BG load path before deciding whether BG051.SHP is chapter-local, global-root, or unused."
        else:
            provenance_class = "missing_in_searched_chapter_roots_unknown_owner"
            next_static_need = "Find owner traversal or load call path before assigning runtime collection semantics."
        classifications.append({
            "resource_id": str(item.get("resource_id", "")),
            "resource_ref": str(item.get("resource_ref", "")),
            "resource_category": str(item.get("resource_category", "")),
            "object_codes": [str(code) for code in item.get("object_codes", []) if code is not None],
            "shape_number_candidates": [str(value) for value in item.get("shape_number_candidates", [])],
            "signals": [str(signal) for signal in item.get("signals", [])],
            "context_signals": context,
            "searched_payload_roots": [str(root) for root in item.get("searched_payload_roots", [])],
            "static_provenance_class": provenance_class,
            "runtime_usage_status": "unresolved",
            "global_asset_status": "unresolved",
            "unused_definition_status": "unresolved",
            "missing_archive_root_status": "candidate",
            "evidence_tier": str(item.get("evidence_tier", "resource_ref_only")),
            "next_static_need": next_static_need,
        })
    player_install_count = sum(
        1
        for item in classifications
        if item["static_provenance_class"] == "missing_in_searched_chapter_roots_player_install_definition"
    )
    return {
        "schema": "hsl_static_resource_provenance_classification.v1",
        "evidence_tier": "resource_provenance_static_join",
        "semantic_status": "unresolved",
        "unresolved_shape_ref_count": len(classifications),
        "searched_payload_root_count": len({
            root
            for item in classifications
            for root in item.get("searched_payload_roots", [])
        }),
        "classification_counts": {
            "missing_in_searched_chapter_roots_player_install_definition": player_install_count,
            "missing_in_searched_chapter_roots_return_background_definition": sum(
                1
                for item in classifications
                if item["static_provenance_class"] == "missing_in_searched_chapter_roots_return_background_definition"
            ),
            "missing_in_searched_chapter_roots_unknown_owner": sum(
                1
                for item in classifications
                if item["static_provenance_class"] == "missing_in_searched_chapter_roots_unknown_owner"
            ),
        },
        "color_header_0x10_static_note": {
            "semantic_status": "unresolved",
            "resource_summary_counts": summary.get("color_header_0x10_counts", {}),
            "resource_only_negative_evidence": "Resource-formats reports resolved referenced SHP refs do not show header 0x10 values in pixels; EXE render-path evidence is still needed before naming color-key, flags, palette index, checksum-like, or unused metadata semantics.",
            "next_static_need": "Find SHP header field readers in EXE render/load path and correlate data refs or constants with header offset 0x10 without relying on resource-only evidence.",
        },
        "classifications": classifications,
        "negative_evidence": [
            "OBS references mean unresolved refs cannot be called unused definitions from resource provenance alone.",
            "Three searched payload roots missing by basename supports missing-root/archive candidate, not proof of absent original assets.",
            "No EXE owner traversal path has yet proven these refs are loaded by UI, map, unit, story, or return-background collections.",
        ],
    }


def build_object_shape_handler_candidates(manifest: dict[str, Any]) -> dict[str, Any]:
    fingerprints_by_slot = _fingerprint_by_slot(manifest)
    action_names = _ordered_action_names(manifest)
    catalog_by_action = _script_catalog_by_action(manifest)
    object_helper_calls = {
        "0x44fcf0",
        "0x44fd90",
        "0x44fe40",
        "0x44fed0",
        "0x44ff50",
        "0x450050",
        "0x450140",
        "0x4501f0",
        "0x450450",
    }
    object_context_globals = {"0x4c1d38", "0x4c1d3c", "0x4c1d40", "0x4c1d44", "0x4c1d48", "0x4c1d4c"}
    priority_categories = {"object", "movement", "ui"}
    candidates: list[dict[str, Any]] = []
    for ordinal, action_name in enumerate(action_names):
        entries = catalog_by_action.get(action_name, [])
        categories = sorted({
            str(entry.get("category"))
            for entry in entries
            if entry.get("category")
        })
        candidate_fingerprint = fingerprints_by_slot.get(ordinal)
        if candidate_fingerprint is None:
            continue
        calls = set(candidate_fingerprint.get("call_target_addresses", []))
        data_refs = set(candidate_fingerprint.get("data_ref_addresses", []))
        score = 0
        reasons: list[str] = []
        matched_calls = sorted(calls & object_helper_calls)
        matched_globals = sorted(data_refs & object_context_globals)
        if matched_calls:
            score += 3
            reasons.append("candidate handler calls object/script-object helper")
        if matched_globals:
            score += 2
            reasons.append("candidate handler reads object-context global")
        if priority_categories & set(categories):
            score += 1
            reasons.append("resource catalog category is object/movement/ui")
        if not score:
            continue
        candidates.append({
            "action_name": action_name,
            "resource_order_index": ordinal,
            "catalog_categories": categories,
            "catalog_occurrence_count": len(entries),
            "candidate_slot_if_order_matched": ordinal,
            "candidate_handler_if_order_matched": candidate_fingerprint.get("handler_address"),
            "correlation_status": "unresolved",
            "ordinal_as_slot_status": "not_evidence",
            "score": score,
            "score_reasons": reasons,
            "matched_object_helper_calls": matched_calls,
            "matched_object_context_globals": matched_globals,
            "handler_call_targets": candidate_fingerprint.get("call_target_addresses", []),
            "handler_data_refs": candidate_fingerprint.get("data_ref_addresses", []),
        })
    candidates.sort(key=lambda item: (-int(item["score"]), int(item["resource_order_index"]), str(item["action_name"])))
    resource_refs = manifest.get("resource_refs")
    return {
        "schema": "hsl_static_object_shape_handler_candidates.v1",
        "evidence_tier": "static_ranked_candidates",
        "correlation_status": "unresolved",
        "ranking_inputs": [
            "script-vm action_semantics_catalog categories and resource first-seen order",
            "0x4537f4 action handler compact fingerprints",
            "object helper call target allowlist from 0x450840 body",
            "object-context global refs around 0x4c1d38",
            "resource_refs obj_shape_number summary",
        ],
        "resource_refs_summary": _resource_ref_compact_summary(resource_refs),
        "candidate_count": len(candidates),
        "top_candidates": candidates[:24],
        "negative_evidence": [
            "Resource action order is not proven to equal 0x4537f4 slot number.",
            "Object helper calls are candidate signals, not handler names.",
            "No candidate proves obj_shape_number is a frame index, variant id, or process-specific argument yet.",
            "Missing current imported SHP payloads do not prove global assets are unused or absent from the original install.",
        ],
    }


def _condition_predicate_catalog(manifest: dict[str, Any]) -> dict[str, dict[str, Any]]:
    semantics = manifest.get("script_vm_semantics")
    if not isinstance(semantics, dict):
        return {}
    catalog = semantics.get("condition_predicate_catalog")
    if not isinstance(catalog, dict):
        return {}
    by_action = catalog.get("by_action")
    if not isinstance(by_action, dict):
        return {}
    return {
        str(name): entry
        for name, entry in by_action.items()
        if isinstance(name, str) and isinstance(entry, dict)
    }


def build_condition_predicate_handler_candidates(manifest: dict[str, Any]) -> dict[str, Any] | None:
    predicates = _condition_predicate_catalog(manifest)
    if not predicates:
        return None
    action_names = _ordered_action_names(manifest)
    fingerprints_by_slot = _fingerprint_by_slot(manifest)
    condition_windows_by_handler = {
        str(item.get("handler_address")): item
        for item in build_condition_handler_window_summaries(manifest.get("condition_handler_windows", []))
        if isinstance(item, dict)
    }
    actions: list[dict[str, Any]] = []
    for action_name in sorted(predicates):
        predicate = predicates[action_name]
        ordinal = action_names.index(action_name) if action_name in action_names else None
        fingerprint = fingerprints_by_slot.get(ordinal) if ordinal is not None else None
        handler_address = fingerprint.get("handler_address") if fingerprint else None
        handler_window = condition_windows_by_handler.get(str(handler_address)) if handler_address else None
        actions.append({
            "action_name": action_name,
            "condition_type": str(predicate.get("condition_type", "")),
            "candidate_context_binding": str(predicate.get("candidate_context_binding", "")),
            "args_schema_candidate": [str(item) for item in predicate.get("args_schema_candidate", [])],
            "occurrence_count": int(predicate.get("occurrence_count", 0)),
            "candidate_slot_if_order_matched": ordinal if fingerprint is not None else None,
            "candidate_handler_if_order_matched": handler_address,
            "handler_call_targets_if_order_matched": fingerprint.get("call_target_addresses", []) if fingerprint else [],
            "handler_data_refs_if_order_matched": fingerprint.get("data_ref_addresses", []) if fingerprint else [],
            "handler_op_type_counts_if_order_matched": fingerprint.get("op_type_counts", {}) if fingerprint else {},
            "condition_handler_window_status": handler_window.get("comparison_branch_shape_status") if handler_window else "not_exported",
            "condition_handler_compare_op_count": handler_window.get("compare_op_count_until_first_ret", 0) if handler_window else 0,
            "condition_handler_conditional_jump_count": handler_window.get("conditional_jump_count_until_first_ret", 0) if handler_window else 0,
            "correlation_status": "unresolved",
            "ordinal_as_slot_status": "not_evidence",
            "slot_opcode_evidence_status": "unresolved",
            "comparison_polarity_evidence_status": "unresolved",
            "why_unresolved": "Condition catalog action name is not yet proven to map to a numeric opcode or 0x4537f4 slot.",
        })
    return {
        "schema": "hsl_static_condition_predicate_handler_candidates.v1",
        "evidence_tier": "static_candidate_skeleton",
        "semantic_status": "unresolved",
        "static_script_action_dispatch_table": "0x4537f4",
        "condition_action_count": sum(int(item.get("occurrence_count", 0)) for item in predicates.values()),
        "unique_condition_action_count": len(actions),
        "actions": actions,
        "handler_window_summaries": build_condition_handler_window_summaries(manifest.get("condition_handler_windows", [])),
        "negative_evidence": [
            "No condition action has proven opcode-to-slot evidence yet.",
            "Candidate handler fields use resource order as a navigation aid only.",
            "No comparison operator, threshold polarity, or live-state binding is proven by this static slice.",
        ],
        "next_static_need": "Inspect candidate 0x4537f4 handler windows and recover argument loads/comparison branches without exporting decoded instruction text.",
    }


def build_player_control_action_menu_context() -> dict[str, Any]:
    return {
        "schema": "hsl_static_player_control_action_menu_context.v1",
        "evidence_tier": "static_context_only",
        "interpretation_status": "runtime_transition_unproven",
        "phase_ids_for_runtime_probe": [
            "player_control",
            "action_menu",
            "confirm_down",
            "confirm_up",
            "cancel_down",
            "cancel_up",
            "click_down",
            "click_up",
            "camera_scroll",
        ],
        "static_flow": [
            {
                "step": "input_aggregate",
                "address": "0x415910",
                "known_window": "input_aggregator_candidate",
                "tracked_scalars": ["0x4c6390", "0x4c6398", "0x4c1a88", "0x4c1a8c", "0x4c1a90"],
                "why_next": "Correlate held/edge input, button bits, and logical cursor coordinates before action menu opens.",
            },
            {
                "step": "menu_state_loop",
                "address": "0x42d7c0",
                "known_window": "menu_start_state_candidate",
                "tracked_scalars": ["0x4c1ac8", "0x4c1b98", "0x4c1b9c", "0x4c1bb8"],
                "why_next": "Separate title/start-like menu state from battle action menu without assuming shared semantics.",
            },
            {
                "step": "logical_ui_hit_test",
                "address": "0x445977",
                "known_window": "logical_ui_hit_test_candidate",
                "tracked_scalars": ["0x4c1a8c", "0x4c1a90", "0x4c6390", "0x4c6398"],
                "why_next": "Explain action-menu hover/click via logical-coordinate object hit-test before direct Godot click mapping.",
            },
            {
                "step": "script_bridge_entry",
                "address": "0x450840",
                "known_window": "script_interpreter_bridge_candidate",
                "tracked_tables": ["0x453708", "0x4537f4"],
                "why_next": "Correlate menu/action state with script VM bridge only after phase or caller evidence exists.",
            },
        ],
        "negative_evidence": [
            "This context does not prove that player_control enters 0x450840.",
            "0x42d7c0 is start/menu-like and must not be renamed battle action menu until runtime or stronger static caller evidence proves it.",
            "0x445977 proves logical hit-test behavior, not unit selection semantics by itself.",
        ],
    }


def build_resource_object_static_question_context(manifest: dict[str, Any]) -> dict[str, Any]:
    resource_refs = manifest.get("resource_refs")
    summary = resource_refs.get("summary", {}) if isinstance(resource_refs, dict) else {}
    referenced = resource_refs.get("referenced_resources", []) if isinstance(resource_refs, dict) else []
    unresolved_ids = [
        str(item.get("resource_id"))
        for item in referenced
        if isinstance(item, dict) and item.get("match_status") == "unresolved_missing_payload" and item.get("resource_id")
    ]
    return {
        "schema": "hsl_static_resource_object_question_context.v1",
        "evidence_tier": "static_question_context",
        "interpretation_status": "unresolved",
        "resource_refs_source_file": DEFAULT_RESOURCE_REFS.as_posix(),
        "resource_refs_summary": {
            "object_shape_ref_count": summary.get("object_shape_ref_count"),
            "resolved_shape_payload_count": summary.get("resolved_shape_payload_count"),
            "unresolved_shape_ref_count": summary.get("unresolved_shape_ref_count"),
            "resource_category_counts": summary.get("resource_category_counts", {}),
            "shape_number_candidate_kind_counts": summary.get("shape_number_candidate_kind_counts", {}),
            "unresolved_missing_resource_ids": sorted(unresolved_ids),
        },
        "questions": [
            {
                "id": "obj_shape_number_semantics",
                "question": "Is obj_shape_number an animation/frame index, a shape-table count, or a process-specific argument?",
                "static_anchors": ["0x450840", "0x4c1d38"],
                "current_evidence": "Resource refs group obj_shape_number by process/category, and script bridge fingerprints expose object/action handler addresses and data refs, but no handler is named enough to assign obj_shape_number semantics.",
                "next_static_need": "Find handlers that call SHP/object load or frame-selection routines and compare their slot fingerprints with resource-formats obj_shape_number distributions.",
            },
            {
                "id": "object_owner_traversal_semantics",
                "question": "Does object traversal distinguish UI-only objects, object-list records, unit-selectable actors, and map objects?",
                "static_anchors": ["0x445977", "0x4c1a8c", "0x4c1a90", "0x4c6390", "0x4c6398"],
                "current_evidence": "The logical UI hit-test window walks object-like links and tests cursor/input masks; resource refs distinguish actor_sprite, battle_ui, map_object, magic_effect, and unknown categories, but runtime owner collections remain unresolved.",
                "next_static_need": "Expand callers/owner function around 0x445977 and compare object mask/flag offsets against OBS/EVEF actor and UI resource refs.",
            },
            {
                "id": "actor_sprite_template_or_global_definition",
                "question": "Are actor sprite refs 002-00001..009-00001 player-install templates or unused/global definitions?",
                "static_anchors": ["0x450840", "0x4537f4", "0x4c1d38"],
                "current_evidence": "Resource refs identify unresolved actor/global-looking refs and BG051.SHP missing payloads; current static table fingerprints can identify action handlers and object-context globals, but do not yet bind actor sprite refs to install/template handlers.",
                "next_static_need": "Prioritize action handler fingerprints in object/movement categories and search for handlers with object insertion or shape-loading call targets.",
            },
        ],
        "negative_evidence": [
            "No current static summary proves obj_shape_number frame/count/argument semantics.",
            "No current static summary proves 002-00001..009-00001 are used in first player installation.",
            "Do not collapse UI/object/unit traversal into one Godot concept until owner/caller evidence is stronger.",
        ],
    }


def build_xref_target_summaries(targets: list[dict[str, Any]]) -> list[dict[str, Any]]:
    summaries: list[dict[str, Any]] = []
    for target in targets:
        xrefs = target.get("xrefs", [])
        xref_list = xrefs if isinstance(xrefs, list) else []
        sanitized = _sanitize_xrefs(xref_list)
        type_counts: dict[str, int] = {}
        for item in sanitized:
            xref_type = str(item.get("type", ""))
            type_counts[xref_type] = type_counts.get(xref_type, 0) + 1
        summaries.append({
            "id": str(target.get("id", "")),
            "address": str(target.get("address", "")),
            "label": str(target.get("label", "")),
            "evidence_tier": "static_xref_observed" if sanitized else "static_xref_none_observed",
            "status": str(target.get("status", "unknown")),
            "xref_count": len(sanitized),
            "xref_type_counts": dict(sorted(type_counts.items())),
            "xrefs": sanitized,
            "evidence_sources": [
                str(item)
                for item in target.get("evidence_sources", [])
            ],
            "why_next": str(target.get("why_next", "")),
        })
    return summaries


def build_tracked_static_index(manifest: dict[str, Any]) -> dict[str, Any]:
    commands: list[dict[str, Any]] = manifest.get("commands", [])
    windows: list[dict[str, Any]] = manifest.get("known_windows", [])
    tool_presence = {
        name: bool(path)
        for name, path in manifest.get("tools", {}).items()
    }
    return {
        "schema": "hsl_static_compact_index.v1",
        "source_policy": TRACKED_SOURCE_POLICY,
        "evidence_tier": "static_export_candidate",
        "tool_presence": dict(sorted(tool_presence.items())),
        "export_status_counts": _command_status_counts(commands),
        "export_count_summary": {
            "tool_exports": len(commands),
            "known_windows": len(windows),
            "dispatch_tables": len(manifest.get("dispatch_tables", [])),
            "xref_targets": len(manifest.get("xref_targets", [])),
            "body_windows": len(manifest.get("body_windows", [])),
            "condition_handler_windows": len(manifest.get("condition_handler_windows", [])),
            "shp_render_windows": len(manifest.get("shp_render_windows", [])),
            "status_handler_windows": len(manifest.get("status_handler_windows", [])),
            "ui_owner_windows": len(manifest.get("ui_owner_windows", [])),
            "script_commit_caller_windows": len(manifest.get("script_commit_caller_windows", [])),
            "script_commit_callee_windows": len(manifest.get("script_commit_callee_windows", [])),
            "map_object_static_windows": len(manifest.get("map_object_static_windows", [])),
        },
        "known_windows": [
            {
                "label": str(item.get("label", "")),
                "address": str(item.get("address", "")),
                "byte_count": int(item.get("bytes", 0)),
                "status": str(item.get("status", "unknown")),
            }
            for item in windows
        ],
        "dispatch_table_summaries": build_dispatch_table_summaries(manifest.get("dispatch_tables", [])),
        "xref_target_summaries": build_xref_target_summaries(manifest.get("xref_targets", [])),
        "body_window_summaries": build_body_window_summaries(manifest.get("body_windows", [])),
        "condition_handler_window_summaries": build_condition_handler_window_summaries(
            manifest.get("condition_handler_windows", [])
        ),
        "shp_render_header_static_evidence": build_shp_render_header_static_evidence(manifest),
        "status_lifecycle_handler_candidates": build_status_lifecycle_handler_candidates(manifest),
        "script_status_commit_path_static_context": build_script_status_commit_path_context(manifest),
        "script_numeric_dispatch_token_context": build_script_numeric_dispatch_token_context(manifest),
        "ui_owner_traversal_static_context": build_ui_owner_traversal_static_context(manifest),
        "action_handler_fingerprints": build_action_handler_fingerprints(
            manifest.get("dispatch_tables", []),
            manifest.get("body_windows", []),
        ),
        "script_action_correlation_skeleton": build_script_action_correlation_skeleton(manifest),
        "object_shape_handler_candidates": build_object_shape_handler_candidates(manifest),
        "condition_predicate_handler_candidates": build_condition_predicate_handler_candidates(manifest),
        "player_control_action_menu_static_context": build_player_control_action_menu_context(),
        "resource_object_static_question_context": build_resource_object_static_question_context(manifest),
        "resource_provenance_static_classification": build_resource_provenance_static_classification(manifest),
        "map_object_visibility_static_context": build_map_object_visibility_static_context(manifest),
        "battle_state_target_count": len(DEFAULT_BATTLE_STATE_TARGETS),
        "battle_state_targets": DEFAULT_BATTLE_STATE_TARGETS,
        "unresolved_negative_evidence": [
            str(item)
            for item in manifest.get("unresolved_negative_evidence", [])
        ],
        "semantic_boundary": (
            "static window registration only; this index does not prove runtime globals, "
            "battle action identities, menu semantics, or Godot behavior"
        ),
    }


def write_tracked_static_index(index: dict[str, Any], output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(index, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exe", type=Path, default=DEFAULT_EXE)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    parser.add_argument("--tracked-index-out", type=Path)
    parser.add_argument("--timeout", type=int, default=60)
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    manifest = export_static_evidence(args.exe, args.out_dir, args.timeout, args.dry_run)
    if args.tracked_index_out is not None:
        write_tracked_static_index(build_tracked_static_index(manifest), args.tracked_index_out)
        print(f"wrote tracked static index: {args.tracked_index_out}")
    print(f"wrote static export manifest: {args.out_dir / 'manifest.json'}")
    print(f"commands: {len(manifest['commands'])}, windows: {len(manifest['known_windows'])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
