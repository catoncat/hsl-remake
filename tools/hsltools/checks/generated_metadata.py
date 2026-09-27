"""Structural check of the chapter01 generated metadata (content/generated/hsl/chapter01).

Registry task generated_metadata_check (family checks, CheckTask). Bodies (main included) moved verbatim
from the former hsl_generated_metadata_check.py.
"""
import argparse
import json
from collections import Counter
from pathlib import Path
from typing import Any

from hsltools.checks import CheckTask
from hsltools.data import printed_last_line
from hsltools.registry import Context


EXPECTED_FILES = {
    "index": "index.json",
    "mechanics": "mechanics.json",
    "map_grid": "map_grid.json",
    "initial_placements": "initial_placements.json",
    "script_summary": "script_summary.json",
}

EXPECTED_SCHEMAS = {
    "index": "hsl_chapter01_generated_index.v1",
    "mechanics": "hsl_chapter01_generated_metadata.v1",
    "map_grid": "hsl_chapter01_map_grid.v1",
    "initial_placements": "hsl_chapter01_initial_placements.v1",
    "script_summary": "hsl_chapter01_script_summary.v1",
}

FORBIDDEN_FIELD_NAMES = {
    "action_args",
    "args",
    "blocker",
    "blockers",
    "capture_path",
    "chain",
    "common_cell_values",
    "first_bytes_hex",
    "full_sha256",
    "flag_counts",
    "flagged_cell_samples",
    "low24_max",
    "low24_min",
    "memory_bytes",
    "memory_dump",
    "move_cost",
    "move_costs",
    "non_zero_u32",
    "normalized_output_path",
    "object_name",
    "original_status_ids",
    "order",
    "pixels",
    "preview_output_path",
    "private_path",
    "raw_bytes",
    "sample_rows_low24",
    "screenshot_path",
    "section_blocks",
    "sections",
    "sha256",
    "source_path",
    "script_order",
    "terrain",
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


def load_json(path: Path) -> tuple[Any | None, str | None]:
    try:
        return json.loads(path.read_text(encoding="utf-8")), None
    except FileNotFoundError:
        return None, f"missing file: {path.name}"
    except json.JSONDecodeError as exc:
        return None, f"invalid JSON in {path.name}: {exc.msg}"


def field_path(parent: str, key: str) -> str:
    return f"{parent}.{key}" if parent else key


def collect_forbidden_fields(value: Any, prefix: str = "") -> list[str]:
    errors: list[str] = []
    if isinstance(value, dict):
        for key, child in value.items():
            child_path = field_path(prefix, str(key))
            if key in FORBIDDEN_FIELD_NAMES:
                errors.append(f"forbidden field {child_path}")
            errors.extend(collect_forbidden_fields(child, child_path))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            errors.extend(collect_forbidden_fields(child, f"{prefix}[{index}]"))
    return errors


def is_int(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def string_counter(items: list[Any]) -> dict[str, int]:
    return dict(sorted(Counter(str(item) for item in items).items()))


def int_count(counts: dict[str, Any], key: str) -> int:
    value = counts.get(key, 0)
    return value if is_int(value) else 0


def computed_status_action_contract(script_summary: dict[str, Any]) -> dict[str, Any]:
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


def computed_status_lifecycle_summary(
    script_summary: dict[str, Any],
    status_action_contract: dict[str, Any],
) -> dict[str, Any]:
    story = script_summary.get("story051", {}) if isinstance(script_summary, dict) else {}
    winfail = script_summary.get("winfail051", {}) if isinstance(script_summary, dict) else {}
    story_actions = story.get("action_counts", {}) if isinstance(story, dict) else {}
    winfail_actions = winfail.get("action_counts", {}) if isinstance(winfail, dict) else {}
    if not isinstance(story_actions, dict):
        story_actions = {}
    if not isinstance(winfail_actions, dict):
        winfail_actions = {}

    event_insert_count = int_count(status_action_contract, "event_status_insert_count")
    event_delete_count = int_count(status_action_contract, "event_status_delete_count")
    return {
        "summary_semantics": STATUS_LIFECYCLE_SUMMARY_SEMANTICS,
        "fail": {"insert_count": int_count(status_action_contract, "fail_status_count")},
        "event": {
            "insert_count": event_insert_count,
            "delete_count": event_delete_count,
            "net_enabled_candidate": event_insert_count - event_delete_count,
        },
        "win": {"insert_count": int_count(status_action_contract, "win_status_count")},
        "checks": {
            "round": int_count(status_action_contract, "round_check_count"),
            "enemy_total": int_count(status_action_contract, "enemy_total_check_count"),
            "enemy_number": int_count(status_action_contract, "enemy_number_check_count"),
            "arrival": int_count(status_action_contract, "arrival_check_count"),
        },
        "show_status_count": int_count(story_actions, "actShowWinFailStatus")
        + int_count(winfail_actions, "actShowWinFailStatus"),
    }


def computed_placement_aggregates(items: list[dict[str, Any]]) -> dict[str, Any]:
    by_role: dict[str, dict[str, dict[str, int]]] = {}
    roles = sorted({str(item.get("role", "unknown")) for item in items})
    for role in roles:
        role_items = [item for item in items if str(item.get("role", "unknown")) == role]
        by_role[role] = {
            "object_code_counts": string_counter([item.get("object_code", "unknown") for item in role_items]),
            "process_counts": string_counter([item.get("process", "unknown") for item in role_items]),
            "shape_id_counts": string_counter([item.get("shape_id", "unknown") for item in role_items]),
        }
    return {
        "role_counts": string_counter([item.get("role", "unknown") for item in items]),
        "object_code_counts": string_counter([item.get("object_code", "unknown") for item in items]),
        "process_counts": string_counter([item.get("process", "unknown") for item in items]),
        "shape_id_counts": string_counter([item.get("shape_id", "unknown") for item in items]),
        "by_role": by_role,
    }


def computed_placement_join_integrity(
    items: list[dict[str, Any]],
    mechanics: dict[str, Any],
    aggregates: dict[str, Any],
) -> dict[str, Any]:
    evef = mechanics.get("evef") if isinstance(mechanics.get("evef"), dict) else {}
    object_records = mechanics.get("object_records") if isinstance(mechanics.get("object_records"), dict) else {}
    non_zero_record_count = evef.get("non_zero_record_count")
    if not is_int(non_zero_record_count):
        non_zero_record_count = 0
    joined_record_count = sum(1 for item in items if item.get("role") != "unmatched")
    object_code_counts = aggregates.get("object_code_counts", {}) if isinstance(aggregates, dict) else {}
    role_counts = aggregates.get("role_counts", {}) if isinstance(aggregates, dict) else {}
    return {
        "summary_semantics": PLACEMENT_JOIN_INTEGRITY_SEMANTICS,
        "evef_record_count": evef.get("record_count"),
        "non_zero_record_count": non_zero_record_count,
        "joined_record_count": joined_record_count,
        "unmatched_record_count": max(0, non_zero_record_count - joined_record_count),
        "placed_object_code_count": len(object_code_counts) if isinstance(object_code_counts, dict) else 0,
        "object_record_count": object_records.get("object_count"),
        "role_coverage_counts": role_counts if isinstance(role_counts, dict) else {},
    }


def check_schema_and_policy(docs: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    policies = []
    for key, doc in docs.items():
        expected = EXPECTED_SCHEMAS[key]
        actual = doc.get("schema") if isinstance(doc, dict) else None
        if actual != expected:
            errors.append(f"{EXPECTED_FILES[key]} schema mismatch: expected {expected}, got {actual!r}")
        if key != "index":
            tier = doc.get("evidence_tier") if isinstance(doc, dict) else None
            if tier != "resource_parser_candidate":
                errors.append(f"{EXPECTED_FILES[key]} evidence_tier mismatch: {tier!r}")
        policy = doc.get("source_policy") if isinstance(doc, dict) else None
        if policy:
            policies.append((key, policy))
    if policies:
        first_key, first_policy = policies[0]
        for key, policy in policies[1:]:
            if policy != first_policy:
                errors.append(
                    f"source_policy mismatch: {EXPECTED_FILES[first_key]} differs from {EXPECTED_FILES[key]}"
                )
    return errors


def check_index(index: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    files = index.get("files")
    if not isinstance(files, dict):
        return ["index.json files must be an object"]
    expected = {key: name for key, name in EXPECTED_FILES.items() if key != "index"}
    if files != expected:
        errors.append(f"index.json files mismatch: expected {expected}, got {files!r}")
    return errors


def check_map_grid(mechanics: dict[str, Any], map_grid_doc: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    mechanics_grid = mechanics.get("map_grid")
    split_grid = map_grid_doc.get("map_grid")
    if mechanics_grid != split_grid:
        errors.append("map_grid mismatch between mechanics.json and map_grid.json")
    if not isinstance(split_grid, dict):
        return errors + ["map_grid.json map_grid must be an object"]

    dimensions = split_grid.get("dimensions")
    if not isinstance(dimensions, dict):
        return errors + ["map_grid dimensions must be an object"]
    width = dimensions.get("width")
    height = dimensions.get("height")
    bytes_per_cell = split_grid.get("bytes_per_cell")
    if not (is_int(width) and is_int(height) and width > 0 and height > 0):
        errors.append(f"map_grid dimensions must be positive integers, got {dimensions!r}")
    if not (is_int(bytes_per_cell) and bytes_per_cell > 0):
        errors.append(f"map_grid bytes_per_cell must be positive integer, got {bytes_per_cell!r}")
    if split_grid.get("size_matches_grid") is not True:
        errors.append("map_grid size_matches_grid must be true")
    integrity = split_grid.get("opaque_integrity")
    if not isinstance(integrity, dict):
        return errors + ["map_grid opaque_integrity must be an object"]
    cell_count = integrity.get("cell_count")
    flagged_count = integrity.get("flagged_cell_count")
    unflagged_count = integrity.get("unflagged_cell_count")
    unique_count = integrity.get("unique_cell_value_count")
    low24_unique_count = integrity.get("low24_unique_cell_value_count")
    dense = integrity.get("low24_is_dense_cell_range")
    if is_int(width) and is_int(height):
        expected_cell_count = width * height
        if cell_count != expected_cell_count:
            errors.append(f"map_grid opaque_integrity cell_count {cell_count!r} != width*height {expected_cell_count}")
    if not is_int(cell_count) or cell_count <= 0:
        errors.append(f"map_grid opaque_integrity cell_count must be positive integer, got {cell_count!r}")
    for key, value in (
        ("flagged_cell_count", flagged_count),
        ("unflagged_cell_count", unflagged_count),
        ("unique_cell_value_count", unique_count),
        ("low24_unique_cell_value_count", low24_unique_count),
    ):
        if not is_int(value) or value < 0:
            errors.append(f"map_grid opaque_integrity {key} must be non-negative integer, got {value!r}")
    if is_int(flagged_count) and is_int(unflagged_count) and is_int(cell_count):
        if flagged_count + unflagged_count != cell_count:
            errors.append(
                "map_grid opaque_integrity flagged_cell_count + unflagged_cell_count "
                f"{flagged_count + unflagged_count} != cell_count {cell_count}"
            )
    low24_range = integrity.get("low24_range")
    if isinstance(low24_range, dict):
        low24_min = low24_range.get("min")
        low24_max = low24_range.get("max")
        if not is_int(low24_min) or not is_int(low24_max):
            errors.append(f"map_grid opaque_integrity low24_range must contain integer min/max, got {low24_range!r}")
        elif low24_min < 0 or low24_max > 0x00FFFFFF or low24_min > low24_max:
            errors.append(f"map_grid opaque_integrity low24_range is invalid: {low24_range!r}")
        elif dense is True and is_int(cell_count):
            if low24_min != 0 or low24_max != cell_count - 1:
                errors.append(
                    "map_grid opaque_integrity dense low24_range must be 0..cell_count-1, "
                    f"got {low24_range!r} for cell_count {cell_count}"
                )
    else:
        errors.append("map_grid opaque_integrity low24_range must be an object")
    if not isinstance(dense, bool):
        errors.append(f"map_grid opaque_integrity low24_is_dense_cell_range must be boolean, got {dense!r}")
    if dense is True and is_int(low24_unique_count) and is_int(cell_count) and low24_unique_count != cell_count:
        errors.append(
            "map_grid opaque_integrity dense low24_unique_cell_value_count "
            f"{low24_unique_count} != cell_count {cell_count}"
        )
    semantics = integrity.get("summary_semantics")
    if not isinstance(semantics, str) or "opaque structural WORL integrity summary" not in semantics:
        errors.append("map_grid opaque_integrity summary_semantics must describe opaque structural WORL integrity")
    return errors


def check_placements(mechanics: dict[str, Any], placements_doc: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    mechanics_items = mechanics.get("initial_placements")
    split_items = placements_doc.get("initial_placements")
    if mechanics_items != split_items:
        errors.append("initial_placements mismatch between mechanics.json and initial_placements.json")
    if not isinstance(split_items, list):
        return errors + ["initial_placements.json initial_placements must be a list"]

    role_counts = Counter()
    record_indexes = set()
    for index, item in enumerate(split_items):
        if not isinstance(item, dict):
            errors.append(f"initial_placements[{index}] must be an object")
            continue
        role = item.get("role")
        if not isinstance(role, str) or not role:
            errors.append(f"initial_placements[{index}] role must be non-empty string")
        else:
            role_counts[role] += 1
        record_index = item.get("record_index")
        if not is_int(record_index):
            errors.append(f"initial_placements[{index}] record_index must be integer")
        elif record_index in record_indexes:
            errors.append(f"duplicate placement record_index {record_index}")
        else:
            record_indexes.add(record_index)

    computed_role_counts = dict(sorted(role_counts.items()))
    split_role_counts = placements_doc.get("placement_role_counts")
    mechanics_role_counts = mechanics.get("placement_role_counts")
    if split_role_counts != mechanics_role_counts:
        errors.append("placement_role_counts mismatch between mechanics.json and initial_placements.json")
    if split_role_counts != computed_role_counts:
        errors.append(f"placement_role_counts mismatch: expected {computed_role_counts}, got {split_role_counts!r}")

    split_aggregates = placements_doc.get("placement_aggregates")
    mechanics_aggregates = mechanics.get("placement_aggregates")
    if split_aggregates != mechanics_aggregates:
        errors.append("placement_aggregates mismatch between mechanics.json and initial_placements.json")
    if isinstance(split_aggregates, dict):
        computed_aggregates = computed_placement_aggregates(split_items)
        for key in ("role_counts", "object_code_counts", "process_counts", "shape_id_counts", "by_role"):
            if split_aggregates.get(key) != computed_aggregates[key]:
                errors.append(f"placement_aggregates {key} mismatch: expected {computed_aggregates[key]}, got {split_aggregates.get(key)!r}")
        semantics = split_aggregates.get("summary_semantics")
        if not isinstance(semantics, str) or "coordinates" not in semantics or "unresolved" not in semantics:
            errors.append("placement_aggregates summary_semantics must keep coordinate semantics unresolved")
    else:
        errors.append("placement_aggregates must be an object")

    split_join_integrity = placements_doc.get("placement_join_integrity")
    mechanics_join_integrity = mechanics.get("placement_join_integrity")
    if split_join_integrity != mechanics_join_integrity:
        errors.append("placement_join_integrity mismatch between mechanics.json and initial_placements.json")
    if isinstance(split_join_integrity, dict) and isinstance(split_aggregates, dict):
        expected_join_integrity = computed_placement_join_integrity(split_items, mechanics, split_aggregates)
        if split_join_integrity != expected_join_integrity:
            errors.append(
                f"placement_join_integrity mismatch: expected {expected_join_integrity!r}, got {split_join_integrity!r}"
            )
        semantics = split_join_integrity.get("summary_semantics")
        required_phrases = (
            "count-only",
            "object names",
            "raw object fields",
            "unresolved",
        )
        if not isinstance(semantics, str) or any(phrase not in semantics for phrase in required_phrases):
            errors.append("placement_join_integrity summary_semantics must keep object join semantics count-only")
    else:
        errors.append("placement_join_integrity must be an object")

    evef = mechanics.get("evef")
    if isinstance(evef, dict):
        non_zero = evef.get("non_zero_record_count")
        if is_int(non_zero) and non_zero != len(split_items):
            errors.append(f"evef non_zero_record_count {non_zero} != placement count {len(split_items)}")
        code_counts = evef.get("record_code_counts")
        if isinstance(code_counts, dict):
            count_sum = sum(value for value in code_counts.values() if is_int(value))
            if is_int(non_zero) and count_sum != non_zero:
                errors.append(f"evef record_code_counts sum {count_sum} != non_zero_record_count {non_zero}")
        else:
            errors.append("evef record_code_counts must be an object")
    else:
        errors.append("mechanics.json evef must be an object")
    return errors


def check_script_summary(mechanics: dict[str, Any], script_doc: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    mechanics_summary = mechanics.get("script_summary")
    split_summary = script_doc.get("script_summary")
    if mechanics_summary != split_summary:
        errors.append("script_summary mismatch between mechanics.json and script_summary.json")
    if not isinstance(split_summary, dict):
        return errors + ["script_summary.json script_summary must be an object"]
    for key in ("story051", "winfail051"):
        section = split_summary.get(key)
        if not isinstance(section, dict):
            errors.append(f"script_summary missing {key}")
            continue
        if not isinstance(section.get("section_counts"), dict):
            errors.append(f"script_summary {key} section_counts must be an object")
        if not isinstance(section.get("action_counts"), dict):
            errors.append(f"script_summary {key} action_counts must be an object")

    mechanics_contract = mechanics.get("status_action_contract")
    split_contract = script_doc.get("status_action_contract")
    if mechanics_contract != split_contract:
        errors.append("status_action_contract mismatch between mechanics.json and script_summary.json")
    expected_contract = computed_status_action_contract(split_summary)
    if split_contract != expected_contract:
        errors.append(
            f"status_action_contract mismatch: expected {expected_contract!r}, got {split_contract!r}"
        )

    mechanics_lifecycle = mechanics.get("status_lifecycle_summary")
    split_lifecycle = script_doc.get("status_lifecycle_summary")
    if mechanics_lifecycle != split_lifecycle:
        errors.append("status_lifecycle_summary mismatch between mechanics.json and script_summary.json")
    if not isinstance(split_contract, dict):
        return errors + ["status_action_contract must be an object"]
    expected_lifecycle = computed_status_lifecycle_summary(split_summary, split_contract)
    if split_lifecycle != expected_lifecycle:
        errors.append(
            f"status_lifecycle_summary mismatch: expected {expected_lifecycle!r}, got {split_lifecycle!r}"
        )
    elif isinstance(split_lifecycle, dict):
        semantics = split_lifecycle.get("summary_semantics")
        required_phrases = (
            "not original status ids",
            "action args",
            "script order",
        )
        if not isinstance(semantics, str) or any(phrase not in semantics for phrase in required_phrases):
            errors.append(
                "status_lifecycle_summary summary_semantics must reject original status ids, action args, and script order"
            )
    return errors


def check_chapter_dir(chapter_dir: Path | str) -> list[str]:
    chapter_dir = Path(chapter_dir)
    errors: list[str] = []
    docs: dict[str, Any] = {}
    for key, filename in EXPECTED_FILES.items():
        doc, error = load_json(chapter_dir / filename)
        if error:
            errors.append(error)
        else:
            docs[key] = doc
    if len(docs) != len(EXPECTED_FILES):
        return errors

    for key, doc in docs.items():
        errors.extend(collect_forbidden_fields(doc, EXPECTED_FILES[key]))

    errors.extend(check_schema_and_policy(docs))
    errors.extend(check_index(docs["index"]))
    errors.extend(check_map_grid(docs["mechanics"], docs["map_grid"]))
    errors.extend(check_placements(docs["mechanics"], docs["initial_placements"]))
    errors.extend(check_script_summary(docs["mechanics"], docs["script_summary"]))
    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Check HSL chapter01 generated metadata consistency.")
    parser.add_argument("chapter_dir", type=Path)
    args = parser.parse_args(argv)

    errors = check_chapter_dir(args.chapter_dir)
    if errors:
        print(f"FAIL hsl generated metadata ({len(errors)} error(s))")
        for error in errors[:8]:
            print(f"- {error}")
        if len(errors) > 8:
            print(f"- ... {len(errors) - 8} more")
        return 1
    print("PASS hsl generated metadata")
    return 0


class GeneratedMetadataCheckTask(CheckTask):
    name = 'generated_metadata_check'
    family = 'checks'
    inputs = ('content/generated/hsl/chapter01/',)
    replaces = ('tools/hsl_generated_metadata_check.py content/generated/hsl/chapter01',)
    scripts = ('tools/hsltools/checks/generated_metadata.py',)

    def check(self, ctx: Context) -> str:
        return printed_last_line(main, ['content/generated/hsl/chapter01'])


def tasks() -> list[GeneratedMetadataCheckTask]:
    return [GeneratedMetadataCheckTask()]


if __name__ == '__main__':
    raise SystemExit(main())
