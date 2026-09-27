"""Validate the opening choreography evidence packet.

Registry task opening_choreography_packet (family evidence): the tracked
first_scene_opening_choreography_packet.json. Bodies moved verbatim from the former hsl_opening_choreography_packet_check.py.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from hsltools.paths import ROOT
from hsltools.registry import Context, ScriptCheckTask


SCHEMA = "hsl_first_scene_opening_choreography_packet.v1"
DEFAULT_PACKET = Path("docs/evidence_packets/runtime_observations/first_scene_opening_choreography_packet.json")
MISSING_CAPTURE_STATUS = "missing_generated_capture"
GENERATED_CAPTURE_SOURCES = {
    "runtime_capture",
    "opening_capture",
    "opening_autoplay_capture",
}

REQUIRED_VISUAL_IDS = {
    "opening_transition_rain_frame",
    "opening_transition_castle_wall_frame",
    "opening_lower_formation_before_dialogue",
    "opening_dialogue_leonard",
    "opening_dialogue_map_only_gap",
    "opening_dialogue_soldier",
    "p1_route_upper_formation_11",
    "p1_route_upper_formation_12",
    "p1_route_action_menu_13",
    "first_control_action_menu",
}

REQUIRED_SEGMENTS = {
    "transition_context",
    "upper_gate_bridge_context",
    "leonard_story_walk",
    "dialogue_lower_context",
    "status_and_first_control_handoff",
}

REQUIRED_MISSING_TRUTH = {
    "first_control_idle_no_menu",
    "complete_enemy_gate_entry_paths",
    "complete_friendly_entry_paths",
    "continuous_camera_curve",
    "dialogue_text_source",
}


def _fail(message: str) -> None:
    raise SystemExit(f"opening choreography packet check failed: {message}")


def check_packet(path: Path, repo_root: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        packet: dict[str, Any] = json.load(handle)

    if packet.get("schema") != SCHEMA:
        _fail("unexpected schema")
    if not packet.get("provisional", False):
        _fail("packet must remain provisional")

    sources = packet.get("sources")
    if not isinstance(sources, dict):
        _fail("sources missing")
    for source_name in [
        "visual_index",
        "opening_timeline",
        "map_objects",
        "map_object_visibility",
        "actor_walk_manifest",
        "runtime_capture",
        "opening_capture",
        "opening_autoplay_capture",
    ]:
        source = sources.get(source_name)
        if not isinstance(source, dict):
            _fail(f"missing source {source_name}")
        source_path = Path(str(source.get("path", "")))
        if source_path.is_absolute():
            _fail(f"{source_name} path must be repo-relative")
        if not str(source.get("schema", "")):
            _fail(f"{source_name} missing schema")
        if not (repo_root / source_path).exists():
            generated_capture = source_name in GENERATED_CAPTURE_SOURCES and source_path.parts[:1] == ("ignored",)
            missing_status = str(source.get("capture_status", "")) == MISSING_CAPTURE_STATUS
            # Generated capture manifests are intentionally ignored. A tracked
            # packet may preserve their compact summary even when the local
            # manifest has been cleaned, and a fresh packet may mark them
            # missing until the capture scripts are rerun.
            if not generated_capture and not missing_status:
                _fail(f"{source_name} path does not exist: {source_path}")

    visual = packet.get("visual_evidence")
    if not isinstance(visual, list):
        _fail("visual_evidence must be a list")
    visual_by_id = {str(item.get("id", "")): item for item in visual if isinstance(item, dict)}
    missing_visual = REQUIRED_VISUAL_IDS - set(visual_by_id)
    if missing_visual:
        _fail(f"missing visual ids {sorted(missing_visual)}")
    for evidence_id in REQUIRED_VISUAL_IDS:
        item = visual_by_id[evidence_id]
        if not str(item.get("file", "")):
            _fail(f"{evidence_id} missing file")
        if str(item.get("evidence_tier", "")) != "runtime-measured":
            _fail(f"{evidence_id} must be runtime-measured")
        if str(item.get("status", "")) not in {"confirmed", "candidate"}:
            _fail(f"{evidence_id} has invalid status")
    _require_not_for_contains(
        visual_by_id["opening_dialogue_map_only_gap"],
        ["confirmed first-control idle", "player control has started"],
    )
    for evidence_id in ["p1_route_upper_formation_11", "p1_route_upper_formation_12"]:
        _require_not_for_contains(visual_by_id[evidence_id], ["first-control idle", "complete actor entry path"])

    timeline = packet.get("script_timeline")
    if not isinstance(timeline, dict):
        _fail("script_timeline missing")
    if str(timeline.get("schema", "")) != "hsl_first_scene_opening_timeline.v1":
        _fail("script_timeline schema mismatch")
    if int(timeline.get("event_count", 0)) != 20:
        _fail("script_timeline event_count must be 20")
    if int(timeline.get("direct_actor_motion_count", 0)) != 1:
        _fail("exactly one direct opening actor motion token is currently proven")
    direct_tokens = timeline.get("direct_actor_motion_tokens", [])
    if not isinstance(direct_tokens, list) or len(direct_tokens) != 1:
        _fail("direct_actor_motion_tokens must contain one item")
    direct = direct_tokens[0]
    if str(direct.get("actor_token", "")) != "SID_PLAYER0":
        _fail("direct actor motion must remain limited to SID_PLAYER0")
    if str(direct.get("source_token", "")) != "actWalkDispWait(SID_PLAYER0,1,0,-96,2)":
        _fail("direct actor source token mismatch")

    actors = packet.get("actor_choreography")
    if not isinstance(actors, list):
        _fail("actor_choreography must be a list")
    actors_by_token = {str(item.get("actor_token", "")): item for item in actors if isinstance(item, dict)}
    for token in ["SID_PLAYER0", "SID_ENEMY021", "SID_ENEMY023", "SID_ENEMY024", "SID_ENEMY026"]:
        if token not in actors_by_token:
            _fail(f"missing actor choreography {token}")
    if str(actors_by_token["SID_PLAYER0"].get("motion_status", "")) != "direct_story051_walk_token":
        _fail("SID_PLAYER0 should be the only direct STORY051 walk actor")
    for token in ["SID_ENEMY021", "SID_ENEMY023", "SID_ENEMY024"]:
        status = str(actors_by_token[token].get("motion_status", ""))
        if status != "dialogue_actor_only_no_direct_walk_token":
            _fail(f"{token} must remain dialogue-only for direct opening motion, actual={status}")
    if str(actors_by_token["SID_ENEMY026"].get("motion_status", "")) != "known_first_scene_actor_no_story051_motion_token":
        _fail("SID_ENEMY026 must remain without STORY051 motion token")

    segments = packet.get("choreography_segments")
    if not isinstance(segments, list):
        _fail("choreography_segments must be a list")
    segment_by_id = {str(item.get("id", "")): item for item in segments if isinstance(item, dict)}
    missing_segments = REQUIRED_SEGMENTS - set(segment_by_id)
    if missing_segments:
        _fail(f"missing choreography segments {sorted(missing_segments)}")
    if not bool(segment_by_id["leonard_story_walk"].get("can_drive_runtime_motion", False)):
        _fail("leonard_story_walk should be the only segment allowed to drive runtime motion")
    for segment_id, segment in segment_by_id.items():
        if segment_id != "leonard_story_walk" and bool(segment.get("can_drive_runtime_motion", False)):
            _fail(f"{segment_id} must not drive runtime motion without stronger evidence")
        not_proven = segment.get("not_proven")
        if not isinstance(not_proven, list) or not not_proven:
            _fail(f"{segment_id} must keep not_proven list")

    missing_truth = set(packet.get("missing_original_truth", []))
    if not REQUIRED_MISSING_TRUTH <= missing_truth:
        _fail(f"missing_original_truth lacks {sorted(REQUIRED_MISSING_TRUTH - missing_truth)}")
    forbidden = packet.get("forbidden_inferences")
    if not isinstance(forbidden, list) or len(forbidden) < 3:
        _fail("forbidden_inferences must preserve overclaim guardrails")
    if not any("dialogue speaker" in str(item) for item in forbidden):
        _fail("forbidden_inferences must block dialogue-speaker path inference")
    for required_guard in [
        "p1_route_upper_formation_11/12 as first-control idle truth",
        "opening_dialogue_map_only_gap as proof that player control has started",
        "current Godot token overlay as original UI or original handler timing",
    ]:
        if not any(required_guard in str(item) for item in forbidden):
            _fail(f"forbidden_inferences missing guard: {required_guard}")

    current = packet.get("current_godot_consumption")
    if not isinstance(current, dict):
        _fail("current_godot_consumption missing")
    capture_status = current.get("generated_capture_status", {})
    if not isinstance(capture_status, dict):
        capture_status = {}
    runtime_capture_missing = str(capture_status.get("runtime_capture", "")) == MISSING_CAPTURE_STATUS
    opening_capture_missing = str(capture_status.get("opening_capture", "")) == MISSING_CAPTURE_STATUS
    autoplay_capture_missing = str(capture_status.get("opening_autoplay_capture", "")) == MISSING_CAPTURE_STATUS
    if int(current.get("map_object_spawn_count", 0)) != 10 and not runtime_capture_missing:
        _fail("current Godot map-object count must be 10")
    if str(current.get("autoplay_final_event", "")) != "first_control_ready" and not autoplay_capture_missing:
        _fail("autoplay must currently hand off to first_control_ready")
    if str(current.get("runtime_contract_opening_choreography_packet_schema", "")) != SCHEMA and not runtime_capture_missing:
        _fail("runtime contract must expose choreography packet schema")
    if current.get("runtime_contract_opening_choreography_motion_driver_segments", []) != ["leonard_story_walk"] and not runtime_capture_missing:
        _fail("runtime contract must expose only the Leonard choreography motion driver")
    if str(current.get("opening_capture_choreography_packet_schema", "")) != SCHEMA and not opening_capture_missing:
        _fail("opening capture manifest must expose choreography packet schema")
    if current.get("opening_capture_motion_driver_segments", []) != ["leonard_story_walk"] and not opening_capture_missing:
        _fail("opening capture manifest must expose only the Leonard choreography motion driver")
    if not opening_capture_missing:
        _require_capture_segment_record(
            current.get("opening_capture_segment_record_stages", []),
            "opening_music",
            ["transition_context", "upper_gate_bridge_context"],
            "complete enemy entry path",
        )
        _require_capture_segment_record(
            current.get("opening_capture_segment_record_stages", []),
            "actor_walk_token",
            ["leonard_story_walk"],
            "foot anchor",
        )
        _require_capture_segment_record(
            current.get("opening_capture_segment_record_stages", []),
            "dialogue_message_363",
            ["dialogue_lower_context"],
            "original message box layout",
        )
        _require_capture_segment_record(
            current.get("opening_capture_segment_record_stages", []),
            "winfail_board_refresh",
            ["status_and_first_control_handoff"],
            "first_control_idle_no_menu",
        )
        _require_capture_camera_contract_record(
            current.get("opening_capture_camera_contract_stages", []),
            "opening_music",
            "upper_formation_candidate",
            ["p1_route_upper_formation_11", "p1_route_upper_formation_12"],
            "complete_enemy_gate_entry_paths",
            transition_context_only=True,
        )
        _require_capture_camera_contract_record(
            current.get("opening_capture_camera_contract_stages", []),
            "actor_walk_token",
            "lower_formation_candidate",
            ["opening_lower_formation_before_dialogue", "opening_dialogue_map_only_gap"],
            "complete_friendly_entry_paths",
        )
        _require_capture_camera_contract_record(
            current.get("opening_capture_camera_contract_stages", []),
            "dialogue_message_363",
            "lower_dialogue_candidate",
            ["opening_dialogue_leonard", "opening_dialogue_soldier", "opening_lower_formation_before_dialogue"],
            "dialogue_text_source",
        )
        _require_capture_camera_contract_record(
            current.get("opening_capture_camera_contract_stages", []),
            "winfail_board_refresh",
            "lower_status_candidate",
            ["opening_lower_formation_before_dialogue", "opening_dialogue_map_only_gap"],
            "first_control_idle_no_menu",
        )
    if str(current.get("autoplay_capture_choreography_packet_schema", "")) != SCHEMA and not autoplay_capture_missing:
        _fail("autoplay capture manifest must expose choreography packet schema")
    if current.get("autoplay_capture_motion_driver_segments", []) != ["leonard_story_walk"] and not autoplay_capture_missing:
        _fail("autoplay capture manifest must expose only the Leonard choreography motion driver")
    if not autoplay_capture_missing:
        _require_capture_segment_record(
            current.get("autoplay_capture_segment_record_stages", []),
            "autoplay_start",
            ["transition_context", "upper_gate_bridge_context"],
            "complete enemy entry path",
        )
        _require_capture_camera_contract_record(
            current.get("autoplay_capture_camera_contract_stages", []),
            "autoplay_start",
            "upper_formation_candidate",
            ["p1_route_upper_formation_11", "p1_route_upper_formation_12"],
            "complete_enemy_gate_entry_paths",
            transition_context_only=True,
        )
        _require_capture_camera_contract_record(
            current.get("autoplay_capture_camera_contract_stages", []),
            "autoplay_first_control",
            "first_control_action_menu_context",
            ["first_control_action_menu", "p1_route_action_menu_13"],
            "original_action_menu_handler_semantics",
        )

    return {
        "segments": len(segments),
        "direct_actor_motion_count": int(timeline.get("direct_actor_motion_count", 0)),
    }


def _require_not_for_contains(item: dict[str, Any], required_fragments: list[str]) -> None:
    not_for = item.get("not_for")
    if not isinstance(not_for, list):
        _fail(f"{item.get('id', '<unknown>')} not_for must be a list")
    joined = " | ".join(str(value) for value in not_for)
    for fragment in required_fragments:
        if fragment not in joined:
            _fail(f"{item.get('id', '<unknown>')} not_for missing fragment: {fragment}")


def _require_capture_segment_record(
    records: Any,
    stage: str,
    expected_segment_ids: list[str],
    required_not_proven: str,
) -> None:
    if not isinstance(records, list):
        _fail(f"capture segment records missing for {stage}")
    record = next(
        (
            item
            for item in records
            if isinstance(item, dict) and str(item.get("stage", "")) == stage
        ),
        None,
    )
    if not isinstance(record, dict):
        _fail(f"capture segment record missing stage {stage}")
    if record.get("segment_ids", []) != expected_segment_ids:
        _fail(f"capture segment ids mismatch for {stage}: {record.get('segment_ids', [])}")
    if int(record.get("segment_record_count", 0)) != len(expected_segment_ids):
        _fail(f"capture segment record count mismatch for {stage}")
    if not bool(record.get("segment_claims_present", False)):
        _fail(f"capture segment claims missing for {stage}")
    statuses = record.get("segment_implementation_statuses", [])
    if not isinstance(statuses, list) or len(statuses) != len(expected_segment_ids) or not all(str(item) for item in statuses):
        _fail(f"capture segment implementation statuses missing for {stage}")
    if required_not_proven not in record.get("segment_not_proven", []):
        _fail(f"capture segment missing not_proven '{required_not_proven}' for {stage}")


def _require_capture_camera_contract_record(
    records: Any,
    stage: str,
    expected_camera_stage: str,
    expected_candidate_ids: list[str],
    required_not_proven: str,
    *,
    transition_context_only: bool = False,
) -> None:
    if not isinstance(records, list):
        _fail(f"capture camera contract records missing for {stage}")
    record = next(
        (
            item
            for item in records
            if isinstance(item, dict) and str(item.get("stage", "")) == stage
        ),
        None,
    )
    if not isinstance(record, dict):
        _fail(f"capture camera contract record missing stage {stage}")
    if str(record.get("camera_stage", "")) != expected_camera_stage:
        _fail(f"capture camera stage mismatch for {stage}: {record.get('camera_stage', '')}")
    if str(record.get("continuous_curve_status", "")) != "missing_original_truth":
        _fail(f"capture camera curve status must stay missing for {stage}")
    if int(record.get("candidate_anchor_sequence_count", 0)) != 5:
        _fail(f"capture camera candidate sequence count mismatch for {stage}")
    if str(record.get("current_stage_record_schema", "")) != "hsl_first_scene_opening_camera_stage.v1":
        _fail(f"capture camera current stage record schema missing for {stage}")
    if record.get("candidate_camera_evidence_ids", []) != expected_candidate_ids:
        _fail(
            f"capture camera candidate ids mismatch for {stage}: "
            f"{record.get('candidate_camera_evidence_ids', [])}"
        )
    if not bool(record.get("candidate_evidence_records_present", False)):
        _fail(f"capture camera evidence records missing for {stage}")
    if required_not_proven not in record.get("current_stage_not_proven", []):
        _fail(f"capture camera contract missing not_proven '{required_not_proven}' for {stage}")
    if transition_context_only:
        if not bool(record.get("transition_frames_are_context_only", False)):
            _fail(f"capture camera transition frames must remain context-only for {stage}")
        context_ids = record.get("context_only_evidence_ids", [])
        if context_ids != ["opening_transition_rain_frame", "opening_transition_castle_wall_frame"]:
            _fail(f"capture camera context-only ids mismatch for {stage}: {context_ids}")
        if not bool(record.get("context_only_records_present", False)):
            _fail(f"capture camera context-only evidence records missing for {stage}")


class OpeningChoreographyPacketTask(ScriptCheckTask):
    name = 'opening_choreography_packet'
    family = 'evidence'
    inputs = ('docs/evidence_packets/runtime_observations/first_battle_visual_evidence_index.json',
              'content/imported/hsl/chapter01/opening_timeline.json')
    outputs = (DEFAULT_PACKET.as_posix(),)
    replaces = ('tools/hsl_opening_choreography_packet_check.py',)
    scripts = ('tools/hsltools/evidence/opening_choreography_packet.py',)

    def verify(self, ctx: Context) -> None:
        summary = check_packet(DEFAULT_PACKET, ROOT)
        print(
            "opening choreography packet ok: "
            f"segments={summary['segments']} direct_actor_motion={summary['direct_actor_motion_count']} packet={DEFAULT_PACKET}"
        )


def tasks() -> list[OpeningChoreographyPacketTask]:
    return [OpeningChoreographyPacketTask()]
