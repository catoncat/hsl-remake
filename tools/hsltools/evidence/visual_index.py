"""Validate the first-battle visual evidence manifest.

This checker keeps visual evidence references executable enough for agents:
the manifest must name concrete files, classify their visual state, and mark
the Move overlay baseline as blocking for the spatial-contract surfaces.

Registry task visual_evidence_index (family evidence): the tracked
first_battle_visual_evidence_index.json. Bodies moved verbatim from the former hsl_visual_evidence_index_check.py.
"""

from __future__ import annotations

import json
import struct
from pathlib import Path
from typing import Any

from hsltools.paths import ROOT
from hsltools.registry import Context, ScriptCheckTask


DEFAULT_MANIFEST = (
    "docs/evidence_packets/runtime_observations/"
    "first_battle_visual_evidence_index.json"
)

REQUIRED_GATE_TOPICS = {
    "camera_crop",
    "grid_to_world_projection",
    "actor_foot_anchor",
    "movement_range_overlay",
    "hit_test",
    "foreground_z_order",
    "menu_anchor",
    "cancel_return",
}

MOVE_BLOCKING_TOPICS = {
    "camera_crop",
    "grid_to_world_projection",
    "actor_foot_anchor",
    "movement_range_overlay",
    "hit_test",
    "foreground_z_order",
}

REQUIRED_OPENING_EVIDENCE_IDS = {
    "opening_transition_rain_frame",
    "opening_transition_castle_wall_frame",
    "opening_lower_formation_before_dialogue",
    "opening_dialogue_leonard",
    "opening_dialogue_map_only_gap",
    "opening_dialogue_soldier",
}

REQUIRED_FORMATION_CANDIDATE_IDS = {
    "opening_lower_formation_before_dialogue",
    "opening_dialogue_map_only_gap",
    "p1_route_upper_formation_11",
    "p1_route_upper_formation_12",
}

REQUIRED_FIRST_CONTROL_EVIDENCE_IDS = {
    "first_control_action_menu",
    "first_control_action_menu_hover_move",
    "p1_route_action_menu_13",
    "move_overlay_primary",
}

ALLOWED_STATUSES = {
    "confirmed",
    "confirmed_negative_for_cancel_return",
    "candidate",
    "rejected",
}


def _fail(message: str) -> None:
    raise SystemExit(f"visual evidence index check failed: {message}")


def _read_png_size(path: Path) -> tuple[int, int]:
    with path.open("rb") as handle:
        header = handle.read(24)
    if len(header) < 24 or header[:8] != b"\x89PNG\r\n\x1a\n":
        _fail(f"{path} is not a PNG")
    if header[12:16] != b"IHDR":
        _fail(f"{path} has no PNG IHDR chunk")
    width, height = struct.unpack(">II", header[16:24])
    return width, height


def _require_string(entry: dict[str, Any], key: str) -> str:
    value = entry.get(key)
    if not isinstance(value, str) or not value:
        _fail(f"entry {entry.get('id', '<unknown>')} missing string {key}")
    return value


def _require_string_list(entry: dict[str, Any], key: str) -> list[str]:
    value = entry.get(key)
    if not isinstance(value, list) or not value:
        _fail(f"entry {entry.get('id', '<unknown>')} missing non-empty list {key}")
    if not all(isinstance(item, str) and item for item in value):
        _fail(f"entry {entry.get('id', '<unknown>')} has invalid {key}")
    return value


def check_manifest(manifest_path: Path, repo_root: Path) -> None:
    with manifest_path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)

    if data.get("schema") != "hsl_first_battle_visual_evidence_index.v1":
        _fail("unexpected schema")

    topics = set(data.get("required_gate_topics", []))
    missing_topics = REQUIRED_GATE_TOPICS - topics
    if missing_topics:
        _fail(f"required_gate_topics missing {sorted(missing_topics)}")

    evidence = data.get("evidence")
    if not isinstance(evidence, list) or not evidence:
        _fail("evidence must be a non-empty list")

    seen_ids: set[str] = set()
    entries_by_id: dict[str, dict[str, Any]] = {}

    for entry in evidence:
        if not isinstance(entry, dict):
            _fail("evidence entry must be an object")
        entry_id = _require_string(entry, "id")
        if entry_id in seen_ids:
            _fail(f"duplicate evidence id {entry_id}")
        seen_ids.add(entry_id)
        entries_by_id[entry_id] = entry

        file_value = _require_string(entry, "file")
        status = _require_string(entry, "status")
        if status not in ALLOWED_STATUSES:
            _fail(f"{entry_id} has unsupported status {status}")
        if entry.get("evidence_tier") != "runtime-measured":
            _fail(f"{entry_id} must be runtime-measured")
        _require_string(entry, "visual_state")
        _require_string_list(entry, "use_for")
        _require_string_list(entry, "not_for")

        if Path(file_value).is_absolute():
            _fail(f"{entry_id} file must be repo-relative, got absolute path")
        file_path = repo_root / file_value
        if not file_path.exists():
            _fail(f"{entry_id} file does not exist: {file_value}")
        if file_path.suffix.lower() == ".png":
            width, height = _read_png_size(file_path)
            if width <= 0 or height <= 0:
                _fail(f"{entry_id} PNG has invalid size {width}x{height}")

    move = entries_by_id.get("move_overlay_primary")
    if not move:
        _fail("missing move_overlay_primary")
    if move.get("status") != "confirmed":
        _fail("move_overlay_primary must be confirmed")
    move_blocking = set(move.get("blocking_for", []))
    missing_move_topics = MOVE_BLOCKING_TOPICS - move_blocking
    if missing_move_topics:
        _fail(f"move_overlay_primary missing blocking topics {sorted(missing_move_topics)}")

    opening_ids = set(data.get("opening_choreography_evidence_ids", []))
    missing_opening = REQUIRED_OPENING_EVIDENCE_IDS - opening_ids
    if missing_opening:
        _fail(f"opening_choreography_evidence_ids missing {sorted(missing_opening)}")
    if opening_ids - seen_ids:
        _fail(f"opening_choreography_evidence_ids references unknown entries {sorted(opening_ids - seen_ids)}")

    formation_ids = set(data.get("formation_candidate_evidence_ids", []))
    missing_formation = REQUIRED_FORMATION_CANDIDATE_IDS - formation_ids
    if missing_formation:
        _fail(f"formation_candidate_evidence_ids missing {sorted(missing_formation)}")
    if formation_ids - seen_ids:
        _fail(f"formation_candidate_evidence_ids references unknown entries {sorted(formation_ids - seen_ids)}")

    first_control_ids = set(data.get("first_control_confirmed_evidence_ids", []))
    missing_first_control = REQUIRED_FIRST_CONTROL_EVIDENCE_IDS - first_control_ids
    if missing_first_control:
        _fail(f"first_control_confirmed_evidence_ids missing {sorted(missing_first_control)}")
    if first_control_ids - seen_ids:
        _fail(f"first_control_confirmed_evidence_ids references unknown entries {sorted(first_control_ids - seen_ids)}")

    idle_entry = entries_by_id.get("first_control_idle_no_menu")
    if idle_entry is not None and idle_entry.get("status") == "confirmed":
        _fail("first_control_idle_no_menu cannot be confirmed without updating the known_missing_evidence gate")
    known_missing = data.get("known_missing_evidence")
    if not isinstance(known_missing, list) or not any("first_control_idle_no_menu" in str(item) for item in known_missing):
        _fail("known_missing_evidence must preserve first_control_idle_no_menu gap")

    forbidden = data.get("forbidden_or_downgraded_sources")
    if not isinstance(forbidden, list) or len(forbidden) < 3:
        _fail("forbidden_or_downgraded_sources must list the main downgraded sources")
    for item in forbidden:
        if not isinstance(item, dict):
            _fail("forbidden source entry must be an object")
        _require_string(item, "path")
        _require_string(item, "reason")

    gate_rules = data.get("gate_rules")
    if not isinstance(gate_rules, list) or len(gate_rules) < 3:
        _fail("gate_rules must be a non-empty list")
    if not any("move_overlay_primary" in rule for rule in gate_rules if isinstance(rule, str)):
        _fail("gate_rules must name move_overlay_primary")


class VisualEvidenceIndexTask(ScriptCheckTask):
    name = 'visual_evidence_index'
    family = 'evidence'
    inputs = ()
    outputs = (DEFAULT_MANIFEST, 'docs/evidence_packets/runtime_observations/first_battle_visuals/')
    replaces = ('tools/hsl_visual_evidence_index_check.py',)
    scripts = ('tools/hsltools/evidence/visual_index.py',)

    def verify(self, ctx: Context) -> None:
        manifest_path = ROOT / DEFAULT_MANIFEST
        check_manifest(manifest_path, ROOT)
        print(f"visual evidence index ok: {manifest_path.relative_to(ROOT)}")


def tasks() -> list[VisualEvidenceIndexTask]:
    return [VisualEvidenceIndexTask()]
