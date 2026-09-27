"""Validate the imported content that the live runtime or near-term UI work uses.

Registry task imported_content_check (family checks, CheckTask): the summary lines the script prints after
"PASS hsl_imported_content_check" are still printed, the PASS line is the task summary. Bodies (main included)
moved verbatim from the former hsl_imported_content_check.py; parse_args/main take argv.
"""
from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path
from typing import Any

from hsltools.checks import CheckTask
from hsltools.data import printed_last_line
from hsltools.registry import Context

ROOT = Path("content/imported/hsl/chapter01")

EXPECTED_SCHEMAS = {
    "map_objects.json": "hsl_chapter01_imported_map_objects_ir.v1",
    "map_object_alignment.json": "hsl_chapter01_map_object_alignment.v1",
    "map_object_visibility_evidence.json": "hsl_chapter01_map_object_visibility_evidence.v1",
    "shape_preview_index.json": "hsl_chapter01_imported_shape_preview_index.v1",
    "ui_preview_index.json": "hsl_chapter01_imported_ui_preview_index.v1",
    "audio_normalized.json": "hsl_chapter01_imported_audio_normalized.v1",
    "script_ir_index.json": "hsl_chapter01_script_ir_index.v1",
    "opening_timeline.json": "hsl_first_scene_opening_timeline.v1",
}

EXPECTED_MAP_OBJECT_SHAPES = {
    "tree07.SHP": 6,
    "FIRE01-01.SHP": 2,
    "bar004a.SHP": 1,
    "bar004b.SHP": 1,
}
EXPECTED_ACTORS = {"001", "021", "023", "024", "026"}
EXPECTED_SCRIPTS = {"story051", "winfail051"}


class CheckFailure(RuntimeError):
    pass


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise CheckFailure(f"missing file: {path}") from exc
    except json.JSONDecodeError as exc:
        raise CheckFailure(
            f"invalid JSON in {path}: {exc.msg} at line {exc.lineno}, column {exc.colno}"
        ) from exc
    if not isinstance(value, dict):
        raise CheckFailure(f"JSON root must be an object: {path}")
    return value


def resolve_res_path(root: Path, value: str) -> Path:
    """A chapter-01 res path under root, or a shared one (SHP previews) under the sibling shared/."""
    for prefix, base in (("res://content/imported/hsl/chapter01/", root),
                         ("res://content/imported/hsl/shared/", root.parent / "shared")):
        if value.startswith(prefix):
            return base / value.removeprefix(prefix)
    raise CheckFailure(f"unexpected imported res path: {value}")


def require_schema(path: Path, document: dict[str, Any], expected: str) -> None:
    actual = document.get("schema")
    if actual != expected:
        raise CheckFailure(f"{path}: expected schema {expected}, got {actual!r}")


def check_indexed_previews(
    root: Path,
    document: dict[str, Any],
    *,
    list_key: str,
    path_key: str,
) -> Counter[str]:
    entries = document.get(list_key)
    if not isinstance(entries, list) or not entries:
        raise CheckFailure(f"{list_key} must be a non-empty array")
    categories: Counter[str] = Counter()
    seen_ids: set[str] = set()
    for index, value in enumerate(entries):
        if not isinstance(value, dict):
            raise CheckFailure(f"{list_key}[{index}] must be an object")
        resource_id = str(value.get("resource_id", ""))
        if not resource_id or resource_id in seen_ids:
            raise CheckFailure(f"{list_key}[{index}] has missing/duplicate resource_id")
        seen_ids.add(resource_id)
        category = str(value.get("category", value.get("ui_group", "unknown")))
        categories[category] += 1
        res_path = str(value.get(path_key, ""))
        preview = resolve_res_path(root, res_path)
        if not preview.is_file() or preview.stat().st_size <= 0:
            raise CheckFailure(f"missing/empty preview for {resource_id}: {preview}")
    return categories


def check_map_objects(root: Path, document: dict[str, Any]) -> dict[str, int]:
    placements = document.get("placements")
    if not isinstance(placements, list) or not placements:
        raise CheckFailure("map_objects.placements must be a non-empty array")
    joined = 0
    shape_counts: Counter[str] = Counter()
    for index, value in enumerate(placements):
        if not isinstance(value, dict):
            raise CheckFailure(f"map_objects.placements[{index}] must be an object")
        if value.get("join", {}).get("status") == "joined":
            joined += 1
        if value.get("role") == "map_object":
            shape_counts[str(value.get("shape_resource_id", ""))] += 1
        coordinate = value.get("coordinate_interpretation")
        if not isinstance(coordinate, dict) or coordinate.get("interpretation_status") != "provisional":
            raise CheckFailure(f"placement {index} lost its provisional coordinate boundary")
    if joined != len(placements):
        raise CheckFailure(f"expected all placements joined, got {joined}/{len(placements)}")
    if dict(shape_counts) != EXPECTED_MAP_OBJECT_SHAPES:
        raise CheckFailure(
            f"map-object shape counts mismatch: expected {EXPECTED_MAP_OBJECT_SHAPES}, got {dict(shape_counts)}"
        )
    return dict(shape_counts)


def check_alignment(root: Path, document: dict[str, Any]) -> None:
    shapes = document.get("shapes", {})
    if set(shapes) != set(EXPECTED_MAP_OBJECT_SHAPES):
        raise CheckFailure("map object SHP origins are missing")
    for shape in shapes.values():
        origin = shape.get("draw_origin", [])
        if len(origin) != 2 or any(type(value) is not int for value in origin):
            raise CheckFailure("map object SHP origin must contain two signed integers")
    calibrations = document.get("calibrations")
    if not isinstance(calibrations, list) or len(calibrations) != 2:
        raise CheckFailure("map_object_alignment must contain the two bridge calibrations")
    if {int(item.get("record_index", -1)) for item in calibrations if isinstance(item, dict)} != {8, 13}:
        raise CheckFailure("bridge calibration record ids must be 8 and 13")
    for item in calibrations:
        if not isinstance(item, dict) or item.get("evidence_tier") != "runtime-measured":
            raise CheckFailure("bridge calibration lost runtime-measured evidence tier")
        for source in item.get("anchor_source_files", []):
            source_path = Path(str(source))
            if not source_path.is_file():
                raise CheckFailure(f"bridge calibration source is missing: {source_path}")
            if "docs/evidence_packets/runtime_observations/first_battle_visuals" not in source_path.as_posix():
                raise CheckFailure(f"bridge calibration must use curated visual evidence: {source_path}")


def check_visibility(root: Path, document: dict[str, Any]) -> None:
    objects = document.get("objects")
    if not isinstance(objects, list) or not objects:
        raise CheckFailure("map_object_visibility_evidence.objects must be non-empty")
    ids = {str(item.get("resource_id", "")) for item in objects if isinstance(item, dict)}
    if ids != set(EXPECTED_MAP_OBJECT_SHAPES):
        raise CheckFailure(f"map-object visibility ids mismatch: {sorted(ids)}")
    for item in objects:
        preview = resolve_res_path(root, str(item.get("display_preview", {}).get("preview_res_path", "")))
        if not preview.is_file():
            raise CheckFailure(f"map-object visibility preview missing: {preview}")


def check_audio(root: Path, document: dict[str, Any]) -> int:
    entries = document.get("normalized_audio")
    if not isinstance(entries, list) or not entries:
        raise CheckFailure("audio_normalized.normalized_audio must be non-empty")
    for entry in entries:
        if not isinstance(entry, dict):
            raise CheckFailure("audio_normalized entry must be an object")
        path = resolve_res_path(root, str(entry.get("normalized_res_path", "")))
        if not path.is_file() or path.read_bytes()[:4] != b"RIFF":
            raise CheckFailure(f"normalized audio is missing or not RIFF WAV: {path}")
        if entry.get("trigger_semantics_status") != "unresolved":
            raise CheckFailure(f"audio trigger semantics must stay unresolved: {path}")
    return len(entries)


def check_scripts(root: Path, document: dict[str, Any]) -> int:
    scripts = document.get("scripts")
    if not isinstance(scripts, list):
        raise CheckFailure("script_ir_index.scripts must be an array")
    ids = {str(item.get("id", "")) for item in scripts if isinstance(item, dict)}
    if ids != EXPECTED_SCRIPTS:
        raise CheckFailure(f"script ids mismatch: {sorted(ids)}")
    for item in scripts:
        path = resolve_res_path(root, str(item.get("path", "")))
        script = load_json(path)
        if script.get("id") != item.get("id") or script.get("schema") != "hsl_chapter01_script_ir.v1":
            raise CheckFailure(f"script index mismatch: {path}")
    return len(scripts)


def check_timeline(document: dict[str, Any]) -> int:
    events = document.get("events")
    if not isinstance(events, list) or len(events) != 20:
        raise CheckFailure(f"opening timeline must contain 20 events, got {len(events) if isinstance(events, list) else 'invalid'}")
    if events[0].get("kind") != "opening_music" or events[-1].get("kind") != "first_control_marker":
        raise CheckFailure("opening timeline endpoints are invalid")
    if sum(1 for event in events if event.get("kind") == "actor_walk_disp_wait") != 1:
        raise CheckFailure("opening timeline must retain exactly one direct actor-walk token")
    return len(events)


def check_imported_content(root: Path = ROOT) -> dict[str, Any]:
    docs: dict[str, dict[str, Any]] = {}
    for filename, schema in EXPECTED_SCHEMAS.items():
        path = root / filename
        docs[filename] = load_json(path)
        require_schema(path, docs[filename], schema)

    shape_categories = check_indexed_previews(
        root, docs["shape_preview_index.json"], list_key="entries", path_key="preview_res_path"
    )
    ui_groups = check_indexed_previews(
        root, docs["ui_preview_index.json"], list_key="entries", path_key="preview_res_path"
    )
    actor_ids = {
        str(entry.get("resource_id", "")).split("-", 1)[0]
        for entry in docs["shape_preview_index.json"].get("entries", [])
        if entry.get("category") == "actor_sprite"
    }
    if not EXPECTED_ACTORS.issubset(actor_ids):
        raise CheckFailure(f"shape preview index is missing current actors: {sorted(EXPECTED_ACTORS - actor_ids)}")

    map_shapes = check_map_objects(root, docs["map_objects.json"])
    check_alignment(root, docs["map_object_alignment.json"])
    check_visibility(root, docs["map_object_visibility_evidence.json"])
    audio_count = check_audio(root, docs["audio_normalized.json"])
    script_count = check_scripts(root, docs["script_ir_index.json"])
    event_count = check_timeline(docs["opening_timeline.json"])

    return {
        "schema": "hsl_imported_content_check.v1",
        "root": root.as_posix(),
        "map_object_shapes": map_shapes,
        "shape_preview_count": sum(shape_categories.values()),
        "ui_preview_count": sum(ui_groups.values()),
        "audio_count": audio_count,
        "script_count": script_count,
        "opening_event_count": event_count,
    }


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", nargs="?", type=Path, default=ROOT)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        summary = check_imported_content(args.root)
    except CheckFailure as exc:
        print(f"FAIL hsl_imported_content_check: {exc}")
        return 1
    print("PASS hsl_imported_content_check")
    for key, value in summary.items():
        if key != "schema":
            print(f"  {key}={value}")
    return 0


class ImportedContentCheckTask(CheckTask):
    name = 'imported_content_check'
    family = 'checks'
    inputs = ('content/imported/hsl/chapter01/',)
    replaces = ('tools/hsl_imported_content_check.py content/imported/hsl/chapter01',)
    scripts = ('tools/hsltools/checks/imported_content.py',)

    def check(self, ctx: Context) -> str:
        return printed_last_line(main, ['content/imported/hsl/chapter01'], marker='PASS')


def tasks() -> list[ImportedContentCheckTask]:
    return [ImportedContentCheckTask()]


if __name__ == '__main__':
    raise SystemExit(main())
