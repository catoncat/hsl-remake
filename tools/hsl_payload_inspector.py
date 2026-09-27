#!/usr/bin/env python3
"""Inspect local-private HSL first-chapter payloads without exporting text/raw data."""

from __future__ import annotations

import argparse
import collections
import hashlib
import json
import re
import wave
from io import BytesIO
from pathlib import Path
from typing import Any

from hsltools.sources.pak import decoded_xor_a8_wave_bytes, parse_xor_a8_wave_candidate
from hsltools.sources.scripts import EVEF_MAGIC, parse_evef, parse_text_metadata
from hsltools.sources.shp import SHP_MAGIC, parse_shp, read_u32le, write_shp_preview


DEFAULT_OUTPUT_JSON = Path("ignored/payload-inspector/report.json")
DEFAULT_OUTPUT_MARKDOWN = Path("ignored/payload-inspector/report.md")
DEFAULT_PREVIEW_DIR = Path("ignored/payload-inspector/previews")

WORL_MAGIC = b"WORL"


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def parse_worl(data: bytes) -> dict[str, Any]:
    if not data.startswith(WORL_MAGIC):
        raise ValueError("not a WORL payload")
    width = read_u32le(data, 0x0C)
    height = read_u32le(data, 0x10)
    bytes_per_cell = read_u32le(data, 0x14)
    header_size = 0x18
    expected_size = header_size + width * height * bytes_per_cell
    cells = [
        read_u32le(data, header_size + offset)
        for offset in range(0, max(0, len(data) - header_size), 4)
    ]
    low24_values = [cell & 0x00FFFFFF for cell in cells]
    flags = [cell >> 24 for cell in cells]
    flagged_cell_count = sum(1 for flag in flags if flag != 0)
    cell_table = [
        {
            "index": index,
            "x": index % width if width else index,
            "y": index // width if width else 0,
            "raw_value_hex": f"0x{cell:08x}",
            "low24_tile_ref_candidate": cell & 0x00FFFFFF,
            "high8_flag_candidate_hex": f"0x{cell >> 24:02x}",
            "source_kind": "resource-derived",
            "evidence_tier": "resource_parser_candidate",
            "interpretation_status": "unresolved",
        }
        for index, cell in enumerate(cells)
    ]
    flagged_samples = [
        {
            "x": index % width if width else index,
            "y": index // width if width else 0,
            "raw_hex": f"0x{cell:08x}",
            "low24": cell & 0x00FFFFFF,
            "flag_hex": f"0x{cell >> 24:02x}",
        }
        for index, cell in enumerate(cells)
        if cell >> 24
    ][:24]
    return {
        "kind": "worl_grid_binary",
        "magic": "WORL",
        "byte_length": len(data),
        "version_or_count_0x04": read_u32le(data, 0x04),
        "width_candidate_0x0c": width,
        "height_candidate_0x10": height,
        "bytes_per_cell_candidate_0x14": bytes_per_cell,
        "expected_size_from_grid": expected_size,
        "size_matches_grid": expected_size == len(data),
        "cell_count": len(cells),
        "flagged_cell_count": flagged_cell_count,
        "unflagged_cell_count": len(cells) - flagged_cell_count,
        "cell_table": cell_table,
        "unique_cell_values": len(set(cells)),
        "low24_unique_cell_values": len(set(low24_values)),
        "low24_min": min(low24_values) if low24_values else None,
        "low24_max": max(low24_values) if low24_values else None,
        "low24_is_permutation_0_to_cell_count_minus_1": sorted(low24_values)
        == list(range(len(cells))),
        "flag_counts": [
            {"flag_hex": f"0x{flag:02x}", "count": count}
            for flag, count in sorted(collections.Counter(flags).items())
        ],
        "flagged_cell_samples": flagged_samples,
        "sample_rows_low24": [
            low24_values[row_start : row_start + width]
            for row_start in range(0, min(len(low24_values), width * 2), width)
        ],
        "common_cell_values": [
            {"value_hex": f"0x{value:08x}", "count": count}
            for value, count in collections.Counter(cells).most_common(16)
        ],
    }


OPAQUE_WORL_INTEGRITY_SUMMARY_SEMANTICS = (
    "opaque structural WORL integrity summary derived from parser counts only; "
    "raw cell rows, raw cell values, terrain, blockers, and movement costs are not exported or decoded"
)


def nonzero_flag_count_from_flag_counts(flag_counts: list[Any]) -> int | None:
    total = 0
    for item in flag_counts:
        if not isinstance(item, dict):
            return None
        flag_hex = item.get("flag_hex")
        count = item.get("count")
        if not isinstance(flag_hex, str) or not isinstance(count, int) or isinstance(count, bool):
            return None
        try:
            flag_value = int(flag_hex, 16)
        except ValueError:
            return None
        if flag_value != 0:
            total += count
    return total


def build_opaque_worl_integrity(worl: dict[str, Any] | None) -> dict[str, Any]:
    if not worl:
        return {
            "cell_count": None,
            "flagged_cell_count": None,
            "unflagged_cell_count": None,
            "low24_range": {"min": None, "max": None},
            "unique_cell_value_count": None,
            "low24_unique_cell_value_count": None,
            "low24_is_dense_cell_range": None,
            "summary_semantics": OPAQUE_WORL_INTEGRITY_SUMMARY_SEMANTICS,
        }

    cell_count = worl.get("cell_count")
    flagged_cell_count = worl.get("flagged_cell_count")
    if flagged_cell_count is None:
        flagged_cell_count = nonzero_flag_count_from_flag_counts(worl.get("flag_counts", []))
    unflagged_cell_count = worl.get("unflagged_cell_count")
    if unflagged_cell_count is None and isinstance(cell_count, int) and isinstance(flagged_cell_count, int):
        unflagged_cell_count = cell_count - flagged_cell_count

    return {
        "cell_count": cell_count,
        "flagged_cell_count": flagged_cell_count,
        "unflagged_cell_count": unflagged_cell_count,
        "low24_range": {
            "min": worl.get("low24_min"),
            "max": worl.get("low24_max"),
        },
        "unique_cell_value_count": worl.get("unique_cell_values"),
        "low24_unique_cell_value_count": worl.get("low24_unique_cell_values"),
        "low24_is_dense_cell_range": worl.get("low24_is_permutation_0_to_cell_count_minus_1"),
        "summary_semantics": OPAQUE_WORL_INTEGRITY_SUMMARY_SEMANTICS,
    }


def placement_role_for_object(obj: dict[str, Any] | None) -> str:
    if not obj:
        return "unmatched"
    process = str(obj.get("obj_process_code") or "")
    if process == "defProcPlayerInstall":
        return "player_install"
    if process == "defProcEnemy":
        return "enemy"
    if process == "defProcStandObject":
        return "map_object"
    if process in {"defProcBattleBOSS", "defProcIconBG", "defProcCursor", "defProcPlayerReversePos"}:
        return "battle_manager"
    if "Status" in process or "Button" in process or "Bar" in process or "Window" in process:
        return "battle_ui"
    return "other"


def first_payload_matching(report: dict[str, Any], needle: str) -> dict[str, Any] | None:
    needle_lower = needle.lower()
    for item in report.get("payloads", []):
        if needle_lower in str(item.get("path", "")).lower():
            return item
    return None


def placement_aggregates(placements: list[dict[str, Any]]) -> dict[str, Any]:
    role_counts = collections.Counter(str(item.get("role", "unknown")) for item in placements)
    process_counts = collections.Counter(str(item.get("process", "unknown")) for item in placements)
    object_code_counts = collections.Counter(str(item.get("object_code", "unknown")) for item in placements)
    shape_counts = collections.Counter(
        logical_source_id(str(item.get("shape"))) if item.get("shape") else "unknown"
        for item in placements
    )
    by_role: dict[str, dict[str, dict[str, int]]] = {}
    for role in sorted(role_counts):
        role_items = [item for item in placements if str(item.get("role", "unknown")) == role]
        by_role[role] = {
            "object_code_counts": dict(
                sorted(collections.Counter(str(item.get("object_code", "unknown")) for item in role_items).items())
            ),
            "process_counts": dict(
                sorted(collections.Counter(str(item.get("process", "unknown")) for item in role_items).items())
            ),
            "shape_id_counts": dict(
                sorted(
                    collections.Counter(
                        logical_source_id(str(item.get("shape"))) if item.get("shape") else "unknown"
                        for item in role_items
                    ).items()
                )
            ),
        }
    return {
        "summary_semantics": "counts derived from EVEF object-code joins only; coordinates, stats, terrain, and formulas remain unresolved",
        "role_counts": dict(sorted(role_counts.items())),
        "object_code_counts": dict(sorted(object_code_counts.items())),
        "process_counts": dict(sorted(process_counts.items())),
        "shape_id_counts": dict(sorted(shape_counts.items())),
        "by_role": by_role,
    }


STATUS_ACTION_CONTRACT_SOURCE_SEMANTICS = (
    "action-count contract derived only from STORY051.TXT action_counts and "
    "winfail051.txt action_counts/section_counts; not original status ids, "
    "action args, chains, or script order"
)

STATUS_LIFECYCLE_SUMMARY_SEMANTICS = (
    "count-only lifecycle summary derived from status_action_contract; "
    "not original status ids, action args, chains, or script order"
)

PLACEMENT_JOIN_INTEGRITY_SEMANTICS = (
    "count-only EVEF/object join coverage summary; object names, raw object fields, "
    "coordinates, stats, terrain, AI, and formulas remain unresolved"
)


def int_count(counts: dict[str, Any], key: str) -> int:
    value = counts.get(key, 0)
    return value if isinstance(value, int) and not isinstance(value, bool) else 0


def safe_int(value: Any) -> int:
    return value if isinstance(value, int) and not isinstance(value, bool) else 0


def build_placement_join_integrity(
    evef: dict[str, Any] | None,
    obj_051: dict[str, Any] | None,
    placements: list[dict[str, Any]],
    aggregates: dict[str, Any],
) -> dict[str, Any]:
    non_zero_record_count = safe_int(evef.get("non_zero_record_count") if evef else 0)
    joined_record_count = sum(1 for item in placements if item.get("role") != "unmatched")
    unmatched_record_count = max(0, non_zero_record_count - joined_record_count)
    object_code_counts = aggregates.get("object_code_counts", {}) if isinstance(aggregates, dict) else {}
    role_counts = aggregates.get("role_counts", {}) if isinstance(aggregates, dict) else {}
    return {
        "summary_semantics": PLACEMENT_JOIN_INTEGRITY_SEMANTICS,
        "evef_record_count": evef.get("record_count") if evef else None,
        "non_zero_record_count": non_zero_record_count,
        "joined_record_count": joined_record_count,
        "unmatched_record_count": unmatched_record_count,
        "placed_object_code_count": len(object_code_counts) if isinstance(object_code_counts, dict) else 0,
        "object_record_count": obj_051.get("object_count") if obj_051 else None,
        "role_coverage_counts": role_counts if isinstance(role_counts, dict) else {},
    }


def build_status_action_contract(script_summary: dict[str, Any]) -> dict[str, Any]:
    story = script_summary.get("story051", {}) if isinstance(script_summary, dict) else {}
    winfail = script_summary.get("winfail051", {}) if isinstance(script_summary, dict) else {}
    story_actions = story.get("action_counts", {}) if isinstance(story, dict) else {}
    winfail_actions = winfail.get("action_counts", {}) if isinstance(winfail, dict) else {}
    winfail_sections = winfail.get("section_counts", {}) if isinstance(winfail, dict) else {}
    if not isinstance(story_actions, dict):
        story_actions = {}
    if not isinstance(winfail_actions, dict):
        winfail_actions = {}
    if not isinstance(winfail_sections, dict):
        winfail_sections = {}

    return {
        "fail_status_count": int_count(story_actions, "actInsertFailStatus"),
        "event_status_insert_count": int_count(story_actions, "actInsertEventStatus")
        + int_count(winfail_actions, "actInsertEventStatus"),
        "event_status_delete_count": int_count(winfail_actions, "actDeleteEventStatus"),
        "win_status_count": int_count(winfail_actions, "actInsertWinStatus"),
        "round_check_count": int_count(winfail_actions, "actCheckRoundNumber"),
        "enemy_total_check_count": int_count(winfail_actions, "actCheckEnemyTotalNumber"),
        "enemy_number_check_count": int_count(winfail_actions, "actCheckEnemyNumber"),
        "arrival_check_count": int_count(winfail_actions, "actCheckPlayerArrivePos"),
        "source_semantics": STATUS_ACTION_CONTRACT_SOURCE_SEMANTICS,
    }


def build_status_lifecycle_summary(
    script_summary: dict[str, Any],
    status_action_contract: dict[str, Any] | None = None,
) -> dict[str, Any]:
    contract = status_action_contract or build_status_action_contract(script_summary)
    story = script_summary.get("story051", {}) if isinstance(script_summary, dict) else {}
    winfail = script_summary.get("winfail051", {}) if isinstance(script_summary, dict) else {}
    story_actions = story.get("action_counts", {}) if isinstance(story, dict) else {}
    winfail_actions = winfail.get("action_counts", {}) if isinstance(winfail, dict) else {}
    if not isinstance(story_actions, dict):
        story_actions = {}
    if not isinstance(winfail_actions, dict):
        winfail_actions = {}

    event_insert_count = int_count(contract, "event_status_insert_count")
    event_delete_count = int_count(contract, "event_status_delete_count")
    return {
        "summary_semantics": STATUS_LIFECYCLE_SUMMARY_SEMANTICS,
        "fail": {"insert_count": int_count(contract, "fail_status_count")},
        "event": {
            "insert_count": event_insert_count,
            "delete_count": event_delete_count,
            "net_enabled_candidate": event_insert_count - event_delete_count,
        },
        "win": {"insert_count": int_count(contract, "win_status_count")},
        "checks": {
            "round": int_count(contract, "round_check_count"),
            "enemy_total": int_count(contract, "enemy_total_check_count"),
            "enemy_number": int_count(contract, "enemy_number_check_count"),
            "arrival": int_count(contract, "arrival_check_count"),
        },
        "show_status_count": int_count(story_actions, "actShowWinFailStatus")
        + int_count(winfail_actions, "actShowWinFailStatus"),
    }


def build_first_battle_mechanics_fixture(report: dict[str, Any]) -> dict[str, Any]:
    obj_051 = first_payload_matching(report, "obj-051.obs")
    worl = first_payload_matching(report, "level051.wrd")
    evef = first_payload_matching(report, "level051.bin")
    story = first_payload_matching(report, "STORY051.TXT")
    winfail = first_payload_matching(report, "winfail051.txt")
    obj_header = first_payload_matching(report, "obj-051.h")

    object_lookup = {
        str(obj.get("obj_code")): obj
        for obj in (obj_051 or {}).get("objects", [])
        if obj.get("obj_code") is not None
    }

    placements: list[dict[str, Any]] = []
    for record in (evef or {}).get("record_summaries", []):
        code = record.get("field_0x04_code_candidate")
        if code is None:
            continue
        obj = object_lookup.get(str(code))
        placement = {
            "record_index": record.get("index"),
            "object_code": code,
            "object_name": obj.get("obj_name") if obj else None,
            "role": placement_role_for_object(obj),
            "process": obj.get("obj_process_code") if obj else None,
            "shape": obj.get("obj_shape_name") if obj else None,
            "shape_number": obj.get("obj_shape_number") if obj else None,
            "placement_x_candidate": record.get("placement_x_candidate_0x08"),
            "placement_y_candidate": record.get("placement_y_candidate_0x0c"),
            "coordinate_semantics": "placement coordinates candidate; not yet proven as grid cells",
        }
        placements.append(placement)

    aggregates = placement_aggregates(placements)

    script_summary = {
        "story051": {
            "source_path": story.get("path") if story else None,
            "section_counts": story.get("section_counts") if story else {},
            "action_counts": story.get("action_counts") if story else {},
        },
        "winfail051": {
            "source_path": winfail.get("path") if winfail else None,
            "section_counts": winfail.get("section_counts") if winfail else {},
            "action_counts": winfail.get("action_counts") if winfail else {},
            "sections": winfail.get("section_blocks", []) if winfail else [],
        },
    }

    status_action_contract = build_status_action_contract(script_summary)

    return {
        "source_policy": "compact mechanics metadata only; original payload text, maps, sprites, audio, and dialogue are not exported",
        "map_grid": {
            "source_path": worl.get("path") if worl else None,
            "dimensions": {
                "width": worl.get("width_candidate_0x0c") if worl else None,
                "height": worl.get("height_candidate_0x10") if worl else None,
            },
            "bytes_per_cell": worl.get("bytes_per_cell_candidate_0x14") if worl else None,
            "size_matches_grid": worl.get("size_matches_grid") if worl else None,
            "opaque_integrity": build_opaque_worl_integrity(worl),
            "semantics": "24x24 cell table confirmed; high-byte flags and low24 tile/cell values unresolved",
        },
        "evef": {
            "source_path": evef.get("path") if evef else None,
            "record_count": evef.get("record_count") if evef else None,
            "non_zero_record_count": evef.get("non_zero_record_count") if evef else None,
            "record_code_counts": evef.get("record_code_counts") if evef else {},
            "record_layout": "EVEF header 0x10 + fixed 0xd0 records; field 0x04 joins obj-051.obs obj_code for level051.bin",
        },
        "object_records": {
            "source_path": obj_051.get("path") if obj_051 else None,
            "object_count": obj_051.get("object_count") if obj_051 else None,
            "resource_ref_count": len(obj_051.get("resource_refs", [])) if obj_051 else 0,
            "story_define_values": obj_header.get("define_values", {}) if obj_header else {},
        },
        "initial_placements": placements,
        "placement_role_counts": aggregates["role_counts"],
        "placement_aggregates": aggregates,
        "placement_join_integrity": build_placement_join_integrity(evef, obj_051, placements, aggregates),
        "scripts": script_summary,
        "status_action_contract": status_action_contract,
        "status_lifecycle_summary": build_status_lifecycle_summary(
            script_summary,
            status_action_contract,
        ),
    }


def logical_source_id(source_path: str | None) -> str | None:
    if not source_path:
        return None
    return Path(source_path.replace("\\", "/")).name


def build_chapter01_generated_metadata(report: dict[str, Any]) -> dict[str, Any]:
    mechanics = build_first_battle_mechanics_fixture(report)
    return {
        "schema": "hsl_chapter01_generated_metadata.v1",
        "source_policy": "tracked compact metadata only; original payload text, images, audio, raw bytes, full hashes, and screenshots are not exported",
        "evidence_tier": "resource_parser_candidate",
        "unresolved_semantics": [
            "WORL terrain and movement-cost semantics are not decoded",
            "EVEF placement coordinates are candidates, not proven Godot grid cells",
            "script action names are summarized as counts only, not exported as source text",
        ],
        "map_grid": {
            "source_id": logical_source_id(mechanics["map_grid"].get("source_path")),
            "dimensions": mechanics["map_grid"].get("dimensions"),
            "bytes_per_cell": mechanics["map_grid"].get("bytes_per_cell"),
            "size_matches_grid": mechanics["map_grid"].get("size_matches_grid"),
            "opaque_integrity": mechanics["map_grid"].get("opaque_integrity"),
            "semantics": mechanics["map_grid"].get("semantics"),
        },
        "evef": {
            "source_id": logical_source_id(mechanics["evef"].get("source_path")),
            "record_count": mechanics["evef"].get("record_count"),
            "non_zero_record_count": mechanics["evef"].get("non_zero_record_count"),
            "record_code_counts": mechanics["evef"].get("record_code_counts", {}),
            "record_layout": mechanics["evef"].get("record_layout"),
        },
        "object_records": {
            "source_id": logical_source_id(mechanics["object_records"].get("source_path")),
            "object_count": mechanics["object_records"].get("object_count"),
            "resource_ref_count": mechanics["object_records"].get("resource_ref_count"),
        },
        "initial_placements": [
            {
                "record_index": item.get("record_index"),
                "object_code": item.get("object_code"),
                "role": item.get("role"),
                "process": item.get("process"),
                "shape_id": logical_source_id(str(item.get("shape"))) if item.get("shape") else None,
                "placement_x_candidate": item.get("placement_x_candidate"),
                "placement_y_candidate": item.get("placement_y_candidate"),
                "coordinate_semantics": item.get("coordinate_semantics"),
            }
            for item in mechanics.get("initial_placements", [])
        ],
        "placement_role_counts": mechanics.get("placement_role_counts", {}),
        "placement_aggregates": mechanics.get("placement_aggregates", {}),
        "placement_join_integrity": mechanics.get("placement_join_integrity", {}),
        "script_summary": {
            "story051": {
                "source_id": logical_source_id(mechanics["scripts"]["story051"].get("source_path")),
                "section_counts": mechanics["scripts"]["story051"].get("section_counts", {}),
                "action_counts": mechanics["scripts"]["story051"].get("action_counts", {}),
            },
            "winfail051": {
                "source_id": logical_source_id(mechanics["scripts"]["winfail051"].get("source_path")),
                "section_counts": mechanics["scripts"]["winfail051"].get("section_counts", {}),
                "action_counts": mechanics["scripts"]["winfail051"].get("action_counts", {}),
            },
        },
        "status_action_contract": mechanics.get("status_action_contract", {}),
        "status_lifecycle_summary": mechanics.get("status_lifecycle_summary", {}),
    }


def write_chapter01_generated_metadata(report: dict[str, Any], output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    generated = build_chapter01_generated_metadata(report)
    write_json_report(
        generated,
        output_dir / "mechanics.json",
    )
    write_json_report(
        {
            "schema": "hsl_chapter01_map_grid.v1",
            "source_policy": generated["source_policy"],
            "evidence_tier": generated["evidence_tier"],
            "map_grid": generated["map_grid"],
        },
        output_dir / "map_grid.json",
    )
    write_json_report(
        {
            "schema": "hsl_chapter01_initial_placements.v1",
            "source_policy": generated["source_policy"],
            "evidence_tier": generated["evidence_tier"],
            "unresolved_semantics": [
                item
                for item in generated["unresolved_semantics"]
                if "placement" in item.lower() or "coordinate" in item.lower()
            ],
            "placement_role_counts": generated["placement_role_counts"],
            "placement_aggregates": generated["placement_aggregates"],
            "placement_join_integrity": generated["placement_join_integrity"],
            "initial_placements": generated["initial_placements"],
        },
        output_dir / "initial_placements.json",
    )
    write_json_report(
        {
            "schema": "hsl_chapter01_script_summary.v1",
            "source_policy": generated["source_policy"],
            "evidence_tier": generated["evidence_tier"],
            "script_summary": generated["script_summary"],
            "status_action_contract": generated["status_action_contract"],
            "status_lifecycle_summary": generated["status_lifecycle_summary"],
        },
        output_dir / "script_summary.json",
    )
    write_json_report(
        {
            "schema": "hsl_chapter01_generated_index.v1",
            "source_policy": generated["source_policy"],
            "files": {
                "mechanics": "mechanics.json",
                "map_grid": "map_grid.json",
                "initial_placements": "initial_placements.json",
                "script_summary": "script_summary.json",
            },
        },
        output_dir / "index.json",
    )


def imported_script_section(block: dict[str, Any]) -> dict[str, Any]:
    actions = []
    for action_index, action in enumerate(block.get("actions", [])):
        chain = action.get("chain", []) if isinstance(action, dict) else []
        primary = action.get("primary") if isinstance(action, dict) else None
        if primary is None and chain and isinstance(chain[0], dict):
            primary = chain[0].get("name")
        actions.append(
            {
                "index": action_index,
                "primary": primary,
                "name": primary,
                "chain": [
                    {
                        "name": item.get("name"),
                        "args": item.get("args", []),
                    }
                    for item in chain
                    if isinstance(item, dict)
                ],
            }
        )
    messages = block.get("messages", [])
    return {
        "index": block.get("index"),
        "type": block.get("name"),
        "name": block.get("name"),
        "evidence_tier": "resource-derived",
        "codes": block.get("codes", []),
        "messages": messages,
        "message_ids": [
            token.strip()
            for message in messages
            if isinstance(message, str)
            for token in message.split(",")
            if token.strip()
        ],
        "actions": actions,
        "unresolved_semantics": [
            "section code meaning and trigger binding are not fully decoded",
            "action args preserve original script tokens but are not all mapped to engine semantics",
        ],
    }


def flatten_imported_script_actions(script_id: str, source_file: str, sections: list[dict[str, Any]]) -> list[dict[str, Any]]:
    flattened: list[dict[str, Any]] = []
    for section in sections:
        section_index = section.get("index")
        section_name = section.get("name")
        for action in section.get("actions", []):
            if not isinstance(action, dict):
                continue
            action_index = action.get("index")
            primary = action.get("primary")
            for chain_index, chain_item in enumerate(action.get("chain", [])):
                if not isinstance(chain_item, dict):
                    continue
                flattened.append(
                    {
                        "index": len(flattened),
                        "script_id": script_id,
                        "source_file": source_file,
                        "section_index": section_index,
                        "section_name": section_name,
                        "section_type": section.get("type"),
                        "section_codes": section.get("codes", []),
                        "action_index": action_index,
                        "chain_index": chain_index,
                        "primary": primary,
                        "name": chain_item.get("name"),
                        "args": chain_item.get("args", []),
                        "evidence_tier": "resource-derived",
                        "unresolved_semantics": [
                            "dry-run action record preserves original order and args; handler behavior is not fully mapped",
                        ],
                    }
                )
    return flattened


def build_imported_script_ir_document(
    report: dict[str, Any],
    script_id: str,
    source_name: str,
) -> dict[str, Any]:
    payload = first_payload_matching(report, source_name)
    sections = []
    if payload:
        sections = [
            imported_script_section(block)
            for block in payload.get("section_blocks", [])
            if isinstance(block, dict)
        ]
    action_chain = flatten_imported_script_actions(script_id, source_name, sections)
    return {
        "schema": "hsl_chapter01_script_ir.v1",
        "id": script_id,
        "source_file": source_name,
        "source_id": logical_source_id(payload.get("path")) if payload else source_name,
        "source_policy": "private reverse-engineering script IR; preserves original section order, action order, nested action chains, args, message ids, resource refs, and includes for Godot reimplementation",
        "evidence_tier": "resource-derived",
        "encoding": payload.get("encoding") if payload else None,
        "includes": payload.get("includes", []) if payload else [],
        "resource_refs": payload.get("resource_refs", []) if payload else [],
        "define_values": payload.get("define_values", {}) if payload else {},
        "section_counts": payload.get("section_counts", {}) if payload else {},
        "action_counts": payload.get("action_counts", {}) if payload else {},
        "action_line_count": sum(len(section.get("actions", [])) for section in sections),
        "action_chain_count": len(action_chain),
        "sections": sections,
        "action_chain": action_chain,
        "interpreter_status": "dry_run_ir_only",
        "unresolved_semantics": [
            "script action handlers are not fully mapped to engine functions",
            "status ids, object ids, coordinates, and timing args remain resource-derived tokens until static/runtime evidence maps them",
        ],
    }


def build_chapter01_script_ir(report: dict[str, Any]) -> dict[str, Any]:
    scripts = [
        build_imported_script_ir_document(report, "story051", "STORY051.TXT"),
        build_imported_script_ir_document(report, "winfail051", "winfail051.txt"),
    ]
    return {
        "schema": "hsl_chapter01_script_ir_index.v1",
        "source_policy": "private reverse-engineering script IR index; per-script files preserve original action order and args for Godot reimplementation",
        "evidence_tier": "resource-derived",
        "scripts": [
            {
                "id": script["id"],
                "file": f"scripts/{script['id']}.json",
                "path": f"res://content/imported/hsl/chapter01/scripts/{script['id']}.json",
                "source_file": script["source_file"],
                "source_id": script["source_id"],
                "section_count": len(script["sections"]),
                "action_line_count": script["action_line_count"],
                "action_chain_count": script["action_chain_count"],
                "evidence_tier": script["evidence_tier"],
            }
            for script in scripts
        ],
        "total_action_line_count": sum(script["action_line_count"] for script in scripts),
        "total_action_chain_count": sum(script["action_chain_count"] for script in scripts),
        "unresolved_semantics": [
            "index points at per-script dry-run IR files; action handler semantics remain partially unresolved",
        ],
    }


def write_chapter01_imported_script_ir(report: dict[str, Any], output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    scripts_dir = output_dir / "scripts"
    scripts_dir.mkdir(parents=True, exist_ok=True)
    for script_id, source_name in (("story051", "STORY051.TXT"), ("winfail051", "winfail051.txt")):
        write_json_report(
            build_imported_script_ir_document(report, script_id, source_name),
            scripts_dir / f"{script_id}.json",
        )
    write_json_report(build_chapter01_script_ir(report), output_dir / "script_ir_index.json")


def ir_scalar(
    value: Any,
    *,
    source_kind: str = "resource-derived",
    evidence_tier: str = "resource_parser_candidate",
    interpretation_status: str = "provisional",
    field_name: str | None = None,
    field_offset: int | None = None,
    semantics: str | None = None,
) -> dict[str, Any]:
    result = {
        "value": value,
        "source_kind": source_kind,
        "evidence_tier": evidence_tier,
        "interpretation_status": interpretation_status,
    }
    if field_name is not None:
        result["field_name"] = field_name
    if field_offset is not None:
        result["field_offset_hex"] = f"0x{field_offset:02x}"
    if semantics is not None:
        result["semantics"] = semantics
    return result


def imported_object_fields(obj: dict[str, Any] | None) -> dict[str, Any]:
    if not obj:
        return {}
    fields: dict[str, Any] = {}
    named_fields = {
        "obj_code": "object definition code joined from EVEF record field 0x04",
        "obj_name": "original object definition name",
        "obj_plane": "object plane/layer candidate",
        "obj_shape_name": "shape resource reference",
        "obj_shape_number": "shape frame/index candidate",
        "obj_process_code": "symbolic process/behavior function reference",
    }
    for key, semantics in named_fields.items():
        if key in obj:
            fields[key] = ir_scalar(
                obj.get(key),
                field_name=key,
                semantics=semantics,
                interpretation_status="resource-derived",
            )
    for key, value in sorted((obj.get("obj_data_fields") or {}).items()):
        fields[key] = ir_scalar(
            value,
            field_name=key,
            semantics="original object data/collision/mode field; gameplay meaning unresolved",
            interpretation_status="unresolved",
        )
    return fields


def imported_evef_record_fields(record: dict[str, Any]) -> dict[str, Any]:
    fields = {
        "field_0x04_code_candidate": ir_scalar(
            record.get("field_0x04_code_candidate"),
            field_offset=0x04,
            semantics="candidate object code; joins obj-051.obs obj_code",
        ),
        "placement_x_candidate_0x08": ir_scalar(
            record.get("placement_x_candidate_0x08"),
            field_offset=0x08,
            semantics="placement x coordinate candidate; coordinate system unresolved",
        ),
        "placement_y_candidate_0x0c": ir_scalar(
            record.get("placement_y_candidate_0x0c"),
            field_offset=0x0C,
            semantics="placement y coordinate candidate; coordinate system unresolved",
        ),
    }
    for word in record.get("non_zero_u32", []):
        if not isinstance(word, dict):
            continue
        offset = word.get("field_offset")
        if not isinstance(offset, int) or offset in {0x04, 0x08, 0x0C}:
            continue
        fields[f"u32_0x{offset:02x}"] = ir_scalar(
            word.get("value"),
            field_offset=offset,
            semantics="non-zero EVEF u32 field; semantic unresolved",
            interpretation_status="unresolved",
        )
    return fields


def source_relpath(path_value: str | None) -> str | None:
    if not path_value:
        return None
    parts = Path(path_value.replace("\\", "/")).parts
    if "drive_at" in parts:
        index = parts.index("drive_at")
        return "/".join(parts[index + 1 :])
    return Path(path_value.replace("\\", "/")).name


def archive_relpath(path_value: str | None) -> str | None:
    if not path_value:
        return None
    parts = Path(path_value.replace("\\", "/")).parts
    if "hsl" in parts:
        index = parts.index("hsl")
        return "/".join(parts[index:])
    return Path(path_value.replace("\\", "/")).name


def derived_root(path_value: str | None) -> str | None:
    if not path_value:
        return None
    parts = Path(path_value.replace("\\", "/")).parts
    if "hsl" in parts:
        index = parts.index("hsl")
        if index > 0:
            return "/".join(parts[:index])
    return None


def payload_provenance(payload: dict[str, Any] | None) -> dict[str, Any] | None:
    if not payload:
        return None
    path = payload.get("path")
    return {
        "source_path": path,
        "derived_root": derived_root(path),
        "archive_relpath": archive_relpath(path),
        "drive_relpath": source_relpath(path),
        "basename_match_key": resource_ref_key(path),
        "evidence_tier": "resource_imported",
    }


def resource_ref_key(value: str | None) -> str | None:
    if not value:
        return None
    return Path(str(value).replace("\\", "/")).name.lower()


def object_resource_ref_records(obj_051: dict[str, Any] | None) -> dict[str, list[dict[str, Any]]]:
    records: dict[str, list[dict[str, Any]]] = collections.defaultdict(list)
    for obj in (obj_051 or {}).get("objects", []):
        if not isinstance(obj, dict):
            continue
        key = resource_ref_key(obj.get("obj_shape_name"))
        if key is None:
            continue
        records[key].append(
            {
                "object_code": str(obj.get("obj_code")) if obj.get("obj_code") is not None else None,
                "object_name": obj.get("obj_name"),
                "role": placement_role_for_object(obj),
                "process": obj.get("obj_process_code"),
                "shape_number": obj.get("obj_shape_number"),
                "resource_ref": obj.get("obj_shape_name"),
            }
        )
    return records


def classify_shape_resource(
    ref: str,
    payload: dict[str, Any] | None,
    object_records: list[dict[str, Any]],
    placements: list[dict[str, Any]],
) -> dict[str, Any]:
    signals: list[str] = []
    roles = {str(item.get("role")) for item in object_records + placements if item.get("role")}
    processes = {str(item.get("process")) for item in object_records + placements if item.get("process")}
    basename = str(logical_source_id(ref) or "").lower()
    relpath = source_relpath(payload.get("path")) if payload else None
    relpath_lower = str(relpath or ref).replace("\\", "/").lower()

    if "player_install" in roles or "enemy" in roles or "defProcPlayerInstall" in processes or "defProcEnemy" in processes:
        if "player_install" in roles:
            signals.append("role:player_install")
        if "enemy" in roles:
            signals.append("role:enemy")
        for process in sorted(processes & {"defProcPlayerInstall", "defProcEnemy"}):
            signals.append(f"obj_process_code:{process}")
        category = "actor_sprite"
        tier = "resource_imported"
    elif "magic/" in relpath_lower or str(ref).replace("\\", "/").lower().startswith("magic/"):
        signals.append("source_relpath:magic")
        category = "magic_effect"
        tier = "resource_imported" if payload else "resource_ref_only"
    elif (
        "battle_manager" in roles
        or any(process in {"defProcBattleBOSS", "defProcCursor", "defProcIconBG"} for process in processes)
        or basename.startswith(("cursor", "i_rect", "bcmd", "b_cmd", "window", "icon", "board", "bt_", "b_", "stat", "num", "kill_", "win"))
        or basename in {"barh1_01.shp", "bar_hp1.shp", "bar_st1.shp", "bar_blk1.shp", "bar_blk3.shp"}
    ):
        if "battle_manager" in roles:
            signals.append("role:battle_manager")
        for process in sorted(processes & {"defProcBattleBOSS", "defProcCursor", "defProcIconBG"}):
            signals.append(f"obj_process_code:{process}")
        if basename:
            signals.append(f"basename:{basename}")
        category = "battle_ui"
        tier = "resource_imported" if payload or signals else "resource_ref_only"
    elif "map_object" in roles or "defProcStandObject" in processes or "shape01/" in relpath_lower:
        if "map_object" in roles:
            signals.append("role:map_object")
        if "defProcStandObject" in processes:
            signals.append("obj_process_code:defProcStandObject")
        if "shape01/" in relpath_lower:
            signals.append("source_relpath:shape01")
        category = "map_object"
        tier = "resource_imported" if payload or signals else "resource_ref_only"
    else:
        category = "unknown"
        tier = "resource_ref_only"

    return {
        "category": category,
        "evidence": {
            "evidence_tier": tier,
            "signals": sorted(set(signals)),
            "unresolved_semantics": [
                "category is an evidence-tiered resource-import hint, not proof of runtime owner or animation state",
                "shape_number candidates are preserved separately and are not interpreted as frames here",
            ],
        },
    }


def shape_number_candidate_kind(value: Any) -> str:
    if value is None or str(value) == "":
        return "missing"
    text = str(value)
    if text.isdigit():
        return "numeric_literal"
    return "symbolic_or_expression"


def shape_number_evidence_table(
    resource_category: str,
    object_records: list[dict[str, Any]],
    placements: list[dict[str, Any]],
) -> dict[str, Any]:
    grouped: dict[tuple[str, str, str], dict[str, Any]] = {}
    for item, source in [(item, "object") for item in object_records] + [(item, "placement") for item in placements]:
        shape_number = item.get("shape_number")
        key = (
            str(item.get("process") or "unknown"),
            str(item.get("role") or "unknown"),
            str(shape_number) if shape_number is not None else "",
        )
        group = grouped.setdefault(
            key,
            {
                "resource_category": resource_category,
                "process": key[0],
                "role": key[1],
                "shape_number": key[2],
                "object_codes": set(),
                "object_definition_count": 0,
                "placed_instance_count": 0,
                "candidate_kind": shape_number_candidate_kind(shape_number),
                "evidence_tier": "resource_ref_join",
                "unresolved_semantics": [
                    "obj_shape_number value is grouped with process/resource usage but not interpreted as an animation frame",
                ],
            },
        )
        if item.get("object_code") is not None:
            group["object_codes"].add(str(item.get("object_code")))
        if source == "object":
            group["object_definition_count"] += 1
        else:
            group["placed_instance_count"] += 1

    groups = []
    for group in grouped.values():
        finalized = dict(group)
        finalized["object_codes"] = sorted(group["object_codes"])
        groups.append(finalized)
    groups.sort(
        key=lambda item: (
            item["resource_category"],
            item["process"],
            item["role"],
            item["shape_number"],
            ",".join(item["object_codes"]),
        )
    )
    return {
        "semantic_status": "unresolved",
        "evidence_tier": "resource_ref_join",
        "candidate_kind_counts": dict(sorted(collections.Counter(item["candidate_kind"] for item in groups).items())),
        "groups": groups,
        "static_verification_questions": [
            "Does the EXE read obj_shape_number as a SHP frame/image index, a resource variant id, or another object field?",
            "Which owner traversal consumes this object ref: UI object list, map object list, unit selectable list, or another runtime collection?",
        ],
        "unresolved_semantics": [
            "obj_shape_number is joined from obj-051.obs object definitions and level051.bin placements only",
            "No animation frame, direction set, palette, or owner traversal semantics are asserted from this table",
        ],
    }


def resource_resolution_evidence(
    payload: dict[str, Any] | None,
    resource_category: str,
    object_records: list[dict[str, Any]],
    placements: list[dict[str, Any]],
    searched_payload_roots: list[str],
) -> dict[str, Any]:
    signals = ["matched_shp_payload_by_basename"] if payload else ["not_found_in_current_imported_shp_payloads_by_basename"]
    context_signals: list[str] = []
    roles = {str(item.get("role")) for item in object_records + placements if item.get("role")}
    processes = {str(item.get("process")) for item in object_records + placements if item.get("process")}
    if resource_category == "actor_sprite" and "player_install" in roles and not placements:
        context_signals.append("player_install_object_definition_without_level051_placement")
    if resource_category == "unknown":
        context_signals.append("category_unresolved_from_resource_join")
    for process in sorted(processes):
        context_signals.append(f"obj_process_code:{process}")
    return {
        "evidence_tier": "resource_imported" if payload else "resource_ref_only",
        "signals": signals,
        "payload_provenance": payload_provenance(payload),
        "searched_payload_roots": searched_payload_roots,
        "context_signals": sorted(set(context_signals)),
        "unresolved_semantics": [
            "Payload resolution is a basename join against currently scanned imported SHP payloads",
            "Missing payload refs may require another archive/root, EXE resource lookup evidence, or an unused-template proof",
            "Resolution status does not prove runtime owner traversal, render order, or animation frame semantics",
        ],
    }


def shape_number_object_codes(groups: list[dict[str, Any]]) -> list[str]:
    codes = {
        str(code)
        for group in groups
        if isinstance(group, dict)
        for code in group.get("object_codes", [])
        if code is not None
    }
    return sorted(codes)


def symbolic_shape_number_refs(referenced_resources: list[dict[str, Any]]) -> list[dict[str, Any]]:
    refs: list[dict[str, Any]] = []
    for item in referenced_resources:
        for group in item.get("shape_number_evidence", {}).get("groups", []):
            if group.get("candidate_kind") != "symbolic_or_expression":
                continue
            refs.append(
                {
                    "resource_id": item.get("resource_id"),
                    "resource_category": item.get("resource_category"),
                    "process": group.get("process"),
                    "role": group.get("role"),
                    "shape_number": group.get("shape_number"),
                    "object_codes": group.get("object_codes", []),
                    "match_status": item.get("match_status"),
                    "evidence_tier": "resource_ref_join",
                    "unresolved_semantics": [
                        "symbolic obj_shape_number is preserved as a candidate token and not evaluated to a frame count",
                    ],
                }
            )
    return sorted(
        refs,
        key=lambda item: (
            str(item.get("resource_id")),
            str(item.get("process")),
            str(item.get("shape_number")),
        ),
    )


def unresolved_shape_refs(referenced_resources: list[dict[str, Any]]) -> list[dict[str, Any]]:
    refs: list[dict[str, Any]] = []
    for item in referenced_resources:
        if item.get("match_status") == "resolved_payload":
            continue
        groups = item.get("shape_number_evidence", {}).get("groups", [])
        refs.append(
            {
                "resource_id": item.get("resource_id"),
                "resource_ref": item.get("resource_ref"),
                "resource_category": item.get("resource_category"),
                "signals": item.get("resource_resolution_evidence", {}).get("signals", []),
                "context_signals": item.get("resource_resolution_evidence", {}).get("context_signals", []),
                "searched_payload_roots": item.get("resource_resolution_evidence", {}).get("searched_payload_roots", []),
                "shape_number_candidates": item.get("usage", {}).get("shape_number_candidates", []),
                "object_codes": shape_number_object_codes(groups),
                "evidence_tier": "resource_ref_only",
                "unresolved_semantics": [
                    "Referenced by obj-051.obs but no matching SHP payload was found in the current imported payload set",
                    "This is a resource import gap candidate, not proof that the original game never loads the asset",
                ],
            }
        )
    return sorted(refs, key=lambda item: str(item.get("resource_id")))


def rounded_ratio(numerator: Any, denominator: Any) -> float | None:
    if not isinstance(numerator, int) or isinstance(numerator, bool):
        return None
    if not isinstance(denominator, int) or isinstance(denominator, bool) or denominator <= 0:
        return None
    return round(numerator / denominator, 4)


def visual_extent_class(width: Any, height: Any) -> str:
    if not isinstance(width, int) or not isinstance(height, int):
        return "unknown_extent"
    area = width * height
    if area <= 1024:
        return "small_sprite"
    if area <= 4096:
        return "medium_sprite"
    return "large_sprite"


def row_segment_complexity(row_summary: dict[str, Any], all_full_width: Any) -> str:
    if all_full_width is True:
        return "full_width_single_segment"
    common = row_summary.get("segment_count_common", [])
    if isinstance(common, list) and common:
        first = common[0]
        if isinstance(first, dict) and first.get("count") == 1:
            return "mostly_single_segment"
    return "multi_segment_rows"


def shp_visual_profile(payload: dict[str, Any], row_summary: dict[str, Any]) -> dict[str, Any]:
    width = payload.get("width")
    height = payload.get("height")
    coverage_min = row_summary.get("coverage_min")
    coverage_max = row_summary.get("coverage_max")
    all_full_width = payload.get("all_rows_full_width_single_segment")
    if all_full_width is True:
        classification = "full_rect_or_dense_sprite"
        transparent_model = "opaque_or_full_row_candidate"
    else:
        classification = "partial_row_sprite"
        transparent_model = "row_gap_transparency_candidate"
    return {
        "classification": classification,
        "extent_class": visual_extent_class(width, height),
        "width": width,
        "height": height,
        "area_pixels": width * height if isinstance(width, int) and isinstance(height, int) else None,
        "coverage_ratio_range": {
            "min": rounded_ratio(coverage_min, width),
            "max": rounded_ratio(coverage_max, width),
        },
        "row_segment_complexity": row_segment_complexity(row_summary, all_full_width),
        "transparent_pixel_model": transparent_model,
        "atlas_padding_pixels_candidate": 1,
        "evidence_tier": "resource_parser_candidate",
        "unresolved_semantics": [
            "visual profile is derived from SHP row coverage/segments only and is not animation frame semantics",
            "transparent pixel model is inferred from missing row coverage, not from a proven palette or color key",
        ],
    }


def shp_color_key_evidence(payload: dict[str, Any]) -> dict[str, Any]:
    summary = payload.get("pixel_value_summary") if isinstance(payload.get("pixel_value_summary"), dict) else {}
    header_value = payload.get("color_key_or_flags_0x10")
    return {
        "header_0x10_rgb565_hex": summary.get(
            "header_0x10_rgb565_hex",
            f"0x{header_value & 0xffff:04x}" if isinstance(header_value, int) and not isinstance(header_value, bool) else None,
        ),
        "header_0x10_value_seen_in_pixels": summary.get("header_0x10_value_seen_in_pixels"),
        "present_pixel_count": summary.get("present_pixel_count"),
        "transparent_gap_count": summary.get("transparent_gap_count"),
        "top_rgb565_values": summary.get("top_rgb565_values", []),
        "semantic_status": "unresolved",
        "evidence_tier": "resource_parser_candidate",
        "unresolved_semantics": [
            "header 0x10 is preserved as a color/key/flags candidate but not proven to be a transparent color",
            "row gaps provide transparency candidates independently of any palette or color-key interpretation",
        ],
    }


def shp_resource_metadata(payload: dict[str, Any]) -> dict[str, Any]:
    row_summary = payload.get("row_header_summary") if isinstance(payload.get("row_header_summary"), dict) else {}
    return {
        "source_id": logical_source_id(payload.get("path")),
        "source_relpath": source_relpath(payload.get("path")),
        "classification": "shp",
        "evidence_tier": "resource_imported",
        "dimensions": {
            "width": payload.get("width"),
            "height": payload.get("height"),
        },
        "row_table_entries": payload.get("row_table_entries"),
        "row_encoding_hypothesis": payload.get("row_encoding_hypothesis"),
        "row_coverage": {
            "min": row_summary.get("coverage_min"),
            "max": row_summary.get("coverage_max"),
        },
        "row_segment_shape": {
            "common_segment_counts": row_summary.get("segment_count_common", []),
            "common_coverages": row_summary.get("common_coverage", []),
        },
        "all_rows_decode": payload.get("all_rows_decode"),
        "all_rows_full_width_single_segment": payload.get("all_rows_full_width_single_segment"),
        "bytes_per_pixel_candidate": payload.get("bytes_per_pixel_candidate"),
        "color_key_or_flags_0x10": payload.get("color_key_or_flags_0x10"),
        "visual_profile": shp_visual_profile(payload, row_summary),
        "color_key_evidence": shp_color_key_evidence(payload),
        "interpretation_status": "resource_parser_candidate",
        "unresolved_semantics": [
            "SHP pixel payload is decoded as RGB565 row segments, but animation/frame semantics are not decoded",
            "Resource usage is joined by basename from obj-051.obs refs; load path and palette semantics remain provisional",
        ],
    }


def wav_resource_metadata(payload: dict[str, Any]) -> dict[str, Any]:
    decoded = payload.get("decoded_wave") if isinstance(payload.get("decoded_wave"), dict) else {}
    usage_hint = wav_usage_hint(payload)
    return {
        "source_id": logical_source_id(payload.get("path")),
        "source_relpath": source_relpath(payload.get("path")),
        "classification": "wav",
        "evidence_tier": "resource_imported",
        "decoded_wave": payload.get("decoded_wave"),
        "audio_profile": wav_audio_profile(decoded),
        "usage_hint": usage_hint,
        "trigger_semantics": {
            "semantic_status": "unresolved",
            "evidence_tier": "resource_imported",
            "unresolved_semantics": [
                "WAV resource name gives a usage hint only; script/action trigger semantics are not joined yet",
            ],
        },
        "provenance": payload_provenance(payload),
        "route_decision": payload.get("route_decision"),
        "interpretation_status": "resource_parser_candidate",
        "unresolved_semantics": [
            "Audio trigger/action semantics are not joined to script or battle events yet",
        ],
    }


def wav_audio_profile(decoded: dict[str, Any]) -> dict[str, Any]:
    sample_rate = decoded.get("sample_rate")
    frame_count = decoded.get("frame_count")
    duration = None
    if isinstance(sample_rate, int) and sample_rate > 0 and isinstance(frame_count, int):
        duration = round(frame_count / sample_rate, 4)
    return {
        "channels": decoded.get("channels"),
        "sample_rate": sample_rate,
        "bits_per_sample": decoded.get("bits_per_sample"),
        "frame_count": frame_count,
        "duration_seconds": duration,
        "format_hint": "pcm_wav_after_xor_a8_header_normalization",
        "godot_import_hint": "AudioStreamWAV-compatible after header normalization",
        "evidence_tier": "resource_imported",
    }


def wav_usage_hint(payload: dict[str, Any]) -> dict[str, Any]:
    basename = str(logical_source_id(payload.get("path")) or "").lower()
    signals: list[str] = []
    if basename.startswith("accept"):
        category = "ui_confirm_or_accept"
        signals.append("basename:accept")
    elif basename.startswith("attack"):
        category = "battle_attack_effect"
        signals.append("basename:attack")
    else:
        category = "unknown_audio"
        if basename:
            signals.append(f"basename:{basename}")
    return {
        "category": category,
        "signals": signals,
        "evidence_tier": "resource_name_hint",
        "unresolved_semantics": [
            "Audio category is inferred from resource basename only and does not prove trigger/action semantics",
        ],
    }


def battle_ui_group_for_resource(item: dict[str, Any]) -> str:
    basename = str(item.get("resource_id") or "").lower()
    processes = set(item.get("usage", {}).get("processes", {}).keys())
    if basename.startswith("cursor") or "defProcCursor" in processes:
        return "cursor_or_selection"
    if basename.startswith(("bcmd", "b_cmd")):
        return "battle_command_icon"
    if basename.startswith(("bar", "barh")):
        return "status_bar_or_gauge"
    if basename.startswith(("b_next", "b_prev")):
        return "battle_navigation"
    if basename.startswith(("i_rect", "window", "board")):
        return "window_or_panel"
    if basename.startswith(("num", "kill", "win", "stat")):
        return "status_text_or_number"
    if basename.startswith("level"):
        return "level_or_background_ui"
    return "battle_ui_unknown"


def build_battle_ui_resources(referenced_resources: list[dict[str, Any]]) -> list[dict[str, Any]]:
    resources: list[dict[str, Any]] = []
    for item in referenced_resources:
        if item.get("resource_category") != "battle_ui" or item.get("payload") is None:
            continue
        payload = item["payload"]
        resolution = item.get("resource_resolution_evidence", {})
        process_hints = sorted(
            set(item.get("usage", {}).get("processes", {}).keys())
            | {
                group.get("process")
                for group in item.get("shape_number_evidence", {}).get("groups", [])
                if group.get("process")
            }
        )
        resources.append(
            {
                "resource_id": item.get("resource_id"),
                "resource_ref": item.get("resource_ref"),
                "ui_group": battle_ui_group_for_resource(item),
                "match_status": item.get("match_status"),
                "dimensions": payload.get("dimensions"),
                "visual_profile": payload.get("visual_profile"),
                "shape_number_candidates": item.get("usage", {}).get("shape_number_candidates", []),
                "process_hints": process_hints,
                "object_codes": sorted(
                    set(item.get("usage", {}).get("object_codes", []))
                    | {
                        code
                        for group in item.get("shape_number_evidence", {}).get("groups", [])
                        for code in group.get("object_codes", [])
                    }
                ),
                "provenance": resolution.get("payload_provenance"),
                "owner_semantics": {
                    "semantic_status": "unresolved",
                    "evidence_tier": "resource_ref_join",
                    "unresolved_semantics": [
                        "UI resource grouping is a loader hint from basename/process/resource refs only",
                        "Runtime owner traversal, hit-test ownership, and command identity are not proven here",
                    ],
                },
                "evidence_tier": "resource_imported",
            }
        )
    return sorted(resources, key=lambda item: (str(item.get("ui_group")), str(item.get("resource_id"))))


def build_chapter01_imported_resource_refs(report: dict[str, Any]) -> dict[str, Any]:
    obj_051 = first_payload_matching(report, "obj-051.obs")
    map_objects = build_chapter01_imported_map_objects(report)
    shp_payloads = [
        item
        for item in report.get("payloads", [])
        if isinstance(item, dict) and item.get("classification") == "shp"
    ]
    wav_payloads = [
        item
        for item in report.get("payloads", [])
        if isinstance(item, dict) and item.get("classification") == "wav"
    ]
    shp_lookup = {
        key: item
        for item in shp_payloads
        if (key := resource_ref_key(item.get("path"))) is not None
    }
    searched_payload_roots = sorted(
        {
            root
            for item in shp_payloads
            if (root := derived_root(item.get("path"))) is not None
        }
    )
    object_refs_by_key = object_resource_ref_records(obj_051)

    placements_by_shape: dict[str, list[dict[str, Any]]] = collections.defaultdict(list)
    for placement in map_objects.get("placements", []):
        if not isinstance(placement, dict):
            continue
        key = resource_ref_key(placement.get("shape_resource"))
        if key is not None:
            placements_by_shape[key].append(placement)

    object_refs = sorted(
        {
            str(obj.get("obj_shape_name"))
            for obj in (obj_051 or {}).get("objects", [])
            if isinstance(obj, dict) and obj.get("obj_shape_name")
        },
        key=lambda value: value.lower(),
    )
    referenced_resources: list[dict[str, Any]] = []
    for ref in object_refs:
        key = resource_ref_key(ref)
        payload = shp_lookup.get(key or "")
        placements = placements_by_shape.get(key or "", [])
        object_records = object_refs_by_key.get(key or "", [])
        classification = classify_shape_resource(ref, payload, object_records, placements)
        shape_number_candidates = sorted(
            {
                str(item.get("shape_number"))
                for item in object_records + placements
                if item.get("shape_number") is not None
            }
        )
        shape_number_evidence = shape_number_evidence_table(
            classification["category"],
            object_records,
            placements,
        )
        referenced_resources.append(
            {
                "resource_ref": ref,
                "resource_id": logical_source_id(ref),
                "resource_key": key,
                "resource_kind": "shape",
                "resource_category": classification["category"],
                "category_evidence": classification["evidence"],
                "match_status": "resolved_payload" if payload else "unresolved_missing_payload",
                "evidence_tier": "resource_imported" if payload else "resource_ref_only",
                "resource_resolution_evidence": resource_resolution_evidence(
                    payload,
                    classification["category"],
                    object_records,
                    placements,
                    searched_payload_roots,
                ),
                "usage": {
                    "placed_instance_count": len(placements),
                    "object_definition_count": len(object_records),
                    "object_codes": sorted({str(item.get("object_code")) for item in placements}),
                    "shape_number_candidates": shape_number_candidates,
                    "roles": dict(sorted(collections.Counter(str(item.get("role")) for item in placements).items())),
                    "processes": dict(sorted(collections.Counter(str(item.get("process")) for item in placements).items())),
                },
                "shape_number_evidence": shape_number_evidence,
                "payload": shp_resource_metadata(payload) if payload else None,
                "unresolved_semantics": [
                    "obj_shape_number is preserved on object records but not mapped to animation frame semantics",
                    "SHP usage is a resource reference join, not proof of render order or runtime animation state",
                ],
            }
        )

    available_audio = [wav_resource_metadata(payload) for payload in wav_payloads]
    battle_ui_resources = build_battle_ui_resources(referenced_resources)
    return {
        "schema": "hsl_chapter01_imported_resource_refs.v1",
        "source_policy": "private remake resource reference IR; preserves obj-051.obs resource refs and joins available SHP/audio payload metadata without dropping unresolved refs",
        "evidence_tier": "resource_imported",
        "sources": {
            "objects": logical_source_id((obj_051 or {}).get("path")),
            "placements": "map_objects.json",
        },
        "unresolved_semantics": [
            "SHP dimensions and row decoding are resource format facts, not final sprite animation semantics",
            "UI/actor/map-object categorization is inferred from object process/role and resource basename only",
            "Audio files are available imported resources but are not joined to script action triggers yet",
        ],
        "summary": {
            "object_shape_ref_count": len(object_refs),
            "resolved_shape_payload_count": sum(1 for item in referenced_resources if item["match_status"] == "resolved_payload"),
            "unresolved_shape_ref_count": sum(
                1 for item in referenced_resources if item["match_status"] != "resolved_payload"
            ),
            "available_audio_count": len(wav_payloads),
            "battle_ui_resource_count": len(battle_ui_resources),
            "audio_usage_hint_counts": dict(
                sorted(collections.Counter(item["usage_hint"]["category"] for item in available_audio).items())
            ),
            "resource_category_counts": dict(
                sorted(collections.Counter(item["resource_category"] for item in referenced_resources).items())
            ),
            "battle_ui_group_counts": dict(
                sorted(collections.Counter(item["ui_group"] for item in battle_ui_resources).items())
            ),
            "shape_number_candidate_kind_counts": dict(
                sorted(
                    collections.Counter(
                        group["candidate_kind"]
                        for item in referenced_resources
                        for group in item["shape_number_evidence"]["groups"]
                    ).items()
                )
            ),
            "visual_profile_class_counts": dict(
                sorted(
                    collections.Counter(
                        item["payload"]["visual_profile"]["classification"]
                        for item in referenced_resources
                        if item["payload"] is not None
                    ).items()
                )
            ),
            "color_header_0x10_counts": dict(
                sorted(
                    collections.Counter(
                        item["payload"]["color_key_evidence"]["header_0x10_rgb565_hex"]
                        for item in referenced_resources
                        if item["payload"] is not None
                    ).items()
                )
            ),
            "unresolved_shape_ref_reason_counts": dict(
                sorted(
                    collections.Counter(
                        signal
                        for item in referenced_resources
                        if item["match_status"] != "resolved_payload"
                        for signal in item["resource_resolution_evidence"]["signals"]
                    ).items()
                )
            ),
        },
        "referenced_resources": referenced_resources,
        "symbolic_shape_number_refs": symbolic_shape_number_refs(referenced_resources),
        "unresolved_shape_refs": unresolved_shape_refs(referenced_resources),
        "battle_ui_resources": battle_ui_resources,
        "available_audio": available_audio,
    }


def build_chapter01_imported_ui_resources(report: dict[str, Any]) -> dict[str, Any]:
    resource_refs = build_chapter01_imported_resource_refs(report)
    resources = resource_refs.get("battle_ui_resources", [])
    return {
        "schema": "hsl_chapter01_imported_ui_resources.v1",
        "source_policy": "private remake UI resource loader manifest; preserves imported battle UI SHP metadata without proving owner traversal",
        "evidence_tier": "resource_imported",
        "sources": {"resource_refs": "resource_refs.json"},
        "summary": {
            "resource_count": len(resources),
            "ui_group_counts": resource_refs.get("summary", {}).get("battle_ui_group_counts", {}),
        },
        "unresolved_semantics": [
            "UI owner traversal, hit-test ownership, command identity, and action dispatch mapping remain unresolved",
        ],
        "resources": resources,
    }


def build_chapter01_imported_ui_preview_index(
    ui_resources: dict[str, Any],
    shape_preview_index: dict[str, Any],
) -> dict[str, Any]:
    previews_by_id = {
        str(item.get("resource_id")): item
        for item in shape_preview_index.get("entries", [])
        if isinstance(item, dict) and item.get("resource_id") is not None
    }
    entries: list[dict[str, Any]] = []
    missing_previews: list[dict[str, Any]] = []
    for order, item in enumerate(ui_resources.get("resources", [])):
        if not isinstance(item, dict):
            continue
        resource_id = str(item.get("resource_id"))
        preview = previews_by_id.get(resource_id)
        if preview is None:
            missing_previews.append(
                {
                    "resource_id": resource_id,
                    "ui_group": item.get("ui_group"),
                    "reason": "missing_shape_preview_index_entry",
                    "evidence_tier": "resource_imported",
                }
            )
            continue
        owner_semantics = item.get("owner_semantics") if isinstance(item.get("owner_semantics"), dict) else {}
        entries.append(
            {
                "display_order": len(entries),
                "resource_id": resource_id,
                "ui_group": item.get("ui_group"),
                "dimensions": item.get("dimensions"),
                "preview_relpath": preview.get("preview_relpath"),
                "preview_res_path": preview.get("preview_res_path"),
                "process_hints": item.get("process_hints", []),
                "object_codes": item.get("object_codes", []),
                "shape_number_candidates": item.get("shape_number_candidates", []),
                "owner_semantics_status": owner_semantics.get("semantic_status", "unresolved"),
                "command_identity_status": "unresolved",
                "frame_semantics_status": preview.get("frame_semantics_status"),
                "evidence_tier": "resource_imported",
            }
        )
    return {
        "schema": "hsl_chapter01_imported_ui_preview_index.v1",
        "source_policy": "private remake resource UI preview index; preserves Godot preview paths without proving UI owner traversal or command identity",
        "evidence_tier": "resource_imported",
        "sources": {"ui_resources": "ui_resources.json", "shape_preview_index": "shape_preview_index.json"},
        "summary": {
            "entry_count": len(entries),
            "ui_group_counts": dict(sorted(collections.Counter(item.get("ui_group") for item in entries).items())),
            "missing_preview_count": len(missing_previews),
        },
        "unresolved_semantics": [
            "UI preview entries are display hints for Godot panels; command identity and owner traversal remain unresolved",
            "Preview paths are decoded SHP images and are not animation frame definitions",
        ],
        "entries": entries,
        "missing_previews": missing_previews,
    }


def safe_audio_filename(source_id: str) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", source_id)


def audio_resources_from_report(report: dict[str, Any]) -> list[dict[str, Any]]:
    if isinstance(report.get("available_audio"), list):
        return [item for item in report["available_audio"] if isinstance(item, dict)]
    return build_chapter01_imported_resource_refs(report).get("available_audio", [])


def build_chapter01_imported_audio_normalized(report: dict[str, Any], output_dir: Path) -> dict[str, Any]:
    resources = audio_resources_from_report(report)
    normalized_audio: list[dict[str, Any]] = []
    skipped: list[dict[str, Any]] = []
    for item in resources:
        source_id = str(item.get("source_id") or "unknown.wav")
        provenance = item.get("provenance") if isinstance(item.get("provenance"), dict) else {}
        source_path = provenance.get("source_path")
        if not isinstance(source_path, str) or not source_path:
            skipped.append({"source_id": source_id, "reason": "missing_source_path"})
            continue
        path = Path(source_path)
        if not path.exists():
            skipped.append({"source_id": source_id, "reason": "source_path_not_found", "source_path": source_path})
            continue
        candidate = parse_xor_a8_wave_candidate(path, 0, path.stat().st_size)
        if candidate is None:
            skipped.append({"source_id": source_id, "reason": "not_xor_a8_wave_candidate", "source_path": source_path})
            continue
        try:
            decoded = decoded_xor_a8_wave_bytes(path, candidate)
        except (OSError, ValueError) as exc:
            skipped.append({"source_id": source_id, "reason": "decode_failed", "detail": str(exc), "source_path": source_path})
            continue
        normalized_relpath = f"audio_normalized/{safe_audio_filename(source_id)}"
        output_path = output_dir / normalized_relpath
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_bytes(decoded)
        normalized_audio.append(
            {
                "source_id": source_id,
                "source_relpath": item.get("source_relpath"),
                "normalized_relpath": normalized_relpath,
                "normalized_res_path": f"res://content/imported/hsl/chapter01/{normalized_relpath}",
                "audio_profile": item.get("audio_profile"),
                "usage_hint": item.get("usage_hint"),
                "trigger_semantics_status": item.get("trigger_semantics", {}).get("semantic_status", "unresolved")
                if isinstance(item.get("trigger_semantics"), dict)
                else "unresolved",
                "evidence_tier": "resource_imported",
            }
        )
    return {
        "schema": "hsl_chapter01_imported_audio_normalized.v1",
        "source_policy": "private remake resource audio normalization manifest; preserves Godot WAV paths without proving trigger semantics",
        "evidence_tier": "resource_imported",
        "sources": {"resource_refs": "resource_refs.json"},
        "summary": {"normalized_count": len(normalized_audio), "skipped_count": len(skipped)},
        "unresolved_semantics": [
            "Audio trigger semantics remain unresolved after WAV normalization",
            "Usage hints are resource-name hints only and are not script/runtime trigger proof",
        ],
        "normalized_audio": normalized_audio,
        "skipped": skipped,
    }


def message_id_sort_key(value: str) -> tuple[int, str]:
    return (int(value), value) if value.isdigit() else (10**9, value)


def collect_script_message_ids(payload: dict[str, Any]) -> list[str]:
    ids: set[str] = set()
    for block in payload.get("section_blocks", []):
        if not isinstance(block, dict):
            continue
        for message in block.get("messages", []):
            if isinstance(message, str):
                ids.update(token.strip() for token in message.split(",") if token.strip().isdigit())
        for action in block.get("actions", []):
            if not isinstance(action, dict):
                continue
            for item in action.get("chain", []):
                if not isinstance(item, dict):
                    continue
                if item.get("name") not in {"actMessage", "actMessageIfExist"}:
                    continue
                for arg in item.get("args", []):
                    token = str(arg).strip()
                    if token.isdigit():
                        ids.add(token)
    return sorted(ids, key=message_id_sort_key)


def collect_word_shape_refs(payload: dict[str, Any]) -> list[str]:
    refs: set[str] = set()
    for ref in payload.get("resource_refs", []):
        if isinstance(ref, str) and "WORD" in ref.upper() and ref.upper().endswith(".SHP"):
            refs.add(ref)
    for block in payload.get("section_blocks", []):
        if not isinstance(block, dict):
            continue
        for action in block.get("actions", []):
            if not isinstance(action, dict):
                continue
            for item in action.get("chain", []):
                if not isinstance(item, dict):
                    continue
                for arg in item.get("args", []):
                    token = str(arg).strip()
                    if "WORD" in token.upper() and token.upper().endswith(".SHP"):
                        refs.add(token)
    return sorted(refs)


def message_text_candidate_path(path_value: str | None) -> bool:
    if not path_value:
        return False
    name = Path(path_value.replace("\\", "/")).name.lower()
    suffix = Path(name).suffix.lower()
    if name in {"story051.txt", "winfail051.txt", "obj-051.obs", "obj-000.obs"}:
        return False
    return suffix in {".txt", ".msg", ".tbl", ".dat", ".bin"} and any(
        token in name for token in ("msg", "mess", "talk", "dialog", "word", "text")
    )


def build_chapter01_imported_message_text_evidence(report: dict[str, Any]) -> dict[str, Any]:
    payloads = [item for item in report.get("payloads", []) if isinstance(item, dict)]
    roots = sorted({root for item in payloads if (root := derived_root(item.get("path"))) is not None})
    suffix_counts = collections.Counter(
        Path(str(item.get("path", ""))).suffix.lower() or "<none>"
        for item in payloads
        if item.get("path")
    )
    script_sources: list[dict[str, Any]] = []
    all_message_ids: set[str] = set()
    word_shape_refs: set[str] = set()
    for item in payloads:
        path = str(item.get("path", ""))
        basename = Path(path.replace("\\", "/")).name.lower()
        if basename in {"story051.txt", "winfail051.txt"}:
            ids = collect_script_message_ids(item)
            all_message_ids.update(ids)
            script_sources.append(
                {
                    "source_id": logical_source_id(path),
                    "source_relpath": source_relpath(path),
                    "message_id_candidates": ids,
                    "act_message_count": item.get("action_counts", {}).get("actMessage")
                    if isinstance(item.get("action_counts"), dict)
                    else None,
                    "act_message_if_exist_count": item.get("action_counts", {}).get("actMessageIfExist")
                    if isinstance(item.get("action_counts"), dict)
                    else None,
                    "evidence_tier": "resource_derived_script",
                }
            )
        word_shape_refs.update(collect_word_shape_refs(item))

    structured_candidates = [
        {
            "source_id": logical_source_id(str(item.get("path"))),
            "source_relpath": source_relpath(str(item.get("path"))),
            "classification": item.get("classification"),
            "provenance": payload_provenance(item),
            "evidence_tier": "resource_name_candidate",
            "unresolved_semantics": [
                "Filename suggests a possible message/text table but structure is not decoded",
            ],
        }
        for item in payloads
        if message_text_candidate_path(str(item.get("path")))
    ]
    return {
        "schema": "hsl_chapter01_imported_message_text_evidence.v1",
        "source_policy": "private remake resource message text evidence; preserves search scope and unresolved message text status without exporting dialogue text",
        "evidence_tier": "resource_imported",
        "sources": {"script_ir": "script_ir_index.json", "resource_refs": "resource_refs.json"},
        "message_text_status": "not_resolved_in_imported_assets",
        "message_text_source_status": "missing_structured_text_table",
        "summary": {
            "script_message_id_candidate_count": len(all_message_ids),
            "structured_text_table_candidate_count": len(structured_candidates),
            "word_shape_ref_count": len(word_shape_refs),
        },
        "searched_payload_roots": roots,
        "searched_file_type_counts": dict(sorted(suffix_counts.items())),
        "script_message_sources": script_sources,
        "script_message_id_candidates": sorted(all_message_ids, key=message_id_sort_key),
        "word_shape_resource_refs": sorted(word_shape_refs),
        "structured_text_table_candidates": structured_candidates,
        "negative_evidence": [
            "no structured message text table payload was identified in searched imported roots",
            "level051.wrd remains classified as WORL/grid binary evidence, not message text",
            "script message ids are present in imported script resources, but localized/dialogue text lookup is unresolved",
        ],
        "unresolved_semantics": [
            "message id to localized text lookup remains unresolved until a structured message text table or decoded dialogue resource is found",
            "WORD*.SHP refs are preserved as visual/resource hints and are not decoded text tables",
        ],
    }


def safe_preview_filename(resource_id: str) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", resource_id)


def write_chapter01_shape_previews(report: dict[str, Any], output_dir: Path) -> dict[str, Any]:
    """SHP previews go to the imported `shared/` tree beside output_dir (the engine reads them
    for every level); the index keeps `preview_relpath` relative to that tree."""
    shared_dir = output_dir.parent / "shared"
    resource_refs = build_chapter01_imported_resource_refs(report)
    previews: list[dict[str, Any]] = []
    skipped: list[dict[str, Any]] = []
    for item in resource_refs.get("referenced_resources", []):
        if item.get("match_status") != "resolved_payload" or item.get("payload") is None:
            continue
        payload = item["payload"]
        resolution = item.get("resource_resolution_evidence", {})
        provenance = resolution.get("payload_provenance") if isinstance(resolution, dict) else {}
        source_path = provenance.get("source_path") if isinstance(provenance, dict) else None
        resource_id = str(item.get("resource_id") or "unknown.shp")
        category = str(item.get("resource_category") or "unknown")
        if not isinstance(source_path, str) or not source_path:
            skipped.append({"resource_id": resource_id, "reason": "missing_source_path"})
            continue
        source = Path(source_path)
        if not source.exists():
            skipped.append({"resource_id": resource_id, "reason": "source_path_not_found"})
            continue
        data = source.read_bytes()
        shp = parse_shp(data)
        preview_relpath = f"shape_previews/{category}/{safe_preview_filename(resource_id)}.png"
        write_shp_preview(data, shp, shared_dir / preview_relpath)
        previews.append(
            {
                "resource_id": resource_id,
                "atlas_group": category,
                "preview_relpath": preview_relpath,
                "dimensions": payload.get("dimensions"),
                "transparent_source": "row_gap_alpha",
                "header_0x10_policy": "unresolved_do_not_use_as_transparency",
                "frame_semantics_status": "unresolved",
                "evidence_tier": "resource_imported",
            }
        )
    previews.sort(key=lambda item: (str(item.get("atlas_group")), str(item.get("resource_id"))))
    return {
        "schema": "hsl_chapter01_imported_shape_previews.v2",
        "source_policy": "private remake SHP preview artifacts generated directly from resource_refs; not animation frames",
        "evidence_tier": "resource_imported",
        "sources": {"resource_refs": "resource_refs.json"},
        "summary": {"preview_count": len(previews), "skipped_count": len(skipped)},
        "unresolved_semantics": [
            "Preview PNGs are decoded SHP images using row gaps for alpha; they are not animation frames",
            "Header 0x10 remains unresolved and is not used as transparent color",
        ],
        "previews": previews,
        "skipped": skipped,
    }


def build_chapter01_imported_shape_preview_index(shape_previews: dict[str, Any]) -> dict[str, Any]:
    entries: list[dict[str, Any]] = []
    for order, item in enumerate(shape_previews.get("previews", [])):
        if not isinstance(item, dict):
            continue
        preview_relpath = item.get("preview_relpath")
        category = item.get("atlas_group")
        entries.append(
            {
                "display_order": order,
                "resource_id": item.get("resource_id"),
                "category": category,
                "dimensions": item.get("dimensions"),
                "preview_relpath": preview_relpath,
                "preview_res_path": f"res://content/imported/hsl/shared/{preview_relpath}",
                "frame_semantics_status": item.get("frame_semantics_status"),
                "evidence_tier": "resource_imported",
            }
        )
    return {
        "schema": "hsl_chapter01_imported_shape_preview_index.v1",
        "source_policy": "private remake resource preview index; preserves Godot res paths for decoded SHP preview display without animation frame semantics",
        "evidence_tier": "resource_imported",
        "sources": {"resource_refs": "resource_refs.json"},
        "summary": {
            "entry_count": len(entries),
            "category_counts": dict(sorted(collections.Counter(item.get("category") for item in entries).items())),
        },
        "unresolved_semantics": [
            "Preview index entries are decoded SHP images for Godot display panels, not animation frames",
            "Frame/animation slicing semantics remain unresolved and are not inferred from preview order",
        ],
        "entries": entries,
    }


def build_chapter01_imported_map_objects(report: dict[str, Any]) -> dict[str, Any]:
    obj_051 = first_payload_matching(report, "obj-051.obs")
    evef = first_payload_matching(report, "level051.bin")
    object_lookup = {
        str(obj.get("obj_code")): obj
        for obj in (obj_051 or {}).get("objects", [])
        if isinstance(obj, dict) and obj.get("obj_code") is not None
    }

    placements: list[dict[str, Any]] = []
    for record in (evef or {}).get("record_summaries", []):
        if not isinstance(record, dict):
            continue
        code = record.get("field_0x04_code_candidate")
        if code is None:
            continue
        obj = object_lookup.get(str(code))
        placements.append(
            {
                "record_index": record.get("index"),
                "record_offset_hex": f"0x{record.get('offset', 0):x}",
                "object_code": code,
                "role": placement_role_for_object(obj),
                "process": obj.get("obj_process_code") if obj else None,
                "object_name": obj.get("obj_name") if obj else None,
                "shape_resource": obj.get("obj_shape_name") if obj else None,
                "shape_resource_id": logical_source_id(obj.get("obj_shape_name")) if obj else None,
                "shape_number": obj.get("obj_shape_number") if obj else None,
                "candidate_x": record.get("placement_x_candidate_0x08"),
                "candidate_y": record.get("placement_y_candidate_0x0c"),
                "coordinate_interpretation": {
                    "source_kind": "resource-derived",
                    "evidence_tier": "resource_parser_candidate",
                    "interpretation_status": "provisional",
                    "semantics": "EVEF placement coordinate candidates; not proven as Godot grid, screen, or world cells",
                },
                "evef_fields": imported_evef_record_fields(record),
                "object_fields": imported_object_fields(obj),
                "join": {
                    "status": "joined" if obj else "unmatched",
                    "left": "level051.bin EVEF field_0x04_code_candidate",
                    "right": "obj-051.obs obj_code",
                    "evidence_tier": "resource_parser_candidate",
                },
            }
        )

    aggregates = placement_aggregates(
        [
            {
                "role": placement.get("role"),
                "process": placement.get("process"),
                "object_code": placement.get("object_code"),
                "shape": placement.get("shape_resource"),
            }
            for placement in placements
        ]
    )
    object_records = [
        {
            "obj_code": obj.get("obj_code"),
            "object_name": obj.get("obj_name"),
            "role": placement_role_for_object(obj),
            "process": obj.get("obj_process_code"),
            "shape_resource": obj.get("obj_shape_name"),
            "shape_resource_id": logical_source_id(obj.get("obj_shape_name")),
            "shape_number": obj.get("obj_shape_number"),
            "fields": imported_object_fields(obj),
            "fields_present": obj.get("fields_present", []),
        }
        for obj in (obj_051 or {}).get("objects", [])
        if isinstance(obj, dict)
    ]
    return {
        "schema": "hsl_chapter01_imported_map_objects_ir.v1",
        "source_policy": "private remake resource/object reverse-engineering IR; preserves original object fields, EVEF field offsets, resource refs, provisional coordinates, unresolved semantics, and evidence tiers",
        "evidence_tier": "resource_imported",
        "unresolved_semantics": [
            "EVEF coordinates are resource-derived candidates, not proven Godot grid cells",
            "obj_Data*/obj_Collide*/obj_Mode fields are preserved with unresolved gameplay meaning",
            "obj_Process_Code names are symbolic process references; exact runtime behavior remains static/runtime work",
        ],
        "sources": {
            "evef": logical_source_id((evef or {}).get("path")),
            "objects": logical_source_id((obj_051 or {}).get("path")),
        },
        "join_integrity": build_placement_join_integrity(evef, obj_051, placements, aggregates),
        "placement_aggregates": aggregates,
        "placements": placements,
        "object_records": object_records,
    }


def write_chapter01_imported_map_object_ir(report: dict[str, Any], output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    deprecated_outputs = [
        "asset_browser_index.json",
        "audio_resources.json",
        "blocking_placement.json",
        "map_grid.json",
        "shape_atlas_plan.json",
        "shape_previews.json",
        "terrain_cost_evidence.json",
        "terrain_placement_projection.json",
    ]
    for filename in deprecated_outputs:
        path = output_dir / filename
        if path.exists():
            path.unlink()

    write_json_report(build_chapter01_imported_map_objects(report), output_dir / "map_objects.json")
    resource_refs = build_chapter01_imported_resource_refs(report)
    write_json_report(resource_refs, output_dir / "resource_refs.json")
    ui_resources = build_chapter01_imported_ui_resources(report)
    write_json_report(ui_resources, output_dir / "ui_resources.json")
    audio_normalized = build_chapter01_imported_audio_normalized(report, output_dir)
    write_json_report(audio_normalized, output_dir / "audio_normalized.json")
    message_text_evidence = build_chapter01_imported_message_text_evidence(report)
    write_json_report(message_text_evidence, output_dir / "message_text_evidence.json")
    shape_previews = write_chapter01_shape_previews(report, output_dir)
    shape_preview_index = build_chapter01_imported_shape_preview_index(shape_previews)
    write_json_report(shape_preview_index, output_dir / "shape_preview_index.json")
    ui_preview_index = build_chapter01_imported_ui_preview_index(ui_resources, shape_preview_index)
    write_json_report(ui_preview_index, output_dir / "ui_preview_index.json")


def parse_wav_record(path: Path, data: bytes, preview_dir: Path | None) -> dict[str, Any]:
    candidate = parse_xor_a8_wave_candidate(path, 0, len(data))
    result: dict[str, Any] = {
        "kind": "xor_a8_header_wave_record",
        "byte_length": len(data),
        "candidate": candidate,
        "route_decision": "normalize XOR-A8 RIFF/WAVE header before Godot/Python WAV consumption",
    }
    if candidate is None:
        return result

    decoded = decoded_xor_a8_wave_bytes(path, candidate)
    with wave.open(BytesIO(decoded), "rb") as handle:
        result["decoded_wave"] = {
            "channels": handle.getnchannels(),
            "sample_rate": handle.getframerate(),
            "bits_per_sample": handle.getsampwidth() * 8,
            "frame_count": handle.getnframes(),
        }
    if preview_dir is not None:
        output_path = preview_dir / "wav-normalized" / path.name
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_bytes(decoded)
        result["normalized_output_path"] = output_path.as_posix()
        result["normalized_sha256"] = sha256_bytes(decoded)
    return result


def classify_payload(path: Path, data: bytes) -> str:
    suffix = path.suffix.lower()
    if data.startswith(SHP_MAGIC):
        return "shp"
    if data.startswith(EVEF_MAGIC):
        return "evef"
    if data.startswith(WORL_MAGIC):
        return "worl"
    if suffix in {".txt", ".obs", ".h"}:
        return "text"
    if suffix == ".wav":
        return "wav"
    return "unknown"


def inspect_payload(path: Path, preview_dir: Path | None = None) -> dict[str, Any]:
    data = path.read_bytes()
    result: dict[str, Any] = {
        "path": path.as_posix(),
        "size": len(data),
        "sha256": sha256_bytes(data),
        "first_bytes_hex": data[:32].hex(),
    }
    kind = classify_payload(path, data)
    result["classification"] = kind
    if kind == "text":
        result.update(parse_text_metadata(data))
    elif kind == "shp":
        shp = parse_shp(data)
        if preview_dir is not None:
            output_path = preview_dir / "shp-rgb565" / f"{path.stem}.png"
            write_shp_preview(data, shp, output_path)
            shp["preview_output_path"] = output_path.as_posix()
        result.update(shp)
    elif kind == "evef":
        result.update(parse_evef(data))
    elif kind == "worl":
        result.update(parse_worl(data))
    elif kind == "wav":
        result.update(parse_wav_record(path, data, preview_dir))
    else:
        result["kind"] = "unknown"
    return result


def load_manifest_paths(manifest_path: Path) -> list[Path]:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    return [Path(record["output_path"]) for record in manifest.get("records", [])]


def collect_payload_paths(manifest_path: Path, extra_roots: list[Path]) -> list[Path]:
    paths = load_manifest_paths(manifest_path)
    for root in extra_roots:
        if root.exists():
            paths.extend(sorted(path for path in root.rglob("*") if path.is_file()))
    unique: list[Path] = []
    seen: set[str] = set()
    for path in paths:
        key = path.as_posix()
        if key in seen:
            continue
        seen.add(key)
        unique.append(path)
    return unique


def write_json_report(report: dict[str, Any], output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def write_markdown_report(report: dict[str, Any], output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "# HSL Payload Preview",
        "",
        "This ignored local-private report stores compact metadata only; original scripts, maps, and raw payloads are not copied into tracked docs.",
        "",
        f"manifest: `{report['manifest_path']}`",
        f"payload_count: {report['payload_count']}",
        "",
        "## Summary",
        "",
        "| class | count |",
        "| --- | ---: |",
    ]
    for key, count in sorted(report["classification_counts"].items()):
        lines.append(f"| `{key}` | {count} |")

    lines.extend(["", "## Text And Object Definitions", ""])
    for item in report["payloads"]:
        if item["classification"] != "text":
            continue
        lines.append(
            "- `{}`: encoding `{}`, lines {}, includes {}, sections {}, actions {}, objects {}, resources {}".format(
                item["path"],
                item["encoding"],
                item["line_count"],
                item["includes"],
                item["section_counts"],
                sum(item["action_counts"].values()),
                item["object_count"],
                item["resource_refs"],
            )
        )

    lines.extend(["", "## SHP", ""])
    for item in report["payloads"]:
        if item["classification"] != "shp":
            continue
        lines.append(
            "- `{}`: {}x{}, rows {}, RGB565 preview `{}`, rows_decode {}, full_width_single_segment {}, table_ok {}".format(
                item["path"],
                item["width"],
                item["height"],
                item["row_table_entries"],
                item.get("preview_output_path", "none"),
                item["all_rows_decode"],
                item["all_rows_full_width_single_segment"],
                item["first_row_is_after_table"] and item["final_row_ends_at_file_size"],
            )
        )

    lines.extend(["", "## Binary Level Context", ""])
    for item in report["payloads"]:
        if item["classification"] in {"evef", "worl"}:
            if item["classification"] == "evef":
                lines.append(
                    "- `{}`: EVEF count {}, record_size {}, size_ok {}, nonzero_records {}".format(
                        item["path"],
                        item["record_count"],
                        item["fixed_record_size_hypothesis"],
                        item["size_matches_count_times_record_size"],
                        item["non_zero_record_count"],
                    )
                )
            else:
                lines.append(
                    "- `{}`: WORL {}x{} cells, bytes_per_cell {}, size_ok {}, unique_values {}".format(
                        item["path"],
                        item["width_candidate_0x0c"],
                        item["height_candidate_0x10"],
                        item["bytes_per_cell_candidate_0x14"],
                        item["size_matches_grid"],
                        item["unique_cell_values"],
                    )
                )

    lines.extend(["", "## WAV", ""])
    for item in report["payloads"]:
        if item["classification"] == "wav":
            decoded = item.get("decoded_wave") or {}
            lines.append(
                "- `{}`: {}, normalized `{}`".format(
                    item["path"],
                    decoded,
                    item.get("normalized_output_path", "none"),
                )
            )

    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def build_report(manifest_path: Path, extra_roots: list[Path], preview_dir: Path | None) -> dict[str, Any]:
    paths = collect_payload_paths(manifest_path, extra_roots)
    payloads = [inspect_payload(path, preview_dir=preview_dir) for path in paths]
    return {
        "manifest_path": manifest_path.as_posix(),
        "extra_roots": [root.as_posix() for root in extra_roots],
        "preview_dir": preview_dir.as_posix() if preview_dir else None,
        "payload_count": len(payloads),
        "classification_counts": dict(collections.Counter(item["classification"] for item in payloads)),
        "payloads": payloads,
    }


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--manifest",
        type=Path,
        required=True,
        help="explicit resource-scan manifest to inspect; raw manifests are not stored in the active repo",
    )
    parser.add_argument("--extra-root", action="append", default=[], type=Path)
    parser.add_argument("--json", dest="json_output", type=Path, default=DEFAULT_OUTPUT_JSON)
    parser.add_argument("--markdown", dest="markdown_output", type=Path, default=DEFAULT_OUTPUT_MARKDOWN)
    parser.add_argument("--mechanics-json", dest="mechanics_json_output", type=Path)
    parser.add_argument("--generated-chapter01-dir", dest="generated_chapter01_dir", type=Path)
    parser.add_argument("--imported-chapter01-dir", dest="imported_chapter01_dir", type=Path)
    parser.add_argument("--preview-dir", type=Path, default=DEFAULT_PREVIEW_DIR)
    parser.add_argument("--no-previews", action="store_true")
    return parser.parse_args(argv)


def main() -> int:
    args = parse_args()
    if not args.manifest.exists():
        raise SystemExit(f"manifest does not exist: {args.manifest}")
    preview_dir = None if args.no_previews else args.preview_dir
    report = build_report(args.manifest, args.extra_root, preview_dir=preview_dir)
    write_json_report(report, args.json_output)
    write_markdown_report(report, args.markdown_output)
    if args.mechanics_json_output is not None:
        write_json_report(
            build_first_battle_mechanics_fixture(report),
            args.mechanics_json_output,
        )
    if args.generated_chapter01_dir is not None:
        write_chapter01_generated_metadata(report, args.generated_chapter01_dir)
    if args.imported_chapter01_dir is not None:
        write_chapter01_imported_script_ir(report, args.imported_chapter01_dir)
        write_chapter01_imported_map_object_ir(report, args.imported_chapter01_dir)
    print(
        "inspected {} payload(s); wrote {} and {}".format(
            report["payload_count"],
            args.json_output,
            args.markdown_output,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
